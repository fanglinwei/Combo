import AppKit
import SwiftUI
@testable import Combo

/// A visual tool: render every settings page without requesting permissions or changing system settings.
@main struct RenderSettings {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            app.applicationIconImage = icon
            icon.setName(NSImage.applicationIconName)
        }
        let defaults = UserDefaults.standard
        let keys = [OnboardingState.completedKey, OnboardingState.postponedKey, "themeFamily", "appearanceMode", Localization.preferenceKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) }; Localization.shared.refresh() }
        defaults.set(true, forKey: OnboardingState.completedKey)
        let store = Store()
        store.stop()
        store.mediaVisible = true
        store.mediaControlsAvailable = true
        store.mediaTrack = MediaTrack(title: "微风", artist: "空频信号", source: "Music", bundleIdentifier: "com.apple.Music", playing: true, artwork: nil)
        store.live.playing = true
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/settings-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var count = 0
        for language in [AppLanguage.simplifiedChinese, .english] {
            Localization.shared.selection = language
            for theme in ComboTheme.allCases {
                defaults.set(theme.rawValue, forKey: "themeFamily")
                for dark in [false, true] {
                    for frameSize in [NSSize(width: 850, height: 690), NSSize(width: 780, height: 620)] {
                        let size = NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize),
                                                        styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
                        for page in Page.allCases {
                            let variants = language == .english && theme == .blue && dark && size.width == 780 ? [false, true] : [false]
                            for accessible in variants {
                                let view = SettingsView(store: store, page: page) { _ in }
                                    .environment(\.colorScheme, dark ? .dark : .light)
                                    .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                                let hosting = NSHostingView(rootView: view)
                                hosting.frame = NSRect(origin: .zero, size: size)
                                let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
                                window.isReleasedWhenClosed = false
                                window.appearance = NSAppearance(named: accessible ? .accessibilityHighContrastDarkAqua : dark ? .darkAqua : .aqua)
                                window.contentView = hosting
                                window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
                                window.orderFrontRegardless()
                                hosting.layoutSubtreeIfNeeded()
                                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                                guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw Failure.render }
                                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                                guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.render }
                                let name = "\(language.rawValue)-\(theme.rawValue)-\(dark ? "dark" : "light")-\(Int(size.width))-\(page.id)\(accessible ? "-large-text-contrast" : "").png"
                                try png.write(to: out.appendingPathComponent(name))
                                window.orderOut(nil)
                                count += 1
                            }
                        }
                    }
                }
            }
        }
        print("Rendered \(count) settings previews → \(out.path)")
    }
    enum Failure: Error { case render }
}
