import Testing
import Foundation
import AppKit
import Combine
import ApplicationServices
@testable import ComboTestHost

extension IntegrationTests {
    struct StoreIsolationTests {
        @Test
        @MainActor
        func testMenuPermissionRefreshAndDeniedAccessGuidance() {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            #expect(!store.checkingMenus)
            #expect(!store.showMenuPermission, "permission guide must not interrupt startup")
            store.refreshMenuAccess()
            #expect(store.menuAccessGranted == AXIsProcessTrusted())
            if !store.menuAccessGranted {
                store.checkMenus()
                #expect(store.showMenuPermission, "denied menu check must show permission guide")
                #expect(!store.checkingMenus, "denied menu check must not start an AX scan")
                Attachment.record(Data("Denied-access branch exercised. guidanceVisible=\(store.showMenuPermission), scanning=\(store.checkingMenus)".utf8), named: "menu-permission-coverage.txt")
            } else {
                Attachment.record(Data("Current host is authorized; permission refresh exercised, denied-access branch not exercised".utf8), named: "menu-permission-coverage.txt")
            }
        }

        @Test
        @MainActor
        func testBatteryThresholdNotifiesStore() {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            var iconUpdates = 0
            let observer = store.objectWillChange.sink { iconUpdates += 1 }
            defer { observer.cancel() }
            let originalThreshold = store.battery.displayThreshold
            defer { store.battery.displayThreshold = originalThreshold }
            store.battery.displayThreshold = originalThreshold == 50 ? 49 : 50
            #expect(iconUpdates > 0, "Changing the battery threshold must redraw the menu bar icon")
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
