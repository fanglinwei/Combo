import AppKit
@testable import Combo

@main struct PanelDismissCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "Combo.PanelCheck.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw NSError(domain: suite, code: 1) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let discovery = AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })
        var permissionVisible = false
        let delegate = AppDelegate(store: Store(audio: AudioStore(discovery: discovery), isSystemPermissionAlertVisible: { permissionVisible }))
        delegate.status = NSStatusBar.system.statusItem(withLength: 30)
        let outside = CGPoint(x: -10000, y: -10000)
        func open() async throws {
            delegate.togglePanel()
            delegate.store.reduceMotion = true
            try await Task.sleep(for: .milliseconds(300))
            assert(delegate.store.panelVisible)
        }

        try await open()
        let panel = try require(delegate.panel)
        panel.resignKey()
        assert(delegate.store.panelVisible, "Losing key alone must not dismiss a permission-preserved panel")
        delegate.handlePanelMouseDown(at: CGPoint(x: panel.frame.midX, y: panel.frame.midY), in: panel)
        assert(delegate.store.panelVisible, "Clicks in the panel must stay open")
        if let button = delegate.status.button, let anchor = button.window {
            let frame = anchor.convertToScreen(button.convert(button.bounds, to: nil))
            delegate.handlePanelMouseDown(at: CGPoint(x: frame.midX, y: frame.midY), in: anchor)
            assert(delegate.store.panelVisible, "The icon must reach togglePanel without close-then-reopen")
        }
        delegate.store.detailSection = .battery
        delegate.updateDetailWindow(.battery)
        try await Task.sleep(for: .milliseconds(100))
        let detail = try require(NSApp.windows.first { $0 is ComboPanel && $0 !== panel && $0.isVisible })
        delegate.handlePanelMouseDown(at: CGPoint(x: detail.frame.midX, y: detail.frame.midY), in: detail)
        assert(delegate.store.panelVisible, "The detail belongs to the panel")
        delegate.store.detailSection = .sound
        delegate.updateDetailWindow(.sound)
        try await Task.sleep(for: .milliseconds(300))
        let soundFrame = detail.frame
        let scroll = try require(scrollView(in: try require(detail.contentView)))
        let document = try require(scroll.documentView)
        let maximumHeight = try require(detail.screen).visibleFrame.height - 16
        assert(abs(soundFrame.height - min(ceil(document.frame.height), maximumHeight)) < 1,
               "The native detail window must match its visible content, without a transparent tail")
        delegate.store.detailSection = .battery
        delegate.updateDetailWindow(.battery)
        try await Task.sleep(for: .milliseconds(300))
        delegate.store.detailSection = .sound
        delegate.updateDetailWindow(.sound)
        try await Task.sleep(for: .milliseconds(300))
        assert(abs(detail.frame.height - soundFrame.height) < 1, "Returning to sound must restore its content height")
        delegate.store.message = LocalizedText { String(repeating: "Panel height regression\n", count: 120) }
        try await Task.sleep(for: .milliseconds(300))
        let expandedFrame = detail.frame
        let expandedScroll = try require(scrollView(in: try require(detail.contentView)))
        let expandedDocument = try require(expandedScroll.documentView)
        assert(abs(expandedFrame.height - maximumHeight) < 1 && expandedDocument.frame.height > maximumHeight,
               "Long content must grow to the screen limit and remain scrollable: window=\(expandedFrame.height), content=\(expandedDocument.frame.height), limit=\(maximumHeight)")
        delegate.store.message = ""
        try await Task.sleep(for: .milliseconds(300))
        assert(abs(detail.frame.height - soundFrame.height) < 1 && abs(detail.frame.maxY - expandedFrame.maxY) < 1,
               "Removing content must shrink the native window while keeping its top anchored")
        let formerTail = CGPoint(x: detail.frame.midX, y: detail.frame.minY - 10)
        assert(expandedFrame.contains(formerTail) && !detail.frame.contains(formerTail))
        delegate.handlePanelMouseDown(at: formerTail)
        assert(!delegate.store.panelVisible && delegate.store.detailSection == nil,
               "Outside clicks must close the whole group even when neither window has key")
        try await Task.sleep(for: .milliseconds(300))

        try await open()
        permissionVisible = true
        delegate.handlePanelMouseDown(at: outside)
        delegate.handlePanelApplicationSwitch(to: 123456, bundleIdentifier: "local.test.other-app")
        assert(delegate.store.panelVisible, "Permission dialogs must suppress mouse and application-switch dismissal")
        try await Task.sleep(for: .seconds(5.1))
        delegate.handlePanelMouseDown(at: outside)
        assert(delegate.store.panelVisible, "Permission protection must last longer than the old five-second window")
        permissionVisible = false
        assert(delegate.store.panelVisible, "Resolving a prompt must not replay ignored clicks")
        delegate.handlePanelMouseDown(at: outside)
        assert(!delegate.store.panelVisible, "The first click after resolution must close, without regaining key")
        try await Task.sleep(for: .milliseconds(300))

        try await open()
        delegate.handlePanelApplicationSwitch(to: ProcessInfo.processInfo.processIdentifier)
        assert(delegate.store.panelVisible, "Activating Combo is an internal interaction")
        delegate.handlePanelApplicationSwitch(to: 123456, bundleIdentifier: "com.apple.UserNotificationCenter")
        assert(delegate.store.panelVisible, "A system permission host must not look like Command-Tab")
        delegate.handlePanelApplicationSwitch(to: ProcessInfo.processInfo.processIdentifier)
        assert(delegate.store.panelVisible, "Restoring the previous application after permission must keep the panel")
        delegate.handlePanelApplicationSwitch(to: 123457, bundleIdentifier: "local.test.other-app")
        assert(!delegate.store.panelVisible, "Switching to another application must dismiss without needing key")
        try await Task.sleep(for: .milliseconds(300))

        try await open()
        permissionVisible = true
        delegate.togglePanel()
        assert(!delegate.store.panelVisible, "A second icon click must remain an explicit close during authorization")
        permissionVisible = false
        try await Task.sleep(for: .milliseconds(300))

        // Keep the existing whole-group closing animation regression.
        try await open()
        delegate.store.detailSection = .battery
        delegate.updateDetailWindow(.battery)
        try await Task.sleep(for: .milliseconds(100))
        let resting = panel.frame.minX
        delegate.store.reduceMotion = false
        delegate.handlePanelMouseDown(at: outside)
        try await Task.sleep(for: .milliseconds(600))
        assert(panel.frame.minX - resting > 300 && delegate.store.detailSection == nil)
        try await open()
        let plainResting = panel.frame.minX
        delegate.store.reduceMotion = false
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(600))
        assert(panel.frame.minX - plainResting > 300)

        // Exercise AppKit's local monitor, not just its shared dismissal handler.
        try await open()
        let other = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderFront(nil)
        let event = try require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: other.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        assert(!delegate.store.panelVisible, "The actual local mouse monitor must close on another Combo window")
        other.orderOut(nil)
        try await Task.sleep(for: .milliseconds(300))
        try await open()
        permissionVisible = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        assert(delegate.store.panelVisible, "Changing Spaces while a permission prompt is visible must stay open")
        permissionVisible = false
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        assert(!delegate.store.panelVisible, "The actual Space observer must close when there is no permission prompt")

        delegate.panel?.orderOut(nil)
        delegate.store.stop()
        NSStatusBar.system.removeStatusItem(delegate.status)
        print("PASS: non-key outside click, internal/detail/icon clicks, long permission protection, resolution, application switching, explicit close and group animation")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "PanelDismissCheck", code: 1) }
        return value
    }

    @MainActor private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
}
