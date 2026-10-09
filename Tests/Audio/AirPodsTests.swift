import Testing
import Foundation
import Combine

struct AirPodsTests {
    @Test
    @MainActor
    func testVolumeChannelFallback() async throws {
        #expect(AudioVolume.elements(main: true, preferred: [1, 2], has: { _ in true }) == [0])
        #expect(AudioVolume.elements(main: false, preferred: [], has: { $0 == 1 || $0 == 2 }) == [1, 2])
        #expect(AudioVolume.elements(main: false, preferred: [3, 3, 4], has: { _ in true }) == [3, 4])
        #expect(AudioVolume.elements(main: false, preferred: [], has: { _ in false }).isEmpty)
        #expect(!AudioVolume.set(.nan, device: 0) && !AudioVolume.set(2, device: 0))
    }

    @Test
    @MainActor
    func testDragBoundsAndReleaseSelection() async throws {
        func drag(_ translation: Double, count: Int = 3, selected: Int = 1, x: Double = 150, y: Double = 24) -> Double? {
            airPodsDragPosition(selected: selected, count: count, width: 300,
                                 startX: x, startY: y, translation: translation)
        }
        #expect(drag(-1000) == 0 && drag(1000) == 2, "Dragging must clamp to both ends")
        #expect(try #require(drag(49)).rounded() == 1 && #require(drag(51)).rounded() == 2, "Release selects the nearest center")
        #expect(try drag(0) == 1 && #require(drag(-40)).rounded() == 1, "Returning to the original option must not switch")
        #expect((try #require(drag(90, count: 2, selected: 0, x: 75))).rounded() == 1)
        #expect((try #require(drag(-90, count: 2, selected: 1, x: 225))).rounded() == 0)
        #expect(drag(80, x: 20) == nil && drag(80, y: 60) == nil, "Drag must start on the selected capsule")
        #expect(drag(.nan) == nil && drag(10, count: 1, selected: 0) == nil)
    }

