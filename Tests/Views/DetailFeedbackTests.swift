import Testing
import Foundation
@testable import ComboTestHost

extension IntegrationTests {
    struct DetailFeedbackTests {
        @Test
        @MainActor
        func testWiFiFailureRecoveryAndBusyFeedback() async throws {
            let wifi = WiFiControl(observesLocationAuthorization: false)
            wifi.message = "Test scan failure"
            let rows = WiFiSection.feedback(wifi: wifi, systemMessage: "")
            #expect(rows.contains { $0.text == "Test scan failure" }, "Scan results must remain visible")
            wifi.busy = true
            let busyRows = WiFiSection.feedback(wifi: wifi, systemMessage: "Unrelated system error")
            #expect(busyRows.contains { $0.busy && $0.text == "Test scan failure" },
                   "An unrelated system error must not hide the active Wi-Fi operation")
            #expect(busyRows.allSatisfy { $0.action == nil }, "Do not offer recovery actions during an operation")
        }

        @Test
        @MainActor
        func testWiFiPermissionRecovery() async throws {
            let wifi = WiFiControl(observesLocationAuthorization: false)
            // This check executable has no Location grant and never requests one.
            #expect(!wifi.nameAccess)
            wifi.powerOn = true
            wifi.message = "Location access is required"
            let rows = WiFiSection.feedback(wifi: wifi, systemMessage: "")
            #expect(rows.contains { $0.text == "Location access is required" })
            #expect(rows.contains { $0.action != nil && ($0.actionTitle == L("请求定位权限") || $0.actionTitle == L("打开系统设置")) },
                   "A nonempty error must not remove the Location permission recovery action")
            wifi.powerOn = false
            #expect(!WiFiSection.feedback(wifi: wifi, systemMessage: "").contains { $0.actionTitle == L("请求定位权限") || $0.actionTitle == L("打开系统设置") },
                   "Location access is not needed to display a powered-off Wi-Fi interface")
        }

        @Test
        @MainActor
        func testIndependentBatteryFeedback() async throws {
            let suite = "Combo.DetailFeedbackCheck.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            for powerMessage in ["Authorization cancelled", "Mode change failed", "Mode changed successfully"] {
                let rows = BatteryDetail.operationFeedback(chargeBusy: false, chargeMessage: "Charging confirmed",
                                                            powerBusy: false, powerMessage: powerMessage)
                #expect(rows.contains { $0.text == powerMessage },
                       "An older charging result must not hide an energy mode result")
                #expect(rows.contains { $0.text == "Charging confirmed" }, "Keep the charging result independently")
            }
            let busyRows = BatteryDetail.operationFeedback(chargeBusy: true, chargeMessage: "Charge request pending",
                                                            powerBusy: true, powerMessage: "Energy mode authorization pending")
            #expect(busyRows.contains { $0.busy && $0.text == "Energy mode authorization pending" })
            #expect(busyRows.contains { $0.busy && $0.text == "Charge request pending" })
            let loadingRows = BatteryDetail.operationFeedback(chargeBusy: true, chargeMessage: "", powerBusy: true, powerMessage: "")
            #expect(loadingRows.count == 2 && loadingRows.allSatisfy { $0.busy && !$0.text.isEmpty },
                   "Both background reads need progress feedback even before they have a message")
            #expect(BatteryDetail.operationFeedback(chargeBusy: false, chargeMessage: "", powerBusy: false, powerMessage: "").isEmpty)
        }
    }
}
