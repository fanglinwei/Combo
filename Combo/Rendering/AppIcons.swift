import AppKit
import SwiftUI

// Callers choose a category and meaning; only this library knows SF Symbol names.
enum AppIcon: Hashable {
    case audio(AudioIconFamily, part: AudioIconPart = .device)
    case network(NetworkIcon)
    case power(PowerIcon)
    case device(DeviceIcon)
    case sound(SoundIcon)
    case status(StatusIcon)

    enum SoundIcon: CaseIterable { case muted }
    enum StatusIcon: CaseIterable { case unavailable }
    enum NetworkIcon: CaseIterable { case wifi, off, warning }
    enum PowerIcon: CaseIterable { case plug, connected, disconnected, charging }
    enum DeviceIcon: CaseIterable { case computer, display, audioOutput }
}

enum AudioIconPart: String, Codable, CaseIterable { case device, left, right, chargingCase }

enum AudioIconFamily: String, Codable, CaseIterable {
    case airPods
    case airPods3
    case airPods4
    case airPodsPro1
    case airPodsPro2
    case airPodsPro3
    case airPodsMax
    case powerbeatsPro
    case powerbeatsPro2
    case beatsFitPro
    case beatsStudioBuds
    case beatsStudioBudsPlus
    case beatsSoloBuds
    case beatsHeadphones
    case beatsEarphones
    case powerbeats
    case powerbeats3
    case beatsPill
    case headphones
    case earbuds
    case inEar
    case stemless
    case boneConduction
    case hearingDevice
    case speaker
    case airPlay, appleTV, homePod, homePodMini, car

    var hasCaseBattery: Bool {
        switch self {
        case .airPods, .airPods3, .airPods4, .airPodsPro1, .airPodsPro2, .airPodsPro3,
             .powerbeatsPro, .powerbeatsPro2, .beatsFitPro, .beatsStudioBuds, .beatsStudioBudsPlus,
             .earbuds, .inEar, .stemless: true
        default: false
        }
    }

    var isSingleBattery: Bool {
        switch self {
        case .airPodsMax, .beatsHeadphones, .beatsEarphones, .powerbeats, .powerbeats3,
             .beatsPill, .headphones, .boneConduction, .speaker: true
        default: false
        }
    }

    fileprivate var symbols: [AudioIconPart: String] {
        switch self {
        case .airPods: [.device: "airpods", .left: "airpod.left", .right: "airpod.right", .chargingCase: "airpods.chargingcase.fill"]
        case .airPods3: [.device: "airpods.gen3", .left: "airpod.gen3.left", .right: "airpod.gen3.right", .chargingCase: "airpods.gen3.chargingcase.wireless.fill"]
        case .airPods4: [.device: "airpods.gen4", .left: "airpods.gen4.left", .right: "airpods.gen4.right", .chargingCase: "airpods.gen4.chargingcase.wireless.fill"]
        case .airPodsPro1: [.device: "airpods.pro.gen1", .left: "airpods.pro.gen1.left", .right: "airpods.pro.gen1.right", .chargingCase: "airpods.pro.gen1.chargingcase.wireless.fill"]
        case .airPodsPro2: [.device: "airpods.pro", .left: "airpods.pro.left", .right: "airpods.pro.right", .chargingCase: "airpods.pro.chargingcase.wireless.fill"]
        case .airPodsPro3: [.device: "airpods.pro.gen3", .left: "airpods.pro.gen3.left", .right: "airpods.pro.gen3.right", .chargingCase: "airpods.pro.gen3.chargingcase.wireless.fill"]
        case .airPodsMax: [.device: "airpods.max"]
        case .powerbeatsPro: [.device: "beats.powerbeats.pro", .left: "beats.powerbeats.pro.left", .right: "beats.powerbeats.pro.right", .chargingCase: "beats.powerbeats.pro.chargingcase.fill"]
        case .powerbeatsPro2: [.device: "beats.powerbeats.pro.2", .left: "beats.powerbeats.pro.2.left", .right: "beats.powerbeats.pro.2.right", .chargingCase: "beats.powerbeats.pro.2.chargingcase.fill"]
        case .beatsFitPro: [.device: "beats.fitpro", .left: "beats.fitpro.left", .right: "beats.fitpro.right", .chargingCase: "beats.fitpro.chargingcase.fill"]
        case .beatsStudioBuds: [.device: "beats.studiobuds", .left: "beats.studiobuds.left", .right: "beats.studiobuds.right", .chargingCase: "beats.studiobuds.chargingcase.fill"]
        case .beatsStudioBudsPlus: [.device: "beats.studiobuds.plus", .left: "beats.studiobuds.plus.left", .right: "beats.studiobuds.plus.right", .chargingCase: "beats.studiobuds.plus.chargingcase.fill"]
        case .beatsSoloBuds: [.device: "beats.solobuds", .left: "beats.solobuds.left", .right: "beats.solobuds.right", .chargingCase: "beats.solobuds.chargingcase.fill"]
        case .beatsHeadphones: [.device: "beats.headphones"]
        case .beatsEarphones: [.device: "beats.earphones"]
        case .powerbeats: [.device: "beats.powerbeats", .left: "beats.powerbeats.left", .right: "beats.powerbeats.right"]
        case .powerbeats3: [.device: "beats.powerbeats3", .left: "beats.powerbeats3.left", .right: "beats.powerbeats3.right"]
        case .beatsPill: [.device: "beats.pill.fill"]
        case .headphones: [.device: "headphones"]
        case .earbuds: [.device: "earbuds", .left: "earbud.left", .right: "earbud.right", .chargingCase: "earbuds.case.fill"]
        case .inEar: [.device: "earbuds.in.ear", .left: "earbuds.in.ear.left", .right: "earbuds.in.ear.right", .chargingCase: "earbuds.case.fill"]
        case .stemless: [.device: "earbuds.stemless", .left: "earbuds.stemless.left", .right: "earbuds.stemless.right", .chargingCase: "earbuds.case.fill"]
        case .boneConduction: [.device: "earbuds.bone.conduction", .left: "earbuds.bone.conduction.left", .right: "earbuds.bone.conduction.right"]
        case .hearingDevice: [.device: "hearingdevice.ear"]
        case .speaker: [.device: "hifispeaker.fill"]
        case .airPlay: [.device: "airplay.audio"]
        case .appleTV: [.device: "appletv.fill"]
        case .homePod: [.device: "homepod.fill"]
        case .homePodMini: [.device: "homepod.mini.fill"]
        case .car: [.device: "car.fill"]
        }
    }
}