    @Test
    @MainActor
    func testReplyValidationAndBatteryMetadata() async throws {
        var payload: [String: Any] = ["deviceID": 99, "target": String(repeating: "a", count: 64),
            "available": true, "modes": ["transparency", "noise-cancellation"], "mode": "noise-cancellation",
            "canSetMode": true, "conversation": false, "canSetConversation": true,
            "left": 43, "right": 34, "attempted": false, "verified": false]
        func decode(_ payload: [String: Any]) throws -> AirPodsReply {
            try JSONDecoder().decode(AirPodsReply.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        #expect((try decode(payload)).valid)
        #expect((try decode(payload)).batteryText == "左 43% · 右 34%")
        #expect((try decode(payload)).classOfDevice == nil, "Older helpers may omit Class of Device")
        for value: UInt32 in [1, 0x240418, 0xffffff] {
            var classified = payload; classified["classOfDevice"] = value
            let reply = try decode(classified)
            #expect(reply.valid && reply.classOfDevice == value)
        }
        for value: UInt32 in [0, 0x1000000, .max] {
            var broken = payload; broken["classOfDevice"] = value
            let reply = try decode(broken)
            #expect(!reply.valid)
        }
        var unknown = payload; unknown["classOfDevice"] = NSNull()
        let unknownReply = try decode(unknown)
        #expect(unknownReply.valid && unknownReply.classOfDevice == nil)
        for value: Any in [-1, 0x100000000 as UInt64, true, "0x240418"] {
            var broken = payload; broken["classOfDevice"] = value
            #expect((try? decode(broken)) == nil, "Malformed Class of Device must fail decoding")
        }
        for invalid in [0, 101, -1] {
            var broken = payload; broken["left"] = invalid
            #expect(!(try decode(broken)).valid)
        }
        var broken = payload; broken["conversation"] = NSNull()
        #expect(!(try decode(broken)).valid)
        broken = payload; broken["target"] = "stale"
        #expect(!(try decode(broken)).valid)
        broken = payload; broken["modes"] = ["transparency", "transparency"]
        #expect(!(try decode(broken)).valid)
    }

    @Test
    @MainActor
    func testHelperIdentityReadbackWritesRollbackTimeoutAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.AirPodsTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var payload: [String: Any] = ["deviceID": 99, "target": String(repeating: "a", count: 64),
            "available": true, "modes": ["transparency", "noise-cancellation"], "mode": "noise-cancellation",
            "canSetMode": true, "conversation": false, "canSetConversation": true,
            "left": 43, "right": 34, "attempted": false, "verified": false]
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
        defer { control.cancel() }
        func settle() async throws {
            for _ in 0..<100 {
                if !control.busy && !control.refreshing { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw NSError(domain: "AirPodsTests.wait", code: 1, userInfo: [NSLocalizedDescriptionKey: "helper did not settle"])
        }
        try respond(payload)
        control.refresh(deviceID: 99)
        #expect(!control.busy, "Background polling must not disable and dim the AirPods controls")
        try await settle()
        #expect(control.snapshot?.mode == .noiseCancellation && !control.unavailable)
        let target = String(repeating: "a", count: 64)
        let statusJSON = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        try write("test \"$1\" = --status && test \"$2\" = 99 && test \"$3\" = '" + target + "' || exit 1\nprintf '%s' '" + statusJSON + "'")
        control.refresh(deviceID: 99, target: target)
        try await settle()
        #expect(control.snapshot?.deviceID == 99 && !control.unavailable, "Status reads must pass the caller ID and stable UID to the helper")
        var otherDevice = payload; otherDevice["target"] = String(repeating: "b", count: 64)
        try respond(otherDevice)
        control.refresh(deviceID: 99, target: target)
        try await settle()
        #expect(control.snapshot == nil && control.unavailable, "A reused numeric ID must not accept another device's UID")
        try respond(payload)
        control.refresh(deviceID: 99, target: target)
        try await settle()
        var changes = 0
        let observation = control.objectWillChange.sink { changes += 1 }
        defer { observation.cancel() }
        for _ in 0..<3 {
            control.refresh(deviceID: 99)
            #expect(!control.busy && control.snapshot?.mode == .noiseCancellation)
            try await settle()
        }
        #expect(changes == 0, "Unchanged background reads must not publish UI updates")
        observation.cancel()
        control.setMode(.noiseCancellation); #expect(!control.busy, "same value must not write")
        control.setMode(.off); #expect(!control.busy, "unsupported mode must not write")
        payload["attempted"] = true; payload["verified"] = true; payload["mode"] = "transparency"
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        try write("if [ \"$1\" = \"--status\" ]; then exec /bin/sleep 5; fi\nprintf '%s' '" + json + "'")
        control.refresh(deviceID: 99)
        #expect(control.refreshing && !control.busy)
        control.setMode(.transparency)
        #expect(control.busy && !control.refreshing, "User writes must take priority over background reads")
        #expect(control.displayedMode == .transparency && control.snapshot?.mode == .noiseCancellation,
               "Move selection immediately without claiming the device has confirmed it")
        control.setConversation(true)
        #expect(control.busy && control.pendingConversation == nil && control.pendingMode == .transparency,
               "A second write must not replace the pending selection")
        try await settle()
        #expect(control.snapshot?.mode == .transparency && control.pendingMode == nil && control.message.isEmpty)
        payload["verified"] = false; payload["error"] = "unconfirmed"
        try respond(payload)
        control.setConversation(true)
        #expect(control.displayedConversation == true && control.snapshot?.conversation == false)
        try await settle()
        #expect(!control.message.isEmpty && control.displayedConversation == false && control.pendingConversation == nil,
               "An unconfirmed switch must roll back the displayed selection")
        payload.removeValue(forKey: "error"); payload["attempted"] = false; payload["verified"] = false
        try respond(payload)
        control.refresh(deviceID: 99); try await settle()
        try write("exec /bin/sleep 5")
        control.setMode(.noiseCancellation)
        #expect(control.displayedMode == .noiseCancellation)
        try await settle()
        #expect(control.unavailable && control.pendingMode == nil && control.displayedMode == .transparency,
               "Timeout must restore the last confirmed selection")
        try respond(payload)
        control.refresh(deviceID: 99); try await settle()
        try write("exec /bin/sleep 5")
        control.setConversation(true); control.cancel()
        #expect(!control.busy && control.pendingConversation == nil && control.displayedConversation == nil)
        try respond(payload)
        control.refresh(deviceID: 100); try await settle()
        #expect(control.snapshot == nil && control.unavailable, "stale output must not be displayed")
        try write("echo '{}'")
        control.refresh(deviceID: 99); try await settle()
        #expect(control.snapshot == nil && control.unavailable)
        try write("exit 1")
        control.refresh(deviceID: 99); try await settle()
        #expect(control.unavailable)
        try write("exec /bin/sleep 5")
        control.refresh(deviceID: 99); try await settle()
        #expect(control.unavailable && !control.busy)
        control.refresh(deviceID: 99); control.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!control.busy && !control.refreshing && control.snapshot == nil && !control.unavailable)
    }
}
