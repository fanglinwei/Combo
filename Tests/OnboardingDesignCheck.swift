import AppKit
import SwiftUI
@testable import Combo

/// Render the real guide and exercise its navigation without requesting system permissions.
@main struct OnboardingDesignCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
            icon.setName(NSImage.applicationIconName)
        }
        let suite = "Combo.OnboardingDesign.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.render }
        defer { defaults.removePersistentDomain(forName: suite) }
        let language = Localization.shared.selection
        defer { Localization.shared.selection = language }
        let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })))
        store.stop()
        store.screenActive = false
        store.reduceMotion = true
        defer { store.stop() }
        try await checkWindowRestoration(store: store)
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/checks/onboarding-design", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
                            print("Rendering \(language.rawValue) \(theme.rawValue) dark=\(dark) minimum=\(accessible) step=\(step)")
                            fflush(stdout)
                            let view = SettingsView(store: store) { _ in }
                                .defaultAppStorage(defaults)
                                .environment(\.colorScheme, dark ? .dark : .light)
                            let hosting = NSHostingView(rootView: view)
                            hosting.sizingOptions = []
                            let size = NSSize(width: accessible ? 780 : 850, height: 598)
                            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                                                  styleMask: .borderless, backing: .buffered, defer: false)
                            window.isReleasedWhenClosed = false
                            window.appearance = NSAppearance(named: accessible ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua) : (dark ? .darkAqua : .aqua))
                            window.contentView = hosting
                            window.orderFrontRegardless()
                            try await settle()
                            hosting.layoutSubtreeIfNeeded()
                            assert(window.frame.size == size, "The guide must not enlarge the settings window")
                            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw Failure.render }
                            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
                            let name = "\(language.rawValue)-\(theme.rawValue)-\(dark ? "dark" : "light")-\(accessible ? "accessible" : "standard")-step\(step + 1).png"
                            try png.write(to: directory.appendingPathComponent(name))
                            guard let screenshot = NSBitmapImageRep(data: png) else { throw Failure.render }
                            let bounds = try primaryVerticalBounds(in: screenshot, palette: theme.palette(isDark: dark))
                            if let footerBounds {
                                assert(bounds == footerBounds, "All four pages must keep the primary action at the same height")
                            } else { footerBounds = bounds }
                            if language == .simplifiedChinese && theme == .blue && dark && !accessible {
                                store.scene = .music
                                try pressKey("\r", code: 36, in: hosting)
                                try await Task.sleep(for: .milliseconds(90))
                                if step < OnboardingState.stepCount {
                                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                    guard let motionPNG = bitmap.representation(using: .png, properties: [:]),
                                          let motionScreenshot = NSBitmapImageRep(data: motionPNG) else { throw Failure.render }
                                    try motionPNG.write(to: directory.appendingPathComponent("slide-step\(step + 1).png"))
                                    let motionBounds = try primaryVerticalBounds(in: motionScreenshot, palette: theme.palette(isDark: dark))
                                    assert(motionBounds == bounds,
                                           "The footer must stay fixed during the slide")
                                }
                                try await Task.sleep(for: .milliseconds(300))
                                assert(store.scene == .live, "Navigation and completion must restore the live demo")
                                if step == 1 {
                                    try pressPrevious(in: hosting)
                                    try await Task.sleep(for: .milliseconds(90))
                                    assert(defaults.integer(forKey: OnboardingState.stepKey) == step, "Previous must restore saved progress")
                                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                    guard let reversePNG = bitmap.representation(using: .png, properties: [:]),
                                          let reverseScreenshot = NSBitmapImageRep(data: reversePNG) else { throw Failure.render }
                                    try reversePNG.write(to: directory.appendingPathComponent("slide-back.png"))
                                    assert(outgoingHeadingOnRight(in: reverseScreenshot, palette: theme.palette(isDark: dark)),
                                           "The outgoing permission page must slide right when returning to menu setup")
                                    let reverseBounds = try primaryVerticalBounds(in: reverseScreenshot, palette: theme.palette(isDark: dark))
                                    assert(reverseBounds == bounds, "Previous must keep the footer fixed")
                                    try await Task.sleep(for: .milliseconds(300))
                                    try pressKey("\r", code: 36, in: hosting)
                                    try await Task.sleep(for: .milliseconds(90))
                                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                    guard let resumedPNG = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
                                    try resumedPNG.write(to: directory.appendingPathComponent("slide-forward-after-back.png"))
                                    try await Task.sleep(for: .milliseconds(300))
                                }
                                if step < OnboardingState.stepCount {
                                    assert(defaults.integer(forKey: OnboardingState.stepKey) == step + 1)
                                    if step < OnboardingState.stepCount - 1 {
                                        try pressKey("\u{1b}", code: 53, in: hosting, handled: false)
                                        try await settle()
                                        assert(!defaults.bool(forKey: OnboardingState.postponedKey) && !defaults.bool(forKey: OnboardingState.completedKey),
                                               "Escape must not postpone the guide after removing Not Now")
                                        assert(defaults.integer(forKey: OnboardingState.stepKey) == step + 1, "Escape must preserve progress")
                                    }
                                } else {
                                    assert(defaults.bool(forKey: OnboardingState.completedKey) && !defaults.bool(forKey: OnboardingState.postponedKey))
                                    assert(defaults.integer(forKey: OnboardingState.stepKey) == 0)
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
        assert(store.audio.bluetoothPermission.askedAt == nil,
               "Showing and navigating the guide must not request permissions")
        assert(renders == 96)
        print("PASS: compact 620pt guide with settings frame restoration; \(renders) native guide renders; forward/back/forward navigation, fixed footer, Return/Escape, saved progress, completion and demo cleanup")
    }

    @MainActor private static func checkWindowRestoration(store: Store) async throws {
        assert(Bundle.main.bundleIdentifier == "local.combo.onboarding-design-check", "Preference checks must run in the isolated test app")
        let defaults = UserDefaults.standard
        let keys = [OnboardingState.completedKey, OnboardingState.postponedKey, OnboardingState.stepKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(true, forKey: OnboardingState.completedKey)
        defaults.set(false, forKey: OnboardingState.postponedKey)
        defaults.set(0, forKey: OnboardingState.stepKey)
        let delegate = AppDelegate(store: store)
        delegate.openSettings()
        guard let window = delegate.settings, let hosting = window.contentView else { throw Failure.render }
        window.orderOut(nil)
        try await settle()
        for height in [CGFloat(870), 760] {
            var original = window.frame
            original.size.height = height
            window.setFrame(original, display: true)
            defaults.set(false, forKey: OnboardingState.completedKey)
            try await settle()
            assert(window.frame.height == 620 && window.frame.maxY == original.maxY)
            window.close()
            delegate.openSettings()
            window.orderOut(nil)
            try await settle()
            for _ in 0...OnboardingState.stepCount {
                try pressKey("\r", code: 36, in: hosting)
                try await settle()
            }
            assert(defaults.bool(forKey: OnboardingState.completedKey))
            assert(window.frame == original, "Completing a reopened guide must restore the previous settings frame")
        }
        window.contentView = nil
        window.close()
    }

    /// In the fixed Chinese/blue/dark fixture, only the outgoing permission heading can be here.
    @MainActor private static func outgoingHeadingOnRight(in bitmap: NSBitmapImageRep, palette: ComboPalette) -> Bool {
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

    @MainActor private static func pressPrevious(in view: NSView) throws {
        guard let window = view.window else { throw Failure.render }
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 120, y: 38), modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { throw Failure.render }
            window.sendEvent(event)
        }
    }

    /// Compare the real primary-button pixels to catch content-dependent page height changes.
    @MainActor private static func primaryVerticalBounds(in bitmap: NSBitmapImageRep, palette: ComboPalette) throws -> ClosedRange<Int> {
        guard let expected = NSColor(palette.accent).usingColorSpace(bitmap.colorSpace) else { throw Failure.render }
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
        guard let first = rows.first, let last = rows.last else { throw Failure.render }
        return first...last
    }

    @MainActor private static func pressKey(_ characters: String, code: UInt16, in view: NSView, handled: Bool = true) throws {
        guard let window = view.window,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw Failure.render }
        assert(view.performKeyEquivalent(with: event) == handled, "Return advances the guide; Escape has no postpone action")
    }

    @MainActor private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(180))
    }

    enum Failure: Error { case render }
}
