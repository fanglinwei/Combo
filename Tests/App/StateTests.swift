import Testing
import Foundation

struct StateTests {
    @Test
    @MainActor
    func testFullChargeEligibility() async throws {
        let eligibleCharge = #"{"supported":true,"accepted":false,"attempted":false,"manualState":1,"limit":80,"onAC":true,"charging":false,"percent":80,"limitBlocked":true}"#
        let decoder = JSONDecoder()
        let eligibleReply = try decoder.decode(ChargeHelperReply.self, from: Data(eligibleCharge.utf8))
        #expect(eligibleReply.canRequest)
        for (before, after) in [("\"supported\":true", "\"supported\":false"), ("\"manualState\":1", "\"manualState\":3"), ("\"limit\":80", "\"limit\":100"), ("\"onAC\":true", "\"onAC\":false"), ("\"charging\":false", "\"charging\":true"), ("\"percent\":80", "\"percent\":100"), ("\"limitBlocked\":true", "\"limitBlocked\":null")] {
            let reply = try decoder.decode(ChargeHelperReply.self, from: Data(eligibleCharge.replacingOccurrences(of: before, with: after).utf8))
            #expect(!reply.canRequest)
        }
        #expect((try? decoder.decode(ChargeHelperReply.self, from: Data("{}".utf8))) == nil)
        #expect(canChargeToFull(scene: .live, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
        for limit: ChargeLimit in [.loading, .unknown, .conflicting, .none, .value(100)] {
            #expect(!canChargeToFull(scene: .live, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: limit))
        }
        #expect(!canChargeToFull(scene: .charging, onAC: true, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
        #expect(!canChargeToFull(scene: .live, onAC: nil, charging: false, battery: 0.8, limitBlocked: true, limit: .value(80)))
    }

    @Test
    @MainActor
    func testPowerPolicies() async throws {
        let powerPolicies = parsePowerModes("Battery Power:\n lowpowermode 1\nAC Power:\n lowpowermode 0\n")
        #expect(powerPolicies[.battery]?.mode == .low && powerPolicies[.adapter]?.mode == .automatic)
        #expect(powerPolicies[.adapter]?.command(source: .adapter, mode: .low) == "/usr/bin/pmset -c lowpowermode 1")
        #expect(powerPolicies[.battery]?.command(source: .battery, mode: .automatic) == "/usr/bin/pmset -b lowpowermode 0")
        #expect(powerPolicies[.battery]?.command(source: .battery, mode: .high) == nil)
        let highPolicy = parsePowerModes("Battery Power:\n powermode 2")[.battery]
        #expect(highPolicy?.mode == .high)
        #expect(highPolicy?.command(source: .battery, mode: .low) == "/usr/bin/pmset -b powermode 1")
        for bad in ["lowpowermode 1", "Battery Power:\n lowpowermode 2", "AC Power:\n powermode 3", "AC Power:\n lowpowermode 0\n lowpowermode 1", "AC Power:\n lowpowermode 0\n highpowermode 1", "UPS Power:\n lowpowermode 1", "Battery Power:\n powermode x"] {
            #expect(parsePowerModes(bad).isEmpty)
        }
    }

    @Test
    @MainActor
    func testVolumeDisplayPrecedence() async throws {
        #expect(volumeDots(nil) == nil)
        #expect(volumeDots(0) == 0)
        #expect(volumeDots(0.01) == 1)
        #expect(volumeDots(0.25) == 1)
        #expect(volumeDots(0.26) == 2)
        #expect(volumeDots(1) == 4)
        #expect(volumeDots(-0.1) == nil)
        #expect(volumeDots(.nan) == nil)
        #expect(bottomState(muted: true, adjusting: true, playing: true, animate: true) == .muted)
        #expect(bottomState(muted: false, adjusting: true, playing: true, animate: true) == .volume)
        #expect(bottomState(muted: false, adjusting: false, playing: true, animate: true) == .playing)
        #expect(bottomState(muted: false, adjusting: false, playing: true, animate: false) == .volume)
    }

