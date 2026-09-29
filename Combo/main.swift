import AppKit
import SwiftUI
import Combine

final class ComboPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store()
    var status: NSStatusItem!
    var panel: ComboPanel?
    private var panelCompact = false
    var settings: NSWindow?
    var change: AnyCancellable?
    private var appearanceChange: AnyCancellable?
    var animator: Timer?
    private var iconTransition = IconTransition()
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let submenu = NSMenu(); submenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: "退出 Combo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = submenu; NSApp.mainMenu = menu
        status = NSStatusBar.system.statusItem(withLength: 30)
        status.button?.target = self; status.button?.action = #selector(togglePanel)
        change = store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
        appearanceChange = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateWindowAppearance() } }
        updateIcon()
        if !UserDefaults.standard.bool(forKey: "hasOpened") || CommandLine.arguments.contains("--settings") || store.menuSetup.needsRecovery {
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
    func updateIcon() {
        guard status != nil else { return }
        let s = store.snapshot
        iconTransition.update(IconContent(s), at: ProcessInfo.processInfo.systemUptime,
                              reducedMotion: s.reducedMotion || store.reduceMotion, active: store.screenActive)
        drawIcon()
    }
    func drawIcon() {
        let s = store.snapshot
        let now = ProcessInfo.processInfo.systemUptime
        let transitioning = iconTransition.isAnimating(at: now) && store.screenActive
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
                                       transition: iconTransition.frame(at: now))
        image.isTemplate = false
        status.button?.image = image
        let description = "\(store.scene == .live ? "" : "演示 · ")\(s.powerHintText)电量 \(s.batteryText) · \(s.network) · 音量 \(s.volumeText)"
        status.button?.toolTip = description
        status.button?.setAccessibilityLabel(description)
    }
    @objc func togglePanel() {
        if panel?.isVisible == true { closePanel() }
        else if let screen = status.button?.window?.screen ?? NSScreen.main {
            store.refresh()
            let visible = screen.visibleFrame
            let height = min(500, visible.height - 16)
            panelCompact = visible.width < PanelView.width * 2 + 34
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let view = PanelView(store: store, showSettings: showSettings, height: height, compact: panelCompact,
                                 resize: { [weak self] expanded in self?.resizePanel(expanded: expanded) })
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
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            panel = window
            window.alphaValue = store.reduceMotion ? 1 : 0
            window.makeKeyAndOrderFront(nil)
            store.panelVisible = true
            if !store.reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    window.animator().alphaValue = 1
                }
            }
        }
    }
    private func resizePanel(expanded: Bool) {
        guard let panel, let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let width = expanded && !panelCompact ? PanelView.width * 2 + 10 : PanelView.width
        let frame = NSRect(x: visible.maxX - width - 12, y: panel.frame.minY, width: width, height: panel.frame.height)
        if store.reduceMotion { panel.setFrame(frame, display: true) }
        else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
    private func closePanel() { panel?.orderOut(nil); store.panelVisible = false }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { closePanel() }
    }
    @objc func openSettings() {
        closePanel()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.appearance = selectedAppearance
            window.title = "Combo 设置"; window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.minSize = NSSize(width: 780, height: 620)
            window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            if UserDefaults.standard.bool(forKey: "menuSetupSessionActive"), await !store.menuSetup.restore() {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "系统图标尚未确认恢复"
                alert.informativeText = store.menuSetup.message
                alert.addButton(withTitle: "取消退出并手动检查")
                alert.addButton(withTitle: "仍要退出")
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
