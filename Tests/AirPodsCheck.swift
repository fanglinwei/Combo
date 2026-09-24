import Foundation
import Combine

@main struct AirPodsCheck {
    @MainActor static func main() async throws {
        assert(AudioVolume.elements(main: true, preferred: [1, 2], has: { _ in true }) == [0])
        assert(AudioVolume.elements(main: false, preferred: [], has: { $0 == 1 || $0 == 2 }) == [1, 2])
        assert(AudioVolume.elements(main: false, preferred: [3, 3, 4], has: { _ in true }) == [3, 4])
        assert(AudioVolume.elements(main: false, preferred: [], has: { _ in false }).isEmpty)
        assert(!AudioVolume.set(.nan, device: 0) && !AudioVolume.set(2, device: 0))
        func drag(_ translation: Double, count: Int = 3, selected: Int = 1, x: Double = 150, y: Double = 24) -> Double? {
            airPodsDragPosition(selected: selected, count: count, width: 300,
                                 startX: x, startY: y, translation: translation)
        }
        assert(drag(-1000) == 0 && drag(1000) == 2, "Dragging must clamp to both ends")
        assert(drag(49)!.rounded() == 1 && drag(51)!.rounded() == 2, "Release selects the nearest center")
        assert(drag(0) == 1 && drag(-40)!.rounded() == 1, "Returning to the original option must not switch")
        assert(drag(90, count: 2, selected: 0, x: 75)!.rounded() == 1)
        assert(drag(-90, count: 2, selected: 1, x: 225)!.rounded() == 0)
        assert(drag(80, x: 20) == nil && drag(80, y: 60) == nil, "Drag must start on the selected capsule")
        assert(drag(.nan) == nil && drag(10, count: 1, selected: 0) == nil)
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
                if !control.busy && !control.refreshing { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            fatalError("helper did not settle")
        }
        try respond(payload)
        control.refresh(deviceID: 99)
        assert(!control.busy, "Background polling must not disable and dim the AirPods controls")
        try await settle()
        assert(control.snapshot?.mode == .noiseCancellation && !control.unavailable)
        var changes = 0
        let observation = control.objectWillChange.sink { changes += 1 }
        for _ in 0..<3 {
            control.refresh(deviceID: 99)
            assert(!control.busy && control.snapshot?.mode == .noiseCancellation)
            try await settle()
        }
        assert(changes == 0, "Unchanged background reads must not publish UI updates")
        observation.cancel()
        control.setMode(.noiseCancellation); assert(!control.busy, "same value must not write")
        control.setMode(.off); assert(!control.busy, "unsupported mode must not write")
        payload["attempted"] = true; payload["verified"] = true; payload["mode"] = "transparency"
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        try write("if [ \"$1\" = \"--status\" ]; then exec /bin/sleep 5; fi\nprintf '%s' '" + json + "'")
        control.refresh(deviceID: 99)
        assert(control.refreshing && !control.busy)
        control.setMode(.transparency)
        assert(control.busy && !control.refreshing, "User writes must take priority over background reads")
        assert(control.displayedMode == .transparency && control.snapshot?.mode == .noiseCancellation,
               "Move selection immediately without claiming the device has confirmed it")
        control.setConversation(true)
        assert(control.busy && control.pendingConversation == nil && control.pendingMode == .transparency,
               "A second write must not replace the pending selection")
        try await settle()
        assert(control.snapshot?.mode == .transparency && control.pendingMode == nil && control.message.isEmpty)
        payload["verified"] = false; payload["error"] = "unconfirmed"
        try respond(payload)
        control.setConversation(true)
        assert(control.displayedConversation == true && control.snapshot?.conversation == false)
        try await settle()
        assert(!control.message.isEmpty && control.displayedConversation == false && control.pendingConversation == nil,
               "An unconfirmed switch must roll back the displayed selection")
        payload.removeValue(forKey: "error"); payload["attempted"] = false; payload["verified"] = false
        try respond(payload)
        control.refresh(deviceID: 99); try await settle()
        try write("exec /bin/sleep 5")
        control.setMode(.noiseCancellation)
        assert(control.displayedMode == .noiseCancellation)
        try await settle()
        assert(control.unavailable && control.pendingMode == nil && control.displayedMode == .transparency,
               "Timeout must restore the last confirmed selection")
        try respond(payload)
        control.refresh(deviceID: 99); try await settle()
        try write("exec /bin/sleep 5")
        control.setConversation(true); control.cancel()
        assert(!control.busy && control.pendingConversation == nil && control.displayedConversation == nil)
        try respond(payload)
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
        assert(!control.busy && !control.refreshing && control.snapshot == nil && !control.unavailable)
        print("PASS: drag bounds and release selection, optimistic selection, confirmation, rollback, timeout, cancellation, quiet polling, write priority, volume channel fallback; AirPods validation, guarded writes, readback failure, stale device, malformed output, timeout and cancellation")
    }
}
