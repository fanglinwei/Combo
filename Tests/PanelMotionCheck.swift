import AppKit
@testable import Combo

@main struct PanelMotionCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let delegate = AppDelegate()
        delegate.status = NSStatusBar.system.statusItem(withLength: 30)
        delegate.store.reduceMotion = false

        delegate.togglePanel()
        delegate.store.reduceMotion = false
        try await Task.sleep(for: .milliseconds(60))
        let panel = try require(delegate.panel)
        let firstHeight = panel.frame.height
        try await Task.sleep(for: .milliseconds(450))
        assert(abs(panel.frame.height - firstHeight) < 1,
               "First opening must measure its height before becoming visible")
        assert(panel.isVisible && panel.alphaValue > 0.99)
        let hosting = panel.contentView
        let resting = panel.frame

        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(35))
        delegate.togglePanel()
        assert(delegate.store.panelVisible && delegate.panel === panel && panel.contentView === hosting,
               "Reopening during close must reuse the live window and card state")
        try await Task.sleep(for: .milliseconds(450))
        assert(panel.isVisible && panel.alphaValue > 0.99 && abs(panel.frame.minX - resting.minX) < 1,
               "A stale close completion must not hide a reopened panel")

        delegate.store.reduceMotion = true
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(35))
        assert(panel.isVisible && abs(panel.frame.minX - resting.minX) < 1,
               "Reduced-motion close must fade in place instead of cutting or travelling")
        try await Task.sleep(for: .milliseconds(180))
        assert(!panel.isVisible)
        delegate.togglePanel()
        // Opening refreshes the system preference. Override only this test's Store before reveal.
        delegate.store.reduceMotion = true
        try await Task.sleep(for: .milliseconds(35))
        let reducedStart = try require(delegate.panel).frame
        try await Task.sleep(for: .milliseconds(200))
        assert(panel.isVisible && panel.alphaValue > 0.99 && abs(panel.frame.minX - reducedStart.minX) < 1,
               "Reduced opening: visible=\(panel.isVisible), alpha=\(panel.alphaValue), x=\(reducedStart.minX)→\(panel.frame.minX), reduced=\(delegate.store.reduceMotion)")
        assert(Motion.cardShow + 3 * Motion.cardStep < 0.3)

        panel.orderOut(nil)
        delegate.store.stop()
        NSStatusBar.system.removeStatusItem(delegate.status)
        print("Panel motion: measured height, rapid reversal and reduced-motion fades passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "PanelMotionCheck", code: 1) }
        return value
    }
}
