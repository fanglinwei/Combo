import Testing
import Foundation
import AppKit
@testable import ComboTestHost

extension IntegrationTests {
    struct PanelMotionTests {
        @Test
        @MainActor
        func testEntranceGrowthReversalAndReducedMotion() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            delegate.store.reduceMotion = false

            delegate.togglePanel()
            delegate.store.reduceMotion = false
            try await Task.sleep(for: .milliseconds(60))
            let panel = try #require(delegate.panel)
            #expect(!delegate.store.panelExpanded, "AirPods information must wait until the entrance finishes")
            let firstHeight = panel.frame.height
            try await Task.sleep(for: .milliseconds(450))
            #expect(abs(panel.frame.height - firstHeight) < 1,
                   "First opening must measure its height before becoming visible")
            #expect(panel.isVisible && panel.alphaValue > 0.99 && delegate.store.panelExpanded)
            let hosting = panel.contentView
            let beforeGrowth = panel.frame
            var resizeFrames: [NSRect] = []
            let resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { _ in
                MainActor.assumeIsolated { resizeFrames.append(panel.frame) }
            }
            defer { NotificationCenter.default.removeObserver(resizeObserver) }
            delegate.store.message = "Panel resize test"
            var sampledFrames: [NSRect] = []
            var sampleTimes: [Double] = []
            let started = ProcessInfo.processInfo.systemUptime
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(15))
                sampledFrames.append(panel.frame)
                sampleTimes.append(ProcessInfo.processInfo.systemUptime - started)
            }
            NotificationCenter.default.removeObserver(resizeObserver)
            // Native resize notifications preserve intermediate frames if the async sampler resumes late.
            let growthFrames = sampledFrames + resizeFrames
            let trace = "before=\(beforeGrowth)\nsampleTimes=\(sampleTimes)\nsamples=\(sampledFrames)\nresizeEvents=\(resizeFrames)\nfinal=\(panel.frame)"
            Attachment.record(Data(trace.utf8), named: "panel-growth-frames.txt")
            let grown = panel.frame
            #expect(grown.height > beforeGrowth.height, "Late content must increase the native window height")
            #expect(growthFrames.contains { $0.height > beforeGrowth.height + 0.5 && $0.height < grown.height - 0.5 },
                   "Height changes must pass through intermediate frames instead of jumping")
            #expect(growthFrames.allSatisfy { abs($0.maxY - beforeGrowth.maxY) < 1 },
                   "The top edge must remain fixed during height growth")
            delegate.store.message = ""
            try await Task.sleep(for: .milliseconds(300))
            let resting = panel.frame

            delegate.togglePanel()
            #expect(delegate.store.panelExpanded, "Closing must preserve expanded content until the window is hidden")
            try await Task.sleep(for: .milliseconds(35))
            delegate.togglePanel()
            #expect(delegate.store.panelExpanded, "Reversing a close must preserve already expanded content")
            #expect(delegate.store.panelVisible && delegate.panel === panel && panel.contentView === hosting,
                   "Reopening during close must reuse the live window and card state")
            try await Task.sleep(for: .milliseconds(450))
            #expect(panel.isVisible && panel.alphaValue > 0.99 && delegate.store.panelExpanded && abs(panel.frame.minX - resting.minX) < 1,
                   "A stale close completion must not hide a reopened panel: visible=\(panel.isVisible), alpha=\(panel.alphaValue), expanded=\(delegate.store.panelExpanded), panelVisible=\(delegate.store.panelVisible), frame=\(panel.frame), resting=\(resting), reduced=\(delegate.store.reduceMotion)")

            delegate.store.reduceMotion = true
            delegate.togglePanel()
            try await Task.sleep(for: .milliseconds(35))
            #expect(panel.isVisible && abs(panel.frame.minX - resting.minX) < 1,
                   "Reduced-motion close must fade in place instead of cutting or travelling")
            try await Task.sleep(for: .milliseconds(180))
            #expect(!panel.isVisible)
            #expect(!delegate.store.panelExpanded, "Expanded content must reset after the window is hidden")
            delegate.togglePanel()
            // Opening refreshes the system preference. Override only this test's Store before reveal.
            delegate.store.reduceMotion = true
            try await Task.sleep(for: .milliseconds(35))
            let reducedStart = try #require(delegate.panel).frame
            try await Task.sleep(for: .milliseconds(200))
            #expect(panel.isVisible && panel.alphaValue > 0.99 && abs(panel.frame.minX - reducedStart.minX) < 1,
                   "Reduced opening: visible=\(panel.isVisible), alpha=\(panel.alphaValue), x=\(reducedStart.minX)→\(panel.frame.minX), reduced=\(delegate.store.reduceMotion)")
            #expect(delegate.store.panelExpanded, "Reduced motion must also signal entrance completion")
            #expect(Motion.cardShow + 3 * Motion.cardStep < 0.3)

            // 不启动网络浏览器或要求前台焦点，模拟等待中的系统授权窗口。
            fixture.permissionVisible = true
            #expect(delegate.store.permissionPromptActive)
            delegate.handlePanelMouseDown(at: CGPoint(x: -10000, y: -10000))
            try await Task.sleep(for: .milliseconds(300))
            #expect(delegate.store.panelVisible, "Local-network permission must preserve the panel")
            fixture.permissionVisible = false
            #expect(!delegate.store.permissionPromptActive)
        }
    }
}
