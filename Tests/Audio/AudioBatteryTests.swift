import Testing
import Foundation
import AppKit
import SwiftUI

struct AudioBatteryTests {
    private struct Scene: Decodable {
        struct Item: Decodable {
            let label: String
            let icon: String
            let value: Int?
            let charge: AudioChargeState?
        }
        let id: String
        let name: String
        let family: AudioIconFamily
        let items: [Item]

        var device: AudioBatteryDevice {
            let readings = items.flatMap { item -> [AudioBatteryReading] in
                let charge = item.charge ?? .unknown
                if item.label.contains("双耳"), charge == .charging || charge == .full {
                    return [.init(part: .left, percent: item.value, charge: charge, inCase: true),
                            .init(part: .right, percent: item.value, charge: charge, inCase: true)]
                }
                let part: AudioIconPart = item.label.contains("左") ? .left : item.label.contains("右") ? .right : item.label.contains("盒") ? .chargingCase : .device
                return [.init(part: part, percent: item.value, charge: charge)]
            }
            return .init(target: id, name: name, family: family, readings: readings)
        }
    }

    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try JSONDecoder().decode(type, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    @Test @MainActor
    func testEveryReviewedSymbolAndCategory() throws {
        struct Family: Decodable { let id: AudioIconFamily; let symbols: [String: String] }
        let catalog = try fixture("AudioSymbols.json", as: [Family].self)
        #expect(catalog.count == 25)
        var symbolCount = 0
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        for entry in catalog {
            let family = entry.id
            for (slot, name) in entry.symbols {
                let part = try #require(AudioIconPart(rawValue: slot == "case" ? "chargingCase" : slot))
                let icon = AppIcon.audio(family, part: part)
                #expect(icon.symbolCandidates.first == name, "Keep the approved model and part: \(family), \(slot)")
                #expect(AppIcons.image(icon) != nil)
                #expect(AppIcons.swiftUIImage(icon) != nil)
                symbolCount += 1
            }
        }
        #expect(symbolCount == 76)
        let icons = AppIcon.NetworkIcon.allCases.map(AppIcon.network)
            + AppIcon.PowerIcon.allCases.map(AppIcon.power)
            + AppIcon.DeviceIcon.allCases.map(AppIcon.device)
            + [.sound(.muted), .status(.unavailable)]
        for icon in icons { #expect(AppIcons.image(icon) != nil) }
        for (icon, symbol) in [(AppIcon.audio(.appleTV), "appletv.fill"), (.audio(.homePod), "homepod.fill"),
                               (.audio(.homePodMini), "homepod.mini.fill"), (.audio(.car), "car.fill"),
                               (.status(.unavailable), "minus"), (.device(.audioOutput), "speaker.wave.2.fill")] {
            #expect(icon.symbolCandidates.first == symbol)
        }
        // Having a case icon must never create a battery for a case without one.
        #expect(AppIcons.image(.audio(.beatsSoloBuds, part: .chargingCase)) != nil)
        #expect(!AudioIconFamily.beatsSoloBuds.hasCaseBattery)
        #expect(AppIcon.audio(.airPodsPro3).symbolCandidates.contains("earbuds"))
        for family in AudioIconFamily.allCases where !family.hasCaseBattery && family != .beatsSoloBuds {
            #expect(AppIcons.image(.audio(family, part: .chargingCase)) == nil)
        }
        for part in [AudioIconPart.left, .right] {
            #expect(AppIcon.audio(.hearingDevice, part: part).symbolCandidates.first == "hearingdevice.ear")
            #expect(AppIcon.audio(.headphones, part: part).symbolCandidates.first == "headphones")
        }
    }

    @Test @MainActor
    func testFallbackAndCallerImageIsolation() throws {
        var requested: [String] = []
        let result = AppIcons.resolve(.audio(.airPodsPro3, part: .left)) { name in
            requested.append(name)
            return name == "earbud.left" ? NSImage(systemSymbolName: name, accessibilityDescription: nil) : nil
        }
        #expect(result?.name == "earbud.left" && requested == ["airpods.pro.gen3.left", "earbud.left"])
        #expect(AppIcons.resolve(.network(.warning), load: { _ in nil }) == nil)
        for (family, fallback) in [(AudioIconFamily.appleTV, "display"), (.homePod, "hifispeaker.fill"),
                                    (.homePodMini, "hifispeaker.fill"), (.airPlay, "speaker.wave.2.fill"),
                                    (.car, "speaker.wave.2.fill"), (.speaker, "speaker.wave.2.fill"),
                                    (.beatsPill, "speaker.wave.2.fill"), (.hearingDevice, "ear")] {
            let result = AppIcons.resolve(.audio(family)) { name in
                name == fallback ? NSImage(systemSymbolName: name, accessibilityDescription: nil) : nil
            }
            #expect(result?.name == fallback, "Missing resources must preserve device type: \(family)")
        }
        let first = try #require(AppIcons.image(.audio(.airPodsPro2)))
        let originalSize = first.size
        first.size = NSSize(width: 1, height: 1)
        first.isTemplate = false
        let second = try #require(AppIcons.image(.audio(.airPodsPro2)))
        #expect(first !== second && second.size == originalSize && second.isTemplate)
        #expect(AudioIconFamily.matching(vendorID: 76, productID: 0x2014) == .airPodsPro2)
        #expect(AudioIconFamily.matching(vendorID: 76, productID: 0x2027) == .airPodsPro3)
        #expect(AudioIconFamily.matching(vendorID: 76, productID: 0xffff) == nil)
        #expect(AudioIconFamily.matching(vendorID: 1, productID: 0x2014) == nil)
    }

    @Test
    func testProductIdentityToEveryDeviceAndBatteryIcon() throws {
        struct Product: Decodable { let family: AudioIconFamily; let productIDs: [UInt32] }
        struct Family: Decodable { let id: AudioIconFamily; let symbols: [String: String] }
        let products = try fixture("AudioProductIDs.json", as: [Product].self)
        let catalog = try fixture("AudioSymbols.json", as: [Family].self)
        for product in products {
            let reference = try #require(catalog.first { $0.id == product.family })
            for productID in product.productIDs {
                for vendorID: UInt32 in [76, 1452] {
                    let payload: [String: Any] = ["deviceID": 99, "target": String(repeating: "a", count: 64),
                        "available": true, "modes": [], "canSetMode": false, "canSetConversation": false,
                        "attempted": false, "verified": false, "vendorID": vendorID, "productID": productID,
                        "left": 72, "right": 64, "caseBattery": 35, "single": 88, "classOfDevice": 0x240414]
                    let reply = try JSONDecoder().decode(AirPodsReply.self, from: JSONSerialization.data(withJSONObject: payload))
                    #expect(reply.valid && reply.iconFamily == product.family)
                    let device = reply.batteryDevice(family: .speaker, name: "Renamed unrelated device", previous: nil)
                    #expect(device.family == product.family, "Product identity must beat the name and coarse speaker classification")
                    #expect(OutputDeviceClassifier.glyph(for: .bluetooth(.unknown), family: device.family)
                        .symbolCandidates.first == reference.symbols["device"])
                    for gauge in device.gauges() {
                        let slot = gauge.id == .chargingCase ? "case" : gauge.id.rawValue
                        #expect(gauge.icon.symbolCandidates.first == reference.symbols[slot],
                                "Product \(productID), \(product.family), \(slot) must use the matching model part")
                    }
                    let singleBattery: Set<AudioIconFamily> = [.airPodsMax, .powerbeats, .powerbeats3, .beatsHeadphones, .beatsEarphones, .beatsPill]
                    let expected: [AudioBatteryGauge.ID] = singleBattery.contains(product.family) ? [.device]
                        : product.family == .beatsSoloBuds ? [.left, .right] : [.left, .right, .chargingCase]
                    #expect(device.gauges().map(\.id) == expected)
                    #expect(AudioIconFamily.matching(vendorID: 1, productID: productID) == nil)
                }
            }
        }
    }

