import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct PanelDesignTests {
        @Test
        @MainActor
        func testArtworkTintAndContrastAcrossPalettes() async throws {
            var combinations = 0
            for theme in ComboTheme.allCases {
                for dark in [false, true] {
                    let palette = theme.palette(isDark: dark)
                    let samples: [(NSColor, NSColor?)] = [(.black, nil), (.white, nil), (.gray, nil), (.red, nil), (.green, nil), (.blue, nil),
                        (NSColor(srgbRed: 0.7, green: 0.55, blue: 0.45, alpha: 1), nil),
                        (NSColor(srgbRed: 0.31, green: 0.19, blue: 0.42, alpha: 1), nil), (.black, .yellow), (.white, .systemPurple)]
                    for (index, item) in samples.enumerated() {
                        let data = try artwork(item.0, patch: item.1)
                        let sample = MediaArtworkTint.sample(data)
                        if index < 3 { #expect(sample == nil, "Grayscale artwork must fall back to the theme accent") }
                        for increased in [false, true] {
                            let tint = MediaArtworkTint.resolved(sample, palette: palette, increasedContrast: increased)
                            let background = MediaArtworkTint.mixed(tint.color, over: NSColor(palette.surface), alpha: tint.alpha * 2)
                            #expect(MediaArtworkTint.contrast(NSColor(palette.mutedText), background) >= 4.5 - 0.001,
                                   "Artwork tint must preserve readable secondary text")
                            #expect(tint.alpha * 2 <= (dark ? 0.15 : 0.12))
                        }
                        combinations += 1
                    }
                }
            }
            #expect(combinations == 60)
        }

        @Test
        @MainActor
        func testRowHoverPressAndDisabledPixelsAcrossPalettes() async throws {
            for theme in ComboTheme.allCases {
                for dark in [false, true] {
                    try await checkRowHover(palette: theme.palette(isDark: dark), name: "\(theme.rawValue)-\(dark ? "dark" : "light")")
                }
            }
        }

        @Test
        @MainActor
        func testPanelAndDetailLayoutsAcrossPalettes() async throws {
            let suite = "Combo.PanelDesign.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = makeStore(defaults: defaults, cover: try artwork(.systemPurple))
            defer { store.stop() }
            var renders = 0
            for theme in ComboTheme.allCases {
                for dark in [false, true] {
                    defaults.set(theme.rawValue, forKey: "themeFamily")
                    for section in [PanelSection?.none, .battery, .wifi, .sound] {
                        store.panelRevealed = false
                        store.detailSection = section
                        var measured: CGFloat = 0
                        let view = PanelView(store: store, battery: store.battery, audio: store.audio, airpods: store.audio.airpods, bluetoothPermission: store.audio.bluetoothPermission,
                                             mode: section == nil ? .overview : .detail, showSettings: {}, maxHeight: 900, reportHeight: { measured = $0 })
                            .defaultAppStorage(defaults).environment(\.colorScheme, dark ? .dark : .light)
                        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 420, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        defer { window.close(); window.contentView = nil }
                        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                        let hosting = NSHostingView(rootView: view)
                        hosting.sizingOptions = []
                        window.contentView = hosting
                        window.orderFrontRegardless()
                        try await Task.sleep(for: .milliseconds(20))
                        store.panelRevealed = true
                        try await Task.sleep(for: .milliseconds(200))
                        hosting.layoutSubtreeIfNeeded()
                        #expect(measured > 100 && measured < 900, "Default content must fit without internal scrolling: \(measured)")
                        guard measured > 100 && measured < 900 else { return }
                        let frame = NSRect(x: 0, y: 0, width: 420, height: measured)
                        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: frame), "Missing bitmap prerequisite")
                        hosting.cacheDisplay(in: frame, to: bitmap)
                        let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing png prerequisite")
                        let name = "\(theme.rawValue)-\(dark ? "dark" : "light")-\(section?.rawValue ?? "overview")"
                        attachPNG(png, name: name)
                        window.orderOut(nil)
                        renders += 1
                    }
                }
            }
            #expect(renders == 24)
        }

        @Test
        @MainActor
        func testAirPodsExpansionWithEarlyAndLateData() async throws {
            let suite = "Combo.PanelDesign.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = makeStore(defaults: defaults, cover: try artwork(.systemPurple))
            defer { store.stop() }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.PanelDesign.\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try await checkAirPodsExpansion(store: store, directory: directory)
        }
        @MainActor
        private func makeStore(defaults: UserDefaults, cover: Data) -> Store {
            let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in }), initialOutputID: 42), monitorsSystem: false)
            store.screenActive = false
            store.reduceMotion = true
            store.panelVisible = true
            store.panelRevealed = true
            store.detailRevealed = true
            store.scene = .charging
            store.wifi.powerOn = true
            store.wifi.currentSSID = "Office Network With A Long Name"
            store.wifi.currentRSSI = -55
            store.wifi.currentSecurity = .wpa2Personal
            store.live.volume = 0.16
            store.mediaVisible = true
            store.mediaControlsAvailable = true
            store.live.playing = true
            store.mediaTrack = MediaTrack(title: "一首标题很长很长但不应该推挤播放状态的歌曲", artist: "示例艺人", source: "Music",
                                          bundleIdentifier: nil, playing: true, artwork: cover)
            return store
        }

        @MainActor
        private func checkAirPodsExpansion(store: Store, directory: URL) async throws {
            let helper = directory.appendingPathComponent("airpods-helper")
            let id = store.audio.selectedOutputID
            _ = try #require(id != 0 ? id : nil, "Fixture requires a nonzero output identity")
            let target = String(repeating: "a", count: 64)
            let payload: [String: Any] = ["deviceID": id, "target": target, "available": true,
                                        "modes": [], "canSetMode": false, "canSetConversation": false,
                                        "left": 66, "right": 62, "attempted": false, "verified": false]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            try ("#!/bin/sh\nprintf '%s' '" + json + "'\n").write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            defer { try? FileManager.default.removeItem(at: helper) }
            let control = AirPodsControl(helperURL: helper, libraryURL: URL(fileURLWithPath: "/usr/lib/libSystem.B.dylib"))
            defer { control.cancel() }
            let scene = store.scene
            let live = store.live
            defer { store.scene = scene; store.live = live; store.panelExpanded = false; store.reduceMotion = true }
            store.scene = .live
            store.live.deviceKind = .bluetooth(.airPodsPro)
            store.live.output = "Test AirPods Pro"
            store.reduceMotion = false
            store.panelExpanded = false
            var heights: [CGFloat] = []
            let view = PanelView(store: store, battery: store.battery, audio: store.audio, airpods: control,
                                 bluetoothPermission: store.audio.bluetoothPermission, mode: .overview,
                                 showSettings: {}, maxHeight: 900, reportHeight: { heights.append($0) })
            let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 420, height: 900),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.orderFront(nil)
            window.isReleasedWhenClosed = false
            defer { window.close(); window.contentView = nil }
            try await Task.sleep(for: .milliseconds(100))
            let collapsed = try requireHeight(heights.last)
            control.refresh(deviceID: id, target: target)
            for _ in 0..<50 {
                if control.snapshot != nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(control.snapshot != nil, "Fixture must deliver valid AirPods data")
            _ = try #require(control.snapshot)
            try await Task.sleep(for: .milliseconds(50))
            #expect(heights.last == collapsed, "Early data must not resize a panel during entrance")
            heights.removeAll()
            store.panelExpanded = true
            try await Task.sleep(for: .milliseconds(300))
            let expanded = try requireHeight(heights.last)
            #expect(expanded > collapsed, "Battery information must expand the sound card after entrance")
            #expect(heights == [expanded], "Report one target height so the native resize animation is not restarted each frame")
            control.cancel()
            try await Task.sleep(for: .milliseconds(300))
            #expect(heights.last == collapsed, "No battery information must leave no reserved space")
            control.refresh(deviceID: id, target: target)
            try await Task.sleep(for: .milliseconds(400))
            #expect(heights.last == expanded, "Late data must expand without reopening the panel")
            store.reduceMotion = true
            store.panelExpanded = false
            try await Task.sleep(for: .milliseconds(100))
            #expect(heights.last == collapsed)
            store.panelExpanded = true
            try await Task.sleep(for: .milliseconds(100))
            #expect(heights.last == expanded, "Reduced motion must display the data without height animation")
        }
        private func requireHeight(_ height: CGFloat?) throws -> CGFloat {
            return try #require(height, "Missing panel height measurement")
        }
        @MainActor
        private func checkRowHover(palette: ComboPalette, name: String) async throws {
            let frame = NSRect(x: 0, y: 0, width: 200, height: 40)
            var samples: [NSBitmapImageRep] = []
            for (hovered, pressed, enabled) in [(false, false, true), (true, false, true), (true, true, true), (true, true, false)] {
                let view = HStack(spacing: 9) {
                    Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 28, height: 28)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.green).frame(width: 8, height: 12)
                }
                .modifier(PanelRowSurface(hovered: hovered, pressed: pressed))
                .environment(\.comboPalette, palette).environment(\.isEnabled, enabled)
                .frame(width: frame.width, height: frame.height)
                .background(palette.isDark ? Color.black : Color.white)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = frame
                hosting.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
                try await Task.sleep(for: .milliseconds(20))
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: frame), "Missing bitmap prerequisite")
                hosting.cacheDisplay(in: frame, to: bitmap)
                samples.append(bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]), "Missing png prerequisite")
                attachPNG(png, name: "\(name)-row-\(samples.count)")
            }
            func color(_ index: Int, _ x: Int, _ y: Int) throws -> NSColor {
                let bitmap = samples[index]
                return try #require(bitmap.colorAt(x: x * bitmap.pixelsWide / 200, y: y * bitmap.pixelsHigh / 40)?.usingColorSpace(.deviceRGB), "Missing row pixel")
            }
            func difference(_ first: NSColor, _ second: NSColor) -> CGFloat {
                abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent) + abs(first.blueComponent - second.blueComponent)
            }
            #expect(try difference(color(0, 100, 20), color(1, 100, 20)) > 0.1, "Hover must highlight the row")
            #expect(try difference(color(1, 100, 20), color(2, 100, 20)) > 0.05, "Press must be distinct from hover")
            #expect(try difference(color(0, 100, 20), color(3, 100, 20)) < 0.01, "Disabled rows must ignore hover and press")
            #expect(try difference(color(0, 20, 20), color(1, 20, 20)) < 0.01, "Hover backgrounds must not tint the content")
            #expect(try difference(color(0, 0, 0), color(1, 0, 0)) < 0.01, "Hover must stay inside rounded corners")
            #expect(try color(1, 8, 20).redComponent - color(1, 8, 20).greenComponent > 0.8
                   && abs(color(1, 7, 20).redComponent - color(1, 7, 20).greenComponent) < 0.01,
                   "The icon must have an 8pt leading inset")
        }
        @MainActor
        private func artwork(_ color: NSColor, patch: NSColor? = nil) throws -> Data {
            let image = NSImage(size: NSSize(width: 8, height: 8))
            image.lockFocus()
            color.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            if let patch { patch.setFill(); NSRect(x: 2, y: 2, width: 2, height: 2).fill() }
            image.unlockFocus()
            let tiff = try #require(image.tiffRepresentation, "Missing artwork TIFF")
            let bitmap = try #require(NSBitmapImageRep(data: tiff), "Missing artwork bitmap")
            let data = try #require(bitmap.representation(using: .png, properties: [:]), "Missing artwork PNG")
            return data
        }
        @MainActor
        private func attachPNG(_ data: Data, name: String) {
            Attachment.record(data, named: "\(name).png")
        }
    }
}
