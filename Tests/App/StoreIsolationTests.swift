import Testing
import Foundation
import AppKit
import Combine
@testable import ComboTestHost

extension IntegrationTests {
    struct StoreIsolationTests {
        @Test
        func testMaximumCapacityUsesValidatedHealthReport() throws {
            func report(_ value: Any) throws -> Data {
                try JSONSerialization.data(withJSONObject: ["SPPowerDataType": [
                    ["sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": value]],
                    ["sppower_ac_charger_watts": 70]
                ]])
            }
            for value in [0, 91, 100] {
                #expect(BatteryStore.parseMaximumCapacity(try report("\(value)%")) == value)
            }
            for value: Any in ["91", "-1%", "101%", "91.5%", "NaN%", 91, NSNull()] {
                #expect(BatteryStore.parseMaximumCapacity(try report(value)) == nil)
            }
            #expect(BatteryStore.parseMaximumCapacity(Data("{}".utf8)) == nil)
            #expect(BatteryStore.parseMaximumCapacity(Data("not JSON".utf8)) == nil)
        }

        @Test
        @MainActor
        func testMaximumCapacityReadFailuresTimeoutAndCancellation() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.CapacityTests.\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let helper = directory.appendingPathComponent("system_profiler")
            func write(_ body: String) throws {
                try ("#!/bin/sh\n" + body + "\n").write(to: helper, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            }
            let report = #"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"91%"}}]}"#
            let battery = BatteryStore(systemProfilerURL: helper)
            defer { battery.stop() }
            battery.hasInternalBattery = true
            func waitForCapacity(_ value: Int?) async throws {
                let deadline = Date().addingTimeInterval(4)
                while battery.maximumCapacity != value && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
                try #require(battery.maximumCapacity == value, "Capacity read must finish with \(String(describing: value))")
            }
            try write("echo read >> \"$0.calls\"\nsleep 0.05\necho '\(report)'")
            battery.refreshMaximumCapacity()
            battery.refreshMaximumCapacity()
            try await waitForCapacity(91)
            #expect(try String(contentsOfFile: helper.path + ".calls", encoding: .utf8) == "read\n",
                    "Overlapping refreshes must share one read")
            for body in ["echo '\(report)'\nexit 1", "echo '{}'", "exec /bin/sleep 30"] {
                try write(body)
                battery.maximumCapacity = 91
                battery.refreshMaximumCapacity()
                try await waitForCapacity(nil)
            }
            try write("exec /bin/sleep 30")
            battery.refreshMaximumCapacity()
            battery.stop()
            try write("echo '\(report)'")
            battery.refreshMaximumCapacity()
            try await waitForCapacity(91)
            try await Task.sleep(for: .milliseconds(100))
            #expect(battery.maximumCapacity == 91, "A cancelled callback must not replace the latest read")
            try FileManager.default.removeItem(at: helper)
            battery.refreshMaximumCapacity()
            #expect(battery.maximumCapacity == nil, "A missing reader must leave capacity unavailable")
            battery.maximumCapacity = 91
            battery.hasInternalBattery = false
            battery.refreshMaximumCapacity()
            #expect(battery.maximumCapacity == nil, "A Mac without an internal battery must not retain capacity")
        }

        @Test
        @MainActor
        func testBatteryDisplayNotifiesStore() {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            var iconUpdates = 0
            let observer = store.objectWillChange.sink { iconUpdates += 1 }
            defer { observer.cancel() }
            let originalDisplayEnabled = store.battery.displayEnabled
            defer { store.battery.displayEnabled = originalDisplayEnabled }
            store.live = Snapshot(battery: 0.19, symbol: "wifi", deviceKind: .bluetooth(.airPodsPro))
            for enabled in [false, true] {
                iconUpdates = 0
                store.battery.displayEnabled = enabled
                #expect(iconUpdates > 0, "Toggling low-battery display must redraw the menu bar icon")
                #expect(IconContent(store.snapshot).kind == (enabled ? .battery : .headphones))
            }
        }

        @Test
        @MainActor
        func testVolumeHintRenewsAndRestoresResidentState() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            store.live = Snapshot(symbol: "wifi", volume: 0.5, deviceKind: .bluetooth(.airPodsPro), playing: true)
            store.showVolumeHint()
            #expect(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).priority == 4)
            store.live.muted = true
            store.showVolumeHint()
            #expect(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "0")
            store.live.muted = false
            store.showVolumeHint()
            #expect(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "50")
            store.live.volume = 0
            store.showVolumeHint()
            #expect(store.snapshot.centerEvent == .volume && IconContent(store.snapshot).text == "0")
            store.live.volume = 0.5
            store.live.playing = false
            store.showVolumeHint()
            #expect(store.snapshot.centerEvent == .volume, "Idle volume changes must also show P4 digits")
            #expect(store.live.adjusting)
            try await Task.sleep(for: .milliseconds(1100))
            store.showVolumeHint()
            try await Task.sleep(for: .milliseconds(1100))
            #expect(store.live.adjusting && store.snapshot.centerEvent == .volume, "second change must extend hint")
            store.live.deviceKind = .other
            try await Task.sleep(for: .milliseconds(1100))
            #expect(!store.live.adjusting && store.snapshot.centerEvent == nil, "hint must expire")
            #expect(IconContent(store.snapshot).kind == .wifi, "Expiry must restore the latest resident state")
        }

        @Test
        @MainActor
        func testScopeRestoresAppKitAndPreferencesAfterThrownError() async throws {
            enum Probe: Error { case expected }
            let test = try #require(Test.current)
            let menu = NSMenu(title: "Fixture baseline")
            let applicationMenu = NSMenu(title: "Fixture application")
            let applicationItem = NSMenuItem(title: "Application", action: nil, keyEquivalent: "")
            applicationItem.submenu = applicationMenu
            menu.addItem(applicationItem)
            let services = try #require(NSApp.servicesMenu)
            services.supermenu?.items.first { $0.submenu === services }?.submenu = nil
            services.title = "Fixture services"
            let item = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            item.submenu = services
            applicationMenu.addItem(item)
            NSApp.mainMenu = menu
            NSApp.servicesMenu = services
            try #require(NSApp.servicesMenu === services)
            NSApp.setActivationPolicy(.accessory)
            let icon = NSApp.applicationIconImage
            let namedIcon = NSImage(named: NSImage.applicationIconName)
            let domain = "local.combo.integration-host"

            for preferences: [String: Any]? in [nil, ["fixtureSentinel": "preserve", Localization.preferenceKey: AppLanguage.english.rawValue]] {
                if let preferences {
                    UserDefaults.standard.setPersistentDomain(preferences, forName: domain)
                } else {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
                Localization.shared.refresh()
                let language = Localization.shared.selection
                let baseline = UserDefaults.standard.persistentDomain(forName: domain)
                do {
                    try await IntegrationTestScope().provideScope(for: test, testCase: Test.Case.current) { @MainActor in
                        UserDefaults.standard.set("changed", forKey: "fixtureSentinel")
                        Localization.shared.selection = .simplifiedChinese
                        services.title = "Changed services"
                        item.submenu = nil
                        NSApp.mainMenu = NSMenu(title: "Changed menu")
                        NSApp.servicesMenu = NSMenu(title: "Changed services menu")
                        NSApp.applicationIconImage = NSImage(size: NSSize(width: 16, height: 16))
                        NSImage(named: NSImage.applicationIconName)?.setName(nil)
                        NSImage(size: NSSize(width: 16, height: 16)).setName(NSImage.applicationIconName)
                        NSApp.setActivationPolicy(.prohibited)
                        throw Probe.expected
                    }
                    Issue.record("Expected the scope to propagate the probe error")
                } catch Probe.expected {}
                #expect(UserDefaults.standard.persistentDomain(forName: domain).map(NSDictionary.init(dictionary:)) == baseline.map(NSDictionary.init(dictionary:)))
                #expect(Localization.shared.selection == language)
                #expect(NSApp.mainMenu === menu)
                #expect(NSApp.servicesMenu === services && item.submenu === services)
                #expect(services.title == "Fixture services")
                #expect(NSApp.applicationIconImage === icon)
                #expect(NSImage(named: NSImage.applicationIconName) === namedIcon)
                #expect(NSApp.activationPolicy() == .accessory)
            }
        }

        @Test
        @MainActor
        func testHostAndStoreDoNotStartProductMonitoring() async throws {
            #expect(!(NSApp.delegate is AppDelegate))
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            store.refresh()
            try await Task.sleep(for: .milliseconds(50))
            #expect(!(store.battery.monitoringAvailable))
            #expect(!(store.audio.listenersAvailable))
            #expect(store.audio.outputDevices.isEmpty)
            #expect(store.battery.level == nil)
            #expect(store.audio.volume == nil)
            #expect(store.wifi.powerOn == nil)
            #expect(store.mediaTrack == nil)
            store.scene = .music
            #expect(store.scene == .music)
        }
    }
}