extension AppIcon {
    var symbolCandidates: [String] {
        switch self {
        case let .audio(family, part):
            guard let specific = family.symbols[part] else {
                // Unsupported sides keep their device type; unsupported cases never fabricate a case icon.
                return part == .chargingCase ? [] : AppIcon.audio(family).symbolCandidates
            }
            if part == .device {
                switch family {
                case .appleTV: return [specific, "appletv", "display"]
                case .homePod: return [specific, "homepod", "hifispeaker.fill"]
                case .homePodMini: return [specific, "homepod.mini", "homepod", "hifispeaker.fill"]
                case .airPlay: return [specific, "speaker.wave.2.fill"]
                case .car: return [specific, "car", "speaker.wave.2.fill"]
                case .hearingDevice: return [specific, "ear"]
                case .speaker, .beatsPill: return [specific, "hifispeaker.fill", "speaker.wave.2.fill"]
                default: break
                }
            }
            let generic: String
            switch part {
            case .chargingCase: generic = "earbuds.case.fill"
            case .left: generic = "earbud.left"
            case .right: generic = "earbud.right"
            case .device:
                generic = family.symbols[.left] != nil ? "earbuds" : "headphones"
            }
            return [specific, generic, part == .chargingCase ? "shippingbox.fill" : "headphones"]
        case .network(let icon):
            switch icon {
            case .wifi: return ["wifi"]
            case .off: return ["wifi.slash", "wifi"]
            case .warning: return ["wifi.exclamationmark", "exclamationmark.triangle"]
            }
        case .power(let icon):
            switch icon {
            case .plug: return ["powerplug.portrait.fill", "powerplug"]
            case .connected: return ["checkmark.circle", "checkmark"]
            case .disconnected: return ["xmark.circle", "xmark"]
            case .charging: return ["bolt.fill"]
            }
        case .sound(.muted): return ["speaker.slash.fill", "speaker.slash"]
        case .status(.unavailable): return ["minus"]
        case .device(let icon):
            switch icon {
            case .computer: return ["laptopcomputer", "desktopcomputer"]
            case .display: return ["display"]
            case .audioOutput: return ["speaker.wave.2.fill", "speaker.wave.2"]
            }
        }
    }
}

@MainActor enum AppIcons {
    // Cache neutral originals only. Every caller receives its own configured image.
    private static var originals: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func swiftUIImage(_ icon: AppIcon) -> Image? {
        resolve(icon).map { Image(systemName: $0.name) }
    }

    static func image(_ icon: AppIcon, pointSize: CGFloat = 64, weight: NSFont.Weight = .medium, color: NSColor? = nil) -> NSImage? {
        guard let resolved = resolve(icon) else { return nil }
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if let color { configuration = configuration.applying(.init(paletteColors: [color])) }
        let configured = resolved.image.withSymbolConfiguration(configuration) ?? resolved.image
        guard let image = configured.copy() as? NSImage else { return nil }
        image.isTemplate = color == nil
        return image
    }

    static func resolve(_ icon: AppIcon) -> (name: String, image: NSImage)? {
        resolve(icon, load: original)
    }

    // The injected loader also tests missing resources without requiring an older OS.
    static func resolve(_ icon: AppIcon, load: (String) -> NSImage?) -> (name: String, image: NSImage)? {
        for name in icon.symbolCandidates {
            if let image = load(name) { return (name, image) }
        }
        return nil
    }

    private static func original(_ name: String) -> NSImage? {
        if let image = originals[name] { return image }
        if missing.contains(name) { return nil }
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            originals[name] = image
            return image
        }
        missing.insert(name)
        return nil
    }
}
