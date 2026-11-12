import Foundation

enum AudioChargeState: String, Codable, CaseIterable {
    case unknown, idle, charging, full
}

struct AudioBatteryReading: Equatable {
    let part: AudioIconPart
    var percent: Int?
    var charge: AudioChargeState = .unknown
    var inCase: Bool?
}

struct AudioBatteryGauge: Equatable, Identifiable {
    enum ID: String { case device, left, right, pair, chargingCase }
    let id: ID
    let icon: AppIcon
    let percent: Int?
    let charge: AudioChargeState

    var title: String {
        switch id {
        case .device: L("设备")
        case .left: L("左耳")
        case .right: L("右耳")
        case .pair: L("双耳")
        case .chargingCase: L("充电盒")
        }
    }
    var value: String { percent.map(String.init) ?? "—" }
    var accessibilityValue: String {
        let battery = percent.map { "\($0)%" } ?? L("电量暂不可用")
        switch charge {
        case .charging: return battery + L("，正在充电")
        case .full: return battery + L("，已充满")
        case .unknown, .idle: return battery
        }
    }
    var level: Level {
        guard let percent else { return .unknown }
        if percent <= 20 { return .low }
        return percent <= 40 ? .warning : .normal
    }
    enum Level { case unknown, low, warning, normal }
}

struct AudioBatteryDevice: Equatable {
    let target: String
    let name: String
    let family: AudioIconFamily
    var readings: [AudioBatteryReading]

    func gauges(stale: Bool = false) -> [AudioBatteryGauge] {
        let values = readings.map { reading in
            stale ? AudioBatteryReading(part: reading.part, percent: nil) : reading
        }
        let left = values.first { $0.part == .left }
        let right = values.first { $0.part == .right }
        var gauges: [AudioBatteryGauge] = []
        if let left, let right, let leftValue = left.percent, let rightValue = right.percent,
           left.inCase == true, right.inCase == true, left.charge == right.charge,
           left.charge == .charging || left.charge == .full {
            gauges.append(.init(id: .pair, icon: .audio(family), percent: min(leftValue, rightValue), charge: left.charge))
        } else {
            for (id, reading) in [(AudioBatteryGauge.ID.left, left), (.right, right)] {
                if let reading {
                    gauges.append(.init(id: id, icon: .audio(family, part: reading.part), percent: reading.percent, charge: reading.charge))
                }
            }
        }
        if gauges.isEmpty, let single = values.first(where: { $0.part == .device }) {
            gauges.append(.init(id: .device, icon: .audio(family), percent: single.percent, charge: single.charge))
        }
        if family.hasCaseBattery, let chargingCase = values.first(where: { $0.part == .chargingCase }) {
            gauges.append(.init(id: .chargingCase, icon: .audio(family, part: .chargingCase), percent: chargingCase.percent, charge: chargingCase.charge))
        }
        return gauges
    }
}

extension AudioIconFamily {
    // Product IDs and icon families use macOS CoreTypes, AirBattery and MagicPodsCore; see audio.md.
    // Unknown IDs stay generic; device names never select a generation.
    static func matching(vendorID: UInt32?, productID: UInt32?) -> AudioIconFamily? {
        guard vendorID == 76 || vendorID == 1452 else { return nil }
        switch productID {
        case 0x2002, 0x200f: return .airPods
        case 0x2013: return .airPods3
        case 0x200e: return .airPodsPro1
        case 0x2014, 0x2024: return .airPodsPro2
        // 0x2027 confirmed on hardware; 0x2028 is its alternate ID in macOS SFHeadphoneProduct.
        case 0x2027, 0x2028: return .airPodsPro3
        case 0x200a, 0x201f, 0x202d: return .airPodsMax
        // CoreTypes groups all five IDs under AirPods 4; the icon does not distinguish ANC.
        case 0x2019, 0x201b, 0x201c, 0x201e, 0x2020: return .airPods4
        case 0x2003: return .powerbeats3
        case 0x200d: return .powerbeats
        case 0x200b: return .powerbeatsPro
        case 0x201d: return .powerbeatsPro2
        case 0x2011: return .beatsStudioBuds
        case 0x2012, 0x202f: return .beatsFitPro
        case 0x2016: return .beatsStudioBudsPlus
        case 0x2026: return .beatsSoloBuds
        case 0x201a: return .beatsPill
        case 0x2010, 0x2005: return .beatsEarphones
        case 0x200c, 0x2006, 0x2009, 0x2017, 0x2025, 0x2038: return .beatsHeadphones
        default: return nil
        }
    }
}

extension OutputDeviceKind {
    var batteryIconFamily: AudioIconFamily {
        guard case .bluetooth(let family) = self else { return .headphones }
        switch family {
        case .airPods, .airPodsPro, .earbuds: return .earbuds
        case .airPodsMax: return .airPodsMax
        case .speaker: return .speaker
        case .hearingAid: return .hearingDevice
        case .car: return .car
        case .beats, .headphones, .unknown: return .headphones
        }
    }
}
