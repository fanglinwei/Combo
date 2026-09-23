import AppKit
import SwiftUI
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var status: NSStatusItem!
    let popover = NSPopover()
    var settings: NSWindow?
    var change: AnyCancellable?
    var animator: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let root = NSMenuItem(); menu.addItem(root)
        let submenu = NSMenu(); submenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: "退出 Combo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = submenu; NSApp.mainMenu = menu
        status = NSStatusBar.system.statusItem(withLength: 30)
        status.button?.target = self; status.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        change = store.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.updateIcon() } }
        updateIcon()
        if !UserDefaults.standard.bool(forKey: "hasOpened") || CommandLine.arguments.contains("--settings") {
            openSettings(); UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }
    func updateIcon() {
        guard status != nil else { return }
        let shouldAnimate = store.snapshot.playing && store.animate && !store.snapshot.muted && !store.snapshot.adjusting && !store.snapshot.reducedMotion && !store.reduceMotion && store.screenActive
        if shouldAnimate && animator == nil {
            animator = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor in self?.drawIcon() } }
        } else if !shouldAnimate { animator?.invalidate(); animator = nil }
        drawIcon()
    }
    func drawIcon() {
        let s = store.snapshot
        let phase = store.reduceMotion ? 0.3 : Date().timeIntervalSinceReferenceDate / 1.2
        let image = IconRenderer.image(s, center: store.center, animate: store.animate, size: 22, phase: phase, dark: status.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        image.isTemplate = false
        status.button?.image = image
        let description = "\(store.scene == .live ? "" : "演示 · ")电量 \(s.batteryText) · \(s.network) · 音量 \(s.volumeText)"
        status.button?.toolTip = description
        status.button?.setAccessibilityLabel(description)
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = status.button {
            store.refresh()
            let maxHeight = (button.window?.screen?.visibleFrame.height ?? 600) - 24
            let showSettings = { [weak self] in _ = self?.openSettings() }
            let host = NSHostingController(rootView: PanelView(store: store, showSettings: showSettings, height: nil))
            let idealHeight = host.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)).height
            host.rootView = PanelView(store: store, showSettings: showSettings, height: min(idealHeight, maxHeight))
            popover.contentViewController = host
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = host.view.window, let screen = button.window?.screen,
               window.frame.maxY > screen.visibleFrame.maxY {
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: screen.visibleFrame.maxY - window.frame.height))
            }
        }
    }
    @objc func openSettings() {
        popover.performClose(nil)
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Combo 设置"; window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(store: store))
            window.minSize = NSSize(width: 780, height: 620)
            window.isReleasedWhenClosed = false; window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { animator?.invalidate(); store.stop() }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
