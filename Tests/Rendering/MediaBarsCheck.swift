import AppKit
import SwiftUI
@testable import Combo

@main struct MediaBarsCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let savedAnimation = UserDefaults.standard.object(forKey: "animate")
        defer { UserDefaults.standard.set(savedAnimation, forKey: "animate") }
        let store = Store()
        store.stop()
        store.mediaVisible = true
        store.mediaControlsAvailable = true
        store.live.playing = true
        store.animate = true
        store.reduceMotion = true
        let page = SettingsView.MediaPage(store: store)
            .environment(\.comboPalette, ComboTheme.gold.palette(isDark: true))
            .frame(width: 609, height: 600, alignment: .topLeading)
        let hosting = NSHostingView(rootView: page)
        hosting.frame = NSRect(x: 0, y: 0, width: 609, height: 600)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Only the status bars: exclude text, artwork and the animated legend.
        let region = NSRect(x: 20, y: 20, width: 18, height: 20)
        func frames() async throws -> [Data] {
            var frames: [Data] = []
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(200))
                hosting.layoutSubtreeIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: region) else {
                    throw Failure.render
                }
                hosting.cacheDisplay(in: region, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw Failure.render
                }
                frames.append(data)
            }
            return frames
        }

        for reduced in [true, false, true, false] {
            store.reduceMotion = reduced
            try await Task.sleep(for: .milliseconds(300))
            let samples = try await frames()
            let changes = Set(samples).count > 1
            guard changes == !reduced else { throw Failure.motion(reduced: reduced, changes: changes) }
        }
        print("PASS: media status bars stay static with Reduce Motion and resume after repeated preference changes")
    }

    enum Failure: Error { case render, motion(reduced: Bool, changes: Bool) }
}