    @Test
    func testDesignScenesAndBatteryBoundaries() throws {
        let scenes = try fixture("AudioDeviceScenes.json", as: [Scene].self)
        #expect(scenes.count == 39)
        for scene in scenes {
            let gauges = scene.device.gauges()
            #expect(gauges.map(\.percent) == scene.items.map(\.value), "Scene \(scene.id)")
            #expect(gauges.map(\.charge) == scene.items.map { $0.charge ?? .unknown }, "Scene \(scene.id)")
            #expect(gauges.map { $0.icon.symbolCandidates.first } == scene.items.map { Optional($0.icon) },
                    "Each model and part must use its own approved icon: \(scene.id)")
            #expect(gauges.allSatisfy { !$0.value.contains("%") })
            #expect(scene.device.gauges(stale: true).allSatisfy { $0.percent == nil && $0.charge == .unknown })
        }
        for (percent, level) in [(0, AudioBatteryGauge.Level.low), (20, .low), (21, .warning), (40, .warning), (41, .normal), (100, .normal)] {
            let gauge = AudioBatteryGauge(id: .device, icon: .audio(.headphones), percent: percent, charge: .unknown)
            #expect(gauge.level == level && gauge.value == String(percent))
            #expect(gauge.accessibilityValue.contains("\(percent)%"))
        }
        let unknown = AudioBatteryGauge(id: .left, icon: .audio(.earbuds, part: .left), percent: nil, charge: .unknown)
        #expect(unknown.value == "—" && unknown.level == .unknown)
    }

    @Test
    func testMergeRequiresExplicitEqualChargingAndInCaseSignals() {
        for leftCharge in AudioChargeState.allCases {
            for rightCharge in AudioChargeState.allCases {
                for leftCase: Bool? in [nil, false, true] {
                    for rightCase: Bool? in [nil, false, true] {
                        let device = AudioBatteryDevice(target: "a", name: "Test", family: .airPodsPro2, readings: [
                            .init(part: .left, percent: leftCharge == .full ? 100 : 23, charge: leftCharge, inCase: leftCase),
                            .init(part: .right, percent: rightCharge == .full ? 100 : 52, charge: rightCharge, inCase: rightCase),
                            .init(part: .chargingCase, percent: 17, charge: .idle)
                        ])
                        let merged = leftCase == true && rightCase == true && leftCharge == rightCharge && [.charging, .full].contains(leftCharge)
                        let gauges = device.gauges()
                        #expect(gauges.count == (merged ? 2 : 3))
                        #expect(gauges.first?.id == (merged ? .pair : .left))
                        if merged { #expect(gauges.first?.percent == (leftCharge == .full ? 100 : 23)) }
                        #expect(gauges.last?.charge == .idle)
                    }
                }
            }
        }
        let partial = AudioBatteryDevice(target: "a", name: "Test", family: .airPodsPro2, readings: [
            .init(part: .left, percent: nil, charge: .charging, inCase: true),
            .init(part: .right, percent: 52, charge: .charging, inCase: true)
        ])
        #expect(partial.gauges().map(\.id) == [.left, .right])
    }

    @Test @MainActor
    func testFreshnessRetentionAndMalformedMetadata() async throws {
        var payload: [String: Any] = ["deviceID": 99, "target": String(repeating: "a", count: 64), "available": true,
            "modes": [], "canSetMode": false, "canSetConversation": false, "left": 0, "right": 100,
            "vendorID": 76, "productID": 0x2014, "attempted": false, "verified": false]
        func decode(_ value: [String: Any]) throws -> AirPodsReply {
            try JSONDecoder().decode(AirPodsReply.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let reply = try decode(payload)
        #expect(reply.valid && reply.iconFamily == .airPodsPro2)
        let device = reply.batteryDevice(family: .earbuds, name: "Long device name", previous: nil)
        #expect(device.gauges().map(\.percent) == [0, 100])
        #expect(device.gauges().allSatisfy { $0.charge == .unknown }, "100 must never imply a full-charge lightning")
        for (key, value) in [("vendorID", 65536 as Any), ("leftCharge", "invalid" as Any), ("leftInCase", 1 as Any), ("rightCharge", "full" as Any)] {
            var invalid = payload; invalid[key] = value
            if key == "rightCharge" { invalid["right"] = 99 }
            #expect((try? decode(invalid))?.valid != true)
        }
        payload["left"] = NSNull()
        let missing = try decode(payload).batteryDevice(family: .earbuds, name: "Test", previous: device)
        #expect(missing.gauges().first?.id == .left && missing.gauges().first?.percent == nil)
        var genericPayload = payload
        genericPayload["vendorID"] = NSNull(); genericPayload["productID"] = NSNull()
        let generic = try decode(genericPayload).batteryDevice(family: .headphones, name: "Test", previous: nil)
        genericPayload["right"] = NSNull()
        let unavailable = try decode(genericPayload).batteryDevice(family: .headphones, name: "Test", previous: generic)
        #expect(unavailable.family == .earbuds && unavailable.gauges().map(\.id) == [.left, .right])
        genericPayload["classOfDevice"] = 0x240414
        genericPayload["single"] = 42
        let speaker = try decode(genericPayload).batteryDevice(family: .headphones, name: "Speaker", previous: nil)
        #expect(speaker.family == .speaker && speaker.gauges().map(\.percent) == [42])
        var pro3Payload = payload
        pro3Payload["productID"] = 0x2027
        pro3Payload["left"] = 100
        pro3Payload["caseBattery"] = 17
        let pro3 = try decode(pro3Payload).batteryDevice(family: .earbuds, name: "AirPods Pro 3", previous: nil)
        #expect(pro3.family == .airPodsPro3)
        #expect(pro3.gauges().map { $0.icon.symbolCandidates.first } == ["airpods.pro.gen3.left", "airpods.pro.gen3.right", "airpods.pro.gen3.chargingcase.wireless.fill"])
        #expect(OutputDeviceClassifier.glyph(for: .bluetooth(.airPodsPro), family: pro3.family) == .audio(.airPodsPro3))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.BatteryTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        try ("#!/bin/sh\nprintf '%s' '" + json + "'\n").write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let control = AirPodsControl(helperURL: helper, libraryURL: URL(fileURLWithPath: "/usr/lib/libSystem.B.dylib"))
        defer { control.cancel() }
        control.refresh(deviceID: 99, family: .earbuds, name: "Test")
        for _ in 0..<100 where control.refreshing { try await Task.sleep(for: .milliseconds(10)) }
        let readAt = try #require(control.batteryReadAt)
        #expect(!control.batteryIsStale(at: readAt + 14.99))
        #expect(control.batteryIsStale(at: readAt + 15))
        control.cancel(preservingBattery: true)
        #expect(control.snapshot == nil && control.batteryDevice?.target == reply.target)
        control.cancel()
        #expect(control.batteryDevice == nil && control.batteryReadAt == nil)
    }

    @Test @MainActor
    func testEverySymbolMatchesDesignInkProportions() throws {
        struct Reference: Decodable { let canvas: Double; let bounds: [Double] }
        struct Family: Decodable { let id: AudioIconFamily; let symbols: [String: String] }
        let references = try fixture("AudioSymbolBounds.json", as: [String: Reference].self)
        let catalog = try fixture("AudioSymbols.json", as: [Family].self)
        for entry in catalog {
            let family = entry.id
            for (slot, name) in entry.symbols {
                let part = try #require(AudioIconPart(rawValue: slot == "case" ? "chargingCase" : slot))
                let icon = AppIcon.audio(family, part: part)
                guard AppIcons.resolve(icon)?.name == name else { continue } // Older systems deliberately use the semantic fallback.
                let reference = try #require(references[name])
                for diameter: CGFloat in [44, 64] {
                    let gauge = AudioBatteryGauge(id: .device, icon: icon, percent: 0, charge: .unknown)
                    let renderer = ImageRenderer(content: AudioBatteryGaugeView(gauge: gauge, diameter: diameter, reduceMotion: true)
                        .padding(8).environment(\.colorScheme, .light))
                    renderer.scale = 2
                    let pixels = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                    var bounds = [pixels.pixelsWide, pixels.pixelsHigh, 0, 0]
                    for y in 0..<pixels.pixelsHigh {
                        for x in 0..<pixels.pixelsWide {
                            let color = try #require(pixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                            if color.alphaComponent > 0.05 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.3 {
                                bounds[0] = min(bounds[0], x); bounds[1] = min(bounds[1], y)
                                bounds[2] = max(bounds[2], x + 1); bounds[3] = max(bounds[3], y + 1)
                            }
                        }
                    }
                    for index in 0..<4 {
                        let expected = 8 + diameter * 0.125 + reference.bounds[index] / reference.canvas * diameter * 0.75
                        // Allow three physical pixels for the reference PNG versus native symbol rasterization.
                        #expect(abs(Double(bounds[index]) / 2 - expected) <= 1.5,
                                "Approved ink boundary \(index), \(name), \(diameter)pt: \(bounds)")
                    }
                }
            }
        }
    }

    @Test @MainActor
    func testAllDesignScenesRenderOffscreen() throws {
        let scenes = try fixture("AudioDeviceScenes.json", as: [Scene].self)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo-Audio-visuals")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let swatch = dark ? Color(red: 44 / 255, green: 45 / 255, blue: 48 / 255) : Color(red: 232 / 255, green: 233 / 255, blue: 235 / 255)
            for (index, scene) in scenes.enumerated() {
                for detailed in [false, true] {
                    let view = AudioBatterySummary(device: scene.device, detailed: detailed, reduceMotion: true)
                        .padding(20).frame(width: 352).background(swatch)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    #expect(image.width == 704 && image.height > 80 && image.height < 240)
                    let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(detailed ? "" : "overview-")\(dark ? "dark" : "light")-\(index)-\(scene.id).png"))
                }
            }
            for percent: Int? in [nil, 0, 20, 21, 40, 41, 100] {
                for charge in AudioChargeState.allCases {
                    for showsValue in [false, true] {
                        let gauge = AudioBatteryGauge(id: .left, icon: .audio(.airPodsPro2, part: .left), percent: percent, charge: charge)
                        let renderer = ImageRenderer(content: AudioBatteryGaugeView(gauge: gauge, diameter: 44, reduceMotion: true, showsValue: showsValue)
                            .padding(12).background(swatch).environment(\.colorScheme, dark ? .dark : .light))
                        renderer.scale = 2
                        #expect(renderer.cgImage != nil)
                    }
                }
            }
        }
    }
}
