import Testing
import AppKit
import ImageIO
import SwiftUI

final class IconTransitionTests {
    @Test
    @MainActor
    func testCenterCrossfadeAndBottomReversal() throws {
        _ = NSApplication.shared
        var central = IconTransition()
        central.update(IconContent(kind: .battery, text: "82"), at: 0, reducedMotion: false)
        central.update(IconContent(kind: .headphones), at: 1, reducedMotion: false)
        let centralMiddle = central.frame(at: 1.115)
        #expect(centralMiddle.layers.count == 2 && centralMiddle.layers.allSatisfy { abs($0.opacity - 0.5) < 0.0001 },
               "Same-level icons must crossfade together over 230ms")
        #expect(centralMiddle.layers.allSatisfy { abs($0.scale - 0.85) < 0.0001 },
               "Crossfade must shrink the outgoing glyph and grow the incoming glyph")
        #expect(centralMiddle.peripheral == 1 && centralMiddle.ringOpacity == 1 && centralMiddle.ringProgress == 1,
               "A center-only transition must leave visible peripherals unchanged")
        #expect(central.isAnimating(at: 1.229) && !central.isAnimating(at: 1.231))
        var networkLoading = IconTransition()
        networkLoading.update(IconContent(kind: .wifi, priority: 1), at: 0, reducedMotion: false)
        networkLoading.update(IconContent(kind: .connecting, priority: 3), at: 1, reducedMotion: false)
        #expect(networkLoading.frame(at: 20).layers.last?.emphasis == 1 && networkLoading.frame(at: 20).peripheral == 0,
               "Wi-Fi must remain enlarged throughout a long connection")
        let silent = IconContent(Snapshot(symbol: "", muted: true))
        #expect(silent.kind == .battery, "Mute must preserve resident center content")
        var bottom = BottomTransition()
        var dots = Snapshot(volume: 0.5)
        bottom.update(dots, animate: true, at: 0, reducedMotion: false)
        dots.playing = true
        bottom.update(dots, animate: true, at: 1, reducedMotion: false)
        #expect(bottom.isAnimating(at: 1.1) && abs(bottom.value(at: 1.1) - 0.5) < 0.0001)
        dots.playing = false
        bottom.update(dots, animate: true, at: 1.1, reducedMotion: false)
        #expect(abs(bottom.value(at: 1.1) - 0.5) < 0.0001 && abs(bottom.value(at: 1.2) - 0.25) < 0.0001,
               "Rapid playback changes must reverse from the current bottom shape")
        dots.playing = true; dots.adjusting = true
        bottom.update(dots, animate: true, at: 1.2, reducedMotion: false)
        #expect(!bottom.isAnimating(at: 1.2) && bottom.value(at: 1.2) == 0, "Volume adjustment must not morph")
        dots.adjusting = false
        bottom.update(dots, animate: true, at: 2, reducedMotion: true)
        #expect(!bottom.isAnimating(at: 2) && bottom.value(at: 2) == 1, "Reduced motion must switch bottom states directly")
        #expect(IconContent(Snapshot(symbol: "", volume: 0, playing: true)).kind == .battery)
        let adjusting = IconContent(Snapshot(symbol: "wifi", volume: 0.75, playing: true, adjusting: true, centerEvent: .volume))
        #expect(adjusting.kind == .volume, "Playback volume adjustment must override normal Wi-Fi")
        #expect(adjusting.text == "75" && adjusting.glyph == nil, "Volume hints must show digits instead of a speaker")
    }

    @Test
    @MainActor
    func testScenePriorityAndNetworkCompletion() throws {
        // The same resolver serves the real menu bar and the settings preview.

        #expect(content(.airpods).kind == .headphones && content(.airpods).priority == 2)
        #expect(content(.wifiMute).kind == .wifi && content(.mute).kind == .battery)
        #expect(content(.connecting).priority == 3 && content(.connecting).kind == .connecting)
        #expect(content(.plug).priority == 4 && content(.plug).kind == .plugged)
        #expect(content(.plug).text.isEmpty && content(.unplug).text.isEmpty,
               "Cable hints must show the C plug glyph instead of battery digits")
        #expect(!content(.plug).sameState(as: content(.unplug)), "Connected and disconnected badges must differ")
        #expect(content(.adjusting).priority == 4 && content(.adjusting).kind == .volume)
        #expect(content(.wifiOff).kind == .wifiOff && content(.wifiOff).priority == 2)
        #expect(content(.wifi).priority == 1 && content(.wifiMute).priority == 1)
        for scene in [Scene.wired, .music, .paused, .mute, .low, .charging, .offline, .reduced] {
            #expect(content(scene).priority == 2, "Other resident states must move to P2: \(scene)")
        }
        #expect(content(.unplug).priority == 4 && content(.unplug).kind == .unplugged)
        #expect(content(.wifi).networkContent.priority == 1)
        #expect(content(.wifiOff).networkContent.priority == 2)
        #expect(content(.offline).networkContent.priority == 2)
        #expect(content(.connecting).networkContent.priority == 3)
        var resident = IconTransition()
        resident.update(content(.wifi), at: 0, reducedMotion: false)
        resident.update(content(.wired), at: 1, reducedMotion: false)
        #expect(resident.isAnimating(at: 1.1), "P1 to P2 must animate")
        var lowBattery = Snapshot.demo(.wifi); lowBattery.battery = 0.2
        resident.update(IconContent(lowBattery.preferringBattery(threshold: 50)), at: 7, reducedMotion: false)
        #expect(resident.isAnimating(at: 7.1), "Different P2 resident states must animate")
        resident.update(content(.wifi), at: 8, reducedMotion: false)
        var cancelled = Snapshot.demo(.connecting); cancelled.symbol = "wifi.slash"
        #expect(IconContent(cancelled).kind == .wifiOff, "Power off must stop loading before association returns")
        for result in [Scene.wifi, .offline, .wifiOff, .wired] {
            var network = IconTransition()
            network.update(content(.connecting), at: 0, reducedMotion: false)
            #expect(network.frame(at: 30).layers.last?.emphasis == 1)
            network.update(content(result), at: 30, reducedMotion: false)
            #expect(network.frame(at: 30.3).layers.last?.content == content(result))
        }
        var interrupted = IconTransition()
        interrupted.update(content(.connecting), at: 0, reducedMotion: false)
        interrupted.update(content(.plug), at: 1, reducedMotion: false)
        interrupted.update(content(.wifi), at: 6, reducedMotion: false)
        #expect(interrupted.isAnimating(at: 6.1) && !interrupted.isAnimating(at: 6.231),
               "P4 to P1 must use the short center transition")
        interrupted.update(content(.connecting), at: 7, reducedMotion: false)
        interrupted.update(content(.wifi), at: 8, reducedMotion: false)
        interrupted.update(content(.plug), at: 9, reducedMotion: false)
        interrupted.update(content(.wifi), at: 14, reducedMotion: false)
        #expect(interrupted.isAnimating(at: 14.1) && !interrupted.isAnimating(at: 14.231),
               "The latest downgrade must finish without replaying an earlier result")
        var reducedNetwork = IconTransition()
        reducedNetwork.update(content(.connecting), at: 0, reducedMotion: true)
        #expect(!reducedNetwork.isAnimating(at: 1) && reducedNetwork.frame(at: 1).layers.last?.emphasis == 0)
        reducedNetwork.update(content(.connecting), at: 2, reducedMotion: false)
        #expect(reducedNetwork.frame(at: 10).layers.last?.emphasis == 1)
        reducedNetwork.update(content(.connecting), at: 11, reducedMotion: false, active: false)
        #expect(!reducedNetwork.isAnimating(at: 11), "Sleeping must stop loading frames")
        reducedNetwork.update(content(.connecting), at: 12, reducedMotion: false)
        #expect(reducedNetwork.frame(at: 20).layers.last?.emphasis == 1, "Wake must resume an active connection")
        var preferred = Snapshot.demo(.wifi); preferred.battery = 0.2
        var completion = IconTransition()
        completion.update(content(.connecting), at: 0, reducedMotion: false)
        completion.update(IconContent(preferred.preferringBattery(threshold: 50)), at: 1, reducedMotion: false)
        #expect(completion.isAnimating(at: 1.1) && !completion.isAnimating(at: 1.231))
        #expect(completion.frame(at: 1.3).layers.last?.content.kind == .battery)
        var reducedCompletion = IconTransition()
        reducedCompletion.update(content(.connecting), at: 0, reducedMotion: true)
        reducedCompletion.update(IconContent(preferred.preferringBattery(threshold: 50)), at: 1, reducedMotion: true)
        let reducedMiddle = reducedCompletion.frame(at: 1.08)
        #expect(reducedMiddle.layers.count == 2 && reducedMiddle.layers.allSatisfy { $0.opacity > 0 && $0.scale == 1 },
               "Reduced-motion center transitions must crossfade without scaling")
        let compactResult = reducedCompletion.frame(at: 1.3)
        #expect(compactResult.reduced && compactResult.layers.last?.content.kind == .battery)
        #expect(compactResult.layers.allSatisfy { $0.emphasis == 0 })
        #expect(reducedCompletion.isAnimating(at: 1.159) && !reducedCompletion.isAnimating(at: 1.161))
    }

    @Test
    @MainActor
    func testBatteryOutputAndMutePrecedence() throws {
        var media = Snapshot.demo(.airpods)
        media.charging = true
        for playing in [true, false] {
            media.playing = playing
            for level in [0.5, 0.6, 0.8, 1.0] {
                media.battery = level
                #expect(IconContent(media.preferringBattery(threshold: 50)).kind == .headphones,
                       "Active output takes precedence over charging at or above the threshold, including paused playback")
            }
            media.battery = 0.49
            #expect(IconContent(media.preferringBattery(threshold: 50)).kind == .battery,
                   "Low battery takes precedence over the active output even while charging")
            #expect(IconContent(media.preferringBattery(threshold: 0)).kind == .headphones,
                   "Disabling low-battery display restores the active output")
        }
        var chargingWithoutDevice = media
        chargingWithoutDevice.battery = 0.6
        chargingWithoutDevice.deviceKind = .other
        #expect(IconContent(chargingWithoutDevice.preferringBattery(threshold: 50)).kind == .battery,
               "Charging without a device glyph still shows battery")
        media.charging = false; media.battery = 0.2
        #expect(IconContent(media.preferringBattery(threshold: 50)).kind == .battery)
        media.battery = 0.82; media.playing = false
        #expect(IconContent(media).kind == .headphones, "AirPods stay resident even when playback is paused")
        for (symbol, expected) in [("wifi.slash", IconContent.Kind.wifiOff), ("exclamationmark", .warning), ("minus", .unavailable)] {
            media.symbol = symbol
            #expect(IconContent(media.preferringBattery(threshold: 50)).kind == expected)
        }
        media.symbol = ""; media.battery = 0.2
        #expect(IconContent(media.preferringBattery(threshold: 50)).kind == .battery, "Wired low battery also takes precedence over AirPods")
        media.centerEvent = .power; media.symbol = "exclamationmark"
        #expect(IconContent(media).priority == 4, "Events temporarily cover network errors")
        var switched = Snapshot.demo(.airpods)
        let beforeSwitch = IconContent(switched)
        switched.output = "MacBook 扬声器"
        switched.deviceKind = .other
        #expect(beforeSwitch.kind == .headphones && IconContent(switched).kind == .wifi,
               "Switching the active output away from AirPods must restore Wi-Fi")
        for reduced in [false, true] {
            var volume = Snapshot.demo(.adjusting)
            var mutedTransition = IconTransition()
            mutedTransition.update(content(.airpods), at: 0, reducedMotion: reduced)
            mutedTransition.update(IconContent(volume), at: 1, reducedMotion: reduced)
            volume.muted = true
            let muted = IconContent(volume)
            #expect(muted.kind == .volume && muted.text == "0" && muted.priority == 4)
            mutedTransition.update(muted, at: 1.2, reducedMotion: reduced)
            #expect(!mutedTransition.isAnimating(at: 1.2) && mutedTransition.frame(at: 1.2).layers.last?.content.text == "0",
                   "Changing volume or mute must not replay the short fade")
            #expect(bottomState(muted: volume.silenced, adjusting: true, playing: true, animate: true) == .muted)
            volume.muted = false; volume.volume = 0
            #expect(IconContent(volume).kind == .volume && IconContent(volume).text == "0", "Zero volume keeps the P4 digits")
            volume.centerEvent = .power
            #expect(IconContent(volume).priority == 4, "Mute must preserve power hints")
            volume.centerEvent = nil; volume.wifiConnecting = true
            #expect(IconContent(volume).kind == .connecting, "Mute must preserve Wi-Fi connection hints")
            volume.wifiConnecting = false; volume.volume = 0.5; volume.centerEvent = .volume
            mutedTransition.update(IconContent(volume), at: 2, reducedMotion: reduced)
            volume.centerEvent = nil
            mutedTransition.update(IconContent(volume), at: 12, reducedMotion: reduced)
            #expect(mutedTransition.frame(at: 12.3).layers.last?.content.kind == .headphones, "Expired volume hints restore AirPods")
        }
        #expect(IconContent(Snapshot(symbol: "")).text == "—", "Missing battery must remain unknown")
    }

    @Test
    @MainActor
    func testEventReplacementAndLifetime() throws {
        var priority = IconTransition()
        priority.update(content(.wifi), at: 0, reducedMotion: false)
        priority.update(content(.connecting), at: 1, reducedMotion: false)
        #expect(priority.isAnimating(at: 1.1))
        priority.update(content(.unplug), at: 2, reducedMotion: false)
        #expect(priority.isAnimating(at: 2.1))
        priority.update(content(.connecting), at: 2.2, reducedMotion: false)
        #expect(priority.isAnimating(at: 2.3) && priority.frame(at: 2.44).layers.last?.content.kind == .connecting,
               "P4 to P3 must crossfade to the latest center state")
        priority.update(content(.wifi), at: 3, reducedMotion: false)
        #expect(priority.isAnimating(at: 3.1) && !priority.isAnimating(at: 3.231),
               "P3 to P1 must use the short center transition")
        priority.update(content(.wired), at: 4, reducedMotion: false)
        #expect(priority.isAnimating(at: 4.1), "P1 to P2 must animate")
        priority.update(content(.adjusting), at: 5, reducedMotion: false)
        var quieter = Snapshot.demo(.adjusting); quieter.volume = 0.1
        priority.update(IconContent(quieter), at: 6, reducedMotion: false)
        #expect(!priority.isAnimating(at: 9.71), "Volume value changes must not restart entry")
        priority.update(content(.paused), at: 10, reducedMotion: false)
        #expect(priority.isAnimating(at: 10.1) && priority.frame(at: 10.3).layers.last?.content.kind == .battery,
               "Volume timeout must crossfade to current playback state")
        var events = CenterHint()
        for reducedMotion in [false, true] {
            for event in [CenterEvent.power, .volume] {
                let duration = IconTransition.Timing.eventDuration(event: event, reducedMotion: reducedMotion)
                let compactAt = event == .volume || reducedMotion ? 0.16 : 4.2
                let expiresAt = event == .volume ? 3 : 1 + compactAt + 5
                var hint = CenterHint()
                hint.show(event, at: 1, duration: duration, entrance: 0.6)
                var snapshot = Snapshot.demo(.wifi)
                snapshot.centerEvent = event
                var animation = IconTransition()
                animation.update(content(.wifi), at: 0, reducedMotion: reducedMotion)
                animation.update(IconContent(snapshot), at: 1, reducedMotion: reducedMotion)
                let compact = animation.frame(at: 1 + compactAt + 0.001)
                #expect(compact.layers.last?.emphasis == 0 && compact.layers.last?.content.event == event)
                #expect(hint.active(at: expiresAt - 0.001) == event)
                #expect(hint.active(at: expiresAt + 0.001) == nil)
                if event == .volume {
                    let fading = animation.frame(at: 1.08)
                    #expect(try fading.layers.last?.emphasis == 0 && (try #require(fading.layers.last)).opacity > 0,
                           "Volume must fade in at normal size")
                    #expect(fading.peripheral == 1 && fading.ringOpacity == 1)
                    #expect(!animation.isAnimating(at: 1.17))
                }
                snapshot.centerEvent = hint.active(at: expiresAt + 0.001)
                animation.update(IconContent(snapshot), at: expiresAt + 0.001, reducedMotion: reducedMotion)
                #expect(animation.frame(at: expiresAt + 0.3).layers.last?.content.kind == .wifi)
            }
        }
        let hintDuration = IconTransition.Timing.eventDuration(reducedMotion: false)
        let volumeDuration = IconTransition.Timing.eventDuration(event: .volume, reducedMotion: false)
        events.show(.volume, at: 0, duration: volumeDuration, entrance: 0.16)
        let volumeSerial = events.serial
        events.show(.volume, at: 1.5, duration: volumeDuration, entrance: 0.16)
        #expect(events.serial == volumeSerial && events.active(at: 3.499) == .volume && events.active(at: 3.5) == nil,
               "Continuous volume changes extend the hint without replaying entry")
        events.show(.power, at: 9, duration: hintDuration, entrance: 0.6)
        #expect(events.serial != volumeSerial && events.active(at: 10) == .power && events.active(at: 18.201) == nil,
               "A new event replaces the waiting hint without replaying it later")
        events.clear()
        events.show(.volume, at: 0, duration: 2, entrance: 0.6)
        let serial = events.serial
        events.show(.volume, at: 1.5, duration: 2, entrance: 0.6)
        #expect(events.serial == serial && events.active(at: 3.49) == .volume && events.active(at: 3.5) == nil)
        events.show(.power, at: 4, duration: 4.2, entrance: 0.6)
        events.show(.volume, at: 5, duration: 4.2, entrance: 0.6)
        #expect(events.active(at: 8.3) == .volume && events.active(at: 9.2) == nil, "Replaced power event must never return")
        events.show(.volume, at: 10, duration: 0.1, entrance: 0.6)
        #expect(events.active(at: 10.59) == .volume && events.active(at: 10.6) == nil, "Do not cut entry short")
    }

    @Test
    @MainActor
    func testGlyphFallbackDensityAndAppearance() throws {
        #expect(IconContent(kind: .warning).isWiFiGlyph && IconContent(kind: .warning).glyph == nil,
               "Network warnings must use the shared Wi-Fi silhouette")
        for name in ["airpods.pro", "airplay.audio", "appletv", "homepod", "homepod.mini", "hifispeaker", "car", "earbuds", "speaker.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill", "questionmark"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Missing symbol: \(name)")
        }
        #expect(DeviceGlyphImage.symbolName("definitely-not-a-symbol") == DeviceGlyphImage.fallbackName,
               "An unresolvable SF Symbol must fall back instead of leaving a blank center")
        #expect(DeviceGlyphImage.fallbackName == "headphones", "The shared fallback is the generic headphones symbol")
        let resolvedFallback = DeviceGlyphImage.resolve("definitely-not-a-symbol")
        #expect(resolvedFallback.name == DeviceGlyphImage.fallbackName && resolvedFallback.image != nil,
               "The resolved image and SwiftUI name must use the same visible fallback")
        func glyphImage(_ glyph: DeviceGlyph, dark: Bool = true) -> NSImage {
            var content = IconContent(kind: .headphones)
            content.glyph = glyph
            let frame = IconTransition.Frame(layers: [.init(content: content)], peripheral: 0, ringOpacity: 0)
            return IconRenderer.image(Snapshot(), animate: false, size: 100, dark: dark, transition: frame)
        }
        // A menu-bar image must redraw for its destination, including moving between 1x and 2x screens.
        func bitmap(_ image: NSImage, pixels: Int) throws -> NSBitmapImageRep {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "IconTransitionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bitmap context unavailable"]) }
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(pixels) / image.size.width, y: CGFloat(pixels) / image.size.height)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            return bitmap
        }
        let deviceKinds = BluetoothFamily.allCases.map { OutputDeviceKind.bluetooth($0) } + [
            .airPlay(.appleTV), .airPlay(.homePod), .airPlay(.homePodMini), .airPlay(.other)
        ]
        for kind in deviceKinds {
            for dark in [true, false] {
                let snapshot = Snapshot(battery: 0.82, volume: 0.5, deviceKind: kind)
                let menuBar = IconRenderer.image(snapshot, animate: false, size: 22, dark: dark)
                for scale in [1, 2] {
                    let pixels = 22 * scale
                    let actual = try bitmap(menuBar, pixels: pixels)
                    let reference = try bitmap(IconRenderer.image(snapshot, animate: false, size: CGFloat(pixels), dark: dark), pixels: pixels)
                    var error = 0.0
                    for y in 0..<pixels {
                        for x in 0..<pixels {
                            error += abs((try #require(actual.colorAt(x: x, y: y))).alphaComponent - (try #require(reference.colorAt(x: x, y: y))).alphaComponent)
                        }
                    }
                    #expect(error / Double(pixels * pixels) < 0.5 / 255,
                           "Menu-bar artwork must render directly at the destination density: \(kind), \(scale)x, dark=\(dark)")
                }
            }
        }
        let fallbackPixels = (try #require(glyphImage(.fallback).tiffRepresentation))
        for glyph in [DeviceGlyph.symbol("definitely-not-a-symbol"), .asset("definitely-not-an-asset")] {
            #expect((try #require(glyphImage(glyph).tiffRepresentation)) == fallbackPixels,
                   "Missing symbols and assets must render exactly the shared fallback")
        }
        for dark in [true, false, true] {
            let glyphData = try #require(glyphImage(.symbol("airpods.pro"), dark: dark).tiffRepresentation)
            let pixels = try #require(NSBitmapImageRep(data: glyphData))
            var brightness = 0.0, ink = 0.0
            for y in 0..<pixels.pixelsHigh {
                for x in 0..<pixels.pixelsWide {
                    let pixelColor = try #require(pixels.colorAt(x: x, y: y))
                    let color = try #require(pixelColor.usingColorSpace(.sRGB))
                    brightness += color.redComponent * color.alphaComponent
                    ink += color.alphaComponent
                }
            }
            #expect(ink > 0 && (dark ? brightness / ink > 0.8 : brightness / ink < 0.3),
                   "Reusing a symbol must still apply the current appearance's foreground color")
        }
    }

    @Test
    @MainActor
    func testPowerSourceChanges() throws {
        // At a charging limit, plugging in changes the power source but not isCharging.
        var detector = PowerChange()
        var power = Snapshot(battery: 0.8, charging: false, plugged: false, symbol: "wifi")
        let initialPowerChange = detector.update(onAC: power.plugged)
        #expect(!initialPowerChange)
        power.plugged = true
        let pluggedPowerChange = detector.update(onAC: power.plugged)
        #expect(pluggedPowerChange, "Plugging in at charge limit must trigger a hint")
        for charging in [true, false] {
            power.charging = charging
            let chargingPowerChange = detector.update(onAC: power.plugged)
            #expect(!chargingPowerChange, "Charging-only changes must stay silent")
        }
        power.centerEvent = .power
        #expect(IconContent(power).kind == .plugged && power.powerHintText == "已插入电源，")
        var cableTransition = IconTransition()
        cableTransition.update(IconContent(kind: .wifi, priority: 1), at: 0, reducedMotion: false)
        cableTransition.update(IconContent(power), at: 1, reducedMotion: false)
        #expect(cableTransition.isAnimating(at: 1.1))
        power.centerEvent = nil
        cableTransition.update(IconContent(power), at: 5.2, reducedMotion: false)
        #expect(cableTransition.isAnimating(at: 5.3) && !cableTransition.isAnimating(at: 5.431)
               && cableTransition.target?.kind == .wifi)
        power.plugged = false
        let unpluggedPowerChange = detector.update(onAC: power.plugged)
        #expect(unpluggedPowerChange, "Unplugging at charge limit must trigger a hint")
        power.centerEvent = .power
        #expect(IconContent(power).kind == .unplugged && power.powerHintText == "已拔出电源，")
        let missingPowerChange = detector.update(onAC: nil)
        #expect(!missingPowerChange)
        let restoredPowerChange = detector.update(onAC: true)
        #expect(!restoredPowerChange, "Unknown data must not manufacture a change")
    }

    @Test
    @MainActor
    func testGrowthHoldShrinkAndDeviceResolution() throws {
        var transition = IconTransition()
        transition.update(wifi, at: 0, reducedMotion: false)
        #expect(!transition.isAnimating(at: 0))
        transition.update(wifi, at: 0.1, reducedMotion: true)
        #expect(!transition.isAnimating(at: 0.1), "a preference change alone must not animate a settled icon")
        transition.update(battery, at: 1, reducedMotion: false)
        let outgoing = transition.frame(at: 1.15)
        #expect(outgoing.layers.first?.content == wifi && outgoing.peripheral > 0)
        let large = transition.frame(at: 1.61)
        #expect(large.peripheral == 0 && large.layers.count == 1)
        #expect(large.layers.first?.content == battery && large.layers.first?.emphasis == 1)
        transition.update(IconContent(kind: .battery, text: "81"), at: 2.0, reducedMotion: false)
        #expect(transition.frame(at: 2.01).layers.last?.content.text == "81")
        let holdEnd = transition.frame(at: 4.599)
        #expect(holdEnd.layers.last?.emphasis == 1 && holdEnd.peripheral == 0, "hold full size for three seconds after growth")
        #expect(transition.frame(at: 4.65).peripheral == 0, "delay peripherals by 100ms after shrink starts")
        #expect(transition.frame(at: 4.8).peripheral > 0)
        #expect(transition.frame(at: 5.199).ringProgress == 0, "Ring must wait until the center finishes shrinking")
        let filling = transition.frame(at: 5.45)
        #expect(filling.layers.last?.emphasis == 0 && filling.peripheral == 1)
        #expect(abs(filling.ringProgress - 0.5) < 0.0001, "Ring must reach half its target after 0.25 seconds")
        #expect(transition.isAnimating(at: 5.699), "Keep rendering throughout the 0.5-second ring fill")
        #expect(!transition.isAnimating(at: 5.71), "value updates must not restart timing")
        #expect(transition.frame(at: 5.71).ringProgress == 1 && transition.frame(at: 5.71).ringOpacity == 1)
        transition.update(wifi, at: 6, reducedMotion: false)
        #expect(transition.isAnimating(at: 6.1), "Battery P2 to Wi-Fi P1 must use the center transition")
        transition.update(battery, at: 6.1, reducedMotion: false)
        transition.update(content(.airpods), at: 6.4, reducedMotion: false)
        transition.update(IconContent(kind: .volume, text: "75"), at: 11, reducedMotion: true)
        let reduced = transition.frame(at: 11.08)
        #expect(reduced.reduced && reduced.layers.allSatisfy { $0.emphasis == 0 })
        #expect(!transition.isAnimating(at: 11.231))
        transition.update(wifi, at: 12, reducedMotion: false, active: false)
        #expect(!transition.isAnimating(at: 12))
        #expect(IconContent(Snapshot(battery: 0.82, symbol: "wifi")).kind == .wifi)
        let wiredBattery = IconContent(Snapshot(battery: 0.82, symbol: ""))
        #expect(wiredBattery.sameState(as: battery) && wiredBattery.text == battery.text)
        #expect(IconContent(Snapshot(symbol: "", output: "AirPods")).kind == .battery, "A name alone must not identify an AirPods output")
        #expect(IconContent(Snapshot(symbol: "", output: "AirPods", deviceKind: .bluetooth(.airPodsPro))).kind == .headphones)
        let bluetoothSpeaker = IconContent(Snapshot(symbol: "", output: "JBL Flip 5", deviceKind: .bluetooth(.speaker)))
        #expect(bluetoothSpeaker.kind == .headphones && bluetoothSpeaker.glyph == .symbol("hifispeaker"),
               "A Bluetooth speaker must keep the resident device glyph, with its own symbol")
        let airPlay = IconContent(Snapshot(symbol: "wifi", output: "客厅", deviceKind: .airPlay(.appleTV)))
        #expect(airPlay.kind == .headphones && airPlay.glyph == .symbol("appletv"))
        #expect(IconContent(Snapshot(symbol: "wifi", output: "客厅", deviceKind: .airPlay(.homePod))).glyph == .symbol("homepod"))
        #expect(IconContent(Snapshot(symbol: "wifi", output: "厨房", deviceKind: .airPlay(.homePodMini))).glyph == .symbol("homepod.mini"))
        #expect(IconContent(Snapshot(symbol: "wifi", output: "Sonos", deviceKind: .airPlay(.other))).glyph == .symbol("airplay.audio"))
        #expect(IconContent(Snapshot(symbol: "wifi", output: "MacBook Air扬声器", deviceKind: .builtIn)).glyph == nil,
               "Built-in output must not take over the center")
        #expect(Snapshot(deviceKind: .bluetooth(.speaker)).deviceGlyph == .symbol("hifispeaker"))
        #expect(Snapshot(deviceKind: .airPlay(.other)).deviceGlyph == .symbol("airplay.audio"))
        #expect(Snapshot(deviceKind: .builtIn).deviceGlyph == nil && Snapshot(deviceKind: .other).deviceGlyph == nil,
               "Only Bluetooth and AirPlay expose a center device glyph")
        #expect(Snapshot(deviceKind: .bluetooth(.airPodsPro)).outputIsAirPods && !Snapshot(deviceKind: .bluetooth(.beats)).outputIsAirPods,
               "AirPods-only controls must stay tied to the AirPods family")
        var deviceSwitch = IconTransition()
        deviceSwitch.update(IconContent(Snapshot(symbol: "wifi", deviceKind: .bluetooth(.airPodsPro))), at: 0, reducedMotion: false)
        deviceSwitch.update(IconContent(Snapshot(symbol: "wifi", deviceKind: .bluetooth(.beats))), at: 1, reducedMotion: false)
        #expect(deviceSwitch.isAnimating(at: 1.1), "Switching between two Bluetooth families must crossfade like any same-level change")
    }

    @Test
    @MainActor
    func testVolumeArtwork() throws {
        defer { recordArtifacts() }
        let volumeReview = NSImage(size: NSSize(width: 360, height: 200))
        for (row, dark) in [true, false].enumerated() {
            for (column, value) in [0.0, 0.35, 1.0].enumerated() {
                let snapshot = Snapshot(battery: 0.82, symbol: "wifi", volume: value, centerEvent: .volume)
                let digits = IconContent(snapshot)
                #expect(digits.text == ["0", "35", "100"][column] && digits.glyph == nil)
                volumeReview.lockFocus()
                (dark ? NSColor.darkGray : NSColor.white).setFill()
                NSRect(x: column * 120, y: row * 100, width: 120, height: 100).fill()
                IconRenderer.image(snapshot, animate: false, size: 68, dark: dark)
                    .draw(in: NSRect(x: column * 120 + 26, y: row * 100 + 26, width: 68, height: 68))
                IconRenderer.image(snapshot, animate: false, size: 22, dark: dark)
                    .draw(in: NSRect(x: column * 120 + 49, y: row * 100 + 2, width: 22, height: 22))
                volumeReview.unlockFocus()
            }
        }
        let volumeData = try #require(volumeReview.tiffRepresentation)
        let volumeBitmap = try #require(NSBitmapImageRep(data: volumeData))
        try (try #require(volumeBitmap.representation(using: .png, properties: [:])))
            .write(to: artifact("volume-icon-review.png"))
    }

    @Test
    @MainActor
    func testWiFiGeometrySignalAndPixelReference() throws {
        defer { recordArtifacts() }
        // The menu bar, both settings previews and the panel share the same Wi-Fi proportions.
        var wifiCoverage: [Double] = []
        for size: CGFloat in [22, 68, 112] {
            let frame = IconTransition.Frame(layers: [.init(content: wifi)], peripheral: 0, ringOpacity: 0)
            let image = IconRenderer.image(Snapshot(), animate: false, size: size, transition: frame)
            let imageData = try #require(image.tiffRepresentation)
            let pixels = try #require(NSBitmapImageRep(data: imageData))
            var ink = 0.0
            for y in 0..<pixels.pixelsHigh {
                for x in 0..<pixels.pixelsWide { ink += (try #require(pixels.colorAt(x: x, y: y))).alphaComponent }
            }
            wifiCoverage.append(ink / Double(pixels.pixelsWide * pixels.pixelsHigh))
        }
        #expect((try #require(wifiCoverage.max())) / (try #require(wifiCoverage.min())) < 1.06,
               "Wi-Fi proportions must match across the menu bar and previews")

        // Unknown signal stays dim; each additional level lights triangle, inner arc, then outer arc.
        for level in 0...3 {
            let renderer = ImageRenderer(content: WiFiIcon(level: level).foregroundStyle(.white))
            renderer.scale = 8
            let pixels = NSBitmapImageRep(cgImage: (try #require(renderer.cgImage)))
            for (segment, y) in [55.0, 44.1, 36.0].enumerated() {
                let xPixel = Int((50-WiFiGlyph.bounds.minX) / WiFiGlyph.bounds.width * Double(pixels.pixelsWide))
                let yPixel = Int((y-WiFiGlyph.bounds.minY) / WiFiGlyph.bounds.height * Double(pixels.pixelsHigh))
                let alpha = (try #require(pixels.colorAt(x: xPixel, y: yPixel))).alphaComponent
                #expect(abs(alpha - (level > segment ? 1 : 0.25)) < 0.03,
                       "Signal level \(level) must preserve segment \(segment) brightness")
            }
            if level == 3 {
                func tipWidth(at y: Double) throws -> Double {
                    let row = Int((y-WiFiGlyph.bounds.minY) / WiFiGlyph.bounds.height * Double(pixels.pixelsHigh))
                    return try (0..<pixels.pixelsWide).reduce(0) { $0 + (try #require(pixels.colorAt(x: $1, y: row))).alphaComponent }
                }
                #expect(try tipWidth(at: 53.7) > tipWidth(at: 56.3) * 1.5,
                       "The bottom Wi-Fi segment must taper downward instead of forming a circle")
            }
        }
        let wifiReview = ImageRenderer(content: HStack(spacing: 24) {
            ForEach(0...3, id: \.self) { level in
                VStack(spacing: 12) {
                    WiFiIcon(level: level).scaleEffect(3).frame(width: 60, height: 48)
                    WiFiIcon(level: level).frame(width: 28, height: 28).background(.blue, in: Circle())
                    Text(level == 0 ? "未知" : "\(level) 格").font(.caption)
                }
            }
        }.padding(24).foregroundStyle(.white).background(Color(red: 0.12, green: 0.13, blue: 0.16)))
        wifiReview.scale = 2
        let reviewImage = try #require(wifiReview.cgImage)
        try (try #require(NSBitmapImageRep(cgImage: reviewImage).representation(using: .png, properties: [:])))
            .write(to: artifact("combo-wifi-review.png"))

        // Compare the shared paths at the reference screenshot's native pixel size.
        let referenceURL = try #require(Bundle(for: Self.self).url(forResource: "WiFiReference", withExtension: "png"))
        let reference = try #require(NSBitmapImageRep(data: try Data(contentsOf: referenceURL)))
        let matched = (try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 84, pixelsHigh: 94,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)))
        let drawing = (try #require(NSGraphicsContext(bitmapImageRep: matched))).cgContext
        drawing.translateBy(x: 0.78, y: 107.68); drawing.scaleBy(x: 1, y: -1)
        drawing.setStrokeColor(NSColor.white.cgColor); drawing.setFillColor(NSColor.white.cgColor)
        drawing.setLineWidth(WiFiGlyph.lineWidth); drawing.setLineCap(.round); drawing.setLineJoin(.round)
        for index in 0..<2 {
            for points in WiFiGlyph.arcs(index) {
                drawing.beginPath(); drawing.addLines(between: points); drawing.strokePath()
            }
        }
        drawing.addPath(WiFiGlyph.tip); drawing.fillPath()
        let foreground = (try #require(reference.colorAt(x: 50, y: 22))).redComponent
        var coverageError = 0.0, outlineDifferences = 0
        for y in 18..<46 {
            let background = (try #require(reference.colorAt(x: 0, y: y))).redComponent
            for x in 32..<69 {
                let expected = min(1, max(0, ((try #require(reference.colorAt(x: x, y: y))).redComponent-background)/(foreground-background)))
                let actual = (try #require(matched.colorAt(x: x, y: y))).alphaComponent
                coverageError += abs(expected-actual)
                if (expected > 0.5) != (actual > 0.5) { outlineDifferences += 1 }
            }
        }
        #expect(coverageError / (28*37) < 0.02 && outlineDifferences <= 14,
               "Wi-Fi must match the supplied pixel reference, allowing edge antialiasing")
        try (try #require(matched.representation(using: .png, properties: [:])))
            .write(to: artifact("combo-wifi-reference-render.png"))
    }

    @Test
    @MainActor
    func testRendererFramesAndPeripheralVisibility() throws {
        defer { recordArtifacts() }
        // Sample real renderer frames at both native and enlarged sizes, in both appearances.
        let times = [0.0, 0.15, 0.30, 0.45, 0.60, 3.59, 3.75, 3.95, 4.20, 4.45, 4.70]
        let contents = [battery, IconContent(kind: .battery, text: "100"), wifi, content(.plug), content(.unplug), content(.airpods), IconContent(kind: .battery, text: "9")]
        let sheet = NSImage(size: NSSize(width: times.count * 100, height: contents.count * 100))
        sheet.lockFocus()
        NSColor.darkGray.setFill(); NSRect(origin: .zero, size: sheet.size).fill()
        sheet.unlockFocus()
        for (row, content) in contents.enumerated() {
            var animation = IconTransition()
            animation.update(IconContent(kind: .volume), at: 0, reducedMotion: false)
            animation.update(content, at: 1, reducedMotion: false)
            for (column, time) in times.enumerated() {
                let frame = animation.frame(at: 1 + time)
                for dark in [false, true] {
                    for size: CGFloat in [22, 68, 100, 112] {
                        let image = IconRenderer.image(Snapshot(battery: 0.82, charging: true, volume: 0.5), animate: false, size: size, dark: dark, transition: frame)
                        let imageData = try #require(image.tiffRepresentation)
                        let bitmap = try #require(NSBitmapImageRep(data: imageData))
                        #expect(bitmap.pixelsWide > 0)
                        if size == 22 {
                            var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
                            for y in 0..<bitmap.pixelsHigh {
                                for x in 0..<bitmap.pixelsWide where (try #require(bitmap.colorAt(x: x, y: y))).alphaComponent > 0.05 {
                                    minX = min(minX, x); maxX = max(maxX, x)
                                    minY = min(minY, y); maxY = max(maxY, y)
                                }
                            }
                            if time == 0.60 { #expect(minX <= maxX && minY <= maxY, "The incoming glyph must be visible after growth") }
                            if minX <= maxX {
                                #expect(maxX-minX+1 < bitmap.pixelsWide && maxY-minY+1 < bitmap.pixelsHigh,
                                       "Native-size animation must not span the canvas: \(content), \(time), \(minX),\(minY)–\(maxX),\(maxY) / \(bitmap.pixelsWide)")
                            }
                            if time == 0 {
                                #expect(abs(minX + maxX + 1 - bitmap.pixelsWide) <= 1 &&
                                       abs(minY + maxY + 1 - bitmap.pixelsHigh) <= 1,
                                       "Visible menu-bar artwork must be centered")
                                #expect(Double(maxX-minX+1) / Double(bitmap.pixelsWide) > 0.81,
                                       "Menu-bar artwork must be slightly enlarged")
                            }
                        }
                        if time == 4.45 && size == 100 {
                            let left = (try #require(bitmap.colorAt(x: bitmap.pixelsWide * 12 / 100, y: bitmap.pixelsHigh * 48 / 100)))
                            #expect(left.alphaComponent > 0.4, "Partially drawn ring must retain its full radius")
                        }
                        if time == 0.60 && animation.isAnimating(at: 1 + time) {
                            var peripheralOnly = frame
                            peripheralOnly.layers = []
                            let peripheralImage = IconRenderer.image(Snapshot(battery: 0.82, charging: true, volume: 0.5), animate: false, size: size, dark: dark, transition: peripheralOnly)
                            let peripheralData = try #require(peripheralImage.tiffRepresentation)
                            let pixels = try #require(NSBitmapImageRep(data: peripheralData))
                            for y in 0..<pixels.pixelsHigh {
                                for x in 0..<pixels.pixelsWide { #expect((try #require(pixels.colorAt(x: x, y: y))).alphaComponent < 0.01) }
                            }
                        }
                        if dark && size == 100 {
                            sheet.lockFocus()
                            image.draw(in: NSRect(x: column * 100, y: (contents.count-1-row) * 100, width: 100, height: 100))
                            sheet.unlockFocus()
                        }
                    }
                }
            }
        }
        let sheetData = try #require(sheet.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: sheetData))
        try (try #require(bitmap.representation(using: .png, properties: [:]))).write(to: artifact("icon-transition-review.png"))
    }

    @Test
    @MainActor
    func testPowerArtworkAndNetworkPreview() throws {
        defer { recordArtifacts() }
        let powerReview = NSImage(size: NSSize(width: 360, height: 180))
        var powerPixels: [Data] = []
        for (index, scene) in [Scene.plug, .unplug].enumerated() {
            let frame = IconTransition.Frame(layers: [.init(content: content(scene), emphasis: 1)], peripheral: 0, ringOpacity: 0)
            let icon = IconRenderer.image(.demo(scene), animate: false, size: 100, transition: frame)
            powerPixels.append((try #require(icon.tiffRepresentation)))
            powerReview.lockFocus()
            NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
            NSRect(x: index * 180, y: 0, width: 180, height: 180).fill()
            icon.draw(in: NSRect(x: index * 180 + 40, y: 55, width: 100, height: 100))
            NSAttributedString(string: scene.rawValue, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: index * 180 + 64, y: 20))
            powerReview.unlockFocus()
        }
        #expect(powerPixels[0] != powerPixels[1], "Check and X badges must render differently")
        let powerData = try #require(powerReview.tiffRepresentation)
        let powerBitmap = try #require(NSBitmapImageRep(data: powerData))
        try (try #require(powerBitmap.representation(using: .png, properties: [:])))
            .write(to: artifact("power-icon-review.png"))
        // A shareable preview from the exact menu-bar renderer, with no hardware changes.
        let gif = (try #require(CGImageDestinationCreateWithURL(artifact("network-transition-review.gif") as CFURL,
                                                  "com.compuserve.gif" as CFString, 240, nil)))
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var networkDemo = IconTransition()
        var scene = Scene.wifi
        networkDemo.update(content(scene), at: 0, reducedMotion: false)
        for i in 0..<240 {
            let time = Double(i)/20
            let next: Scene = time < 0.5 ? .wifi : time < 4.5 ? .wifiOff : time < 8 ? .connecting : .wifi
            if next != scene { scene = next; networkDemo.update(content(scene), at: time, reducedMotion: false) }
            let canvas = NSImage(size: NSSize(width: 240, height: 260))
            canvas.lockFocus()
            NSColor(srgbRed: 23/255, green: 24/255, blue: 27/255, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 240, height: 260).fill()
            IconRenderer.image(.demo(scene), animate: false, size: 160, phase: time/1.2,
                               transition: networkDemo.frame(at: time)).draw(in: NSRect(x: 40, y: 65, width: 160, height: 160))
            NSAttributedString(string: scene.rawValue, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
                .draw(at: NSPoint(x: 60, y: 30))
            canvas.unlockFocus()
            let canvasData = try #require(canvas.tiffRepresentation)
            let canvasBitmap = try #require(NSBitmapImageRep(data: canvasData))
            let frame = try #require(canvasBitmap.cgImage)
            CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(gif))
    }

    private var outputDirectory: URL?
    private var wifi: IconContent { IconContent(kind: .wifi, priority: 1) }
    private var battery: IconContent { IconContent(kind: .battery, text: "82") }

    private func content(_ scene: Scene) -> IconContent {
        IconContent(Snapshot.demo(scene).preferringBattery(threshold: 50))
    }

    private func artifact(_ name: String) throws -> URL {
        if outputDirectory == nil {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.IconTests.\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            outputDirectory = directory
        }
        return try #require(outputDirectory).appendingPathComponent(name)
    }

    private func recordArtifacts() {
        guard let directory = outputDirectory else { return }
        defer { try? FileManager.default.removeItem(at: directory); outputDirectory = nil }
        do {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                Attachment.record(try Data(contentsOf: file), named: file.lastPathComponent)
            }
        } catch { Issue.record(error) }
    }
}