    @Test
    @MainActor
    func testScrollVolume() async throws {
        // Scrolling up is louder: wheel away from the user (not inverted), or fingers up on a natural-scrolling trackpad (inverted).
        #expect(abs(scrollVolume(current: 0.5, scrollingDelta: 30, precise: true, inverted: false) - 0.6) < 1e-9)
        #expect(abs(scrollVolume(current: 0.5, scrollingDelta: -30, precise: true, inverted: true) - 0.6) < 1e-9)
        #expect(abs(scrollVolume(current: 0.5, scrollingDelta: -30, precise: true, inverted: false) - 0.4) < 1e-9)
        #expect(abs(scrollVolume(current: 0.5, scrollingDelta: 4, precise: false, inverted: false) - 0.7) < 1e-9)
        #expect(scrollVolume(current: 1, scrollingDelta: 300, precise: true, inverted: false) == 1)
        #expect(scrollVolume(current: 0, scrollingDelta: 300, precise: true, inverted: true) == 0)
        #expect(scrollVolume(current: 0.5, scrollingDelta: .nan, precise: true, inverted: false) == 0.5)
        #expect(scrollVolume(current: .nan, scrollingDelta: 30, precise: true, inverted: false).isNaN)
    }

    @Test
    @MainActor
    func testMutedPlayback() async throws {
        for snapshot in [Snapshot(volume: 0, playing: true), Snapshot(volume: 0.5, muted: true, playing: true)] {
            #expect(snapshot.silenced)
            #expect(bottomState(muted: snapshot.silenced, adjusting: false, playing: snapshot.playing, animate: true) == .muted)
        }
        #expect(!Snapshot(volume: nil).silenced && !Snapshot(volume: 0.01, playing: true).silenced)
    }

    @Test
    @MainActor
    func testPreviewScenes() async throws {
        #expect(Scene.allCases.count == 17) // 16 preview states plus live data.
        #expect(Snapshot.demo(.music).symbol.isEmpty)
        #expect(Snapshot.demo(.adjusting).volume == 0.75)
        #expect(Snapshot.demo(.reduced).reducedMotion)
    }

    @Test
    @MainActor
    func testTransportAndVolumeExpiry() async throws {
        #expect(resolveTransport(pathAvailable: false, interfaces: ["wifi"]) == "offline")
        #expect(resolveTransport(pathAvailable: true, interfaces: ["wifi", "ethernet"]) == "unknown")
        #expect(resolveTransport(pathAvailable: true, interfaces: ["wifi", "wifi"]) == "wifi")
        #expect(resolveTransport(pathAvailable: true, interfaces: ["tunnel"]) == "unknown")
        #expect(resolveTransport(pathAvailable: nil, interfaces: []) == "pending")
        #expect(volumeHintActive(changedAt: 10, now: 11.99))
        #expect(!volumeHintActive(changedAt: 10, now: 12))
        #expect(!volumeHintActive(changedAt: nil, now: 11))
    }

    @Test
    @MainActor
    func testMenuRestoreBaseline() async throws {
        let menuKeys: Set<String> = ["wifi", "sound", "battery"]
        #expect(menuBarRestoreKeys(original: ["wifi": true, "sound": false, "battery": true], current: ["wifi": false, "sound": false, "battery": false], keys: menuKeys) == ["battery", "wifi"])
        #expect(menuBarRestoreKeys(original: ["wifi": true], current: ["wifi": false, "sound": false, "battery": false], keys: menuKeys) == nil)
        #expect(menuBarRestoreKeys(original: ["wifi": true, "sound": false, "battery": true], current: ["wifi": false], keys: menuKeys) == nil)
    }

    @Test
    @MainActor
    func testChargeLimitParsingAndStatus() async throws {
        let limitRecord = "{Terminated = 0; chargeSocLimitReason = manualChargeLimit; chargeSocLimitSoc = 80;}"
        #expect(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord))") == .value(80))
        #expect(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord.replacingOccurrences(of: "80", with: "90")))") == .conflicting)
        #expect(parseChargeLimit("Battery level limits:\n(\(limitRecord),\(limitRecord.replacingOccurrences(of: "Terminated = 0", with: "Terminated = 1").replacingOccurrences(of: "80", with: "90")))") == .value(80))
        #expect(parseChargeLimit("Battery level limits:\n(\(limitRecord.replacingOccurrences(of: "Terminated = 0", with: "Terminated = 1")))") == .none)
        #expect(parseChargeLimit("No battery level limits set") == .none)
        #expect(parseChargeLimit("Battery level limits:\n()") == .none)
        for invalid in ["", "pmset: unsupported", "Battery level limits: ({", "Battery level limits: ({chargeSocLimitSoc = 80;})",
                        "Battery level limits: (\(limitRecord.replacingOccurrences(of: "80", with: "101")))",
                        "Battery level limits: (\(limitRecord.replacingOccurrences(of: "manualChargeLimit", with: "otherPolicy")))"] {
            #expect(parseChargeLimit(invalid) == .unknown)
        }
        #expect(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: true, limit: .value(80)) == "已充电至 80% 上限")
        #expect(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: nil, limit: .value(80)) == "已连接电源，未充电")
        #expect(batteryChargeText(onAC: true, charging: true, charged: false, limitBlocked: true, limit: .value(80)) == "正在充电")
        #expect(batteryChargeText(onAC: false, charging: false, charged: false, limitBlocked: true, limit: .value(80)) == "正在使用电池")
        #expect(batteryChargeText(onAC: true, charging: false, charged: true, limitBlocked: false, limit: .none) == "已充满电")
        #expect(batteryChargeText(onAC: nil, charging: nil, charged: nil, limitBlocked: nil, limit: .unknown) == "充电状态无法判断")
        #expect(batteryChargeText(onAC: true, charging: nil, charged: nil, limitBlocked: true, limit: .value(80)) == "充电状态无法判断")
        #expect(batteryChargeText(onAC: true, charging: false, charged: false, limitBlocked: true, limit: .conflicting) == "充电已暂停：系统上限")
    }

