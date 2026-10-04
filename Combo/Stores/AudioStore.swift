import AppKit
import Combine
import CoreAudio

struct OutputChoice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let glyph: DeviceGlyph
}

@MainActor final class AudioStore: ObservableObject {
    @Published var volume: Double?
    @Published var muted = false
    @Published var output: LocalizedText = ""
    /// 当前默认输出设备的类别，是中央图标与输出列表共用的唯一分类结果。
    @Published var deviceKind: OutputDeviceKind = .other
    var outputIsAirPods: Bool { deviceKind.isAirPods }
    @Published var outputDevices: [OutputChoice] = []
    @Published var canVolume = false
    @Published var canMute = false
    @Published var message: LocalizedText = "" { didSet { onMessage?(message) } }
    let airpods = AirPodsControl()
    let bluetoothPermission = BluetoothPermission()
    var onUpdate: (() -> Void)?
    var onVolumeChange: (() -> Void)?
    var onAudioReset: ((Bool) -> Void)?
    var onMessage: ((LocalizedText) -> Void)?
    /// AirPlay 路由读取失败时自动重试，面板活动时持续确认接收端。
    private let routeProbe: AirPlayRouteProbe
    private var route = AirPlayRoute()
    /// 附近 AirPlay 设备：只读发现，当前接收端确认后从列表排除。
    let discovery: AirPlayDiscovery
    var nearbyAirPlay: [DiscoveredAirPlay] {
        AirPlayDiscovery.visible(discovery.devices, selfName: Host.current().localizedName ?? "",
                                 routedName: currentRouteInfo?.displayName)
    }
    private var discoverySubscription: AnyCancellable?
    private var bluetoothSubscription: AnyCancellable?
    private var bluetoothReadingActive = false
    private var routeMonitoringActive = false
    private var bluetoothRefresh: Task<Void, Never>?
    private var bluetoothTarget: String?
    private var bluetoothDevice: AudioDeviceID?
    private var bluetoothClassOfDevice: UInt32?
    private var deviceTarget: String?
    private var device: AudioDeviceID = 0
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private(set) var listenersAvailable = false
    var selectedOutputID: AudioDeviceID { device }

    var currentRouteInfo: AirPlayRoute.Info? { route.info(for: device) }
    var isRouteInfoUnavailable: Bool {
        guard case .airPlay = deviceKind else { return false }
        return currentRouteInfo?.displayName == nil
    }
    var nearbyAirPlayCaption: String {
        L(isRouteInfoUnavailable ? "连接状态未知 · 在系统声音设置中查看" : "在系统声音设置中选择")
    }

    init(discovery: AirPlayDiscovery? = nil, routeProbe: AirPlayRouteProbe? = nil) {
        self.discovery = discovery ?? AirPlayDiscovery()
        self.routeProbe = routeProbe ?? AirPlayRouteProbe()
        self.routeProbe.update = { [weak self] request, info in
            guard let self, self.route.request == request else { return }
            guard AudioOutputIdentity.isCurrent(request) else {
                self.refreshAudio(); self.refreshOutputs()
                return
            }
            self.route.record(info, for: request)
            self.refreshAudio()
            self.refreshOutputs()       // 名称与机型都回填到列表与中央
        }
        discoverySubscription = self.discovery.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        bluetoothSubscription = airpods.$snapshot.sink { [weak self] reply in
            guard let self, let reply, reply.available, reply.valid,
                  self.bluetoothReadingActive, reply.deviceID == self.device,
                  reply.target == self.deviceTarget,
                  self.bluetoothClassOfDevice != reply.classOfDevice else { return }
            self.bluetoothClassOfDevice = reply.classOfDevice
            self.refreshAudio(); self.refreshOutputs()
        }
    }

    /// 面板可见且屏幕活动时才做发现（与热点发现同一策略），关掉即停止浏览。
    func setNearbyDiscoveryActive(_ active: Bool) {
        discovery.setActive(active)
        guard routeMonitoringActive != active else { return }
        routeMonitoringActive = active
        routeProbe.setMonitoring(active)
        if active { retryRoute() }
    }

