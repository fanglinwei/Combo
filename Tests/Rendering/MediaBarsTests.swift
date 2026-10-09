import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ComboTestHost

extension IntegrationTests {
    struct MediaBarsTests {
        @Test
        @MainActor
        func testReducedMotionAndRepeatedPreferenceChanges() async throws {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
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
            defer { window.close(); window.contentView = nil }

            // Only the status bars: exclude text, artwork and the animated legend.
            let region = NSRect(x: 20, y: 20, width: 18, height: 20)
            func frames(cycle: Int) async throws -> [Data] {
                var frames: [Data] = []
                for frame in 0..<6 {
                    try await Task.sleep(for: .milliseconds(200))
                    hosting.layoutSubtreeIfNeeded()
                    let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: region))
                    hosting.cacheDisplay(in: region, to: bitmap)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    Attachment.record(data, named: "media-bars-cycle-\(cycle)-frame-\(frame).png")
                    frames.append(data)
                }
                return frames
            }

            for (cycle, reduced) in [true, false, true, false].enumerated() {
                store.reduceMotion = reduced
                try await Task.sleep(for: .milliseconds(300))
                let samples = try await frames(cycle: cycle)
                let changes = Set(samples).count > 1
                #expect(changes == !reduced, "Cycle \(cycle): reducedMotion=\(reduced), framesChanged=\(changes)")
                guard changes == !reduced else { return }
            }
        }
    }
}
