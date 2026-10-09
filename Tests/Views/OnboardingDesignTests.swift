import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct OnboardingDesignTests {
        @Test
        @MainActor
        func testBilingualGuideLayoutsAndNavigationAcrossPalettes() async throws {
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
                for theme in ComboTheme.allCases {
                    defaults.set(theme.rawValue, forKey: "themeFamily")
                    for dark in [false, true] {
                        for accessible in [false, true] {
                            var footerBounds: ClosedRange<Int>?
                            for step in 0...OnboardingState.stepCount {
                                store.reduceMotion = !(language == .simplifiedChinese && theme == .blue && dark && !accessible)
                                defaults.set(false, forKey: OnboardingState.completedKey)
                                defaults.set(false, forKey: OnboardingState.postponedKey)
                                defaults.set(step, forKey: OnboardingState.stepKey)
                                let view = SettingsView(store: store) { _ in }
                                    .defaultAppStorage(defaults)
                                    .environment(\.colorScheme, dark ? .dark : .light)
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
                                #expect(window.frame.size == size, "The guide must not enlarge the settings window")
                                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), "Missing bitmap prerequisite")
                                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing png prerequisite")
                                let name = "\(language.rawValue)-\(theme.rawValue)-\(dark ? "dark" : "light")-\(accessible ? "accessible" : "standard")-step\(step + 1).png"
                                attachPNG(png, name: name)
                                let screenshot = try #require(NSBitmapImageRep(data: png), "Missing screenshot prerequisite")
                                let bounds = try primaryVerticalBounds(in: screenshot, palette: theme.palette(isDark: dark))
                                if let footerBounds {
                                    #expect(bounds == footerBounds, "All four pages must keep the primary action at the same height")
                                } else { footerBounds = bounds }
                                if language == .simplifiedChinese && theme == .blue && dark && !accessible {
                                    store.scene = .music
                                    try pressKey("\r", code: 36, in: hosting)
                                    try await Task.sleep(for: .milliseconds(90))
                                    if step < OnboardingState.stepCount {
                                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                        let motionPNG = try #require(bitmap.representation(using: .png, properties: [:]), "Missing navigation PNG")
                                        let motionScreenshot = try #require(NSBitmapImageRep(data: motionPNG), "Missing navigation bitmap")
                                        attachPNG(motionPNG, name: "slide-step\(step + 1).png")
                                        let motionBounds = try primaryVerticalBounds(in: motionScreenshot, palette: theme.palette(isDark: dark))
                                        #expect(motionBounds == bounds,
                                               "The footer must stay fixed during the slide")
                                    }
                                    try await Task.sleep(for: .milliseconds(300))
                                    #expect(store.scene == .live, "Navigation and completion must restore the live demo")
                                    if step == 1 {
                                        try pressPrevious(in: hosting)
                                        try await Task.sleep(for: .milliseconds(90))
                                        #expect(defaults.integer(forKey: OnboardingState.stepKey) == step, "Previous must restore saved progress")
                                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                        let reversePNG = try #require(bitmap.representation(using: .png, properties: [:]), "Missing navigation PNG")
                                        let reverseScreenshot = try #require(NSBitmapImageRep(data: reversePNG), "Missing navigation bitmap")
                                        attachPNG(reversePNG, name: "slide-back.png")
                                        #expect(outgoingHeadingOnRight(in: reverseScreenshot, palette: theme.palette(isDark: dark)),
                                               "The outgoing permission page must slide right when returning to menu setup")
                                        let reverseBounds = try primaryVerticalBounds(in: reverseScreenshot, palette: theme.palette(isDark: dark))
                                        #expect(reverseBounds == bounds, "Previous must keep the footer fixed")
                                        try await Task.sleep(for: .milliseconds(300))
                                        try pressKey("\r", code: 36, in: hosting)
                                        try await Task.sleep(for: .milliseconds(90))
                                        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                        let resumedPNG = try #require(bitmap.representation(using: .png, properties: [:]), "Missing resumedPNG prerequisite")
                                        attachPNG(resumedPNG, name: "slide-forward-after-back.png")
                                        try await Task.sleep(for: .milliseconds(300))
                                    }
                                    if step < OnboardingState.stepCount {
                                        #expect(defaults.integer(forKey: OnboardingState.stepKey) == step + 1)
                                        if step < OnboardingState.stepCount - 1 {
                                            try pressKey("\u{1b}", code: 53, in: hosting, handled: false)
                                            try await settle()
                                            #expect(!defaults.bool(forKey: OnboardingState.postponedKey) && !defaults.bool(forKey: OnboardingState.completedKey),
                                                   "Escape must not postpone the guide after removing Not Now")
                                            #expect(defaults.integer(forKey: OnboardingState.stepKey) == step + 1, "Escape must preserve progress")
                                        }
                                    } else {
                                        #expect(defaults.bool(forKey: OnboardingState.completedKey) && !defaults.bool(forKey: OnboardingState.postponedKey))
                                        #expect(defaults.integer(forKey: OnboardingState.stepKey) == 0)
                                    }
                                }
                                renders += 1
                                window.contentView = nil
                                window.close()
                                try await settle()
                            }
                        }
                    }
                }
            }
            #expect(store.audio.bluetoothPermission.askedAt == nil,
                   "Showing and navigating the guide must not request permissions")
            #expect(renders == 96)
        }

        /// Exercise the actual launch path with fresh and completed installation preferences.
        @Test
        @MainActor
        func testFreshAndCompletedApplicationLaunch() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            #expect(Bundle.main.bundleIdentifier == "local.combo.integration-host", "Startup checks must run in the isolated test app")
            let defaults = UserDefaults.standard
            let keys = [OnboardingState.completedKey, OnboardingState.postponedKey, OnboardingState.stepKey, "hasOpened"]
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
            defaults.set(1, forKey: OnboardingState.stepKey)
            window.close()
            #expect(OnboardingState.showsGuide() && defaults.integer(forKey: OnboardingState.stepKey) == 1,
                   "Closing an unfinished guide must preserve progress and show it on the next launch")

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
            let keys = [OnboardingState.completedKey, OnboardingState.postponedKey, OnboardingState.stepKey]
            let saved = keys.map { defaults.object(forKey: $0) }
            defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
            defaults.set(true, forKey: OnboardingState.completedKey)
            defaults.set(false, forKey: OnboardingState.postponedKey)
            defaults.set(0, forKey: OnboardingState.stepKey)
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
                for _ in 0...OnboardingState.stepCount {
                    try pressKey("\r", code: 36, in: hosting)
                    try await settle()
                }
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

        /// In the fixed Chinese/blue/dark fixture, only the outgoing permission heading can be here.
        @MainActor
        private func outgoingHeadingOnRight(in bitmap: NSBitmapImageRep, palette: ComboPalette) -> Bool {
            guard let expected = NSColor(palette.primaryText).usingColorSpace(bitmap.colorSpace) else { return false }
            let scale = Double(bitmap.pixelsWide) / 850
            var matches = 0
            for y in Int(90 * scale)..<Int(114 * scale) {
                for x in bitmap.pixelsWide / 2..<Int(759 * scale) {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    if abs(color.redComponent - expected.redComponent) < 0.03 &&
                        abs(color.greenComponent - expected.greenComponent) < 0.03 &&
                        abs(color.blueComponent - expected.blueComponent) < 0.03 { matches += 1 }
                }
            }
            return matches > 20
        }

        @MainActor
        private func pressPrevious(in view: NSView) throws {
            let window = try #require(view.window, "Missing window prerequisite")
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 120, y: 38), modifierFlags: [],
                                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0), "Missing mouse event")
                window.sendEvent(event)
            }
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
            #expect(view.performKeyEquivalent(with: event) == handled, "Return advances the guide; Escape has no postpone action")
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
