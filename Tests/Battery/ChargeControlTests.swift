import Testing
import Foundation

struct ChargeControlTests {
    @Test
    @MainActor
    func testSuccess() async throws {
        try await checkScenario("success")
    }

    @Test
    @MainActor
    func testStale() async throws {
        try await checkScenario("stale")
    }

    @Test
    @MainActor
    func testFailure() async throws {
        try await checkScenario("failure")
    }

    @Test
    @MainActor
    func testTimeout() async throws {
        try await checkScenario("timeout")
    }

    @Test
    @MainActor
    func testMissingHelper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.ChargeControlTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let absent = ChargeControl(helperURL: directory.appendingPathComponent("missing"))
        defer { absent.stop() }
        absent.refresh(); try await wait(absent)
        #expect(absent.snapshot == nil)
        absent.request(expectedLimit: 80, refreshBattery: {})
        #expect(!absent.busy)
        absent.stop()
    }

    @MainActor
    private func wait(_ control: ChargeControl) async throws {
        let deadline = Date().addingTimeInterval(15)
        while control.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard !control.busy else { throw NSError(domain: "ChargeControlTests.wait", code: 1, userInfo: [NSLocalizedDescriptionKey: "helper must finish or time out"]) }
    }

    @MainActor
    private func checkScenario(_ scenario: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.ChargeControlTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eligible = #"{"supported":true,"accepted":false,"attempted":false,"manualState":1,"limit":80,"onAC":true,"charging":false,"percent":80,"limitBlocked":true}"#
        let charging = #"{"supported":true,"accepted":false,"attempted":false,"manualState":3,"limit":100,"onAC":true,"charging":true,"percent":80,"limitBlocked":false}"#

        let helper = directory.appendingPathComponent(scenario)
        let action: String
        switch scenario {
        case "success": action = "touch \"$0.requested\"; echo '{\"supported\":true,\"accepted\":true,\"attempted\":true}'"
        case "stale": action = "echo '{\"supported\":true,\"accepted\":false,\"attempted\":false,\"error\":\"not_eligible\"}'"
        case "failure": action = "echo '{\"supported\":true,\"accepted\":false,\"attempted\":true,\"error\":\"request_failed\"}'"
        default: action = "exec /bin/sleep 30"
        }
        let script = """
        #!/bin/sh
        if [ "$1" = "--status" ]; then
            if [ -f "$0.requested" ]; then echo '\(charging)'; else echo '\(eligible)'; fi
        else
            echo request >> "$0.calls"
            \(action)
        fi
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let control = ChargeControl(helperURL: helper)
        defer { control.stop() }
        control.refresh(); try await wait(control)
        #expect(control.snapshot?.canRequest == true)
        control.request(expectedLimit: 80, refreshBattery: {})
        control.request(expectedLimit: 80, refreshBattery: {}) // duplicate click must be ignored
        try await wait(control)
        let calls = try String(contentsOfFile: helper.path + ".calls", encoding: .utf8)
        #expect(calls == "request\n")
        if scenario == "success" {
            #expect(control.message.string.contains("已确认开始充电"))
            #expect(control.snapshot?.charging == true)
            try FileManager.default.removeItem(atPath: helper.path + ".requested")
            control.refresh(); try await wait(control)
            #expect(control.message.isEmpty, "restored limit must clear the old success message")
        } else {
            #expect(!control.message.string.contains("已确认开始充电"))
            #expect(control.message.string.contains(scenario == "stale" ? "本次未执行" : "未能确认"))
        }
        control.stop()
    }
}