    @Test
    @MainActor
    func testBatteryPriorityAndPowerChanges() async throws {
        var powerChange = PowerChange()
        let initialUnknown = powerChange.update(onAC: nil)
        #expect(!initialUnknown)
        let initialBattery = powerChange.update(onAC: false)
        #expect(!initialBattery)
        let connected = powerChange.update(onAC: true)
        #expect(connected)
        let stillConnected = powerChange.update(onAC: true)
        #expect(!stillConnected)
        let disconnected = powerChange.update(onAC: false)
        #expect(disconnected)
        let missing = powerChange.update(onAC: nil)
        #expect(!missing)
        let restored = powerChange.update(onAC: true)
        #expect(!restored) // Missing data is not a transition.
        for symbol in ["wifi", "", "minus", "exclamationmark"] {
            for charging in [false, true] {
                    for battery: Double? in [nil, 0, 0.49, 0.50, 0.51, 1, .nan] {
                        let original = Snapshot(battery: battery, charging: charging, symbol: symbol)
                        let result = original.preferringBattery(threshold: 50)
                        let expected = (symbol == "wifi" || symbol.isEmpty) && battery.map { $0.isFinite && $0 < 0.5 } == true
                        #expect(result.symbol == (expected ? "" : symbol))
                        #expect(result.batteryPreferred == expected)
                        #expect(result.network == original.network && result.charging == charging)
                    }
            }
        }
        #expect(Snapshot(battery: 0, symbol: "wifi").preferringBattery(threshold: 0).symbol == "wifi")
        #expect(Snapshot(battery: 1, symbol: "wifi").preferringBattery(threshold: 100).symbol == "wifi")
        #expect(Snapshot(battery: 0.99, symbol: "wifi").preferringBattery(threshold: 100).symbol == "")
        #expect(Snapshot(battery: 1, charging: true, symbol: "wifi").preferringBattery(threshold: 0).symbol == "wifi")
    }

    @Test
    @MainActor
    func testCalloutGeometry() async throws {
        let calloutSize = CGSize(width: 240, height: 68)
        let calloutScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(calloutOrigin(anchor: CGRect(x: 985, y: 876, width: 30, height: 24), size: calloutSize, visible: calloutScreen) == CGPoint(x: 880, y: 802))
        #expect(calloutOrigin(anchor: CGRect(x: 1410, y: 876, width: 30, height: 24), size: calloutSize, visible: calloutScreen) == CGPoint(x: 1192, y: 802))
        #expect(calloutOrigin(anchor: CGRect(x: 0, y: 876, width: 20, height: 24), size: calloutSize, visible: calloutScreen) == CGPoint(x: 8, y: 802))
        #expect(calloutOrigin(anchor: CGRect(x: 1000, y: 876, width: 30, height: 24), size: calloutSize, visible: CGRect(x: 0, y: 0, width: 200, height: 900)).x == 8)
    }

    @Test
    @MainActor
    func testPanelDismissPermissionGuard() async throws {
        #expect(!shouldDismissPanel(panelVisible: false, permissionPrompt: false, interactionInside: false))
        #expect(shouldDismissPanel(panelVisible: true, permissionPrompt: false, interactionInside: false))
        #expect(!shouldDismissPanel(panelVisible: true, permissionPrompt: true, interactionInside: false))
        #expect(!shouldDismissPanel(panelVisible: true, permissionPrompt: false, interactionInside: true))
        #expect(!permissionRequestStarting(nil, now: 100))
        #expect(permissionRequestStarting(100, now: 100.5))
        #expect(!permissionRequestStarting(100, now: 101))
        #expect(!permissionRequestStarting(100, now: 99))
    }
}
