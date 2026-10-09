import Testing
import AppKit
@testable import ComboTestHost

final class PanelTestCase {
    let workspaceNotifications = NotificationCenter()
    @MainActor var permissionVisible = false
    @MainActor private var delegate: AppDelegate?
    @MainActor private var suite: String?
    @MainActor private var existingWindows: Set<ObjectIdentifier> = []
    @MainActor private var opening = 0
    let outside = CGPoint(x: -10000, y: -10000)

    @MainActor
    func makeDelegate() async throws -> AppDelegate {
        existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let suite = "Combo.PanelCheck.\(UUID())"
        self.suite = suite
        let defaults = try #require(UserDefaults(suiteName: suite))
        let discovery = AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })
        let store = Store(audio: AudioStore(discovery: discovery), isSystemPermissionAlertVisible: { [weak self] in self?.permissionVisible ?? false },
                          monitorsSystem: false)
        // Demo data avoids hardware callbacks and live energy-app polling during window assertions.
        store.scene = .wired
        store.screenActive = false
        let delegate = AppDelegate(store: store, panelWorkspaceNotifications: workspaceNotifications, monitorsGlobalPanelClicks: false)
        self.delegate = delegate
        delegate.status = NSStatusBar.system.statusItem(withLength: 30)
        // A zero-height status window can still point at the wrong screen before AppKit places it.
        let deadline = Date().addingTimeInterval(2)
        while ((delegate.status.button?.window?.frame.height ?? 0) <= 0 || delegate.status.button?.window?.screen == nil) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let statusWindow = try #require(delegate.status.button?.window, "Missing status item window")
        #expect(statusWindow.frame.height > 0 && statusWindow.screen != nil,
                      "Status item did not settle within 2 seconds: frame=\(statusWindow.frame), screen=\(String(describing: statusWindow.screen?.frame)), main=\(String(describing: NSScreen.main?.frame))")
        _ = try #require(statusWindow.frame.height > 0 && statusWindow.screen != nil ? statusWindow : nil,
                          "Status item requires a measured frame and screen")
        return delegate
    }

    @MainActor
    func open(_ delegate: AppDelegate) async throws {
        opening += 1
        delegate.togglePanel()
        delegate.store.reduceMotion = true
        try await Task.sleep(for: .milliseconds(300))
        #expect(delegate.store.panelVisible,
                      "Opening \(opening) must stay visible: window=\(String(describing: delegate.panel?.frame)), visible=\(String(describing: delegate.panel?.isVisible)), frontmost=\(String(describing: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)), statusScreen=\(String(describing: delegate.status.button?.window?.screen?.frame))")
        _ = try #require(delegate.store.panelVisible ? delegate.panel : nil, "Opening prerequisite failed")
    }

    @MainActor
    func cleanUp() {
        if let delegate {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            NSStatusBar.system.removeStatusItem(delegate.status)
            for window in NSApp.windows where window is ComboPanel && !existingWindows.contains(ObjectIdentifier(window)) {
                window.isReleasedWhenClosed = false
                window.close()
                window.contentView = nil
            }
            self.delegate = nil
        }
        if let suite { UserDefaults().removePersistentDomain(forName: suite) }
    }
}
