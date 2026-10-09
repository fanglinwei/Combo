import AppKit
import SwiftUI
@testable import Combo

@main struct PanelDesignCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: "build/checks/panel-design", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "Combo.PanelDesign.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.render }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store(audio: AudioStore(discovery: AirPlayDiscovery(defaults: defaults, startBrowser: { _ in })))
        defer { store.stop() }
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
        let cover = try artwork(.systemPurple)
        store.mediaTrack = MediaTrack(title: "一首标题很长很长但不应该推挤播放状态的歌曲", artist: "示例艺人", source: "Music",
                                      bundleIdentifier: nil, playing: true, artwork: cover)
        try await checkAirPodsExpansion(store: store, directory: directory)
        var combinations = 0
        for theme in ComboTheme.allCases {
            for dark in [false, true] {
                let palette = theme.palette(isDark: dark)
                defaults.set(theme.rawValue, forKey: "themeFamily")
                try await checkRowHover(palette: palette, name: "\(theme.rawValue)-\(dark ? "dark" : "light")", directory: directory)
                let samples: [(NSColor, NSColor?)] = [(.black, nil), (.white, nil), (.gray, nil), (.red, nil), (.green, nil), (.blue, nil),
                    (NSColor(srgbRed: 0.7, green: 0.55, blue: 0.45, alpha: 1), nil),
                    (NSColor(srgbRed: 0.31, green: 0.19, blue: 0.42, alpha: 1), nil), (.black, .yellow), (.white, .systemPurple)]
                for (index, item) in samples.enumerated() {
                    let data = try artwork(item.0, patch: item.1)
                    let sample = MediaArtworkTint.sample(data)
                    if index < 3 { assert(sample == nil, "Grayscale artwork must fall back to the theme accent") }
                    for increased in [false, true] {
                        let tint = MediaArtworkTint.resolved(sample, palette: palette, increasedContrast: increased)
                        let background = MediaArtworkTint.mixed(tint.color, over: NSColor(palette.surface), alpha: tint.alpha * 2)
                        assert(MediaArtworkTint.contrast(NSColor(palette.mutedText), background) >= 4.5 - 0.001,
                               "Artwork tint must preserve readable secondary text")
                        assert(tint.alpha * 2 <= (dark ? 0.15 : 0.12))
                    }
                    combinations += 1
                }
                for section in [PanelSection?.none, .battery, .wifi, .sound] {
                    store.panelRevealed = false
                    store.detailSection = section
                    var measured: CGFloat = 0
                    let view = PanelView(store: store, battery: store.battery, audio: store.audio, airpods: store.audio.airpods, bluetoothPermission: store.audio.bluetoothPermission,
                                         mode: section == nil ? .overview : .detail, showSettings: {}, maxHeight: 900, reportHeight: { measured = $0 })
                        .defaultAppStorage(defaults).environment(\.colorScheme, dark ? .dark : .light)
                    let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: 420, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    let hosting = NSHostingView(rootView: view)
                    hosting.sizingOptions = []
                    window.contentView = hosting
                    window.orderFrontRegardless()
                    try await Task.sleep(for: .milliseconds(20))
                    store.panelRevealed = true
                    try await Task.sleep(for: .milliseconds(200))
                    hosting.layoutSubtreeIfNeeded()
                    assert(measured > 100 && measured < 900, "Default content must fit without internal scrolling: \(measured)")
                    let frame = NSRect(x: 0, y: 0, width: 420, height: measured)
                    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: frame) else { throw Failure.render }
                    hosting.cacheDisplay(in: frame, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
                    let name = "\(theme.rawValue)-\(dark ? "dark" : "light")-\(section?.rawValue ?? "overview")"
                    try png.write(to: directory.appendingPathComponent(name + ".png"))
                    print("Rendered \(name): \(measured)pt")
                    window.orderOut(nil)
                }
            }
        }
        print("PASS: \(combinations) artwork/theme combinations, contrast fallback, 24 native panel/detail renders, and row hover/pressed/disabled renders in all 6 palettes")
    }
    @MainActor private static func checkAirPodsExpansion(store: Store, directory: URL) async throws {
        let helper = directory.appendingPathComponent("airpods-helper")
        let id = store.audio.selectedOutputID
        guard id != 0 else { throw Failure.render }
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
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        let collapsed = try requireHeight(heights.last)
        control.refresh(deviceID: id, target: target)
        for _ in 0..<50 {
            if control.snapshot != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        assert(control.snapshot != nil, "Fixture must deliver valid AirPods data")
        try await Task.sleep(for: .milliseconds(50))
        assert(heights.last == collapsed, "Early data must not resize a panel during entrance")
        heights.removeAll()
        store.panelExpanded = true
        try await Task.sleep(for: .milliseconds(300))
        let expanded = try requireHeight(heights.last)
        assert(expanded > collapsed, "Battery information must expand the sound card after entrance")
        assert(heights == [expanded], "Report one target height so the native resize animation is not restarted each frame")
        print("PASS: AirPods early/late arrival, no reserved space, single resize target and reduced motion")
        control.cancel()
        try await Task.sleep(for: .milliseconds(300))
        assert(heights.last == collapsed, "No battery information must leave no reserved space")
        control.refresh(deviceID: id, target: target)
        try await Task.sleep(for: .milliseconds(400))
        assert(heights.last == expanded, "Late data must expand without reopening the panel")
        store.reduceMotion = true
        store.panelExpanded = false
        try await Task.sleep(for: .milliseconds(100))
        assert(heights.last == collapsed)
        store.panelExpanded = true
        try await Task.sleep(for: .milliseconds(100))
        assert(heights.last == expanded, "Reduced motion must display the data without height animation")
    }
    private static func requireHeight(_ height: CGFloat?) throws -> CGFloat {
        guard let height else { throw Failure.render }
        return height
    }
    @MainActor private static func checkRowHover(palette: ComboPalette, name: String, directory: URL) async throws {
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
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: frame) else { throw Failure.render }
            hosting.cacheDisplay(in: frame, to: bitmap)
            samples.append(bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
            try png.write(to: directory.appendingPathComponent("\(name)-row-\(samples.count).png"))
        }
        func color(_ index: Int, _ x: Int, _ y: Int) -> NSColor {
            let bitmap = samples[index]
            guard let color = bitmap.colorAt(x: x * bitmap.pixelsWide / 200, y: y * bitmap.pixelsHigh / 40)?.usingColorSpace(.deviceRGB) else {
                preconditionFailure("Missing row pixel")
            }
            return color
        }
        func difference(_ first: NSColor, _ second: NSColor) -> CGFloat {
            abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent) + abs(first.blueComponent - second.blueComponent)
        }
        assert(difference(color(0, 100, 20), color(1, 100, 20)) > 0.1, "Hover must highlight the row")
        assert(difference(color(1, 100, 20), color(2, 100, 20)) > 0.05, "Press must be distinct from hover")
        assert(difference(color(0, 100, 20), color(3, 100, 20)) < 0.01, "Disabled rows must ignore hover and press")
        assert(difference(color(0, 20, 20), color(1, 20, 20)) < 0.01, "Hover backgrounds must not tint the content")
        assert(difference(color(0, 0, 0), color(1, 0, 0)) < 0.01, "Hover must stay inside rounded corners")
        assert(color(1, 8, 20).redComponent - color(1, 8, 20).greenComponent > 0.8
               && abs(color(1, 7, 20).redComponent - color(1, 7, 20).greenComponent) < 0.01,
               "The icon must have an 8pt leading inset")
    }
    @MainActor private static func artwork(_ color: NSColor, patch: NSColor? = nil) throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        if let patch { patch.setFill(); NSRect(x: 2, y: 2, width: 2, height: 2).fill() }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
        return data
    }
    enum Failure: Error { case render }
}
