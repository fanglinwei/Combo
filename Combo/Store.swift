import AppKit
import Combine
import CoreAudio
import IOKit.ps
import ApplicationServices
import ServiceManagement

struct OutputChoice: Identifiable {
    let id: AudioDeviceID
    let name: String
    var symbol: String = "speaker.wave.2"
}

@MainActor final class Store: ObservableObject {
    @Published var live = Snapshot()
    @Published var scene: Scene = .live {
        didSet {
            sceneStarted = ProcessInfo.processInfo.systemUptime
            sceneExpiry?.cancel()
            guard scene.event != nil else { return }
            let duration = IconTransition.Timing.eventDuration(reducedMotion: reduceMotion)
            sceneExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                self?.objectWillChange.send()
            }
        }
    }
    private var sceneStarted = ProcessInfo.processInfo.systemUptime
    private var sceneExpiry: Task<Void, Never>?
    @Published var animate: Bool { didSet { UserDefaults.standard.set(animate, forKey: "animate") } }
    @Published var batteryDisplayThreshold: Int { didSet { UserDefaults.standard.set(batteryDisplayThreshold, forKey: "batteryDisplayThreshold") } }
    @Published var energyAppLimit: Int { didSet { UserDefaults.standard.set(EnergyApps.displayLimit(energyAppLimit), forKey: "energyAppLimit") } }
    let energyApps = EnergyApps()
    let hotspots = HotspotControl()
    let airpods = AirPodsControl()
    @Published var panelVisible = false
    private var hotspotActivity: AnyCancellable?
    @Published var login = false
    @Published var message = ""
    @Published var outputDevices: [OutputChoice] = []
    @Published var batteryHealth = "未提供"
    @Published var lowPowerMode = false
    let powerMode = PowerModeControl()
    let chargeControl = ChargeControl()
    @Published var batteryOnAC: Bool?
    @Published var batteryCharging: Bool?
    @Published var batteryCharged: Bool?
    @Published var batteryLimitBlocked: Bool?
    @Published var chargeLimit: ChargeLimit = .unknown
    private var chargeLimitProcess: Process?
    private var chargeLimitTimeout: DispatchWorkItem?
    private var powerObserver: NSObjectProtocol?
    var batterySourceText: String { batteryOnAC.map { $0 ? "电源适配器" : "电池" } ?? "无法判断" }
    var batteryStatusText: String {
        batteryChargeText(onAC: batteryOnAC, charging: batteryCharging, charged: batteryCharged, limitBlocked: batteryLimitBlocked, limit: chargeLimit)
    }
    var canRequestFullCharge: Bool {
        canChargeToFull(scene: scene, onAC: batteryOnAC, charging: batteryCharging,
                        battery: live.battery, limitBlocked: batteryLimitBlocked, limit: chargeLimit)
    }
    func requestFullCharge() {
        guard canRequestFullCharge, case .value(let limit) = chargeLimit else { return }
        chargeControl.request(expectedLimit: limit) { [weak self] in self?.refreshBattery() }
    }
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published var screenActive = true
    @Published var observation = "系统监听初始化中"
    @Published var menuDiagnostic = "尚未检测；不会自动请求授权"
    @Published var checkingMenus = false
    @Published var showMenuPermission = false
    @Published var menuAccessGranted = AXIsProcessTrusted()
    @Published var menuPermissionMessage = ""
    @Published var foldExperimentMessage = "折叠实验已暂停：曾同时隐藏 Combo 图标。"
    let foldExperiment = MenuFoldExperiment()
    private var batterySource: CFRunLoopSource?
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var volumeHint: Task<Void, Never>?
    private var powerChange = PowerChange()
    private var centerHint = CenterHint()
    private var centerHintTask: Task<Void, Never>?
    private var wifiChange: AnyCancellable?
    private var lastVolumeChange: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private let network = NetworkStatus()
    let wifi = WiFiControl()
    let menuSetup = MenuBarSetup()
    private var device: AudioDeviceID = 0
    var selectedOutputID: AudioDeviceID { device }
    var canVolume = false
    var canMute = false
    var snapshot: Snapshot {
        var result = snapshot(for: scene)
        if scene != .live, result.centerEvent != nil {
            let duration = IconTransition.Timing.eventDuration(reducedMotion: reduceMotion)
            if ProcessInfo.processInfo.systemUptime - sceneStarted >= duration {
                result.centerEvent = nil; result.adjusting = false
            }
        }
        return result
    }
    func snapshot(for scene: Scene) -> Snapshot {
        var result = (scene == .live ? live : Snapshot.demo(scene)).preferringBattery(threshold: batteryDisplayThreshold)
        if scene == .live {
            result.centerEvent = centerHint.active(at: ProcessInfo.processInfo.systemUptime)
            result.eventSerial = centerHint.serial
        }
        return result
    }
    init() {
        animate = UserDefaults.standard.object(forKey: "animate") as? Bool ?? true
        batteryDisplayThreshold = min(100, max(0, UserDefaults.standard.object(forKey: "batteryDisplayThreshold") as? Int ?? 50))
        energyAppLimit = EnergyApps.displayLimit(UserDefaults.standard.object(forKey: "energyAppLimit") as? Int ?? 1)
        network.update = { [weak self] name, symbol in self?.live.network = name; self?.live.symbol = symbol }
        wifiChange = wifi.$connecting.dropFirst().sink { [weak self] connecting in
            self?.live.wifiConnecting = connecting
            if !connecting { self?.network.refresh() }
        }
        hotspotActivity = Publishers.CombineLatest3($panelVisible, $screenActive, wifi.$powerOn)
            .map { visible, active, power in visible && active && power == true }
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.hotspots.start() } else { self?.hotspots.stop() }
            }
        network.refresh()
        batterySource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<Store>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.refreshBattery() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let batterySource { CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .commonModes) }
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        }
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for (name, active) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true), (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.screenActive = active
                    if active { self?.refresh() } else { self?.foldExperiment.release() }
                }
            })
        }
    }
    func refresh() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        login = SMAppService.mainApp.status == .enabled
        refreshBattery(); refreshAudio(); refreshOutputs(); network.refresh(); wifi.refresh()
    }
    func refreshBattery() {
        live.battery = nil; live.charging = false; live.plugged = false
        batteryHealth = "未提供"
        batteryOnAC = nil; batteryCharging = nil; batteryCharged = nil; batteryLimitBlocked = nil
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            var found = false
            for item in list {
                guard let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                found = true
                if let current = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 { live.battery = min(1, Swift.max(0, current / max)) } else { live.battery = nil }
                batteryCharging = d[kIOPSIsChargingKey] as? Bool
                batteryCharged = d[kIOPSIsChargedKey] as? Bool
                if let source = d[kIOPSPowerSourceStateKey] as? String {
                    batteryOnAC = source == kIOPSACPowerValue ? true : source == kIOPSBatteryPowerValue ? false : nil
                }
                live.charging = batteryCharging ?? false
                live.plugged = batteryOnAC ?? false
                if let health = d[kIOPSBatteryHealthKey] as? String {
                    batteryHealth = health == kIOPSGoodValue ? "良好" : health == kIOPSFairValue ? "一般" : health == kIOPSPoorValue ? "需检修" : "未提供"
                }
            }
            if !found { live.battery = nil }
        }
        if powerChange.update(onAC: batteryOnAC) { showCenterHint(.power) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let data = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let reason = data["NotChargingReason"] as? NSNumber {
                // Community-observed bit (OpenDente BatteryState); absent data stays unknown.
                batteryLimitBlocked = reason.uint64Value & 0x1000000 != 0
            }
        }
        refreshChargeLimit()
        Task { await powerMode.refresh() }
        chargeControl.refresh()
    }
    private func refreshChargeLimit() {
        guard chargeLimitProcess == nil else { return }
        chargeLimit = .loading
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; process.environment = environment
        process.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = finished.terminationStatus == 0 ? parseChargeLimit(String(decoding: data, as: UTF8.self)) : .unknown
            Task { @MainActor in
                guard let self, self.chargeLimitProcess === finished else { return }
                self.chargeLimitTimeout?.cancel(); self.chargeLimitTimeout = nil
                self.chargeLimitProcess = nil; self.chargeLimit = result
            }
        }
        chargeLimitProcess = process
        do { try process.run() } catch { chargeLimitProcess = nil; chargeLimit = .unknown; return }
        let timeout = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, self.chargeLimitProcess === process else { return }
            self.chargeLimit = .unknown
            self.chargeLimitProcess = nil; self.chargeLimitTimeout = nil
            if process.isRunning { process.terminate() }
        }
        chargeLimitTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    }
    func refreshAudio() {
        let oldVolume = live.volume
        let oldDevice = device
        var id: AudioDeviceID = 0
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != 0 else {
            live.volume = nil; live.muted = false; live.output = "输出设备不可用"; canVolume = false; canMute = false
            device = 0; installAudioListeners(); clearVolumeHint(); return
        }
        device = id
        if oldDevice != id || audioListeners.isEmpty { installAudioListeners(); clearVolumeHint() }
        live.output = "未知输出设备"
        a = address(kAudioObjectPropertyName, global: true)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr { live.output = name?.takeRetainedValue() as String? ?? "未知输出设备" }
        let volume = AudioVolume.read(id)
        live.volume = volume.value
        canVolume = volume.writable
        var settable = DarwinBoolean(false)
        var mute: UInt32 = 0
        a = address(kAudioDevicePropertyMute); size = UInt32(MemoryLayout<UInt32>.size)
        let muteRead = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &mute) == noErr
        live.muted = muteRead && mute != 0
        canMute = muteRead && AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
        if oldDevice != id { airpods.cancel() }
        if oldDevice == id, let previous = oldVolume, let current = live.volume, abs(previous-current) > 0.001 { showVolumeHint() }

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
            let symbol: String
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn: symbol = "laptopcomputer"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: symbol = "display"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                symbol = title.localizedCaseInsensitiveContains("AirPods") ? "airpodspro" : "headphones"
            case kAudioDeviceTransportTypeAirPlay: symbol = "airplay.audio"
            default: symbol = "speaker.wave.2"
            }
            return OutputChoice(id: id, name: title, symbol: symbol)
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
    func openSystemSettings(_ section: String) {
        let extensionID: String
        switch section {
        case "wifi": extensionID = "com.apple.wifi-settings-extension"
        case "battery": extensionID = "com.apple.Battery-Settings.extension"
        default: extensionID = "com.apple.Sound-Settings.extension"
        }
        guard let url = URL(string: "x-apple.systempreferences:\(extensionID)"), NSWorkspace.shared.open(url) else {
            message = "无法打开系统设置；请手动进入相应的 Wi‑Fi、电池或声音页面。"
            return
        }
        message = ""
    }
    func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        if !NSWorkspace.shared.open(url) { message = "无法打开活动监视器；请从“应用程序 → 实用工具”打开。" }
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
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.refreshAudio(); self?.refreshOutputs() } }
            if AudioObjectAddPropertyListenerBlock(id, &attr, .main, block) == noErr { audioListeners.append((id,attr,block)) } else { failed = true }
        }
        observation = failed || batterySource == nil ? "部分事件监听不可用；打开面板时刷新" : "电池与音量事件监听已启用"
    }
    func clearVolumeHint() {
        volumeHint?.cancel(); volumeHint = nil; lastVolumeChange = nil; live.adjusting = false
        if centerHint.event == .volume { centerHint.clear(); centerHintTask?.cancel() }
    }
    private func showCenterHint(_ event: CenterEvent) {
        centerHintTask?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        let reduced = reduceMotion || live.reducedMotion
        centerHint.show(event, at: now,
                        duration: IconTransition.Timing.eventDuration(reducedMotion: reduced),
                        entrance: reduced ? IconTransition.Timing.reduced : IconTransition.Timing.hide + IconTransition.Timing.grow)
        objectWillChange.send()
        let delay = max(0, centerHint.deadline - now)
        centerHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.objectWillChange.send()
        }
    }
    func showVolumeHint() {
        volumeHint?.cancel()
        lastVolumeChange = ProcessInfo.processInfo.systemUptime; live.adjusting = true
        if live.playing { showCenterHint(.volume) }
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
        message = AudioVolume.set(value, device: device) ? "" : "未能调节全部声道，请重试。"
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
    func resetDisplay() { animate = true; batteryDisplayThreshold = 50 }
    func stop() {
        centerHintTask?.cancel(); sceneExpiry?.cancel(); wifiChange?.cancel()
        chargeControl.stop()
        energyApps.cancel()
        airpods.cancel()
        hotspotActivity?.cancel(); hotspots.stop()
        chargeLimitTimeout?.cancel()
        if let process = chargeLimitProcess, process.isRunning { process.terminate() }
        chargeLimitProcess = nil
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        foldExperiment.release()
        clearVolumeHint(); network.stop()
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes); CFRunLoopSourceInvalidate(batterySource) }
        for (object, var attr, block) in audioListeners { AudioObjectRemovePropertyListenerBlock(object, &attr, .main, block) }
        audioListeners.removeAll()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
