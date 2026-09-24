import Foundation

@main struct ChargeControlCheck {
    @MainActor static func wait(_ control: ChargeControl) async {
        let deadline = Date().addingTimeInterval(15)
        while control.busy && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        assert(!control.busy, "helper must finish or time out")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let eligible = #"{"supported":true,"accepted":false,"attempted":false,"manualState":1,"limit":80,"onAC":true,"charging":false,"percent":80,"limitBlocked":true}"#
        let charging = #"{"supported":true,"accepted":false,"attempted":false,"manualState":3,"limit":100,"onAC":true,"charging":true,"percent":80,"limitBlocked":false}"#
        for scenario in ["success", "stale", "failure", "timeout"] {
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
            control.refresh(); await wait(control)
            assert(control.snapshot?.canRequest == true)
            control.request(expectedLimit: 80, refreshBattery: {})
            control.request(expectedLimit: 80, refreshBattery: {}) // duplicate click must be ignored
            await wait(control)
            let calls = try String(contentsOfFile: helper.path + ".calls", encoding: .utf8)
            assert(calls == "request\n")
            if scenario == "success" {
                assert(control.message.contains("已确认开始充电"))
                assert(control.snapshot?.charging == true)
                try FileManager.default.removeItem(atPath: helper.path + ".requested")
                control.refresh(); await wait(control)
                assert(control.message.isEmpty, "restored limit must clear the old success message")
            } else {
                assert(!control.message.contains("已确认开始充电"))
                assert(control.message.contains(scenario == "stale" ? "本次未执行" : "未能确认"))
            }
            control.stop()
        }
        let absent = ChargeControl(helperURL: directory.appendingPathComponent("missing"))
        absent.refresh(); await wait(absent)
        assert(absent.snapshot == nil)
        absent.request(expectedLimit: 80, refreshBattery: {})
        assert(!absent.busy)
        absent.stop()
        if CommandLine.arguments.count == 2 {
            let live = ChargeControl(helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
            live.refresh(); await wait(live)
            assert(live.snapshot != nil, "packaged helper must emit valid JSON, including when unsupported")
            print("Packaged helper: supported=\(live.snapshot?.supported == true), eligible=\(live.snapshot?.canRequest == true)")
            live.stop()
        }
        print("PASS: full-charge confirmation, stale state, failed request, timeout, duplicate click and missing helper (no hardware writes)")
    }
}
