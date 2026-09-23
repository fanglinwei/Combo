import AppKit
import Combine
import CoreAudio
import IOKit.ps
import ApplicationServices
import ServiceManagement

@MainActor final class Store: ObservableObject {
    @Published var live = Snapshot()
    @Published var scene: Scene = .live
    @Published var center: String { didSet { UserDefaults.standard.set(center, forKey: "center") } }
    @Published var animate: Bool { didSet { UserDefaults.standard.set(animate, forKey: "animate") } }
    @Published var login = false
    @Published var message = ""
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published var screenActive = true
    @Published var observation = "系统监听初始化中"
    @Published var menuDiagnostic = "尚未检测；不会自动请求授权"
    @Published var checkingMenus = false
    @Published var showMenuPermission = false
    @Published var menuAccessGranted = AXIsProcessTrusted()
    @Published var menuPermissionMessage = ""
    private var batterySource: CFRunLoopSource?
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var volumeHint: Task<Void, Never>?
    private var lastVolumeChange: TimeInterval?
    private var dateTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let network = NetworkStatus()
    private var device: AudioDeviceID = 0
    var canVolume = false
    var canMute = false
    var snapshot: Snapshot { scene == .live ? live : Snapshot.demo(scene) }
    init() {
        center = UserDefaults.standard.string(forKey: "center") ?? "电量百分比"
        animate = UserDefaults.standard.object(forKey: "animate") as? Bool ?? true
        network.update = { [weak self] name, symbol in self?.live.network = name; self?.live.symbol = symbol }
        network.refresh()
        batterySource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.refreshBattery() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let batterySource { CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .commonModes) }
        refresh()
        // Date changes need a UI tick, not continuous hardware polling.
        dateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.screenActive else { return }
                self.live.day = String(format: "%02d", Calendar.current.component(.day, from: Date()))
            }
        }
        let nc = NSWorkspace.shared.notificationCenter
        for (name, active) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true), (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screenActive = active; if active { self?.refresh() } }
            })
        }
    }
    func refresh() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        login = SMAppService.mainApp.status == .enabled
        refreshBattery(); refreshAudio(); network.refresh()
    }
    func refreshBattery() {
        live.battery = nil; live.charging = false; live.plugged = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            var found = false
            for item in list {
                guard let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                found = true
                if let current = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 { live.battery = min(1, Swift.max(0, current / max)) } else { live.battery = nil }
                live.charging = d[kIOPSIsChargingKey] as? Bool ?? false
                live.plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            }
            if !found { live.battery = nil }
        }
    }
    func refreshAudio() {
        let oldVolume = live.volume
        let oldDevice = device
        var id: AudioDeviceID = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else {
            live.volume = nil; live.muted = false; live.headphones = false; live.output = "输出设备不可用"; canVolume = false; canMute = false
            device = 0; installAudioListeners(); clearVolumeHint(); return
        }
        device = id
        if oldDevice != id || audioListeners.isEmpty { installAudioListeners(); clearVolumeHint() }
        live.output = "未知输出设备"; live.headphones = false
        a = address(kAudioObjectPropertyName, global: true)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr { live.output = name?.takeRetainedValue() as String? ?? "未知输出设备" }
        var volume: Float32 = 0
        a = address(kAudioDevicePropertyVolumeScalar)
        size = UInt32(MemoryLayout<Float32>.size)
        let read = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &volume) == noErr
        live.volume = read && volume.isFinite && (0...1).contains(volume) ? Double(volume) : nil
        var settable = DarwinBoolean(false)
        canVolume = read && AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        var mute: UInt32 = 0
        a = address(kAudioDevicePropertyMute); size = UInt32(MemoryLayout<UInt32>.size)
        let muteRead = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &mute) == noErr
        live.muted = muteRead && mute != 0
        canMute = muteRead && AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        // Only the Core Audio terminal type can identify generic headphones here.
        var streamsAddress = address(kAudioDevicePropertyStreams)
        var streamSize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &streamSize) == noErr, streamSize > 0, streamSize < 4096 {
            var streams = [AudioStreamID](repeating: 0, count: Int(streamSize)/MemoryLayout<AudioStreamID>.size)
            let result = streams.withUnsafeMutableBytes { AudioObjectGetPropertyData(id, &streamsAddress, 0, nil, &streamSize, $0.baseAddress!) }
            if result == noErr {
                for stream in streams {
                    var terminal: UInt32 = 0; var length = UInt32(MemoryLayout<UInt32>.size)
                    var attr = address(kAudioStreamPropertyTerminalType, global: true)
                    if AudioObjectGetPropertyData(stream, &attr, 0, nil, &length, &terminal) == noErr, terminal == kAudioStreamTerminalTypeHeadphones { live.headphones = true }
                }
            }
        }
        if oldDevice == id, let previous = oldVolume, let current = live.volume, abs(previous-current) > 0.001 { showVolumeHint() }

    }
    func address(_ selector: AudioObjectPropertySelector, global: Bool = false) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: global ? kAudioObjectPropertyScopeGlobal : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    func installAudioListeners() {
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
        var targets: [(AudioObjectID, AudioObjectPropertyAddress)] = [(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice, global: true))]
        if device != 0 {
            targets += [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute, kAudioDevicePropertyStreams].map { (device, address($0)) }
            targets.append((device, address(kAudioObjectPropertyName, global: true)))
        }
        var failed = false
        for (id, var attr) in targets where AudioObjectHasProperty(id, &attr) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.refreshAudio() } }
            if AudioObjectAddPropertyListenerBlock(id, &attr, .main, block) == noErr { audioListeners.append((id,attr,block)) } else { failed = true }
        }
        observation = failed || batterySource == nil ? "部分事件监听不可用；打开面板时刷新" : "电池与音量事件监听已启用"
    }
    func clearVolumeHint() { volumeHint?.cancel(); volumeHint = nil; lastVolumeChange = nil; live.adjusting = false }
    func showVolumeHint() {
        volumeHint?.cancel()
        lastVolumeChange = ProcessInfo.processInfo.systemUptime; live.adjusting = true
        volumeHint = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            self.live.adjusting = volumeHintActive(changedAt: self.lastVolumeChange, now: ProcessInfo.processInfo.systemUptime)
        }
    }
    func setVolume(_ value: Double) {
        guard scene == .live, value.isFinite, (0...1).contains(value) else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canVolume else { message = "输出设备已变化或不支持音量控制，请重试。"; return }
        var v = Float32(value); var a = address(kAudioDevicePropertyVolumeScalar)
        message = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr ? "" : "当前设备无法调节音量。"
        refreshAudio()
    }
    func toggleMute() {
        guard scene == .live else { return }
        let selectedDevice = device; refreshAudio()
        guard device == selectedDevice, canMute else { message = "输出设备已变化或不支持静音，请重试。"; return }
        var v: UInt32 = live.muted ? 0 : 1; var a = address(kAudioDevicePropertyMute)
        message = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: v)), &v) == noErr ? "" : "当前设备无法切换静音。"
        refreshAudio()
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; message = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 Combo。" : "" }
        catch { message = "登录项设置未完成：\(error.localizedDescription)" }
        login = SMAppService.mainApp.status == .enabled
    }
    func resetDisplay() { center = "电量百分比"; animate = true }
    func stop() {
        dateTimer?.invalidate(); clearVolumeHint(); network.stop()
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes); CFRunLoopSourceInvalidate(batterySource) }
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
