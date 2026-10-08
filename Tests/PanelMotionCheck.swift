import AppKit
@testable import Combo

@main struct PanelMotionCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "Combo.PanelCheck.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let discovery = AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })
        var permissionVisible = false
        let delegate = AppDelegate(store: Store(audio: AudioStore(discovery: discovery), isSystemPermissionAlertVisible: { permissionVisible }))
        delegate.status = NSStatusBar.system.statusItem(withLength: 30)
        delegate.store.reduceMotion = false

        delegate.togglePanel()
        delegate.store.reduceMotion = false
        try await Task.sleep(for: .milliseconds(60))
        let panel = try require(delegate.panel)
        assert(!delegate.store.panelExpanded, "AirPods information must wait until the entrance finishes")
        let firstHeight = panel.frame.height
        try await Task.sleep(for: .milliseconds(450))
        assert(abs(panel.frame.height - firstHeight) < 1,
               "First opening must measure its height before becoming visible")
        assert(panel.isVisible && panel.alphaValue > 0.99 && delegate.store.panelExpanded)
        let hosting = panel.contentView
        let beforeGrowth = panel.frame
        delegate.store.message = "Panel resize test"
        var growthFrames: [NSRect] = []
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(15))
            growthFrames.append(panel.frame)
        }
        let grown = panel.frame
        assert(grown.height > beforeGrowth.height, "Late content must increase the native window height")
        assert(growthFrames.contains { $0.height > beforeGrowth.height + 0.5 && $0.height < grown.height - 0.5 },
               "Height changes must pass through intermediate frames instead of jumping")
        assert(growthFrames.allSatisfy { abs($0.maxY - beforeGrowth.maxY) < 1 },
               "The top edge must remain fixed during height growth")
        delegate.store.message = ""
        try await Task.sleep(for: .milliseconds(300))
        let resting = panel.frame

        delegate.togglePanel()
        assert(delegate.store.panelExpanded, "Closing must preserve expanded content until the window is hidden")
        try await Task.sleep(for: .milliseconds(35))
        delegate.togglePanel()
        assert(delegate.store.panelExpanded, "Reversing a close must preserve already expanded content")
        assert(delegate.store.panelVisible && delegate.panel === panel && panel.contentView === hosting,
               "Reopening during close must reuse the live window and card state")
        try await Task.sleep(for: .milliseconds(450))
        assert(panel.isVisible && panel.alphaValue > 0.99 && delegate.store.panelExpanded && abs(panel.frame.minX - resting.minX) < 1,
               "A stale close completion must not hide a reopened panel")

        delegate.store.reduceMotion = true
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(35))
        assert(panel.isVisible && abs(panel.frame.minX - resting.minX) < 1,
               "Reduced-motion close must fade in place instead of cutting or travelling")
        try await Task.sleep(for: .milliseconds(180))
        assert(!panel.isVisible)
        assert(!delegate.store.panelExpanded, "Expanded content must reset after the window is hidden")
        delegate.togglePanel()
        // Opening refreshes the system preference. Override only this test's Store before reveal.
        delegate.store.reduceMotion = true
        try await Task.sleep(for: .milliseconds(35))
        let reducedStart = try require(delegate.panel).frame
        try await Task.sleep(for: .milliseconds(200))
        assert(panel.isVisible && panel.alphaValue > 0.99 && abs(panel.frame.minX - reducedStart.minX) < 1,
               "Reduced opening: visible=\(panel.isVisible), alpha=\(panel.alphaValue), x=\(reducedStart.minX)→\(panel.frame.minX), reduced=\(delegate.store.reduceMotion)")
        assert(delegate.store.panelExpanded, "Reduced motion must also signal entrance completion")
        assert(Motion.cardShow + 3 * Motion.cardStep < 0.3)

        // 不启动网络浏览器或要求前台焦点，模拟等待中的系统授权窗口。
        permissionVisible = true
        assert(delegate.store.permissionPromptActive)
        delegate.handlePanelMouseDown(at: CGPoint(x: -10000, y: -10000))
        try await Task.sleep(for: .milliseconds(300))
        assert(delegate.store.panelVisible, "Local-network permission must preserve the panel")
        permissionVisible = false
        assert(!delegate.store.permissionPromptActive)

        panel.orderOut(nil)
        delegate.store.stop()
        NSStatusBar.system.removeStatusItem(delegate.status)
        print("Panel motion: measured height, rapid reversal, reduced-motion fades and local-network permission focus guard passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "PanelMotionCheck", code: 1) }
        return value
    }
}
