import AppKit
import SwiftUI
import Combine

final class ComboPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store: Store

    private let panelWorkspaceNotifications: NotificationCenter
    private let monitorsGlobalPanelClicks: Bool

    override convenience init() {
        self.init(store: nil)
    }

    init(store: Store?, panelWorkspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         monitorsGlobalPanelClicks: Bool = true) {
        self.store = store ?? Store()
        self.panelWorkspaceNotifications = panelWorkspaceNotifications
        self.monitorsGlobalPanelClicks = monitorsGlobalPanelClicks
        super.init()
    }
    var status: NSStatusItem!
    var panel: ComboPanel?
    private var overviewHeight: CGFloat = 0
    /// 开合进行中冻结 frame 更新，避免内容测量打断运动。
    private var revealing = false
    private var panelLocalMonitor: Any?
    private var panelGlobalMonitor: Any?
    private var dismissalObservers: [NSObjectProtocol] = []
    private var normalApplicationPID: pid_t?
    private var permissionReturnPID: pid_t?
    private var pointerWindow: NSPanel?
    private var pointerChange: AnyCancellable?
    private var detailChange: AnyCancellable?
    private var escapeMonitor: Any?
    private var revealTask: Task<Void, Never>?
    var settings: NSWindow?
    private var settingsAction: (() -> Void)?
    private var settingsRequested = false
    private var returnToPanelAfterSettings = false
    private var settingsClose: AnyCancellable?
    private var settingsResize: AnyCancellable?
    private var settingsContentHeight: CGFloat?
    private var guideContentHeight: CGFloat?
    private var settingsTargetFrame: NSRect?
    /// 引导这一步要不要压在别人上面；真正的层级由 applyGuideLevel 结合前台应用决定。
    private var guideWantsTop = false
    private var settingsFrameBeforeGuide: NSRect?
    private var activationObserver: NSObjectProtocol?
    var change: AnyCancellable?
    private var appearanceChange: AnyCancellable?
    private var languageChange: AnyCancellable?
    var animator: Timer?
    private var iconTransition = IconTransition()
    private var bottomTransition = BottomTransition()
    private var panelHighlight = PanelHighlightTransition()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppUpdater.shared.start()
        #if COMBO_TEST_HOST
        buildApplicationMenu()
        #endif
        status = NSStatusBar.system.statusItem(withLength: 30)
        status.button?.target = self; status.button?.action = #selector(statusItemClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.wantsLayer = true
        status.button?.layer?.cornerRadius = 12
        change = store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
        detailChange = store.$detailSection.removeDuplicates().sink { [weak self] section in
            DispatchQueue.main.async { self?.updatePanelSection(section) }
        }
        pointerChange = store.$menuBarPointer.removeDuplicates().sink { [weak self] show in
            DispatchQueue.main.async { self?.updatePointer(show) }
        }
        appearanceChange = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateWindowAppearance() } }
        languageChange = Localization.shared.$language.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateLanguage() } }
        // 切到系统设置时把引导让下去；切回 Combo 再抬起来。
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let active = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.applyGuideLevel(active: active) }
        }
        updateIcon()
        let showSettings = OnboardingState.showsGuide() || CommandLine.arguments.contains("--settings")
        if showSettings {
            openSettings()
        }
    }
    private var selectedAppearance: NSAppearance? {
        (ComboAppearance(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system).nsAppearance
    }
    func updateWindowAppearance() {
        let appearance = selectedAppearance
        settings?.appearance = appearance
        panel?.appearance = appearance
    }
    func localizeServicesMenu() {
        guard let services = NSApp.servicesMenu else { return }
        services.title = L("服务")
        services.supermenu?.items.first(where: { $0.submenu === services })?.title = services.title
    }

    @objc func checkForUpdates() { AppUpdater.shared.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(checkForUpdates) || AppUpdater.shared.canCheckForUpdates
    }

    private func updateLanguage() {
        #if COMBO_TEST_HOST
        buildApplicationMenu()
        #endif
        settings?.title = L("Combo 设置")
        drawIcon()
    }
    func updateIcon() {
        guard status != nil else { return }
        let s = store.snapshot
        let now = ProcessInfo.processInfo.systemUptime
        iconTransition.update(IconContent(s), at: now,
                              reducedMotion: s.reducedMotion || store.reduceMotion, active: store.screenActive)
        bottomTransition.update(s, animate: store.animate, at: now,
                                reducedMotion: s.reducedMotion || store.reduceMotion, active: store.screenActive)
        panelHighlight.update(active: store.panelVisible, animate: store.animate, at: now,
                              reducedMotion: s.reducedMotion || store.reduceMotion)
        drawIcon()
    }
    func drawIcon() {
        let s = store.snapshot
        let now = ProcessInfo.processInfo.systemUptime
        let transitioning = (iconTransition.isAnimating(at: now) || bottomTransition.isAnimating(at: now)
                             || panelHighlight.isAnimating(at: now)) && store.screenActive
        let playing = s.playing && store.animate && !s.silenced && !s.adjusting && !s.reducedMotion && !store.reduceMotion && store.screenActive
        let interval = transitioning ? 1.0 / 60 : 0.05
        let connecting = s.wifiConnecting && !s.reducedMotion && !store.reduceMotion && store.screenActive
        if transitioning || playing || connecting {
            if animator?.timeInterval != interval {
                animator?.invalidate()
                let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.drawIcon() } }
                RunLoop.main.add(timer, forMode: .common)
                animator = timer
            }
        } else { animator?.invalidate(); animator = nil }
        let phase = store.reduceMotion ? 0.3 : now / 1.2
        let image = IconRenderer.image(s, animate: store.animate, size: 22, phase: phase, dark: status.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                                       transition: iconTransition.frame(at: now), bottomProgress: bottomTransition.value(at: now))
        image.isTemplate = false
        status.button?.image = image
        let highlight = panelHighlight.value(at: now)
        status.button?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22 * highlight).cgColor
        let description = L("\(store.scene == .live ? "" : L("演示 · "))\(s.powerHintText)电量 \(s.batteryText) · \(LKey(s.network)) · 音量 \(s.volumeText)")
        if status.button?.toolTip != description {
            status.button?.toolTip = description
            status.button?.setAccessibilityLabel(description)
        }
    }
    @objc func statusItemClicked() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            guard let button = status.button else { return }
            if store.panelVisible { closePanel() }
            makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else {
            togglePanel()
        }
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        for (section, title) in [(PanelSection.battery, L("电池")), (.sound, L("音量")), (.wifi, L("Wi‑Fi"))] {
            let item = menu.addItem(withTitle: title, action: #selector(openStatusDetail(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = section.rawValue
        }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L("退出 Combo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        return menu
    }

    @objc func openStatusDetail(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let section = PanelSection(rawValue: value) else { return }
        store.detailSection = section
        if !store.panelVisible { togglePanel() }
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePanel() {
        if store.panelVisible { closePanel() }
        else if let screen = status.button?.window?.screen ?? NSScreen.main {
            store.refresh()
            let visible = screen.visibleFrame
            // Reuse the measured height so opening does not resize the surface mid-flight.
            let height = min(overviewHeight > 0 ? overviewHeight : 500, visible.height - 16)
            let frame = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8,
                               width: PanelView.width, height: height)
            revealing = true
            revealTask?.cancel()
            // Reverse a closing panel in place, preserving its live frame, alpha and card state.
            if let window = panel, window.isVisible {
                store.panelVisible = true
                startPanelDismissalMonitoring()
                store.panelRevealed = true
                revealTask = Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    await self.runPanelReveal(window, to: frame)
                }
                return
            }
            store.panelExpanded = false
            store.panelRevealed = false
            overviewHeight = 0
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let view = PanelView(store: store, showSettings: showSettings, maxHeight: visible.height - 16,
                                 reportHeight: { [weak self] value in self?.updatePanelHeight(value) })
            let window = panel ?? ComboPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            // 起始偏移只由 reveal task 决定（它在动画前才读一次 reduceMotion）。这里再提前 setFrame
            // 会变成两次读取，两次之间偏好被改就会先落在偏移位、再跳回静止位。
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
            // A fully closed window rests offscreen; restore its anchor before measuring.
            window.setFrame(frame, display: false)
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            store.panelVisible = true
            startPanelDismissalMonitoring()
            hosting.layoutSubtreeIfNeeded()
            updatePanelHeight(overviewHeight)
        }
    }
    private func updatePanelHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let hadMeasurement = overviewHeight > 0
        overviewHeight = ceil(value)
        if revealing && !store.panelRevealed, let window = panel, window.isVisible, store.panelVisible {
            revealTask?.cancel()
            revealTask = Task { @MainActor [weak self, weak window] in
                guard !Task.isCancelled, let self, let window, self.panel === window, window.isVisible,
                      let screen = window.screen else { return }
                // Start only after SwiftUI reports the content's actual height.
                let visible = screen.visibleFrame
                let height = min(self.overviewHeight, visible.height - 16)
                let target = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8,
                                    width: PanelView.width, height: height)
                var start = target
                if !self.store.reduceMotion { start.origin.x += Motion.panelOffset }
                window.setFrame(start, display: false)
                self.store.panelRevealed = true
                await self.runPanelReveal(window, to: target)
            }
            return
        }
        updatePanelFrame(animated: hadMeasurement)
    }
    private func updatePanelFrame(animated: Bool = false) {
        guard store.panelVisible, !revealing else { return }
        guard let panel, let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let height = min(max(1, overviewHeight > 0 ? overviewHeight : panel.frame.height), max(1, visible.height - 16))
        let frame = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8, width: PanelView.width, height: height)
        let growth = abs(panel.frame.height - frame.height)
        guard growth > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5 else { return }
        // The first measurement after opening is the panel's real size — snap. Later content changes
        // (media card, message) ease in instead of teleporting.
        // 首次定位直接落定；之后内容变化（媒体卡出现、提示行）才 0.18s 缓动，避免高度瞬跳。
        // growth 上限 120pt 是安全阀：异常大的跳变（首次测量）不走动画。
        guard animated, !store.reduceMotion, growth < 120 else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.detailResize
            context.timingFunction = Motion.out
            panel.animator().setFrame(frame, display: true)
        }
    }
    /// 欢迎页的贴边浮层：落在真实状态栏图标正下方，忽略鼠标事件、不抢焦点，只负责指路。
    /// 状态栏窗口在启动后一拍才落位，太早读到的是零高度占位 frame，所以要等它有效再放。
    private func updatePointer(_ show: Bool, attempt: Int = 0) {
        guard show else {
            pointerWindow?.orderOut(nil)
            return
        }
        guard let button = status.button, let anchorWindow = button.window,
              let screen = anchorWindow.screen ?? NSScreen.main else { return }
        // 状态栏窗口落位前 frame 高度为 0，此时窗口内坐标还换不成屏幕坐标。
        guard anchorWindow.frame.height > 0 else {
            guard attempt < 20 else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.store.menuBarPointer else { return }
                self.updatePointer(true, attempt: attempt + 1)
            }
            return
        }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = NSSize(width: 240, height: 68)
        let frame = NSRect(origin: calloutOrigin(anchor: anchor, size: size, visible: screen.visibleFrame), size: size)
        let pointer = pointerWindow ?? NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if pointerWindow == nil {
            pointer.appearance = selectedAppearance
            pointer.isOpaque = false
            pointer.backgroundColor = .clear
            pointer.hasShadow = true
            pointer.level = .floating
            pointer.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            pointer.ignoresMouseEvents = true
            pointerWindow = pointer
        }
        if !pointer.isVisible {
            pointer.contentView = NSHostingView(rootView: MenuBarCallout(reduceMotion: store.reduceMotion))
        }
        pointer.setFrame(frame, display: false)
        pointer.orderFront(nil)
    }

    func updatePanelSection(_ section: PanelSection?) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        guard section != nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.store.panelVisible, event.window === self.panel,
                  self.store.detailSection != nil else { return event }
            self.handleDetailEscape()
            return nil
        }
    }
    func handleDetailEscape() {
        store.detailSection = nil
    }

    // Native animators retarget the current frame and alpha when opening reverses a close.
    private func runPanelReveal(_ window: NSWindow, to target: NSRect) async {
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = store.reduceMotion ? Motion.reducedFade : Motion.panelReveal
            context.timingFunction = Motion.panelEase
            window.animator().alphaValue = 1
            if !store.reduceMotion { window.animator().setFrame(target, display: true) }
        }
        guard !Task.isCancelled, panel === window, window.isVisible else { return }
        revealing = false
        updatePanelFrame(animated: true)
        store.panelExpanded = true
    }

    private func startPanelDismissalMonitoring() {
        guard panelLocalMonitor == nil else { return }
        normalApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        permissionReturnPID = nil
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        panelLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.handlePanelMouseDown(at: point, in: event.window)
            return event
        }
        if monitorsGlobalPanelClicks {
            panelGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
                MainActor.assumeIsolated { self?.handlePanelMouseDown(at: NSEvent.mouseLocation) }
            }
        }
        dismissalObservers.append(panelWorkspaceNotifications.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.handlePanelApplicationSwitch(to: app.processIdentifier, bundleIdentifier: app.bundleIdentifier) }
        })
        dismissalObservers.append(panelWorkspaceNotifications.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPanelAutomatically(interactionInside: false) }
        })
    }

    private func stopPanelDismissalMonitoring() {
        if let panelLocalMonitor { NSEvent.removeMonitor(panelLocalMonitor); self.panelLocalMonitor = nil }
        if let panelGlobalMonitor { NSEvent.removeMonitor(panelGlobalMonitor); self.panelGlobalMonitor = nil }
        dismissalObservers.forEach { panelWorkspaceNotifications.removeObserver($0) }
        dismissalObservers.removeAll()
        permissionReturnPID = nil
    }

    /// 面板和菜单栏图标组成同一次交互；不依赖窗口是否取得 key。
    func handlePanelMouseDown(at point: CGPoint, in window: NSWindow? = nil) {
        guard store.panelVisible else { return }
        if let panel, panel.isVisible,
           panel === window || panel.frame.contains(point) || window?.parent === panel || window?.sheetParent === panel { return }
        if let button = status?.button, let anchor = button.window,
           anchor.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        dismissPanelAutomatically(interactionInside: false)
    }

    func handlePanelApplicationSwitch(to processIdentifier: pid_t, bundleIdentifier: String? = nil) {
        guard store.panelVisible else { return }
        if SystemPermissionAlert.isAgent(bundleIdentifier) || store.permissionPromptActive
            || permissionRequestStarting(store.audio.discovery.askedAt, now: ProcessInfo.processInfo.systemUptime) {
            permissionReturnPID = normalApplicationPID
            return
        }
        if permissionReturnPID == processIdentifier {
            permissionReturnPID = nil
            normalApplicationPID = processIdentifier
            return
        }
        permissionReturnPID = nil
        normalApplicationPID = processIdentifier
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        dismissPanelAutomatically(interactionInside: false)
    }

    private func dismissPanelAutomatically(interactionInside: Bool) {
        guard shouldDismissPanel(panelVisible: store.panelVisible,
                                 permissionPrompt: store.permissionPromptActive || NSApp.modalWindow != nil,
                                 interactionInside: interactionInside) else { return }
        closePanel()
    }

    // Reduce Motion retains only the fade.
    private func closePanel() {
        stopPanelDismissalMonitoring()
        revealTask?.cancel()
        store.panelRevealed = false
        store.panelSettingsFocusRequested = false
        store.panelVisible = false
        guard let panel else { store.detailSection = nil; return }
        revealing = true
        // 整组往右扫出去：走过一个面板宽度，正好越过屏幕右缘，而不是原地溶解。
        let travel = PanelView.width + Motion.panelOffset
        var target = panel.frame
        target.origin.x += travel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = store.reduceMotion ? Motion.reducedFade : Motion.panelSweep
            context.timingFunction = Motion.panelEase
            panel.animator().alphaValue = 0
            if !store.reduceMotion {
                panel.animator().setFrame(target, display: true)
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.store.panelVisible else { return }
                self.revealing = false
                panel.orderOut(nil)
                self.store.detailSection = nil
                self.store.panelExpanded = false
            }
        }
    }
    func installSettingsAction(_ action: @escaping () -> Void) {
        settingsAction = action
        if settingsRequested { openSettings() }
    }

    @objc func openSettings() {
        if store.panelVisible {
            returnToPanelAfterSettings = true
            closePanel()
        }
        NSApp.setActivationPolicy(.regular)
        #if COMBO_TEST_HOST
        // The isolated AppKit host has no product Settings scene.
        if settingsAction == nil && settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: settingsView())
            hosting.sizingOptions = []
            window.contentView = hosting
            configureSettingsWindow(window)
        }
        #endif
        if let settingsAction {
            settingsRequested = false
            settingsAction()
        } else if settings == nil {
            settingsRequested = true
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if settings?.isMiniaturized == true { settings?.deminiaturize(nil) }
        settings?.makeKeyAndOrderFront(nil)
    }

    func settingsView() -> SettingsView {
        SettingsView(store: store, closeGuide: { [weak self] in
            self?.settings?.close()
        }, contentHeightChanged: { [weak self] height in
            self?.updateSettingsContentHeight(height)
        }, guideHeightChanged: { [weak self] height in
            self?.guideContentHeight = height
            DispatchQueue.main.async { [weak self] in self?.updateSettingsLayout() }
        }) { [weak self] onTop in
            self?.setGuideOnTop(onTop)
        }
    }

    private func setGuideOnTop(_ onTop: Bool) {
        if onTop && !guideWantsTop { settingsFrameBeforeGuide = settings?.frame }
        guideWantsTop = onTop
        // TabView installs or removes its native toolbar during the current layout pass.
        DispatchQueue.main.async { [weak self] in self?.updateSettingsLayout() }
    }

    func updateSettingsContentHeight(_ height: CGFloat) {
        settingsContentHeight = height
        // Geometry reporting runs inside SwiftUI layout; resize after that pass completes.
        DispatchQueue.main.async { [weak self] in self?.updateSettingsLayout() }
    }

    func updateSettingsLayout() {
        guard let window = settings else { return }
        let width = guideWantsTop ? OnboardingLayout.width : SettingsLayout.width
        window.minSize = NSSize(width: width, height: SettingsLayout.minHeight)
        window.titleVisibility = guideWantsTop ? .hidden : .visible
        var frame = window.frame
        frame.origin.x += (frame.width - width) / 2
        frame.size.width = width
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let top = max(min(frame.maxY, screen?.maxY ?? frame.maxY),
                      (screen?.minY ?? 0) + SettingsLayout.minHeight)
        let available = top - (screen?.minY ?? (top - SettingsLayout.height))
        if guideWantsTop {
            if settingsFrameBeforeGuide == nil { settingsFrameBeforeGuide = window.frame }
            let chrome = window.frame.height - window.contentLayoutRect.height
            let height = guideContentHeight.map { $0 + chrome } ?? OnboardingLayout.height
            frame.size.height = min(max(SettingsLayout.minHeight, height), available)
            frame.origin.y = top - frame.height
        } else if let height = settingsContentHeight {
            let chrome = window.frame.height - window.contentLayoutRect.height
            frame.size.height = min(max(SettingsLayout.minHeight, height + chrome), available)
            frame.origin.y = top - frame.height
            settingsFrameBeforeGuide = nil
        } else if let previous = settingsFrameBeforeGuide {
            frame = previous
            if window.toolbar?.isVisible == true { settingsFrameBeforeGuide = nil }
        }
        if settingsTargetFrame != frame {
            settingsTargetFrame = frame
            if window.isVisible && !store.reduceMotion && !guideWantsTop {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.settingsResize
                    context.timingFunction = Motion.out
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true)
            }
        }
        applyGuideLevel(window)
    }

    func configureSettingsWindow(_ window: NSWindow) {
        guard settings !== window else { return }
        window.appearance = selectedAppearance
        window.title = L("Combo 设置")
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.miniaturizable, .resizable])
        window.minSize = NSSize(width: SettingsLayout.width, height: SettingsLayout.minHeight)
        window.setFrame(NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height), display: false)
        window.center()
        settings = window
        settingsTargetFrame = nil
        // Keep SwiftUI's window delegate; observe closing without replacing it.
        settingsClose = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] notification in self?.windowWillClose(notification) }
        settingsResize = NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: window)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.updateSettingsLayout() }
            }
        NSApp.setActivationPolicy(.regular)
        updateSettingsLayout()
    }
    func applicationDidBecomeActive(_ notification: Notification) { Localization.shared.refresh(); store.refresh(); applyGuideLevel() }

    /// 引导平时压在最上层；只要“系统设置”在前台就让位——这一刻用户的任务在那一边，不该被引导盖住。
    private func applyGuideLevel(_ window: NSWindow? = nil, active: String? = nil) {
        guard let window = window ?? settings else { return }
        let front = active ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let onTop = guideWantsTop && front != "com.apple.systempreferences"
        window.level = onTop ? .floating : .normal
        window.collectionBehavior = onTop ? [.moveToActiveSpace, .fullScreenAuxiliary] : []
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settings else { return }
        NSApp.setActivationPolicy(.accessory)
        store.scene = .live
        // Restore after AppKit finishes closing the settings window and handing off key status.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.returnToPanelAfterSettings, self.settings?.isVisible != true else { return }
            self.returnToPanelAfterSettings = false
            if !self.store.panelVisible { self.togglePanel() }
            self.panel?.makeKeyAndOrderFront(nil)
            self.store.panelSettingsFocusRequested = true
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        languageChange?.cancel()
        detailChange?.cancel()
        settingsAction = nil
        settingsRequested = false
        returnToPanelAfterSettings = false
        settingsClose?.cancel()
        revealTask?.cancel()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        stopPanelDismissalMonitoring()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        animator?.invalidate()
        store.stop()
    }
}
