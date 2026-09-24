import Foundation
let eligibleCharge = #"{"supported":true,"accepted":false,"attempted":false,"manualState":1,"limit":80,"onAC":true,"charging":false,"percent":80,"limitBlocked":true}"#
let decoder = JSONDecoder()
let eligibleReply = try decoder.decode(ChargeHelperReply.self, from: Data(eligibleCharge.utf8))
assert(eligibleReply.canRequest)
for (before, after) in [("\"supported\":true", "\"supported\":false"), ("\"manualState\":1", "\"manualState\":3"), ("\"limit\":80", "\"limit\":100"), ("\"onAC\":true", "\"onAC\":false"), ("\"charging\":false", "\"charging\":true"), ("\"percent\":80", "\"percent\":100"), ("\"limitBlocked\":true", "\"limitBlocked\":null")] {
    let reply = try decoder.decode(ChargeHelperReply.self, from: Data(eligibleCharge.replacingOccurrences(of: before, with: after).utf8))
    assert(!reply.canRequest)
}
assert((try? decoder.decode(ChargeHelperReply.self, from: Data("{}".utf8))) == nil)
assert(canChargeToFull(scene: .live, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
for limit: ChargeLimit in [.loading, .unknown, .conflicting, .none, .value(100)] {
    assert(!canChargeToFull(scene: .live, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: limit))
}
assert(!canChargeToFull(scene: .charging, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
assert(!canChargeToFull(scene: .live, onAC: nil, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
print("PASS: full-charge eligibility rejects demos, missing data, active charging and unsupported states")
let powerPolicies = parsePowerModes("Battery Power:\n lowpowermode 1\nAC Power:\n lowpowermode 0\n")
assert(powerPolicies[.battery]?.mode == .low && powerPolicies[.adapter]?.mode == .automatic)
assert(powerPolicies[.adapter]?.command(source: .adapter, mode: .low) == "/usr/bin/pmset -c lowpowermode 1")
assert(powerPolicies[.battery]?.command(source: .battery, mode: .automatic) == "/usr/bin/pmset -b lowpowermode 0")
assert(powerPolicies[.battery]?.command(source: .battery, mode: .high) == nil)
let highPolicy = parsePowerModes("Battery Power:\n powermode 2")[.battery]
assert(highPolicy?.mode == .high)
assert(highPolicy?.command(source: .battery, mode: .low) == "/usr/bin/pmset -b powermode 1")
for bad in ["lowpowermode 1", "Battery Power:\n lowpowermode 2", "AC Power:\n powermode 3", "AC Power:\n lowpowermode 0\n lowpowermode 1", "AC Power:\n lowpowermode 0\n highpowermode 1", "UPS Power:\n lowpowermode 1", "Battery Power:\n powermode x"] {
    assert(parsePowerModes(bad).isEmpty)
}
print("PASS: power policies, source-scoped commands and malformed settings")
assert(volumeDots(nil) == nil)
assert(volumeDots(0) == 0)
assert(volumeDots(0.01) == 1)
assert(volumeDots(0.25) == 1)
assert(volumeDots(0.26) == 2)
assert(volumeDots(1) == 4)
assert(volumeDots(-0.1) == nil)
assert(volumeDots(.nan) == nil)
assert(bottomState(muted: true, adjusting: true, playing: true, animate: true) == .muted)
assert(bottomState(muted: false, adjusting: true, playing: true, animate: true) == .volume)
assert(bottomState(muted: false, adjusting: false, playing: true, animate: true) == .playing)
assert(bottomState(muted: false, adjusting: false, playing: true, animate: false) == .volume)
print("PASS: volume boundaries and display precedence")
for snapshot in [Snapshot(volume: 0, playing: true), Snapshot(volume: 0.5, muted: true, playing: true)] {
    assert(snapshot.silenced)
    assert(bottomState(muted: snapshot.silenced, adjusting: false, playing: snapshot.playing, animate: true) == .muted)
}
assert(!Snapshot(volume: nil).silenced && !Snapshot(volume: 0.01, playing: true).silenced)
print("PASS: zero volume and hardware mute override playback without treating unknown volume as mute")
assert(Scene.allCases.count == 17) // 16 preview states plus live data.
assert(Snapshot.demo(.music).symbol.isEmpty)
assert(Snapshot.demo(.adjusting).volume == 0.75)
assert(Snapshot.demo(.reduced).reducedMotion)
print("PASS: reference scene coverage")
assert(resolveTransport(pathAvailable: false, interfaces: ["wifi"]) == "offline")
assert(resolveTransport(pathAvailable: true, interfaces: ["wifi", "ethernet"]) == "unknown")
assert(resolveTransport(pathAvailable: true, interfaces: ["wifi", "wifi"]) == "wifi")
assert(resolveTransport(pathAvailable: true, interfaces: ["tunnel"]) == "unknown")
assert(resolveTransport(pathAvailable: nil, interfaces: []) == "pending")
assert(volumeHintActive(changedAt: 10, now: 11.99))
assert(!volumeHintActive(changedAt: 10, now: 12))
assert(!volumeHintActive(changedAt: nil, now: 11))
print("PASS: conservative routes and volume hint expiry")
let menuKeys: Set<String> = ["wifi", "sound", "battery"]
assert(menuBarRestoreKeys(original: ["wifi": true, "sound": false, "battery": true], current: ["wifi": false, "sound": false, "battery": false], keys: menuKeys) == ["battery", "wifi"])
assert(menuBarRestoreKeys(original: ["wifi": true], current: ["wifi": false, "sound": false, "battery": false], keys: menuKeys) == nil)
assert(menuBarRestoreKeys(original: ["wifi": true, "sound": false, "battery": true], current: ["wifi": false], keys: menuKeys) == nil)
print("PASS: restore only changed icons with complete baseline")

let limitRecord = "{Terminated = 0; chargeSocLimitReason = manualChargeLimit; chargeSocLimitSoc = 80;}"
assert(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord))") == .value(80))
assert(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord.replacingOccurrences(of: "80", with: "90")))") == .conflicting)
assert(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord.replacingOccurrences(of: "Terminated = 0", with: "Terminated = 1").replacingOccurrences(of: "80", with: "90")))") == .value(80))
assert(parseChargeLimit("Battery level limits:\n(\(limitRecord.replacingOccurrences(of: "Terminated = 0", with: "Terminated = 1")))") == .none)
assert(parseChargeLimit("No battery level limits set") == .none)
assert(parseChargeLimit("Battery level limits:\n()") == .none)
for invalid in ["", "pmset: unsupported", "Battery level limits: ({", "Battery level limits: ({chargeSocLimitSoc = 80;})",
                "Battery level limits: (\(limitRecord.replacingOccurrences(of: "80", with: "101")))",
                "Battery level limits: (\(limitRecord.replacingOccurrences(of: "manualChargeLimit", with: "otherPolicy")))"] {
    assert(parseChargeLimit(invalid) == .unknown)
}
assert(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: true, limit: .value(80)) == "已充电至 80% 上限")
assert(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: nil, limit: .value(80)) == "已连接电源，未充电")
assert(batteryChargeText(onAC: true, charging: true, charged: false, limitBlocked: true, limit: .value(80)) == "正在充电")
assert(batteryChargeText(onAC: false, charging: false, charged: false, limitBlocked: true, limit: .value(80)) == "正在使用电池")
assert(batteryChargeText(onAC: true, charging: false, charged: true, limitBlocked: false, limit: .none) == "已充满电")
assert(batteryChargeText(onAC: nil, charging: nil, charged: nil, limitBlocked: nil, limit: .unknown) == "充电状态无法判断")
assert(batteryChargeText(onAC: true, charging: nil, charged: nil, limitBlocked: true, limit: .value(80)) == "充电状态无法判断")
assert(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: true, limit: .conflicting) == "充电已暂停：系统上限")
print("PASS: charge limits reject missing/conflicting data and charging status requires evidence")

