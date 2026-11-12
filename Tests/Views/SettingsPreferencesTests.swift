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
        func testSettingsWindowLifecycleAndDisplayReset() async throws {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let previousGuide = UserDefaults.standard.object(forKey: OnboardingState.completedKey)
            UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
            defer { UserDefaults.standard.set(previousGuide, forKey: OnboardingState.completedKey) }
            let store = Store(monitorsSystem: false)
            store.reduceMotion = true
            defer { store.stop() }
            let delegate = AppDelegate(store: store)
            delegate.openSettings()
            try await Task.sleep(for: .milliseconds(180))
            let window = try #require(delegate.settings)
            defer { window.close(); window.contentView = nil }
            #expect(window.frame.width == SettingsLayout.width
                    && window.frame.height >= SettingsLayout.minHeight
                    && window.frame.height < SettingsLayout.height, "Settings must fit the General page: \(window.frame)")
            // The isolated AppKit host has no SwiftUI Settings scene to enforce content minimums.
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

        @Test
        @MainActor
        func testIconPreviewCatalogAndVariants() throws {
            let groups = IconPreviewGroup.allCases
            #expect(groups.map { $0.scenes.count } == [5, 30, 8, 8])
            let scenes = groups.flatMap(\.scenes)
            #expect(scenes.count == 51 && Set(scenes.map(\.id)).count == IconPreviewGroup.sceneCount)
            let keys = groups.map(\.rawValue) + scenes.flatMap {
                [$0.titleKey, $0.conditionKey, $0.descriptionKey] + $0.variants.map(\.titleKey) + $0.variants.compactMap(\.detailKey)
            }
            for language in ["en", "zh-Hans"] {
                let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
                let bundle = try #require(Bundle(path: path))
                for key in keys {
                    #expect(bundle.localizedString(forKey: key, value: "<missing>", table: nil) != "<missing>", "Missing \(language) preview text: \(key)")
                }
            }
            #expect(IconPreviewGroup.devices.scenes.allSatisfy { $0.variants[0].snapshot.deviceGlyph != nil })
            let devices = IconPreviewGroup.devices.scenes.flatMap(\.variants)
            #expect(devices.count == AudioIconFamily.allCases.count)
            let families = devices.compactMap { variant -> AudioIconFamily? in
                guard case .audio(let family, part: .device) = variant.snapshot.deviceGlyph else { return nil }
                #expect(IconContent(variant.snapshot).glyph == .audio(family))
                return family
            }
            #expect(Set(families) == Set(AudioIconFamily.allCases), "Every approved device must reach the real central icon resolver")
            let wifi = try #require(IconPreviewGroup.network.scenes.first { $0.titleKey == "Wi-Fi 正常" })
            #expect(wifi.variants.map { IconContent($0.snapshot).kind } == [.wifi])
            let connecting = try #require(IconPreviewGroup.network.scenes.first { $0.titleKey == "Wi-Fi 正在连接" })
            #expect(IconContent(connecting.variants[0].snapshot).kind == .connecting)
            let power = IconPreviewGroup.power.scenes
            let charging = try #require(power.first { $0.titleKey == "充电" })
            #expect(charging.variants.map { $0.snapshot.battery } == [0.5, 0.12, 0, 1, nil])
            #expect(charging.variants.allSatisfy { $0.snapshot.charging && $0.snapshot.plugged })
            let hints = power.suffix(2).map { $0.variants[0].snapshot }
            #expect(hints.allSatisfy { $0.centerEvent == .power })
            #expect(hints.map(\.plugged) == [true, false])
            let audio = IconPreviewGroup.audio.scenes
            #expect(audio[1...4].map { volumeDots($0.variants[0].snapshot.volume) } == [1, 2, 3, 4])
            let playing = try #require(audio.first { $0.titleKey == "播放音柱" })
            #expect(playing.variants.map { $0.snapshot.reducedMotion } == [false, true])
            let adjusting = try #require(audio.first { $0.titleKey == "调整音量提示" })
            #expect(adjusting.variants.map { $0.snapshot.volume } == [0.75, 0, nil])
            #expect(adjusting.variants.allSatisfy { $0.snapshot.adjusting && $0.snapshot.centerEvent == .volume })
            for scene in scenes {
                for variant in scene.variants {
                    for dark in [false, true] {
                        for size in [CGFloat(22), 76] {
                            let image = IconRenderer.image(variant.snapshot, animate: true, size: size, phase: 0.3, dark: dark)
                            #expect(image.size == NSSize(width: size, height: size))
                            #expect(image.tiffRepresentation != nil, "Every preview must render at both display sizes: \(scene.id)")
                        }
                    }
                }
            }
        }

        @Test
        @MainActor
        func testIconPreviewRenderingDoesNotChangeMenuBarState() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            store.scene = .music
            store.live.battery = 0.31
            store.live.volume = 0.63
            let animate = store.animate
            let batteryDisplay = store.battery.displayEnabled
            let hosting = NSHostingView(rootView: IconPreviewView(store: store, close: {}).frame(width: 560, height: 560))
            let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 560, height: 560),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close(); window.contentView = nil }
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(80))
            hosting.layoutSubtreeIfNeeded()
            #expect(store.scene == .music && store.live.battery == 0.31 && store.live.volume == 0.63)
            #expect(store.animate == animate && store.battery.displayEnabled == batteryDisplay)
        }
    }
}
