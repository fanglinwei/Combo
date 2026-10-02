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
    private var panelCompact = false
    private var overviewHeight: CGFloat = 0
    private var detailHeight: CGFloat = 0
    private var detailHeightSection: PanelSection?
    private var selectedSection: PanelSection?
    private var revealTask: Task<Void, Never>?
    var settings: NSWindow?
    var change: AnyCancellable?
    private var appearanceChange: AnyCancellable?
    private var languageChange: AnyCancellable?
    var animator: Timer?
    private var iconTransition = IconTransition()
    private var bottomTransition = BottomTransition()
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
        change = store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
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
        drawIcon()
    }
    func drawIcon() {
        let s = store.snapshot
        let now = ProcessInfo.processInfo.systemUptime
        let transitioning = (iconTransition.isAnimating(at: now) || bottomTransition.isAnimating(at: now)) && store.screenActive
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
            let height = min(500, visible.height - 16)
            panelCompact = visible.width < PanelView.width * 2 + 34
            overviewHeight = 0; detailHeight = 0; detailHeightSection = nil; selectedSection = nil
            revealTask?.cancel()
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, bluetoothPermission: store.audio.bluetoothPermission, showSettings: showSettings, compact: panelCompact, maxHeight: visible.height - 16,
                                 resize: { [weak self] selected in self?.resizePanel(selected: selected) },
                                 reportHeight: { [weak self] section, value in self?.updatePanelHeight(for: section, value) })
            let frame = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8,
                               width: PanelView.width, height: height)
            let window = panel ?? ComboPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setFrame(frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel = window
            window.alphaValue = 0
            configurePanelReveal(hosting)
            window.makeKeyAndOrderFront(nil)
            store.panelVisible = true
            revealTask = Task { @MainActor [weak self, weak window, weak hosting] in
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self, let window, let hosting, self.panel === window, window.isVisible else { return }
                await self.runPanelReveal(window, hosting)
            }
        }
    }
    private func resizePanel(selected: PanelSection?) {
        selectedSection = selected
        updatePanelFrame()
    }
    private func updatePanelHeight(for section: PanelSection?, _ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        if section == nil { overviewHeight = ceil(value) }
        else if selectedSection == nil || section == selectedSection {
            detailHeight = ceil(value)
            detailHeightSection = section
        } else { return }
        updatePanelFrame()
    }
    private func updatePanelFrame() {
        guard let panel, let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let width = selectedSection != nil && !panelCompact ? PanelView.width * 2 + 10 : PanelView.width
        let overview = overviewHeight > 0 ? overviewHeight : panel.frame.height
        let detail = detailHeightSection == selectedSection ? detailHeight : 0
        let desired = selectedSection == nil ? overview : panelCompact ? (detail > 0 ? detail : overview) : max(overview, detail)
        let height = min(max(1, desired), max(1, visible.height - 16))
        let frame = NSRect(x: visible.maxX - width - 12, y: visible.maxY - height - 8, width: width, height: height)
        guard abs(panel.frame.width - frame.width) > 0.5 || abs(panel.frame.height - frame.height) > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5 else { return }
        panel.setFrame(frame, display: true)
    }
    // Panel pop: scale up from the top-right corner (nearest the menu-bar icon) while fading in.
    // A strong ease-out reads as "snappy"; the old ease-in-out alpha fade was what felt stiff.
    private static let panelRevealScale: CGFloat = 0.9
    private static let panelRevealDuration: TimeInterval = 0.22
    private static let panelRevealReducedDuration: TimeInterval = 0.12

    private func configurePanelReveal(_ hosting: NSView) {
        guard !store.reduceMotion else { return }
        hosting.wantsLayer = true
        guard let layer = hosting.layer else { return }
        let bounds = hosting.bounds
        // NSHostingView is flipped (y-down), so (1,0) is the top-right corner — the menu-bar icon side.
        layer.anchorPoint = CGPoint(x: 1, y: 0)
        layer.position = CGPoint(x: bounds.maxX, y: bounds.minY)
        layer.transform = CATransform3DMakeScale(Self.panelRevealScale, Self.panelRevealScale, 1)
    }

    private func runPanelReveal(_ window: NSWindow, _ hosting: NSView) async {
        let reduced = store.reduceMotion
        let duration = reduced ? Self.panelRevealReducedDuration : Self.panelRevealDuration
        let curve = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        if !reduced, let layer = hosting.layer {
            let scale = CABasicAnimation(keyPath: "transform")
            scale.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(Self.panelRevealScale, Self.panelRevealScale, 1))
            scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            scale.duration = duration
            scale.timingFunction = curve
            layer.add(scale, forKey: "panelRevealScale")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = curve
            window.animator().alphaValue = 1
        }
    }

    private func closePanel() {
        revealTask?.cancel()
        panel?.orderOut(nil); store.panelVisible = false
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
