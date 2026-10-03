import CoreAudio
import Foundation

/// 当前默认输出设备的类别。中央图标与声音面板的输出列表共用这一份分类结果，
/// 避免两处各判一套（见 docs/bluetooth-audio-device-icon-research.md §5 的共用分类契约）。
enum OutputDeviceKind: Equatable {
    case bluetooth(BluetoothFamily)
    case airPlay(AirPlayFamily)
    case builtIn
    case display
    case other

    /// 只有蓝牙与 AirPlay 参与中央图标；其余 transport 保持现状，不显示设备符号。
    var showsDeviceGlyph: Bool {
        switch self {
        case .bluetooth, .airPlay: return true
        case .builtIn, .display, .other: return false
        }
    }

    var isBluetooth: Bool {
        if case .bluetooth = self { return true }
        return false
    }

    /// 耳机专属控制（聆听模式、电量）目前只对 AirPods 家族开放。
    var isAirPods: Bool {
        switch self {
        case .bluetooth(.airPodsPro), .bluetooth(.airPods), .bluetooth(.airPodsMax): return true
        case .bluetooth, .airPlay, .builtIn, .display, .other: return false
        }
    }
}

/// 蓝牙设备家族。新增厂商或型号：加一档 + 在 `glyph(for:)` 里给一行映射。
enum BluetoothFamily: CaseIterable {
    case airPodsPro, airPods, airPodsMax, beats, headphones, earbuds, speaker, car, hearingAid, unknown
}

/// AirPlay 路由的机型档位。信号来自 `AVOutputDevice.modelID`（如 `AppleTV14,1`），
/// 由 helper 通过 AVRouting SPI 读出，见 docs/airplay-homepod-api-evidence.md §3.1。
///
/// 机型表来源：libirecovery 的 `irecv_devices[]`（LGPL，维护到 2026 代设备）。HomePod 全部
/// ID 为 `AudioAccessory1,1` / `1,2`（1 代）、`5,1`（mini）、`6,1`（2 代），表中没有更新的
/// HomePod ID。该表**未在本机实测**，所以只分“全尺寸 / mini”：任何未知的
/// `AudioAccessory*`（含未来新机型）都按全尺寸 HomePod 处理，家族级不会退化。
enum AirPlayFamily: Equatable {
    /// `AppleTV*`（实测 `AppleTV14,1` = Apple TV 4K 3 代）。
    case appleTV
    /// `AudioAccessory*` 且非 mini，含未来新机型。
    case homePod
    /// `AudioAccessory5,*`（HomePod mini）。
    case homePodMini
    /// 第三方或未识别：统一 `airplay.audio`，不猜。
    case other

    /// 面板上显示的产品名（产品名不翻译）。
    var label: String? {
        switch self {
        case .appleTV: return "Apple TV"
        case .homePod: return "HomePod"
        case .homePodMini: return "HomePod mini"
        case .other: return nil
        }
    }

    static func matching(model: String?) -> AirPlayFamily {
        guard let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else { return .other }
        let value = model.lowercased()
        if value.hasPrefix("appletv") { return .appleTV }
        if value.hasPrefix("audioaccessory5") { return .homePodMini }
        if value.hasPrefix("audioaccessory") { return .homePod }
        return .other
    }
}

/// 已探测到的 AirPlay 路由：名称、机型与设备音量可控性。
/// 结果只属于"被探测过的那台设备"，中央与输出列表都通过 `info(for:)` 查同一份数据，
/// 因此不会出现"列表显示通用 AirPlay、中央已是 Apple TV"这种不一致。
struct AirPlayRoute: Equatable {
    /// 一次探测的结果。
    struct Info: Equatable {
        /// 房间/设备名（如 `客厅`）。CoreAudio 对 AirPlay 只给通用名 `AirPlay`，所以要用这个。
        var name: String = ""
        /// `AVOutputDevice.modelID`（如 `AppleTV14,1`）。
        var model: String = ""
        /// 接收端**设备自身**音量是否可调（Apple TV 实测为 false：音量由电视遥控）。
        var canSetVolume: Bool?

        var endpointID: String = ""

        var displayName: String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// 归一化后的机型标识；空串视为没有。
        var modelIdentifier: String? {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var family: AirPlayFamily { AirPlayFamily.matching(model: modelIdentifier) }
    }

    struct Request: Equatable {
        let deviceID: AudioDeviceID
        let target: String
        let serial = UUID()
    }

    private(set) var request: Request?
    var deviceID: AudioDeviceID { request?.deviceID ?? 0 }
    private(set) var info: Info?
    var hasProbed: Bool { deviceID != 0 }

    /// 开始探测：先占位（信息未知），避免同一台设备重复起 helper。
    @discardableResult mutating func begin(deviceID: AudioDeviceID, target: String) -> Request {
        let request = Request(deviceID: deviceID, target: target)
        self.request = request
        info = nil
        return request
    }

    /// 探测结果回填；`nil` 表示没拿到（名称与机型都退回 CoreAudio 与统一符号）。
    mutating func record(_ value: Info?, for request: Request) {
        guard request == self.request else { return }
        info = value
    }

    mutating func clear() { request = nil; info = nil }

