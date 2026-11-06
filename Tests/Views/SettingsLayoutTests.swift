import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct SettingsLayoutTests {
        @Test
        @MainActor
        func testHelpDisclosureLayoutAcrossStatesAndPalettes() async throws {
            for dark in [false, true] {
                for expanded in [false, true] {
                    var contentWidth: CGFloat = 0
                    let palette = ComboPalette.settings(isDark: dark)
                    let view = DisclosureGroup(isExpanded: .constant(expanded)) {
                        Text("A long help description that must wrap within the inset content area without widening the settings window.")
                            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
                    } label: {
                        HStack(spacing: 11) {
                            CategoryIcon(symbol: "book", color: palette.iconBlue)
                            Text("Getting started")
                        }
                    }
                    .disclosureGroupStyle(SettingsHelpDisclosureStyle(reduceMotion: true))
                    .environment(\.comboPalette, palette)
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 500).fixedSize(horizontal: false, vertical: true)
                    let hosting = NSHostingView(rootView: view)
                    let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 500, height: 160),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    defer { window.close(); window.contentView = nil }
                    window.contentView = hosting
                    window.orderFrontRegardless()
                    try await Task.sleep(for: .milliseconds(80))
                    hosting.layoutSubtreeIfNeeded()
                    #expect(hosting.fittingSize.width == 500)
                    if expanded {
                        #expect(contentWidth == 430, "Help text must have 35pt insets on both sides")
                        #expect(hosting.fittingSize.height > 66, "Expanded content and its bottom spacing must be visible")
                    } else {
                        #expect(contentWidth == 0, "Collapsed help must hide its content")
                        #expect(hosting.fittingSize.height == 50, "24pt icon plus 13pt vertical padding")
                    }
                    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    Attachment.record(png, named: "help-\(dark ? "dark" : "light")-\(expanded ? "expanded" : "collapsed").png")
                }
            }
        }

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

        @Test
        @MainActor
        func testHeightResizeInterruptionAndReducedMotion() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            store.reduceMotion = true
            let delegate = AppDelegate(store: store)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: 600),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            delegate.configureSettingsWindow(window)
            let screen = try #require(window.screen?.visibleFrame)
            window.setFrameTopLeftPoint(NSPoint(x: screen.midX - SettingsLayout.width / 2, y: screen.maxY - 20))
            window.orderFrontRegardless()
            let top = window.frame.maxY
            let chrome = window.frame.height - window.contentLayoutRect.height
            delegate.updateSettingsContentHeight(280)
            try await Task.sleep(for: .milliseconds(50))
            #expect(abs(window.frame.height - (280 + chrome)) < 1)
            #expect(abs(window.frame.maxY - top) < 1)

            store.reduceMotion = false
            delegate.updateSettingsContentHeight(520)
            try await Task.sleep(for: .milliseconds(70))
            #expect(window.frame.height > 280 + chrome && window.frame.height < 520 + chrome,
                    "Window growth must have intermediate frames: \(window.frame)")
            let interrupted = window.frame.height
            delegate.updateSettingsContentHeight(340)
            try await Task.sleep(for: .milliseconds(20))
            #expect(abs(window.frame.height - interrupted) < 100, "Retarget from the current visible height")
            try await Task.sleep(for: .milliseconds(400))
            #expect(abs(window.frame.height - (340 + chrome)) < 1, "The latest height must win")
            #expect(abs(window.frame.maxY - top) < 1, "Keep the titlebar stationary")

            store.reduceMotion = true
            delegate.updateSettingsContentHeight(10_000)
            try await Task.sleep(for: .milliseconds(50))
            #expect(window.frame.minY >= screen.minY - 1 && window.frame.maxY <= screen.maxY + 1,
                    "Long content must fit the available screen")
            delegate.updateSettingsContentHeight(280)
            try await Task.sleep(for: .milliseconds(50))
            #expect(abs(window.frame.height - (280 + chrome)) < 1, "Reduced Motion resizes immediately")
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
            // Saved legacy colors must not change the standard palette.
            defaults.set("purple", forKey: "themeFamily")
            let language = Localization.shared.selection
            defer { Localization.shared.selection = language }
            let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })), monitorsSystem: false)
            defer { store.stop() }
            store.screenActive = false
            store.reduceMotion = true
            var count = 0
            for language in (accessible ? [.english] : [AppLanguage.simplifiedChinese, .english]) {
                Localization.shared.selection = language
                for dark in [false, true] {
                    for frameSize in (accessible ? [NSSize(width: 560, height: 560)] : [NSSize(width: 560, height: 640), NSSize(width: 560, height: 560)]) {
                        let size = NSWindow.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize),
                                                       styleMask: [.titled, .closable, .miniaturizable, .resizable]).size
                        for page in Page.allCases {
                            let name = "\(language.rawValue)-\(dark ? "dark" : "light")-\(Int(size.width))-\(page.id)\(accessible ? "-large-text-contrast" : "")"
                            var measuredHeight: CGFloat = 0
                            let view = SettingsView(store: store, page: page, contentHeightChanged: { measuredHeight = $0 }) { _ in }
                                .defaultAppStorage(defaults)
                                .environment(\.colorScheme, dark ? .dark : .light)
                                .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                            let hosting = NSHostingView(rootView: view)
                            hosting.sizingOptions = []
                            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -9000, y: -9000), size: size),
                                                  styleMask: .borderless, backing: .buffered, defer: false)
                            window.isReleasedWhenClosed = false
                            window.backgroundColor = NSColor(ComboPalette.settings(isDark: dark).canvasTop)
                            defer { window.close(); window.contentView = nil }
                            window.appearance = NSAppearance(named: accessible ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua) : dark ? .darkAqua : .aqua)
                            window.contentView = hosting
                            window.orderFrontRegardless()
                            try await Task.sleep(for: .milliseconds(80))
                            hosting.layoutSubtreeIfNeeded()
                            #expect(measuredHeight > 200 && measuredHeight < 700,
                                    "Report the selected page's natural content height: \(measuredHeight), \(name)")
                            #expect(window.frame.size == size, "Settings must fit the requested window: \(name)")
                            #expect(hosting.frame.size == size, "Settings must not enlarge the content view: \(name)")
                            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds), "Missing settings bitmap: \(name)")
                            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                            let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing settings PNG: \(name)")
                            Attachment.record(png, named: "\(name).png")
                            try checkNavigationAndContent(hosting, bitmap: bitmap, page: page, window: window, palette: ComboPalette.settings(isDark: dark), name: name)
                            count += 1
                        }
                    }
                }
            }
            #expect(count == (accessible ? 6 : 24), "Every settings variant must be exercised")
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
            let text = NSColor(palette.primaryText)
            let region = NSRect(x: viewport.minX + 20, y: viewport.minY + 20,
                                width: viewport.width - 40, height: min(350, viewport.height - 40))
            #expect(try pixels(matching: text, in: region, bitmap: bitmap, size: window.frame.size) > 30,
                    "The selected settings page must render readable content: \(name)")
            #expect(contrast(text, NSColor(palette.canvasTop)) >= 4.5,
                    "Settings text must remain readable in both appearances: \(name)")

        }

        private func contrast(_ text: NSColor, _ background: NSColor) -> Double {
            func luminance(_ color: NSColor) -> Double {
                let color = color.usingColorSpace(.sRGB) ?? color
                func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
                return linear(color.redComponent) * 0.2126 + linear(color.greenComponent) * 0.7152 + linear(color.blueComponent) * 0.0722
            }
            let a = luminance(text), b = luminance(background)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
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
