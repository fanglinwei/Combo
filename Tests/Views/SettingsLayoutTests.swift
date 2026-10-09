import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct SettingsLayoutTests {
        @Test
        @MainActor
        func testAllPagesAcrossLanguagesPalettesAndWindowSizes() async throws {
            try await renderPages(accessible: false)
        }

        @Test
        @MainActor
        func testAllPagesWithLargeTextAndHighContrast() async throws {
            try await renderPages(accessible: true)
        }

        @MainActor
        private func renderPages(accessible: Bool) async throws {
            let iconURL = try #require(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
            let icon = try #require(NSImage(contentsOf: iconURL))
            NSApp.applicationIconImage = icon
            icon.setName(NSImage.applicationIconName)
            let suite = "Combo.SettingsLayout.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: OnboardingState.completedKey)
            let language = Localization.shared.selection
            defer { Localization.shared.selection = language }
            let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })), monitorsSystem: false)
            defer { store.stop() }
            store.screenActive = false
            store.reduceMotion = true
            store.mediaVisible = true
            store.mediaControlsAvailable = true
            store.mediaTrack = MediaTrack(title: "微风", artist: "空频信号", source: "Music", bundleIdentifier: "com.apple.Music", playing: true, artwork: nil)
            store.live.playing = true
            var count = 0
            for language in (accessible ? [.english] : [AppLanguage.simplifiedChinese, .english]) {
                Localization.shared.selection = language
                for theme in (accessible ? [.blue] : ComboTheme.allCases) {
                    defaults.set(theme.rawValue, forKey: "themeFamily")
                    for dark in (accessible ? [true] : [false, true]) {
                        for frameSize in (accessible ? [NSSize(width: 780, height: 620)] : [NSSize(width: 850, height: 690), NSSize(width: 780, height: 620)]) {
                            let size = NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize),
                                                           styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
                            for page in Page.allCases {
                                let name = "\(language.rawValue)-\(theme.rawValue)-\(dark ? "dark" : "light")-\(Int(size.width))-\(page.id)\(accessible ? "-large-text-contrast" : "")"
                                let view = SettingsView(store: store, page: page) { _ in }
                                    .defaultAppStorage(defaults)
                                    .environment(\.colorScheme, dark ? .dark : .light)
                                    .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                                let hosting = NSHostingView(rootView: view)
                                hosting.sizingOptions = []
                                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                                                      styleMask: .borderless, backing: .buffered, defer: false)
                                window.isReleasedWhenClosed = false
                                defer { window.close(); window.contentView = nil }
                                window.appearance = NSAppearance(named: accessible ? .accessibilityHighContrastDarkAqua : dark ? .darkAqua : .aqua)
                                window.contentView = hosting
                                window.orderFrontRegardless()
                                try await Task.sleep(for: .milliseconds(80))
                                hosting.layoutSubtreeIfNeeded()
                                #expect(window.frame.size == size, "Settings must fit the requested window: \(name)")
                                #expect(hosting.frame.size == size, "Settings must not enlarge the content view: \(name)")
                                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), "Missing settings bitmap: \(name)")
                                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                                let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing settings PNG: \(name)")
                                Attachment.record(png, named: "\(name).png")
                                try checkNavigationAndContent(hosting, bitmap: bitmap, page: page, window: window, palette: theme.palette(isDark: dark), name: name)
                                count += 1
                            }
                        }
                    }
                }
            }
            #expect(count == (accessible ? 6 : 144), "Every settings variant must be exercised")
        }

        @MainActor
        private func checkNavigationAndContent(_ hosting: NSView, bitmap: NSBitmapImageRep, page: Page,
                                               window: NSWindow, palette: ComboPalette, name: String) throws {
            let scroll = try #require(scrollView(in: hosting), "Missing settings scroll view: \(name)")
            let document = try #require(scroll.documentView, "Missing settings document: \(name)")
            let viewport = hosting.convert(scroll.frame, from: scroll.superview)
            #expect(viewport.width > 0 && viewport.height > 0 && hosting.bounds.insetBy(dx: -1, dy: -1).contains(viewport),
                          "Settings scroll viewport must fit the content view: \(viewport), \(name)")
            #expect(document.frame.width <= scroll.contentView.bounds.width + 1,
                          "Settings content must fit horizontally: document=\(document.frame), viewport=\(scroll.contentView.bounds), \(name)")
            let accent = try #require(NSColor(palette.accent).usingColorSpace(.sRGB), "Missing settings accent")
            let label = NSColor(srgbRed: palette.isDark ? 0.96 : 0.11, green: palette.isDark ? 0.96 : 0.11,
                                blue: palette.isDark ? 0.97 : 0.12, alpha: 1)
            let selected = try #require(Page.allCases.firstIndex(of: page))
            for index in Page.allCases.indices {
                let target = index == selected ? accent : label
                let region = NSRect(x: 54, y: 87 + 42 * index, width: 126, height: 38)
                let count = try pixels(matching: target, in: region, bitmap: bitmap, size: window.frame.size)
                #expect(count > 20, "Each navigation label must render inside its row: row=\(index), pixels=\(count), \(name)")
            }
            let heading = NSRect(x: 230, y: 28, width: window.frame.width - 260, height: 32)
            #expect(try pixels(matching: label, in: heading, bitmap: bitmap, size: window.frame.size) > 30,
                          "The page heading must render visibly above its content: \(name)")
            let background = try color(at: NSPoint(x: 180, y: 106 + 42 * selected), bitmap: bitmap, size: window.frame.size)
            #expect(MediaArtworkTint.contrast(accent, background) >= 4.5 - 0.001,
                          "The selected navigation label must remain readable: \(name)")
        }

        @MainActor
        private func pixels(matching target: NSColor, in region: NSRect, bitmap: NSBitmapImageRep, size: NSSize) throws -> Int {
            var count = 0
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) {
                    let sample = try color(at: NSPoint(x: x, y: y), bitmap: bitmap, size: size)
                    if abs(sample.redComponent - target.redComponent) < 0.06
                        && abs(sample.greenComponent - target.greenComponent) < 0.06
                        && abs(sample.blueComponent - target.blueComponent) < 0.06 { count += 1 }
                }
            }
            return count
        }

        @MainActor
        private func color(at point: NSPoint, bitmap: NSBitmapImageRep, size: NSSize) throws -> NSColor {
            let x = Int(point.x * CGFloat(bitmap.pixelsWide) / size.width)
            let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height)
            let sample = try #require(bitmap.colorAt(x: x, y: y), "Missing settings pixel at \(point)")
            // colorAt returns calibrated components even for a Display P3 bitmap; retain the bitmap's profile.
            var components = [sample.redComponent, sample.greenComponent, sample.blueComponent, sample.alphaComponent]
            return try #require(NSColor(colorSpace: bitmap.colorSpace, components: &components, count: 4).usingColorSpace(.sRGB),
                                 "Missing settings sRGB pixel at \(point)")
        }

        @MainActor
        private func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
        }
    }
}
