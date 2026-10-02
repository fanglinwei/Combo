import Foundation

enum PowerSource: String, CaseIterable {
    case battery = "Battery Power", adapter = "AC Power"
    var flag: String { self == .battery ? "-b" : "-c" }
    var title: String { self == .battery ? L("使用电池") : L("连接电源") }
}
enum PowerMode: Int, CaseIterable, Identifiable {
    case automatic = 0, low = 1, high = 2
    var id: Int { rawValue }
    var title: String { [L("自动"), L("低电量"), L("高能耗")][rawValue] }
}
struct PowerModePolicy: Equatable {
    let mode: PowerMode
    let supportsHigh: Bool
    func command(source: PowerSource, mode: PowerMode) -> String? {
        guard supportsHigh || mode != .high else { return nil }
        return "/usr/bin/pmset \(source.flag) \(supportsHigh ? "powermode" : "lowpowermode") \(mode.rawValue)"
    }
}
// Reject incomplete/ambiguous settings instead of guessing a writable policy.
func parsePowerModes(_ text: String) -> [PowerSource: PowerModePolicy] {
    var result: [PowerSource: PowerModePolicy] = [:]
    var source: PowerSource?
    var invalid: Set<PowerSource> = []
    for line in text.components(separatedBy: .newlines) {
        let value = line.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix(":") {
            source = PowerSource(rawValue: String(value.dropLast()))
            continue
        }
        guard let source else { continue }
        let parts = value.split(whereSeparator: { $0.isWhitespace })
        guard let key = parts.first, ["powermode", "lowpowermode", "highpowermode"].contains(key) else { continue }
        guard result[source] == nil, parts.count == 2, key != "highpowermode",
              let number = Int(parts[1]), let mode = PowerMode(rawValue: number),
              key == "powermode" || mode != .high else { invalid.insert(source); continue }
        result[source] = PowerModePolicy(mode: mode, supportsHigh: key == "powermode")
    }
    for source in invalid { result.removeValue(forKey: source) }
    return result
}

enum Bottom { case muted, volume, playing }
func volumeDots(_ value: Double?) -> Int? {
    guard let value, value.isFinite, (0...1).contains(value) else { return nil }
    return Int(ceil(value * 4))
}
func bottomState(muted: Bool, adjusting: Bool, playing: Bool, animate: Bool) -> Bottom {
    if muted { return .muted }
    if adjusting { return .volume }
    return playing && animate ? .playing : .volume
}
// Scrolling up (fingers up on a trackpad, wheel away from the user) raises the volume. Trackpads report points, wheels report lines.
func scrollVolume(current: Double, scrollingDelta: Double, precise: Bool, inverted: Bool) -> Double {
    guard current.isFinite, scrollingDelta.isFinite else { return current }
    let step = (inverted ? -scrollingDelta : scrollingDelta) * (precise ? 1.0 / 300.0 : 0.05)
    return min(1, max(0, current + step))
}
enum Scene: String, CaseIterable, Identifiable {
    var title: String { LKey(rawValue) }
    case live = "本机状态", wifi = "无线正常", wired = "有线 · 默认", music = "媒体播放", adjusting = "调整音量", paused = "暂停 / 未播放", mute = "系统静音", low = "低电量", charging = "充电 + 播放", offline = "网络异常", reduced = "减少动态效果"
    var id: String { rawValue }
    var event: CenterEvent? {
        switch self {
        case .adjusting: .volume
        case .plug, .unplug: .power
        default: nil
        }
    }
    case airpods = "AirPods 播放", connecting = "Wi-Fi 正在连接", wifiMute = "Wi-Fi · 静音"
    case plug = "插入电源", unplug = "拔出电源"
    case wifiOff = "Wi-Fi 已关闭"
}
enum CenterEvent { case power, volume }