var powerChange = PowerChange()
assert(!powerChange.update(onAC: nil))
assert(!powerChange.update(onAC: false))
assert(powerChange.update(onAC: true))
assert(!powerChange.update(onAC: true))
assert(powerChange.update(onAC: false))
assert(!powerChange.update(onAC: nil))
assert(!powerChange.update(onAC: true)) // Missing data is not a transition.
for symbol in ["wifi", "", "minus", "exclamationmark"] {
    for charging in [false, true] {
            for battery: Double? in [nil, 0, 0.49, 0.50, 0.51, 1, .nan] {
                let original = Snapshot(battery: battery, charging: charging, symbol: symbol)
                let result = original.preferringBattery(threshold: 50)
                let expected = (symbol == "wifi" || symbol.isEmpty) && battery.map { $0.isFinite && (charging || $0 < 0.5) } == true
                assert(result.symbol == (expected ? "" : symbol))
                assert(result.batteryPreferred == expected)
                assert(result.network == original.network && result.charging == charging)
            }
    }
}
assert(Snapshot(battery: 0, symbol: "wifi").preferringBattery(threshold: 0).symbol == "wifi")
assert(Snapshot(battery: 1, symbol: "wifi").preferringBattery(threshold: 100).symbol == "wifi")
assert(Snapshot(battery: 0.99, symbol: "wifi").preferringBattery(threshold: 100).symbol == "")
assert(Snapshot(battery: 1, charging: true, symbol: "wifi").preferringBattery(threshold: 0).symbol == "")
print("PASS: battery display priority, threshold boundaries, missing data and power-change detection")
