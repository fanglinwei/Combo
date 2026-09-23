import Foundation

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
enum Scene: String, CaseIterable, Identifiable {
    case live = "本机状态", wifi = "无线正常", wired = "有线 · 默认", date = "有线 · 日期", output = "有线 · 输出设备", music = "媒体播放", adjusting = "播放中调音量", paused = "暂停 / 未播放", mute = "系统静音", low = "低电量", charging = "充电 + 播放", offline = "网络异常", reduced = "减少动态效果"
    var id: String { rawValue }
}
struct Snapshot {
    var battery: Double? = nil
    var charging = false
    var plugged = false
    var network = "正在读取"
    var symbol = "minus"
    var volume: Double? = nil
    var muted = false
    var output = "正在读取"
    var playing = false
    var adjusting = false
    var centerOverride: String? = nil
    var headphones = false
    var reducedMotion = false
    var day: String? = nil
    static func demo(_ scene: Scene) -> Snapshot {
        var s = Snapshot(battery: 0.82, network: "有线网络", symbol: "", volume: 0.5, output: "MacBook 扬声器")
        if scene == .wifi { s.network = "Wi-Fi"; s.symbol = "wifi" }
        if scene != .wired { s.centerOverride = "电量百分比" }
        if scene == .date { s.centerOverride = "当天日期"; s.day = "22" }
        if scene == .output { s.centerOverride = "音频输出设备"; s.headphones = true; s.output = "耳机（示例）" }
        if [.music, .adjusting, .charging, .reduced].contains(scene) { s.playing = true }
        if scene == .adjusting { s.adjusting = true; s.volume = 0.75 }
        if scene == .mute { s.muted = true }
        if scene == .charging { s.charging = true; s.plugged = true }
        if scene == .low { s.battery = 0.12 }
        if scene == .offline { s.network = "无可用路径"; s.symbol = "exclamationmark" }
        if scene == .reduced { s.reducedMotion = true }
        return s
    }
    var batteryText: String { battery.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var volumeText: String { volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "由设备控制" }
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