// One active event: replaced events never return. All times use a monotonic clock.
struct CenterHint {
    private(set) var event: CenterEvent?
    private(set) var serial = 0
    private(set) var started = 0.0
    private(set) var deadline = 0.0
    func active(at now: Double) -> CenterEvent? { now < deadline ? event : nil }
    mutating func show(_ event: CenterEvent, at now: Double, duration: Double, entrance: Double) {
        if event != .volume || active(at: now) != .volume {
            serial += 1
            started = now
        }
        self.event = event
        deadline = max(now + duration, started + entrance)
    }
    mutating func clear() { event = nil; deadline = 0 }
}
struct Snapshot {
    var battery: Double? = nil
    var charging = false
    var plugged = false
    var network = "正在读取"
    var symbol = "minus"
    var volume: Double? = nil
    var muted = false
    var silenced: Bool { muted || volume == 0 }
    var output: LocalizedText = "正在读取"
    var outputIsAirPods = false
    var playing = false
    var adjusting = false
    var reducedMotion = false
    var centerEvent: CenterEvent? = nil
    var eventSerial = 0
    var wifiConnecting = false
    var batteryPreferred = false
    var networkSymbol: String? = nil
    func preferringBattery(threshold: Int) -> Snapshot {
        guard symbol == "wifi" || symbol.isEmpty, let battery, battery.isFinite, (0...1).contains(battery),
              charging || battery < Double(threshold) / 100 else { return self }
        var result = self
        result.networkSymbol = symbol
        result.symbol = ""
        result.batteryPreferred = true
        return result
    }
    static func demo(_ scene: Scene) -> Snapshot {
        var s = Snapshot(battery: 0.82, network: "有线网络", symbol: "", volume: 0.5, output: "MacBook 扬声器")
        if scene == .wifi { s.network = "Wi-Fi"; s.symbol = "wifi" }
        if [.music, .adjusting, .charging, .reduced].contains(scene) { s.playing = true }
        if scene == .adjusting { s.adjusting = true; s.volume = 0.75 }
        if scene == .mute { s.muted = true }
        if scene == .charging { s.charging = true; s.plugged = true }
        if scene == .low { s.battery = 0.12 }
        if scene == .offline { s.network = "无可用路径"; s.symbol = "exclamationmark" }
        if scene == .wifiOff { s.network = "Wi-Fi 已关闭"; s.symbol = "wifi.slash" }
        if scene == .reduced { s.reducedMotion = true }
        if [.airpods, .adjusting, .connecting, .wifiMute, .plug, .unplug].contains(scene) {
            s.network = "Wi-Fi"; s.symbol = "wifi"
        }
        if [.airpods, .adjusting].contains(scene) {
            s.output = "AirPods Pro（示例）"
            s.outputIsAirPods = true
        }
        if scene == .airpods { s.playing = true }
        if scene == .connecting { s.wifiConnecting = true; s.network = "Wi-Fi 正在连接" }
        if scene == .wifiMute { s.muted = true }
        if scene == .plug { s.plugged = true; s.charging = true }
        s.centerEvent = scene.event
        return s
    }
    var batteryText: String { battery.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var volumeText: String { volume.map { "\(Int(($0 * 100).rounded()))%" } ?? L("由设备控制") }
    var powerHintText: String { centerEvent == .power ? (plugged ? L("已插入电源，") : L("已拔出电源，")) : "" }
}

struct PowerChange {
    private var previousOnAC: Bool?
    mutating func update(onAC: Bool?) -> Bool {
        defer { previousOnAC = onAC }
        // Charge limits and full batteries can stop charging while the cable remains connected.
        return onAC != nil && previousOnAC != nil && onAC != previousOnAC
    }
}

func resolveTransport(pathAvailable: Bool?, interfaces: [String]) -> String {
    guard let available = pathAvailable else { return "pending" }
    guard available else { return "offline" }
    let kinds = Set(interfaces)
    guard kinds.count == 1, let type = kinds.first, ["wifi", "ethernet"].contains(type) else { return "unknown" }
    return type
}
func volumeHintActive(changedAt: TimeInterval?, now: TimeInterval) -> Bool {
    guard let changedAt else { return false }
    return now >= changedAt && now - changedAt < 2
}

func menuBarRestoreKeys(original: [String: Bool], current: [String: Bool], keys: Set<String>) -> [String]? {
    guard Set(original.keys) == keys, keys.isSubset(of: Set(current.keys)) else { return nil }
    return keys.sorted().filter { original[$0] != current[$0] }
}

enum ChargeLimit: Equatable {
    case loading, unknown, none, value(Int), conflicting
    var text: String {
        switch self {
        case .loading: L("读取中")
        case .unknown: L("无法判断")
        case .none: L("未检测到活动上限")
        case .value(let value): "\(value)%"
        case .conflicting: L("多个限制，无法判断")
        }
    }
}

struct ChargeHelperReply: Decodable {
    let supported: Bool
    let accepted: Bool
    let attempted: Bool
    let manualState: Int?
    let limit: Int?
    let onAC: Bool?
    let charging: Bool?
    let percent: Double?
    let limitBlocked: Bool?
    let error: String?
    var canRequest: Bool {
        guard supported, error == nil, manualState == 1, let limit, (1..<100).contains(limit),
              let percent, percent.isFinite, (0..<100).contains(percent) else { return false }
        return onAC == true && charging == false && limitBlocked == true
    }
}

func canChargeToFull(scene: Scene, onAC: Bool?, charging: Bool?, battery: Double?, limitBlocked: Bool?, limit: ChargeLimit) -> Bool {
    guard scene == .live, onAC == true, charging == false, limitBlocked == true,
          let battery, battery.isFinite, (0..<1).contains(battery), case .value(let value) = limit else { return false }
    return (1..<100).contains(value)
}

func parseChargeLimit(_ output: String) -> ChargeLimit {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if text == "No battery level limits set" || text == "No battery level limits set." { return .none }
    let header = "Battery level limits:"
    guard text.hasPrefix(header),
          let records = try? PropertyListSerialization.propertyList(from: Data(text.dropFirst(header.count).utf8), format: nil) as? [[String: Any]] else { return .unknown }
    var limits = Set<Int>()
    for record in records {
        guard let terminated = record["Terminated"] as? String, ["0", "1"].contains(terminated) else { return .unknown }
        if terminated == "1" { continue }
        guard let reason = record["chargeSocLimitReason"] as? String else { return .unknown }
        // Other active policies may affect the effective ceiling; do not guess precedence.
        guard reason == "manualChargeLimit" else { return .unknown }
        guard let raw = record["chargeSocLimitSoc"] as? String, let value = Int(raw), (1...100).contains(value) else { return .unknown }
        limits.insert(value)
    }
    if limits.isEmpty { return .none }
    return limits.count == 1 ? .value(limits.first!) : .conflicting
}

func batteryChargeText(onAC: Bool?, charging: Bool?, charged: Bool?, limitBlocked: Bool?, limit: ChargeLimit) -> String {
    guard let onAC else { return L("充电状态无法判断") }
    if !onAC { return L("正在使用电池") }
    guard let charging else { return L("充电状态无法判断") }
    if charging { return L("正在充电") }
    if limitBlocked == true {
        if case .value(let value) = limit { return L("已充电至 \(value)% 上限") }
        return L("充电已暂停：系统上限")
    }
    if charged == true { return L("已充满电") }
    return L("已连接电源，未充电")
}
