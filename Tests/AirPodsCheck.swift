import Foundation

@main struct AirPodsCheck {
    @MainActor static func main() async throws {
        assert(AudioVolume.elements(main: true, preferred: [1, 2], has: { _ in true }) == [0])
        assert(AudioVolume.elements(main: false, preferred: [], has: { $0 == 1 || $0 == 2 }) == [1, 2])
        assert(AudioVolume.elements(main: false, preferred: [3, 3, 4], has: { _ in true }) == [3, 4])
        assert(AudioVolume.elements(main: false, preferred: [], has: { _ in false }).isEmpty)
        assert(!AudioVolume.set(.nan, device: 0) && !AudioVolume.set(2, device: 0))
        var payload: [String: Any] = ["deviceID": 99, "target": String(repeating: "a", count: 64),
            "available": true, "modes": ["transparency", "noise-cancellation"], "mode": "noise-cancellation",
            "canSetMode": true, "conversation": false, "canSetConversation": true,
            "left": 43, "right": 34, "attempted": false, "verified": false]
        func decode(_ payload: [String: Any]) throws -> AirPodsReply {
            try JSONDecoder().decode(AirPodsReply.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        assert((try! decode(payload)).valid)
        assert((try! decode(payload)).batteryText == "左 43% · 右 34%")
        for invalid in [0, 101, -1] {
            var broken = payload; broken["left"] = invalid
            assert(!(try! decode(broken)).valid)
        }
        var broken = payload; broken["conversation"] = NSNull()
        assert(!(try! decode(broken)).valid)
        broken = payload; broken["target"] = "stale"
        assert(!(try! decode(broken)).valid)
        broken = payload; broken["modes"] = ["transparency", "transparency"]
        assert(!(try! decode(broken)).valid)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        func write(_ body: String) throws {
            try ("#!/bin/sh\n" + body + "\n").write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        }
        func respond(_ value: [String: Any]) throws {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            try write("printf '%s' '" + json.replacingOccurrences(of: "'", with: "'\\''") + "'")
        }
        let control = AirPodsControl(helperURL: helper, libraryURL: URL(fileURLWithPath: "/usr/lib/libSystem.B.dylib"), timeoutSeconds: 1)
        func settle() async throws {
            for _ in 0..<100 {
                if !control.busy { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            fatalError("helper did not settle")
        }
        try respond(payload)
        control.refresh(deviceID: 99); try await settle()
        assert(control.snapshot?.mode == .noiseCancellation && !control.unavailable)
        control.setMode(.noiseCancellation); assert(!control.busy, "same value must not write")
        control.setMode(.off); assert(!control.busy, "unsupported mode must not write")
        payload["attempted"] = true; payload["verified"] = true; payload["mode"] = "transparency"
        try respond(payload)
        control.setMode(.transparency); try await settle()
        assert(control.snapshot?.mode == .transparency && control.message.isEmpty)
        payload["verified"] = false; payload["error"] = "unconfirmed"
        try respond(payload)
        control.setConversation(true); try await settle()
        assert(!control.message.isEmpty && control.snapshot?.conversation == false)
        control.refresh(deviceID: 100); try await settle()
        assert(control.snapshot == nil && control.unavailable, "stale output must not be displayed")
        try write("echo '{}'")
        control.refresh(deviceID: 99); try await settle()
        assert(control.snapshot == nil && control.unavailable)
        try write("exit 1")
        control.refresh(deviceID: 99); try await settle()
        assert(control.unavailable)
        try write("exec /bin/sleep 5")
        control.refresh(deviceID: 99); try await settle()
        assert(control.unavailable && !control.busy)
        control.refresh(deviceID: 99); control.cancel()
        try await Task.sleep(for: .milliseconds(100))
        assert(!control.busy && control.snapshot == nil && !control.unavailable)
        print("PASS: volume channel fallback; AirPods validation, guarded writes, readback failure, stale device, malformed output, timeout and cancellation")
    }
}
