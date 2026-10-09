import Testing
import Foundation
import AppKit
import CoreWLAN
@testable import ComboTestHost

extension IntegrationTests {
    struct PanelDismissTests {
        @Test
        @MainActor
        func testInternalClicksAndDetailHeightGrowthAndShrink() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            try await fixture.open(delegate)
            let panel = try #require(delegate.panel)
            panel.resignKey()
            #expect(delegate.store.panelVisible, "Losing key alone must not dismiss a permission-preserved panel")
            delegate.handlePanelMouseDown(at: CGPoint(x: panel.frame.midX, y: panel.frame.midY), in: panel)
            #expect(delegate.store.panelVisible, "Clicks in the panel must stay open")
            let button = try #require(delegate.status.button, "Missing status button")
            let anchor = try #require(button.window, "Missing status anchor")
            do {
                let frame = anchor.convertToScreen(button.convert(button.bounds, to: nil))
                delegate.handlePanelMouseDown(at: CGPoint(x: frame.midX, y: frame.midY), in: anchor)
                #expect(delegate.store.panelVisible, "The icon must reach togglePanel without close-then-reopen")
            }
            delegate.store.detailSection = .battery
            delegate.updateDetailWindow(.battery)
            try await Task.sleep(for: .milliseconds(100))
            let detail = try #require(NSApp.windows.first { $0 is ComboPanel && $0 !== panel && $0.isVisible })
            delegate.handlePanelMouseDown(at: CGPoint(x: detail.frame.midX, y: detail.frame.midY), in: detail)
            #expect(delegate.store.panelVisible, "The detail belongs to the panel")
            delegate.store.detailSection = .sound
            delegate.updateDetailWindow(.sound)
            try await Task.sleep(for: .milliseconds(300))
            let soundFrame = detail.frame
            let visible = try #require(detail.screen).visibleFrame
            #expect(abs(soundFrame.maxY - panel.frame.maxY) < 1, "Detail top must align to the overview panel")
            let detailContent = try #require(detail.contentView)
            let scroll = try #require(scrollView(in: detailContent))
            let document = try #require(scroll.documentView)
            let maximumHeight = visible.height - 16
            #expect(abs(soundFrame.height - min(ceil(document.frame.height), maximumHeight)) < 1,
                   "The native detail window must match its visible content, without a transparent tail")
            delegate.store.detailSection = .battery
            delegate.updateDetailWindow(.battery)
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs(detail.frame.maxY - panel.frame.maxY) < 1, "Switching details must preserve top alignment")
            delegate.store.detailSection = .sound
            delegate.updateDetailWindow(.sound)
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs(detail.frame.height - soundFrame.height) < 1, "Returning to sound must restore its content height")
            delegate.store.message = LocalizedText { String(repeating: "Panel height regression\n", count: 120) }
            try await Task.sleep(for: .milliseconds(300))
            let expandedFrame = detail.frame
            #expect(abs(expandedFrame.maxY - panel.frame.maxY) < 1, "Long details must preserve top alignment")
            let expandedContent = try #require(detail.contentView)
            let expandedScroll = try #require(scrollView(in: expandedContent))
            let expandedDocument = try #require(expandedScroll.documentView)
            #expect(abs(expandedFrame.height - maximumHeight) < 1 && expandedDocument.frame.height > maximumHeight,
                   "Long content must grow to the screen limit and remain scrollable: window=\(expandedFrame.height), content=\(expandedDocument.frame.height), limit=\(maximumHeight)")
            delegate.store.message = ""
            try await Task.sleep(for: .milliseconds(300))
            #expect(abs(detail.frame.height - soundFrame.height) < 1 && abs(detail.frame.maxY - soundFrame.maxY) < 1,
                   "Removing content must shrink the native window and preserve alignment with the overview panel: actual=\(detail.frame), expected=\(soundFrame), overview=\(panel.frame), content=\(expandedDocument.frame), reducedMotion=\(delegate.store.reduceMotion)")
            let formerTail = CGPoint(x: detail.frame.midX, y: detail.frame.minY - 10)
            #expect(expandedFrame.contains(formerTail) && !detail.frame.contains(formerTail))
            delegate.handlePanelMouseDown(at: formerTail)
            #expect(!delegate.store.panelVisible && delegate.store.detailSection == nil,
                   "Outside clicks must close the whole group even when neither window has key")
            try await Task.sleep(for: .milliseconds(300))
        }

        @Test
        @MainActor
        func testPermissionProtectionAndResolution() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            try await fixture.open(delegate)
            fixture.permissionVisible = true
            delegate.handlePanelMouseDown(at: fixture.outside)
            delegate.handlePanelApplicationSwitch(to: 123456, bundleIdentifier: "local.test.other-app")
            #expect(delegate.store.panelVisible, "Permission dialogs must suppress mouse and application-switch dismissal")
            try await Task.sleep(for: .seconds(5.1))
            delegate.handlePanelMouseDown(at: fixture.outside)
            #expect(delegate.store.panelVisible, "Permission protection must last longer than the old five-second window")
            fixture.permissionVisible = false
            #expect(delegate.store.panelVisible, "Resolving a prompt must not replay ignored clicks")
            delegate.handlePanelMouseDown(at: fixture.outside)
            #expect(!delegate.store.panelVisible, "The first click after resolution must close, without regaining key")
            try await Task.sleep(for: .milliseconds(300))
        }

        @Test
        @MainActor
        func testApplicationSwitchRules() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            try await fixture.open(delegate)
            delegate.handlePanelApplicationSwitch(to: ProcessInfo.processInfo.processIdentifier)
            #expect(delegate.store.panelVisible, "Activating Combo is an internal interaction")
            delegate.handlePanelApplicationSwitch(to: 123456, bundleIdentifier: "com.apple.UserNotificationCenter")
            #expect(delegate.store.panelVisible, "A system permission host must not look like Command-Tab")
            delegate.handlePanelApplicationSwitch(to: ProcessInfo.processInfo.processIdentifier)
            #expect(delegate.store.panelVisible, "Restoring the previous application after permission must keep the panel")
            delegate.handlePanelApplicationSwitch(to: 123457, bundleIdentifier: "local.test.other-app")
            #expect(!delegate.store.panelVisible, "Switching to another application must dismiss without needing key")
            try await Task.sleep(for: .milliseconds(300))
        }

        @Test
        @MainActor
        func testExplicitCloseDuringPermission() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            try await fixture.open(delegate)
            fixture.permissionVisible = true
            delegate.togglePanel()
            #expect(!delegate.store.panelVisible, "A second icon click must remain an explicit close during authorization")
            fixture.permissionVisible = false
            try await Task.sleep(for: .milliseconds(300))
        }

        @Test
        @MainActor
        func testGroupAndOverviewClosingTravel() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            // Keep the existing whole-group closing animation regression.
            try await fixture.open(delegate)
            delegate.store.detailSection = .battery
            delegate.updateDetailWindow(.battery)
            try await Task.sleep(for: .milliseconds(100))
            let panel = try #require(delegate.panel)
            let resting = panel.frame.minX
            delegate.store.reduceMotion = false
            delegate.handlePanelMouseDown(at: fixture.outside)
            try await Task.sleep(for: .milliseconds(600))
            #expect(panel.frame.minX - resting > 300 && delegate.store.detailSection == nil)
            try await fixture.open(delegate)
            let plainResting = panel.frame.minX
            delegate.store.reduceMotion = false
            delegate.togglePanel()
            try await Task.sleep(for: .milliseconds(600))
            #expect(panel.frame.minX - plainResting > 300)
        }

        @Test
        @MainActor
        func testActualMouseMonitorAndSpaceObserver() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            // Exercise AppKit's local monitor, not just its shared dismissal handler.
            try await fixture.open(delegate)
            let other = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            defer { other.close(); other.contentView = nil }
            other.orderFront(nil)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 10, y: 10), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: other.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
            #expect(!delegate.store.panelVisible, "The actual local mouse monitor must close on another Combo window")
            other.orderOut(nil)
            try await Task.sleep(for: .milliseconds(300))
            try await fixture.open(delegate)
            fixture.permissionVisible = true
            fixture.workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            #expect(delegate.store.panelVisible, "Changing Spaces while a permission prompt is visible must stay open")
            fixture.permissionVisible = false
            fixture.workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            #expect(!delegate.store.panelVisible, "The actual Space observer must close when there is no permission prompt")
        }

        @Test
        @MainActor
        func testActualApplicationActivationObserver() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            try await fixture.open(delegate)
            fixture.workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                                        userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
            #expect(delegate.store.panelVisible, "The activation observer must preserve internal interaction")
            let other = try #require(NSWorkspace.shared.runningApplications.first {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !SystemPermissionAlert.isAgent($0.bundleIdentifier)
            }, "Application-switch fixture requires another running application")
            fixture.workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                                        userInfo: [NSWorkspace.applicationUserInfoKey: other])
            #expect(!delegate.store.panelVisible, "The actual activation observer must dismiss another application")
        }

        @Test
        @MainActor
        func testTerminationCancelsAnimationsAndRemovesEventObservers() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            delegate.store.reduceMotion = false
            delegate.togglePanel()
            delegate.store.detailSection = .wifi
            delegate.updateDetailWindow(.wifi)
            try await Task.sleep(for: .milliseconds(60))
            #expect(!delegate.store.panelExpanded, "Termination fixture must interrupt the entrance")
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            try await Task.sleep(for: .milliseconds(450))
            #expect(!delegate.store.panelExpanded, "A cancelled entrance must not update the Store after termination")
            delegate.store.panelVisible = true
            fixture.workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            #expect(delegate.store.panelVisible, "Termination must remove the Space observer")
            let other = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            defer { other.close(); other.contentView = nil }
            let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                     modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: other.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(click)
            #expect(delegate.store.panelVisible, "Termination must remove the local mouse monitor")
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: other.windowNumber,
                                      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            NSApp.sendEvent(escape)
            #expect(delegate.store.detailSection == .wifi, "Termination must remove the detail Escape monitor")
        }

        @Test
        @MainActor
        func testInlineEscapePriority() async throws {
            let fixture = PanelTestCase()
            defer { fixture.cleanUp() }
            let delegate = try await fixture.makeDelegate()
            delegate.panel?.orderOut(nil)
            // Inline cancellation takes priority over dismissing the detail surface.
            delegate.store.detailSection = .wifi
            delegate.store.wifi.passwordRequest = WiFiChoice(network: CWNetwork(), name: "Inline form")
            delegate.store.wifi.busy = true
            delegate.handleDetailEscape()
            #expect(delegate.store.wifi.passwordRequest != nil && delegate.store.detailSection == .wifi,
                   "A busy form cannot be cancelled or dismissed by Esc")
            delegate.store.wifi.busy = false
            delegate.handleDetailEscape()
            #expect(delegate.store.wifi.passwordRequest == nil && delegate.store.detailSection == .wifi,
                   "First Esc must cancel the inline form and keep the detail window")
            delegate.handleDetailEscape()
            #expect(delegate.store.detailSection == nil, "Next Esc must close the detail window")
        }

        @MainActor
        private func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
        }
    }
}
