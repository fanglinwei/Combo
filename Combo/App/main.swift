import AppKit
import SwiftUI
import Combine

final class ComboPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: Store

    init(store: Store? = nil) {
        self.store = store ?? Store()
        super.init()
    }
    var status: NSStatusItem!
    var panel: ComboPanel?
    private var overviewHeight: CGFloat = 0
    /// 开合进行中冻结 frame 更新，避免内容测量打断运动。
    private var revealing = false
    private var detailWindow: ComboPanel?
    private var panelLocalMonitor: Any?
    private var panelGlobalMonitor: Any?
    private var dismissalObservers: [NSObjectProtocol] = []
    private var normalApplicationPID: pid_t?
    private var permissionReturnPID: pid_t?
    private var pointerWindow: NSPanel?
    private var pointerChange: AnyCancellable?
    private var detailChange: AnyCancellable?
    private var escapeMonitor: Any?
    private var detailTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    var settings: NSWindow?
    /// 引导这一步要不要压在别人上面；真正的层级由 applyGuideLevel 结合前台应用决定。
    private var guideWantsTop = false
    private var activationObserver: NSObjectProtocol?
    var change: AnyCancellable?
    private var appearanceChange: AnyCancellable?
    private var languageChange: AnyCancellable?
    var animator: Timer?
    private var iconTransition = IconTransition()
    private var bottomTransition = BottomTransition()
    private var panelHighlight = PanelHighlightTransition()
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let submenu = NSMenu(); submenu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: L("退出 Combo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = submenu; NSApp.mainMenu = menu
        status = NSStatusBar.system.statusItem(withLength: 30)
        status.button?.target = self; status.button?.action = #selector(togglePanel)
        status.button?.wantsLayer = true
        status.button?.layer?.cornerRadius = 12
        change = store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
        detailChange = store.$detailSection.removeDuplicates().sink { [weak self] section in
            DispatchQueue.main.async { self?.updateDetailWindow(section) }
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
        OnboardingState.migrate()
        #if DEBUG
        let showSettings = true
        #else
        let showSettings = OnboardingState.showsGuide() || CommandLine.arguments.contains("--settings") || store.menuSetup.needsRecovery
        #endif
        if showSettings {
            openSettings(); UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }
    private var selectedAppearance: NSAppearance? {
        (ComboAppearance(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system).nsAppearance
    }
    private func updateWindowAppearance() {
        let appearance = selectedAppearance
        settings?.appearance = appearance
        panel?.appearance = appearance
    }
    private func updateLanguage() {
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.items.first?.title = L("设置…")
        menu?.items.last?.title = L("退出 Combo")
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
            store.panelRevealed = false
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, bluetoothPermission: store.audio.bluetoothPermission,
                                 mode: .overview, showSettings: showSettings, maxHeight: visible.height - 16,
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
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            store.panelVisible = true
            startPanelDismissalMonitoring()
            revealTask = Task { @MainActor [weak self, weak window] in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self, let window, self.panel === window, window.isVisible else { return }
                // Apply the first layout while still transparent, avoiding a height jump on landing.
                var target = frame
                target.size.height = min(self.overviewHeight > 0 ? self.overviewHeight : height, visible.height - 16)
                target.origin.y = visible.maxY - target.height - 8
                var measuredStart = target
                if !self.store.reduceMotion { measuredStart.origin.x += Motion.panelOffset }
                window.setFrame(measuredStart, display: false)
                self.store.panelRevealed = true
                await self.runPanelReveal(window, to: target)
            }
        }
    }
    private func updatePanelHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let hadMeasurement = overviewHeight > 0
        overviewHeight = ceil(value)
        updatePanelFrame(animated: hadMeasurement)
    }
    private func updatePanelFrame(animated: Bool = false) {
        guard !revealing else { return }
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
    // The section detail lives in its own window beside the panel, as in the reference. Measured off
    // that recording: the window lands on its final frame and fades in — no scale, no slide — over
    // ~200ms ease-out, swaps pages with a cross-fade, and leaves by fading back out.
    private var detailHeight: CGFloat = 500
    private static let detailGap: CGFloat = 12
    /// Reduce Motion keeps fades and drops movement, so these replace the old instant cuts.

    private func detailFrame() -> NSRect {
        let visible = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(detailHeight, max(1, visible.height - 16))
        let x = (panel?.frame.minX ?? visible.maxX) - PanelView.width - Self.detailGap
        return NSRect(x: max(visible.minX + 8, x), y: visible.maxY - height - 8, width: PanelView.width, height: height)
    }

    private func updateDetailHeight(_ value: CGFloat) {
        guard value.isFinite, value > 0, store.detailSection != nil else { return }
        detailHeight = ceil(value)
        guard let window = detailWindow else { return }
        window.setFrame(detailFrame(), display: window.isVisible)
    }

    /// 引导第 1 步的贴边浮层：落在真实状态栏图标正下方，忽略鼠标事件、不抢焦点，只负责指路。
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
            pointer.contentView = NSHostingView(rootView: MenuBarCallout(reduceMotion: store.reduceMotion))
            pointer.isOpaque = false
            pointer.backgroundColor = .clear
            pointer.hasShadow = true
            pointer.level = .floating
            pointer.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            pointer.ignoresMouseEvents = true
            pointerWindow = pointer
        }
        pointer.setFrame(frame, display: false)
        pointer.orderFront(nil)
    }

    func updateDetailWindow(_ section: PanelSection?) {
        detailTask?.cancel()
        guard let section else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            guard let window = detailWindow, window.isVisible else { return }
            detailTask = Task { @MainActor in
                await NSAnimationContext.runAnimationGroup { context in
                    // 面板一起收起时用整组右扫的时长：淡出比行程短的话，后半个行程是白跑的。
                    let closingWithPanel = !store.panelVisible
                    context.duration = store.reduceMotion ? Motion.reducedFade
                        : (closingWithPanel ? Motion.panelSweep : Motion.detailHide)
                    context.timingFunction = closingWithPanel ? Motion.panelEase : Motion.out
                    window.animator().alphaValue = 0
                }
                guard !Task.isCancelled, store.detailSection == nil else { return }
                window.orderOut(nil)
            }
            return
        }
        let frame = detailFrame()
        let window: ComboPanel
        if let existing = detailWindow {
            window = existing
        } else {
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let maxHeight = max(1, ((panel?.screen ?? NSScreen.main)?.visibleFrame.height ?? 0) - 16)
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, bluetoothPermission: store.audio.bluetoothPermission,
                                 mode: .detail, showSettings: showSettings, maxHeight: maxHeight,
                                 reportHeight: { [weak self] value in self?.updateDetailHeight(value) })
            window = ComboPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            detailWindow = window
        }
        if escapeMonitor == nil {
            // Esc closes the detail window; it is not key, so the monitor catches the event app-wide.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, self.store.detailSection != nil else { return event }
                self.store.detailSection = nil
                return nil
            }
        }
        window.setFrame(frame, display: window.isVisible)
        guard !window.isVisible else { window.alphaValue = 1; return }
        window.alphaValue = 0
        window.orderFront(nil)
        detailTask = Task { @MainActor in
            if !store.reduceMotion { try? await Task.sleep(for: .milliseconds(20)) }
            guard !Task.isCancelled, store.detailSection == section else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = store.reduceMotion ? Motion.reducedFade : Motion.detailShow
                context.timingFunction = Motion.out
                window.animator().alphaValue = 1
            }
        }
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
        panelGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.handlePanelMouseDown(at: NSEvent.mouseLocation) }
        }
        dismissalObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.handlePanelApplicationSwitch(to: app.processIdentifier, bundleIdentifier: app.bundleIdentifier) }
        })
        dismissalObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPanelAutomatically(interactionInside: false) }
        })
    }

    private func stopPanelDismissalMonitoring() {
        if let panelLocalMonitor { NSEvent.removeMonitor(panelLocalMonitor); self.panelLocalMonitor = nil }
        if let panelGlobalMonitor { NSEvent.removeMonitor(panelGlobalMonitor); self.panelGlobalMonitor = nil }
        dismissalObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        dismissalObservers.removeAll()
        permissionReturnPID = nil
    }

    /// 主面板、详情和菜单栏图标组成同一次交互；不依赖窗口是否取得 key。
    func handlePanelMouseDown(at point: CGPoint, in window: NSWindow? = nil) {
        guard store.panelVisible else { return }
        let inside = [panel, detailWindow].compactMap { $0 }.contains { candidate in
            candidate.isVisible && (candidate === window || candidate.frame.contains(point)
                || window?.parent === candidate || window?.sheetParent === candidate)
        }
        if inside { return }
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
        let detail = store.detailSection != nil ? detailWindow : nil
        store.detailSection = nil
        store.panelRevealed = false
        store.panelVisible = false
        guard let panel else { return }
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
                if let detail, detail.isVisible {
                    detail.animator().setFrame(detail.frame.offsetBy(dx: travel, dy: 0), display: true)
                }
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.store.panelVisible else { return }
                self.revealing = false
                panel.orderOut(nil)
            }
        }
    }
    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            window.title = L("Combo 设置"); window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store) { [weak self, weak window] onTop in
                guard let self, let window else { return }
                self.guideWantsTop = onTop
                self.applyGuideLevel(window)
            })
            window.minSize = NSSize(width: 780, height: 620)
            window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            if UserDefaults.standard.bool(forKey: "menuSetupSessionActive"), await !store.menuSetup.restore() {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = L("系统图标尚未确认恢复")
                alert.informativeText = store.menuSetup.message.string
                alert.addButton(withTitle: L("取消退出并手动检查"))
                alert.addButton(withTitle: L("仍要退出"))
                if alert.runModal() == .alertFirstButtonReturn { terminating = false; sender.reply(toApplicationShouldTerminate: false); return }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { stopPanelDismissalMonitoring(); animator?.invalidate(); store.stop() }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
