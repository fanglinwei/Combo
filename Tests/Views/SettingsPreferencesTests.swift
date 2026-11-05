import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct SettingsPreferencesTests {
        @Test
        @MainActor
        func testLowBatteryDisplayDefaultsAndPersistence() throws {
            let suite = "Combo.SettingsPreferencesCheck.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let fresh = BatteryStore(defaults: defaults)
            #expect(fresh.displayEnabled)
            for enabled in [false, true] {
                fresh.displayEnabled = enabled
                #expect(defaults.bool(forKey: "batteryDisplayEnabled") == enabled)
                #expect(BatteryStore(defaults: defaults).displayEnabled == enabled)
            }
        }

        @Test
        @MainActor
        func testSettingsWindowLifecycleAndDisplayReset() throws {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let previousGuide = UserDefaults.standard.object(forKey: OnboardingState.completedKey)
            UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
            defer { UserDefaults.standard.set(previousGuide, forKey: OnboardingState.completedKey) }
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            let delegate = AppDelegate(store: store)
            delegate.openSettings()
            let window = try #require(NSApp.windows.first(where: { $0.contentView is NSHostingView<SettingsView> }))
            defer { window.close(); window.contentView = nil }
            #expect(window.frame.size == NSSize(width: 850, height: 690) && window.minSize == NSSize(width: 780, height: 620))
            window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
            store.scene = .music
            let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: other))
            #expect(store.scene == .music, "Closing another window must not end the settings demo")
            window.close()
            #expect(store.scene == .live, "Closing Settings must end its menu bar demo")
            delegate.openSettings()
            #expect(store.scene == .live, "Reopening Settings must keep live data")
            window.close()
            store.stop()
            store.animate = false
            store.battery.displayEnabled = false
            store.resetDisplay()
            #expect(store.animate && store.battery.displayEnabled)
            #expect(BatteryStore().displayEnabled, "Resetting display must persist the enabled preference")
        }
    }
}
