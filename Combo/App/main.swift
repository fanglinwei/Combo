import AppKit
import SwiftUI
import Combine

final class ComboPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var status: NSStatusItem!
    var panel: ComboPanel?
    private var overviewHeight: CGFloat = 0
    /// 滑入进行中。期间冻结窗口 frame 更新，否则内容测量会把窗口拽回终点、把滑动打断。
    private var revealing = false
    private var detailWindow: ComboPanel?
    private var detailChange: AnyCancellable?
    private var escapeMonitor: Any?
    private var detailTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    var settings: NSWindow?
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
        appearanceChange = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateWindowAppearance() } }
        languageChange = Localization.shared.$language.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateLanguage() } }
        updateIcon()
        OnboardingState.migrate()
        #if DEBUG
        let showSettings = true
        #else
        let showSettings = !UserDefaults.standard.bool(forKey: OnboardingState.completedKey) || CommandLine.arguments.contains("--settings") || store.menuSetup.needsRecovery
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
        if panel?.isVisible == true { closePanel() }
        else if let screen = status.button?.window?.screen ?? NSScreen.main {
            store.refresh()
            let visible = screen.visibleFrame
            // Reuse the height measured last time so the sliding frame is already the right size.
            // 沿用上次测到的高度：滑进来的那一帧尺寸就是对的，落位后不用再跳一次。
            let height = min(overviewHeight > 0 ? overviewHeight : 500, visible.height - 16)
            revealing = true
            store.panelRevealed = false
            revealTask?.cancel()
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, bluetoothPermission: store.audio.bluetoothPermission,
                                 mode: .overview, showSettings: showSettings, maxHeight: visible.height - 16,
                                 reportHeight: { [weak self] value in self?.updatePanelHeight(value) })
            let frame = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8,
                               width: PanelView.width, height: height)
            let window = panel ?? ComboPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            // Land off-screen to the right; the reveal slides it left into `frame`. Reduce Motion skips
            // the travel and just fades in place.
            var start = frame
            if !store.reduceMotion { start.origin.x = visible.maxX + 20 }
            window.setFrame(start, display: false)
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
            revealTask = Task { @MainActor [weak self, weak window] in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self, let window, self.panel === window, window.isVisible else { return }
                self.store.panelRevealed = true
                await self.runPanelReveal(window, to: frame)
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
    private static let detailHeight: CGFloat = 570
    private static let detailGap: CGFloat = 12
    /// Reduce Motion keeps fades and drops movement, so these replace the old instant cuts.

    private func detailFrame() -> NSRect {
        let visible = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(Self.detailHeight, visible.height - 16)
        let x = (panel?.frame.minX ?? visible.maxX) - PanelView.width - Self.detailGap
        return NSRect(x: max(visible.minX + 8, x), y: visible.maxY - height - 8, width: PanelView.width, height: height)
    }

    private func updateDetailWindow(_ section: PanelSection?) {
        detailTask?.cancel()
        guard let section else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            guard let window = detailWindow, window.isVisible else { return }
            detailTask = Task { @MainActor in
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = store.reduceMotion ? Motion.reducedFade : Motion.detailHide
                    context.timingFunction = Motion.out
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
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, bluetoothPermission: store.audio.bluetoothPermission,
                                 mode: .detail, showSettings: showSettings, maxHeight: frame.height, reportHeight: { _ in })
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
    // Panel reveal: it slides in from the right edge of the screen — the mirror of the close, which
    // leaves the same way — while fading up, on the drawer curve. ease-in was tried here and held the
    // panel off-screen for ~90ms before arriving; the drawer curve moves from the first frame and still
    // settles softly. Reduce Motion keeps a gentle fade with no travel.

    private func runPanelReveal(_ window: NSWindow, to target: NSRect) async {
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = store.reduceMotion ? Motion.reducedFade : Motion.panelReveal
            context.timingFunction = store.reduceMotion ? Motion.out : Motion.drawer
            window.animator().alphaValue = 1
            if !store.reduceMotion { window.animator().setFrame(target, display: true) }
        }
        guard !Task.isCancelled, panel === window, window.isVisible else { revealing = false; return }
        revealing = false
        updatePanelFrame(animated: true)
    }

    // Reference close: the panel zips off to the right — toward the menu-bar icon — travelling its own
    // width in ~0.14s (the recording measures ~116ms), then disappears past the screen edge. No fade,
    // no shrink: it translates, on the drawer curve so the first frame carries ~40% of the travel.

    private func closePanel() {
        revealTask?.cancel()
        store.detailSection = nil
        store.panelRevealed = false
        store.panelVisible = false
        guard let panel else { return }
        guard !store.reduceMotion else { panel.orderOut(nil); return }
        var target = panel.frame
        target.origin.x = (panel.screen?.visibleFrame.maxX ?? target.maxX) + 20
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.panelClose
            context.timingFunction = Motion.drawer
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            guard let self, !self.store.panelVisible else { return }
            panel.orderOut(nil)
        }
    }
    @objc func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            window.title = L("Combo 设置"); window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.minSize = NSSize(width: 780, height: 620)
            window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) { Localization.shared.refresh(); store.refresh() }
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
    func applicationWillTerminate(_ notification: Notification) { animator?.invalidate(); store.stop() }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
