import CoreWLAN
@testable import Combo

@main struct DetailFeedbackCheck {
    @MainActor static func main() async throws {
        let suite = "Combo.DetailFeedbackCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.defaults }
        defer { defaults.removePersistentDomain(forName: suite) }
        let scenario = CommandLine.arguments.dropFirst().first

        if scenario == nil || scenario == "wifi-message" {
            let wifi = WiFiControl(defaults: defaults, systemPassword: { _ in .cancelled },
                                   associate: { _, _ in throw Failure.connection })
            let choice = WiFiChoice(network: FeedbackNetwork(), name: suite)
            wifi.powerOn = true
            wifi.knownNames = [suite]
            wifi.join(choice)
            try await settle(wifi)
            assert(wifi.systemAccessDeclined)
            wifi.powerOn = true
            wifi.connect(choice, password: "incorrect-test-password", remember: false)
            try await settle(wifi)
            let rows = WiFiSection.feedback(wifi: wifi, systemMessage: "")
            assert(rows.contains { $0.text == wifi.message.string },
                   "A manual connection failure must remain visible after system password access was declined")
            let resume = rows.first { $0.actionTitle == L("重新允许请求") }
            assert(resume?.action != nil, "Keep the separate system-password recovery action")
            resume?.action?()
            assert(!wifi.systemAccessDeclined && wifi.useSystemPasswords)
            assert(!WiFiSection.feedback(wifi: wifi, systemMessage: "").contains { $0.actionTitle == L("重新允许请求") })
            wifi.join(choice)
            try await settle(wifi)
            assert(wifi.systemAccessDeclined)
            wifi.message = "Test scan failure"
            wifi.busy = true
            let busyRows = WiFiSection.feedback(wifi: wifi, systemMessage: "Unrelated system error")
            assert(busyRows.contains { $0.busy && $0.text == "Test scan failure" },
                   "An unrelated system error must not hide the active Wi-Fi operation")
            assert(busyRows.allSatisfy { $0.action == nil }, "Do not offer recovery actions during an operation")
            print("PASS: declined system-password access, manual connection failure, recovery action and busy feedback")
        }

        if scenario == nil || scenario == "wifi-permission" {
            let wifi = WiFiControl(defaults: defaults)
            // This check executable has no Location grant and never requests one.
            assert(!wifi.nameAccess)
            wifi.powerOn = true
            wifi.message = "Location access is required"
            let rows = WiFiSection.feedback(wifi: wifi, systemMessage: "")
            assert(rows.contains { $0.text == "Location access is required" })
            assert(rows.contains { $0.action != nil && ($0.actionTitle == L("请求定位权限") || $0.actionTitle == L("打开系统设置")) },
                   "A nonempty error must not remove the Location permission recovery action")
            wifi.powerOn = false
            assert(!WiFiSection.feedback(wifi: wifi, systemMessage: "").contains { $0.actionTitle == L("请求定位权限") || $0.actionTitle == L("打开系统设置") },
                   "Location access is not needed to display a powered-off Wi-Fi interface")
            print("PASS: Location recovery remains available alongside an error and disappears when Wi-Fi is off")
        }

        if scenario == nil || scenario == "battery-message" {
            for powerMessage in ["Authorization cancelled", "Mode change failed", "Mode changed successfully"] {
                let rows = BatteryDetail.operationFeedback(chargeBusy: false, chargeMessage: "Charging confirmed",
                                                            powerBusy: false, powerMessage: powerMessage)
                assert(rows.contains { $0.text == powerMessage },
                       "An older charging result must not hide an energy mode result")
                assert(rows.contains { $0.text == "Charging confirmed" }, "Keep the charging result independently")
            }
            let busyRows = BatteryDetail.operationFeedback(chargeBusy: true, chargeMessage: "Charge request pending",
                                                            powerBusy: true, powerMessage: "Energy mode authorization pending")
            assert(busyRows.contains { $0.busy && $0.text == "Energy mode authorization pending" })
            assert(busyRows.contains { $0.busy && $0.text == "Charge request pending" })
            let loadingRows = BatteryDetail.operationFeedback(chargeBusy: true, chargeMessage: "", powerBusy: true, powerMessage: "")
            assert(loadingRows.count == 2 && loadingRows.allSatisfy { $0.busy && !$0.text.isEmpty },
                   "Both background reads need progress feedback even before they have a message")
            assert(BatteryDetail.operationFeedback(chargeBusy: false, chargeMessage: "", powerBusy: false, powerMessage: "").isEmpty)
            print("PASS: independent charge and energy mode results, concurrent progress and empty feedback")
        }
    }

    @MainActor private static func settle(_ wifi: WiFiControl) async throws {
        for _ in 0..<200 {
            if !wifi.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }

    enum Failure: Error { case defaults, connection, timeout }
}

private final class FeedbackNetwork: CWNetwork {
    override var ssidData: Data? { Data("Feedback test".utf8) }
    override func supportsSecurity(_ security: CWSecurity) -> Bool { security == .wpa2Personal }
}
