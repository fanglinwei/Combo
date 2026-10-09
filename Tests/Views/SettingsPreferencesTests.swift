import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct SettingsPreferencesTests {
        @Test
        @MainActor
        func testThresholdDefaultsMigrationAndRememberedValue() throws {
            let suite = "Combo.SettingsPreferencesCheck.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            let fresh = BatteryStore(defaults: defaults)
            #expect(fresh.displayEnabled && fresh.displayThreshold == 20)
            for threshold in [-1, 0, 1, 20, 50, 80, 100] {
                defaults.removePersistentDomain(forName: suite)
                defaults.set(threshold, forKey: "batteryDisplayThreshold")
                let battery = BatteryStore(defaults: defaults)
                let normalized = threshold == 0 ? 0 : min(80, max(20, threshold))
                #expect(battery.displayThreshold == normalized, "Existing thresholds must fit the slider range; zero stays disabled")
                #expect(defaults.integer(forKey: "batteryDisplayThreshold") == normalized)
                let expected = normalized == 0 ? 20 : normalized
                battery.displayEnabled = false
                let reopened = BatteryStore(defaults: defaults)
                #expect(!reopened.displayEnabled && reopened.lastDisplayThreshold == expected)
                reopened.displayEnabled = true
                #expect(reopened.displayThreshold == expected, "Re-enabling must restore the last positive threshold")
                reopened.displayThreshold = 37
                reopened.displayEnabled = false
                let later = BatteryStore(defaults: defaults)
                later.displayEnabled = true
                #expect(later.displayThreshold == 37)
            }

            for remembered in [1, 20, 50, 80, 100] {
                defaults.set(0, forKey: "batteryDisplayThreshold")
                defaults.set(remembered, forKey: "batteryLastDisplayThreshold")
                let battery = BatteryStore(defaults: defaults)
                #expect(!battery.displayEnabled)
                battery.displayEnabled = true
                #expect(battery.displayThreshold == min(80, max(20, remembered)))
            }
            for (requested, expected) in [(1, 20), (100, 80), (0, 0)] {
                fresh.displayThreshold = requested
                #expect(fresh.displayThreshold == expected && defaults.integer(forKey: "batteryDisplayThreshold") == expected)
            }
        }

        @Test
        @MainActor
        func testMenuBaselinePersistenceAndRetryPlanning() throws {
            let suite = "Combo.SettingsPreferencesTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            for hasBattery in [true, false] {
                defaults.removePersistentDomain(forName: suite)
                let setup = MenuBarSetup(defaults: defaults, hasInternalBattery: hasBattery)
                #expect(!setup.hasBaseline && setup.states.isEmpty && setup.failedKeys.isEmpty)
                #expect(!setup.recordBaseline(["wifi": true]), "Incomplete reads must not establish a baseline")
                #expect(defaults.dictionary(forKey: "menuSetupBaseline") == nil)
                let baseline = hasBattery ? ["wifi": false, "sound": true, "battery": false] : ["wifi": false, "sound": true]
                #expect(setup.recordBaseline(baseline))
                #expect(setup.hasBaseline && setup.recordedAt != nil)
                #expect(setup.recordBaseline(["wifi": true, "sound": false, "battery": true]))
                #expect(setup.baseline == baseline, "The first complete baseline must never be overwritten")
                let reopened = MenuBarSetup(defaults: defaults, hasInternalBattery: hasBattery)
                #expect(reopened.baseline == baseline && reopened.hasBaseline)
                #expect(reopened.states.isEmpty, "A baseline is not a current detection result")
                let keys = Set(reopened.supportedKeys)
                let changed = Dictionary(uniqueKeysWithValues: baseline.map { ($0.key, !$0.value) })
                #expect(menuBarRestoreKeys(original: baseline, current: changed, keys: keys) == keys.sorted())
                #expect(menuBarRestoreKeys(original: baseline, current: ["sound": false], keys: ["sound"]) == ["sound"],
                       "Retrying Sound must not require or modify already restored items")
                #expect(menuBarRestoreKeys(original: baseline, current: baseline, keys: keys) == [])
                #expect(menuBarRestoreKeys(original: baseline, current: [:], keys: keys) == nil)
            }
        }

        @Test
        @MainActor
        func testSettingsWindowLifecycleAndThresholdBinding() throws {
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
            let thresholdKeys = ["batteryDisplayThreshold", "batteryLastDisplayThreshold"]
            let savedThresholds = thresholdKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
            defer { for (key, value) in savedThresholds { UserDefaults.standard.set(value, forKey: key) } }
            let settings = SettingsView(store: store, page: .integration) { _ in }
            for (input, expected) in [(0.0, 20), (19.4, 20), (20.0, 20), (20.6, 21), (80.0, 80), (100.0, 80)] {
                store.battery.displayThreshold = 50
                settings.thresholdBinding.wrappedValue = input
                #expect(store.battery.displayEnabled, "Dragging the threshold slider must never turn off low-battery display")
                #expect(store.battery.displayThreshold == expected && store.battery.lastDisplayThreshold == expected)
                #expect(UserDefaults.standard.integer(forKey: "batteryDisplayThreshold") == expected)
            }
            store.battery.displayEnabled = false
            #expect(!store.battery.displayEnabled && store.battery.lastDisplayThreshold == 80,
                   "Only the toggle should disable display while remembering the slider value")
        }
    }
}