    func refreshAudio() {
        let oldVolume = volume
        let oldMuted = muted
        let oldDevice = device
        var id: AudioDeviceID = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else {
            volume = nil; muted = false; output = "输出设备不可用"; canVolume = false; canMute = false
            deviceKind = .other
            deviceTarget = nil
            clearRoute()
            setBluetoothReadingActive(bluetoothReadingActive)
            device = 0; installAudioListeners(); onUpdate?(); onAudioReset?(oldDevice != 0); return
        }
        device = id
        let target = AudioOutputIdentity.target(for: id)
        if deviceTarget != target {
            bluetoothClassOfDevice = nil
            clearRoute()
        }
        deviceTarget = target
        if oldDevice != id || audioListeners.isEmpty { installAudioListeners(); onAudioReset?(oldDevice != id) }
        output = "未知输出设备"
        a = address(kAudioObjectPropertyName, global: true)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr { if let name = name?.takeRetainedValue() as String? { output = "\(name)" } }
        var transport: UInt32 = 0
        a = address(kAudioDevicePropertyTransportType, global: true); size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &transport)
        deviceKind = OutputDeviceClassifier.classify(OutputSignals(transport: transport, name: output.string,
                                                                  model: route.model(for: id), classOfDevice: bluetoothClassOfDevice))
        refreshRouteModel(deviceID: id)
        if let routeName = route.name(for: id) { output = "\(routeName)\(L("（AirPlay）"))" }
        setBluetoothReadingActive(bluetoothReadingActive)
        let reading = AudioVolume.read(id)
        volume = reading.value
        canVolume = reading.writable
        var settable = DarwinBoolean(false)
        var mute: UInt32 = 0
        a = address(kAudioDevicePropertyMute); size = UInt32(MemoryLayout<UInt32>.size)
        let muteRead = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &mute) == noErr
        muted = muteRead && mute != 0
        canMute = muteRead && AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        onUpdate?()
        let volumeChanged = oldVolume.flatMap { previous in volume.map { abs(previous-$0) > 0.001 } } ?? false
        if oldDevice == id, volumeChanged || (muteRead && oldMuted != muted) { onVolumeChange?() }

    }
    /// 同一 CoreAudio 身份共用请求；helper 自动重试并在面板活动时刷新接收端。
    private func refreshRouteModel(deviceID: AudioDeviceID) {
        guard case .airPlay = deviceKind else {
            guard route.hasProbed else { return }
            clearRoute()
            return
        }
        guard let target = deviceTarget else { clearRoute(); return }
        guard route.deviceID != deviceID || route.request?.target != target else { return }
        let request = route.begin(deviceID: deviceID, target: target)
        routeProbe.read(request, automaticallyRefresh: true)
    }

    private func clearRoute() {
        routeProbe.cancel()
        route.clear()
        objectWillChange.send()
    }

    func invalidateRoute() { clearRoute() }

    func retryRoute() {
        guard case .airPlay = deviceKind else { return }
        clearRoute(); refreshAudio(); refreshOutputs()
    }

    /// 只在已获蓝牙授权且面板活动时读取。普通蓝牙设备一次，AirPods 电量每三秒刷新。
    func setBluetoothReadingActive(_ active: Bool) {
        bluetoothReadingActive = active
        guard active, bluetoothPermission.authorization == .allowedAlways,
              case .bluetooth = deviceKind, let target = deviceTarget else {
            guard bluetoothTarget != nil || bluetoothRefresh != nil else { return }
            bluetoothRefresh?.cancel(); bluetoothRefresh = nil; bluetoothTarget = nil; bluetoothDevice = nil
            airpods.cancel()
            return
        }
        guard bluetoothTarget != target || bluetoothDevice != device else { return }
        bluetoothRefresh?.cancel(); airpods.cancel()
        bluetoothTarget = target
        bluetoothDevice = device
        let id = device
        let repeatRead = outputIsAirPods
        bluetoothRefresh = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.device == id, self.deviceTarget == target else { return }
                self.airpods.refresh(deviceID: id, target: target)
                guard repeatRead else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }

    func address(_ selector: AudioObjectPropertySelector, global: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: global ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    func refreshOutputs() {
        var a = address(kAudioHardwarePropertyDevices, global: true)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { outputDevices = []; return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard ids.withUnsafeMutableBytes({ AudioObjectGetPropertyData(system, &a, 0, nil, &size, $0.baseAddress!) }) == noErr else { outputDevices = []; return }
        outputDevices = ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = address(kAudioObjectPropertyName, global: true)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let title = name?.takeRetainedValue() as String? else { return nil }
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = address(kAudioDevicePropertyTransportType, global: true)
            _ = AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            let signals = OutputSignals(transport: transport, name: title, model: route.model(for: id),
                                        classOfDevice: id == device ? bluetoothClassOfDevice : nil)
            let kind = OutputDeviceClassifier.classify(signals)
            return OutputChoice(id: id, name: route.name(for: id).map { "\($0)\(L("（AirPlay）"))" } ?? title, glyph: OutputDeviceClassifier.glyph(for: kind))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func setOutput(_ id: AudioDeviceID) {
        refreshOutputs()
        guard outputDevices.contains(where: { $0.id == id }) else { message = "输出设备已不可用，请重试。"; return }
        var selected = id
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, global: true)
        message = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout.size(ofValue: selected)), &selected) == noErr ? "" : "无法切换输出设备。"
        refreshAudio()
    }
    func installAudioListeners() {
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
        var targets: [(AudioObjectID, AudioObjectPropertyAddress)] = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices].map { (AudioObjectID(kAudioObjectSystemObject), address($0, global: true)) }
        if device != 0 {
            targets += AudioVolume.addresses(device).map { (device, $0) }
            targets += [kAudioDevicePropertyMute, kAudioDevicePropertyStreams].map { (device, address($0)) }
            targets.append((device, address(kAudioObjectPropertyName, global: true)))
        }
        var failed = false
        for (id, var attr) in targets where AudioObjectHasProperty(id, &attr) {
            let routeChanged = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices,
                                kAudioDevicePropertyStreams, kAudioObjectPropertyName].contains(attr.mSelector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    if routeChanged { self?.invalidateRoute() }
                    self?.refreshAudio(); self?.refreshOutputs()
                }
            }
            if AudioObjectAddPropertyListenerBlock(id, &attr, .main, block) == noErr { audioListeners.append((id,attr,block)) } else { failed = true }
        }
        listenersAvailable = !failed
    }
    func setVolume(_ value: Double, isLive: Bool) {
        guard isLive, value.isFinite, (0...1).contains(value) else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canVolume else { message = "输出设备已变化或不支持音量控制，请重试。"; return }
        let adjusted = AudioVolume.set(value, device: device)
        message = adjusted ? "" : "未能调节全部声道，请重试。"
        if adjusted && value > 0 && muted {
            if canMute {
                var mute: UInt32 = 0; var a = address(kAudioDevicePropertyMute)
                if AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: mute)), &mute) != noErr {
                    message = "音量已调整，但当前设备无法取消静音。"
                }
            } else { message = "音量已调整，但当前设备不支持取消静音。" }
        }
        refreshAudio()
    }
    func toggleMute(isLive: Bool) {
        guard isLive else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canMute else { message = "输出设备已变化或不支持静音，请重试。"; return }
        var v: UInt32 = muted ? 0 : 1; var a = address(kAudioDevicePropertyMute)
        message = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr ? "" : "当前设备无法切换静音。"
        refreshAudio()
    }
    func stop() {
        routeMonitoringActive = false
        routeProbe.setMonitoring(false)
        bluetoothReadingActive = false
        bluetoothRefresh?.cancel(); bluetoothRefresh = nil; bluetoothTarget = nil; bluetoothDevice = nil
        airpods.cancel()
        clearRoute()
        discovery.setActive(false)
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
    }
}
