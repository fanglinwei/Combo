import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct OnboardingDesignTests {
        @Test
        @MainActor
        func testBilingualWelcomeLayoutsAndCompletion() async throws {
            let iconURL = try #require(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
            let icon = try #require(NSImage(contentsOf: iconURL))
            NSApp.applicationIconImage = icon
            icon.setName(NSImage.applicationIconName)
            let suite = "Combo.OnboardingDesign.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let language = Localization.shared.selection
            defer { Localization.shared.selection = language }
            let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })), monitorsSystem: false)
            store.screenActive = false
            store.reduceMotion = true
            defer { store.stop() }
            var renders = 0
            for language in [AppLanguage.simplifiedChinese, .english] {
                Localization.shared.selection = language
                for dark in [false, true] {
                    for accessible in [false, true] {
                        defaults.set(false, forKey: OnboardingState.completedKey)
                        let view = SettingsView(store: store) { _ in }
                            .defaultAppStorage(defaults)
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                        let hosting = NSHostingView(rootView: view)
                        hosting.sizingOptions = []
                        let size = NSSize(width: accessible ? 780 : 850, height: 598)
                        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                                              styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        defer { window.contentView = nil; window.close() }
                        window.appearance = NSAppearance(named: accessible ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua) : (dark ? .darkAqua : .aqua))
                        window.contentView = hosting
                        window.orderFrontRegardless()
                        try await settle()
                        hosting.layoutSubtreeIfNeeded()
                        #expect(window.frame.size == size, "The welcome page must fit the settings window")
                        #expect(store.menuBarPointer, "The welcome page must point to the real menu-bar icon")
                        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), "Missing welcome bitmap")
                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                        let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing welcome PNG")
                        attachPNG(png, name: "\(language.rawValue)-\(dark ? "dark" : "light")-\(accessible ? "accessible" : "standard")-welcome.png")
                        _ = try primaryVerticalBounds(in: bitmap, palette: ComboPalette.standard(isDark: dark))
                        if language == .simplifiedChinese && dark && accessible {
                            store.panelVisible = true
                            try await settle()
                            #expect(!store.menuBarPointer, "Opening the panel must hide the pointer")
                            store.panelVisible = false
                            try await settle()
                            #expect(store.menuBarPointer)
                        }
                        try pressKey("\u{1b}", code: 53, in: hosting, handled: false)
                        #expect(!defaults.bool(forKey: OnboardingState.completedKey), "Escape must not silently complete the welcome page")
                        try pressKey("\r", code: 36, in: hosting)
                        try await settle()
                        #expect(defaults.bool(forKey: OnboardingState.completedKey), "One Return must finish first use")
                        #expect(!store.menuBarPointer, "Completing first use must dismiss the pointer")
                        renders += 1
                        window.contentView = nil
                        window.close()
                    }
                }
            }
            #expect(store.audio.bluetoothPermission.askedAt == nil && !store.wifi.isRequestingLocation,
                   "The welcome page must not request permissions")
            #expect(renders == 8)
        }

        /// Exercise the actual launch path with fresh and completed installation preferences.
        @Test
        @MainActor
        func testFreshAndCompletedApplicationLaunch() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            #expect(Bundle.main.bundleIdentifier == "local.combo.integration-host", "Startup checks must run in the isolated test app")
            let defaults = UserDefaults.standard
            let keys = [OnboardingState.completedKey]
            let saved = keys.map { defaults.object(forKey: $0) }
            defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
            for key in keys { defaults.removeObject(forKey: key) }
            let notification = Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApp)
            let firstLaunch = AppDelegate(store: store)
            firstLaunch.applicationDidFinishLaunching(notification)
            defer {
                firstLaunch.settings?.close()
                firstLaunch.settings?.contentView = nil
                firstLaunch.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
                NSStatusBar.system.removeStatusItem(firstLaunch.status)
            }
            try await settle()
            let window = try #require(firstLaunch.settings, "Missing window prerequisite")
            #expect(window.isVisible && OnboardingState.showsGuide(), "A fresh installation must show the guide")
            window.close()
            #expect(OnboardingState.showsGuide(),
                   "Closing an unfinished welcome page must show it on the next launch")

            defaults.set(true, forKey: OnboardingState.completedKey)
            let completedLaunch = AppDelegate(store: store)
            completedLaunch.applicationDidFinishLaunching(notification)
            defer {
                completedLaunch.settings?.close()
                completedLaunch.settings?.contentView = nil
                completedLaunch.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
                NSStatusBar.system.removeStatusItem(completedLaunch.status)
            }
            try await settle()
            #expect(completedLaunch.settings == nil, "A completed installation must launch without opening settings in Debug or Release")
            #expect(completedLaunch.status.button != nil, "Combo must remain available in the menu bar")
            firstLaunch.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            completedLaunch.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            let menu = NSApp.mainMenu
            Localization.shared.selection = Localization.shared.language == "en" ? .simplifiedChinese : .english
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(NSApp.mainMenu === menu, "Terminated delegates must stop language-driven menu updates")
        }

        @Test
        @MainActor
        func testGuideCompletionAndSettingsFrameRestoration() async throws {
            let store = Store(monitorsSystem: false)
            store.screenActive = false
            store.reduceMotion = true
            defer { store.stop() }
            #expect(Bundle.main.bundleIdentifier == "local.combo.integration-host", "Preference checks must run in the isolated test app")
            let defaults = UserDefaults.standard
            let keys = [OnboardingState.completedKey]
            let saved = keys.map { defaults.object(forKey: $0) }
            defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
            defaults.set(true, forKey: OnboardingState.completedKey)
            let delegate = AppDelegate(store: store)
            delegate.openSettings()
            defer { delegate.settings?.contentView = nil; delegate.settings?.close() }
            let window = try #require(delegate.settings, "Missing settings window")
            let hosting = try #require(window.contentView, "Missing settings content")
            window.orderOut(nil)
            try await settle()
            let visibleFrame = try #require(window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame, "Missing visibleFrame prerequisite")
            for height in [min(CGFloat(870), visibleFrame.height), min(CGFloat(760), visibleFrame.height)] {
                var original = window.frame
                original.size.height = height
                original.origin.y = visibleFrame.maxY - height
                window.setFrame(original, display: true)
                defaults.set(false, forKey: OnboardingState.completedKey)
                try await settle()
                #expect(window.frame.height == 620 && window.frame.maxY == original.maxY)
                window.close()
                delegate.openSettings()
                window.orderOut(nil)
                try await settle()
                try pressKey("\r", code: 36, in: hosting)
                try await settle()
                #expect(defaults.bool(forKey: OnboardingState.completedKey))
                #expect(!window.isVisible, "Completing the guide must close the window without showing settings")
                #expect(window.frame == original, "Completing the guide must restore the previous settings frame while hidden")
                delegate.openSettings()
                try await settle()
                #expect(window.isVisible && window.frame == original,
                       "Manually opening settings must restore the previous settings frame: visible=\(window.isVisible), frame=\(window.frame), expected=\(original)")
                window.orderOut(nil)
            }
            window.contentView = nil
            window.close()
        }

        /// Compare the real primary-button pixels to catch content-dependent page height changes.
        @MainActor
        private func primaryVerticalBounds(in bitmap: NSBitmapImageRep, palette: ComboPalette) throws -> ClosedRange<Int> {
            let expected = try #require(NSColor(palette.accent).usingColorSpace(bitmap.colorSpace), "Missing expected prerequisite")
            var rows: [Int] = []
            for y in max(0, bitmap.pixelsHigh - 160)..<bitmap.pixelsHigh {
                for x in max(0, bitmap.pixelsWide - 400)..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    if abs(color.redComponent - expected.redComponent) < 0.015 &&
                        abs(color.greenComponent - expected.greenComponent) < 0.015 &&
                        abs(color.blueComponent - expected.blueComponent) < 0.015 {
                        rows.append(y)
                        break
                    }
                }
            }
            let first = try #require(rows.first, "Missing guide primary-button pixels")
            let last = try #require(rows.last, "Missing guide primary-button pixels")
            return first...last
        }

        @MainActor
        private func pressKey(_ characters: String, code: UInt16, in view: NSView, handled: Bool = true) throws {
            let window = try #require(view.window, "Missing key-event window")
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code), "Missing key event")
            #expect(view.performKeyEquivalent(with: event) == handled, "Return completes the welcome page; Escape leaves it unfinished")
        }

        @MainActor
        private func settle() async throws {
            try await Task.sleep(for: .milliseconds(180))
        }

        @MainActor
        private func attachPNG(_ data: Data, name: String) {
            Attachment.record(data, named: name)
        }
    }
}
