import AppKit
import Combine
import ApplicationServices
import ServiceManagement

/// 只读取屏幕上系统窗口的 PID 与透明度，不读取标题或截图，也不请求录屏/辅助功能权限。
enum SystemPermissionAlert {
    static func isAgent(_ bundleIdentifier: String?) -> Bool {
        ["com.apple.UserNotificationCenter", "com.apple.SecurityAgent", "com.apple.coreservices.uiagent"].contains(bundleIdentifier ?? "")
    }

    static func isVisible() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let alpha = window[kCGWindowAlpha as String] as? Double,
                  alpha > 0 else { return false }
            // ponytail: 系统代理窗口只能作为保守保护信号；新增权限宿主时扩展已核实的 bundle ID。
            return isAgent(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
        }
    }
}

@MainActor final class Store: ObservableObject {
    @Published var live = Snapshot()
    @Published var scene: Scene = .live {
        didSet {
            sceneStarted = ProcessInfo.processInfo.systemUptime
            sceneExpiry?.cancel()
            guard let event = scene.event else { return }
            let duration = IconTransition.Timing.eventDuration(event: event, reducedMotion: reduceMotion)
            sceneExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                self?.objectWillChange.send()
            }
        }
    }
    private var sceneStarted = ProcessInfo.processInfo.systemUptime
    private var sceneExpiry: Task<Void, Never>?
    @Published var animate: Bool { didSet { UserDefaults.standard.set(animate, forKey: "animate") } }
    let battery = BatteryStore()
    let audio: AudioStore
    let hotspots = HotspotControl()
    private let mediaPlayback = MediaPlayback()
    @Published var mediaTrack: MediaTrack?
    @Published var mediaVisible = false
    @Published var mediaControlsAvailable = false
    var mediaTitle: String {
        guard let mediaTrack else { return L("未识别到媒体") }
        return mediaTrack.title.isEmpty ? L("正在获取媒体信息") : mediaTrack.title
    }
    @Published var panelVisible = false
    /// 权限请求覆盖整个等待过程；本地网络额外检查系统授权窗口，不能把 waiting 当成用户已拒绝。
    var permissionPromptActive: Bool {
        wifi.isRequestingLocation || wifi.isRequestingSystemPassword
            || audio.bluetoothPermission.isRequestingPermission
            || isSystemPermissionAlertVisible()
    }
    private let isSystemPermissionAlertVisible: () -> Bool
    /// 引导第 1 步把浮层指向真实菜单栏图标；面板打开或离开该步即收起。
    @Published var menuBarPointer = false
    /// 面板窗口真正上屏后才置真。内容入场必须等它，不能用 panelVisible：
    /// 后者在 hosting view 安装前就翻真，新视图首帧即已是真值，onChange 不会触发（卡片会一直不出现）。
    @Published var panelRevealed = false
    /// Which section's detail window is open, if any. The panel and the detail window both read it.
    @Published var detailSection: PanelSection?
    private var hotspotActivity: AnyCancellable?
    private var nearbyAirPlayActivity: AnyCancellable?
    private var bluetoothActivity: AnyCancellable?
    @Published var login = false
    @Published var message: LocalizedText = ""
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published var screenActive = true
    @Published var observation: LocalizedText = "系统监听初始化中"
    @Published var menuDiagnostic: LocalizedText = "尚未检测；不会自动请求授权"
    @Published var checkingMenus = false
    @Published var showMenuPermission = false
    @Published var menuAccessGranted = AXIsProcessTrusted()
    @Published var menuPermissionMessage: LocalizedText = ""
    @Published var foldExperimentMessage: LocalizedText = "折叠实验已暂停：曾同时隐藏 Combo 图标。"
    let foldExperiment = MenuFoldExperiment()
    private var volumeHint: Task<Void, Never>?
    private var centerHint = CenterHint()
    private var centerHintTask: Task<Void, Never>?
    private var wifiChange: AnyCancellable?
    private var lastVolumeChange: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private let network = NetworkStatus()
    let wifi = WiFiControl()
    let menuSetup = MenuBarSetup()
    var snapshot: Snapshot {
        var result = snapshot(for: scene)
        if scene != .live, let event = result.centerEvent {
            let duration = IconTransition.Timing.eventDuration(event: event, reducedMotion: reduceMotion)
            if ProcessInfo.processInfo.systemUptime - sceneStarted >= duration {
                result.centerEvent = nil; result.adjusting = false
            }
        }
        return result
    }
    func snapshot(for scene: Scene) -> Snapshot {
        var result = (scene == .live ? live : Snapshot.demo(scene)).preferringBattery(threshold: battery.displayThreshold)
        if scene == .live {
            result.centerEvent = centerHint.active(at: ProcessInfo.processInfo.systemUptime)
            result.eventSerial = centerHint.serial
        }
        return result
    }
    init(audio audioStore: AudioStore? = nil, isSystemPermissionAlertVisible: (() -> Bool)? = nil) {
        self.audio = audioStore ?? AudioStore()
        self.isSystemPermissionAlertVisible = isSystemPermissionAlertVisible ?? SystemPermissionAlert.isVisible
        animate = UserDefaults.standard.object(forKey: "animate") as? Bool ?? true
        battery.onUpdate = { [weak self] in
            guard let self else { return }
            self.live.battery = self.battery.level
            self.live.charging = self.battery.charging
            self.live.plugged = self.battery.plugged
            self.updateObservation()
        }
        battery.onPowerChange = { [weak self] in self?.showCenterHint(.power) }
        battery.onDisplayThresholdChange = { [weak self] in self?.objectWillChange.send() }
        audio.onUpdate = { [weak self] in
            guard let self else { return }
            self.live.volume = self.audio.volume
            self.live.muted = self.audio.muted
            self.live.output = self.audio.output
            self.live.deviceKind = self.audio.deviceKind
            self.updateObservation()
        }
        audio.onVolumeChange = { [weak self] in self?.showVolumeHint() }
        audio.onAudioReset = { [weak self] changed in
            self?.clearVolumeHint()
            if changed { self?.audio.airpods.cancel() }
        }
        audio.onMessage = { [weak self] in self?.message = $0 }
        network.update = { [weak self] name, symbol in self?.live.network = name; self?.live.symbol = symbol }
        mediaPlayback.update = { [weak self] state in
            self?.live.playing = state.playing
            self?.mediaTrack = state.track
            self?.mediaVisible = state.visible
            self?.mediaControlsAvailable = state.controlsAvailable
        }
        mediaPlayback.setEnabled(true)
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
        nearbyAirPlayActivity = Publishers.CombineLatest3($panelVisible, $screenActive, $scene)
            .map { visible, active, scene in visible && active && scene == .live }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.audio.setNearbyDiscoveryActive(enabled) }
        bluetoothActivity = Publishers.CombineLatest4($panelVisible, $screenActive, $scene, self.audio.bluetoothPermission.$authorization)
            .map { visible, active, scene, authorization in visible && active && scene == .live && authorization == .allowedAlways }
            .removeDuplicates()
            // @Published 在赋值前发出事件，等授权值落地后再读取。
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.audio.setBluetoothReadingActive(enabled) }
        network.refresh()
        battery.start()
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        })
        for (name, active) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true), (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.screenActive = active
                    self?.mediaPlayback.setEnabled(active)
                    if active { self?.audio.invalidateRoute(); self?.refresh() } else { self?.foldExperiment.release() }
                }
            })
        }
    }
    func refresh() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        login = SMAppService.mainApp.status == .enabled
        battery.refreshBattery(); audio.refreshAudio(); audio.refreshOutputs(); network.refresh(); wifi.refresh(); audio.bluetoothPermission.refresh()
    }
    private func updateObservation() {
        observation = audio.listenersAvailable && battery.monitoringAvailable
            ? "电池与音量事件监听已启用" : "部分事件监听不可用；打开面板时刷新"
    }
    func controlMedia(_ command: MediaCommand) { mediaPlayback.command(command) }
    func openMediaSource() {
        guard let bundleID = mediaTrack?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.open(url)
    }
    func openSystemSettings(_ section: String) {
        let extensionID: String
        switch section {
        case "wifi": extensionID = "com.apple.wifi-settings-extension"
        case "battery": extensionID = "com.apple.Battery-Settings.extension"
        case "local-network": extensionID = "com.apple.preference.security?Privacy_LocalNetwork"
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
    func clearVolumeHint() {
        volumeHint?.cancel(); volumeHint = nil; lastVolumeChange = nil; live.adjusting = false
        if centerHint.event == .volume { centerHint.clear(); centerHintTask?.cancel() }
    }
    private func showCenterHint(_ event: CenterEvent) {
        centerHintTask?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        let reduced = reduceMotion || live.reducedMotion
        centerHint.show(event, at: now,
                        duration: IconTransition.Timing.eventDuration(event: event, reducedMotion: reduced),
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
        showCenterHint(.volume)
        volumeHint = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            self.live.adjusting = volumeHintActive(changedAt: self.lastVolumeChange, now: ProcessInfo.processInfo.systemUptime)
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; message = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 Combo。" : "" }
        catch { message = "登录项设置未完成：\(error.localizedDescription)" }
        login = SMAppService.mainApp.status == .enabled
    }
    func resetDisplay() { animate = true; battery.displayThreshold = 50 }
    func stop() {
        mediaPlayback.stop()
        centerHintTask?.cancel(); sceneExpiry?.cancel(); wifiChange?.cancel()
        battery.stop()
        audio.stop()
        hotspotActivity?.cancel(); hotspots.stop()
        nearbyAirPlayActivity?.cancel(); audio.setNearbyDiscoveryActive(false)
        bluetoothActivity?.cancel()
        foldExperiment.release()
        clearVolumeHint(); network.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