    /// 只有被探测过的那台设备能拿到结果。
    func info(for deviceID: AudioDeviceID) -> Info? { deviceID == self.deviceID ? info : nil }
    func name(for deviceID: AudioDeviceID) -> String? { info(for: deviceID)?.displayName }
    func model(for deviceID: AudioDeviceID) -> String? { info(for: deviceID)?.modelIdentifier }
}

/// 字形来源。SF Symbol 是当前唯一在用的来源；第三方厂商的 SVG 日后放进
/// `Combo/App/Media.xcassets`，这里用 `.asset("名字")` 引用，两条绘制路径都已支持。
enum DeviceGlyph: Equatable {
    case symbol(String)
    case asset(String)

    /// 解析失败时的统一下限：中央与面板都退到这里，绝不留空白。
    static let fallback = DeviceGlyph.symbol("headphones")

    var symbolName: String? {
        if case .symbol(let name) = self { return name }
        return nil
    }
}

/// 分类所需信号。CoD 在获蓝牙授权后由现有 helper 读取；为零或缺失时忽略。
struct OutputSignals: Equatable {
    var transport: UInt32 = 0
    var name: String = ""
    /// AirPlay 路由的机型（`AVOutputDevice.modelID`），由 helper 读出后填入；
    /// 拿不到就保持 nil → 统一符号。
    var model: String? = nil
    var classOfDevice: UInt32? = nil
}

/// 纯分类器：无状态、无 IO，便于单测。
enum OutputDeviceClassifier {
    /// 入口规则写死为“只以默认输出设备的 transport 为入口”。蓝牙配对表不能当入口，
    /// 因为 Apple TV / HomePod 也会出现在蓝牙配对表里。
    static func classify(_ signals: OutputSignals) -> OutputDeviceKind {
        switch signals.transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth(family(signals))
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay(AirPlayFamily.matching(model: signals.model))
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return .display
        default:
            return .other
        }
    }

    /// 品牌名保留型号族；可用的类别信号优先于通用名称关键字，最后兜底 unknown。
    private static func family(_ signals: OutputSignals) -> BluetoothFamily {
        let named = BluetoothFamily.matching(name: signals.name)
        if let named, [.airPodsPro, .airPods, .airPodsMax, .beats].contains(named) { return named }
        if let code = signals.classOfDevice, code != 0, let coded = BluetoothFamily.matching(classOfDevice: code) { return coded }
        return named ?? .unknown
    }

    /// 所有类别都有字形（含输出列表要显示的内置扬声器、显示器）。
    static func glyph(for kind: OutputDeviceKind) -> DeviceGlyph {
        switch kind {
        case .builtIn: return .symbol("laptopcomputer")
        case .display: return .symbol("display")
        case .other: return .symbol("speaker.wave.2")
        case .airPlay(let family):
            switch family {
            case .appleTV: return .symbol("appletv")
            case .homePod: return .symbol("homepod")
            case .homePodMini: return .symbol("homepod.mini")
            case .other: return .symbol("airplay.audio")
            }
        case .bluetooth(let family):
            switch family {
            case .airPodsPro: return .symbol("airpods.pro")
            case .airPods: return .symbol("airpods")
            case .airPodsMax: return .symbol("airpods.max")
            case .beats: return .symbol("beats.headphones")
            case .headphones, .unknown: return .symbol("headphones")
            case .earbuds: return .symbol("earbuds")
            case .speaker: return .symbol("hifispeaker")
            case .car: return .symbol("car")
            case .hearingAid: return .symbol("hearingdevice.ear")
            }
        }
    }
}

extension BluetoothFamily {
    /// 名称关键字。设备可改名，所以这只是“最可能”的判断，命中失败就走 unknown。
    /// 按键匹配而不是子串匹配：`Carl's Headphones` 不是车机，`Rosebuds` 不是真无线。
    static func matching(name: String) -> BluetoothFamily? {
        let value = name.lowercased()
        let words = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        // 允许 “Buds2 / Buds3” 这类带代数后缀的写法，但不匹配 “Rosebuds”。
        func word(_ base: String) -> Bool {
            words.contains { $0 == base || ($0.hasPrefix(base) && $0.dropFirst(base.count).allSatisfy(\.isNumber)) }
        }
        if value.contains("airpods max") { return .airPodsMax }
        if value.contains("airpods pro") { return .airPodsPro }
        if value.contains("airpods") { return .airPods }
        if value.contains("beats") { return .beats }
        if word("buds") || word("earbuds") || value.contains("freebuds") { return .earbuds }
        if word("speaker") || word("soundlink") || word("soundbar") { return .speaker }
        if word("car") || value.contains("车载") { return .car }
        if word("headphone") || word("headphones") || value.contains("wh-") || value.contains("qc-") { return .headphones }
        return nil
    }

    /// Class of Device 是 24 位：major 在 bit 8–12（5 位），minor 在 bit 2–7（6 位）。
    /// 表中那些 minor 值只在 major == 0x04（Audio/Video）时有意义。
    static func matching(classOfDevice: UInt32) -> BluetoothFamily? {
        let major = (classOfDevice >> 8) & 0x1F
        let minor = (classOfDevice >> 2) & 0x3F
        switch major {
        case 0x09:
            return .hearingAid
        case 0x04:
            switch minor {
            case 0x01, 0x02, 0x06: return .headphones
            case 0x05, 0x0a: return .speaker
            case 0x08: return .car
            default: return nil
            }
        default:
            return nil
        }
    }
}
