import Testing
import Foundation

@MainActor struct BatteryCapacityTests {
    @Test
    func testMaximumCapacityUsesValidatedHealthReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.CapacityTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("system_profiler")
        try """
        #!/bin/sh
        [ "$LC_ALL" = C ] || exit 1
        [ "$*" = 'SPPowerDataType -json -detailLevel mini -timeout 2' ] || exit 2
        exec /bin/cat "$0.json"
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let reader = BatteryCapacityReader(systemProfilerURL: helper)
        defer { reader.cancel() }
        @MainActor func read(_ data: Data) async throws -> Int? {
            try data.write(to: URL(fileURLWithPath: helper.path + ".json"))
            var completed = false
            var capacity: Int?
            reader.refresh(hasInternalBattery: true) { capacity = $0; completed = true }
            for _ in 0..<100 where !completed { try await Task.sleep(for: .milliseconds(20)) }
            try #require(completed, "Reader must complete each report")
            return capacity
        }
        func report(_ value: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["SPPowerDataType": [
                ["sppower_battery_health_info": ["sppower_battery_health_maximum_capacity": value]],
                ["sppower_ac_charger_watts": 70]
            ]])
        }
        for value in [0, 91, 100] {
            #expect(try await read(report("\(value)%")) == value)
        }
        for value: Any in ["91", "-1%", "101%", "91.5%", "NaN%", 91, NSNull()] {
            #expect(try await read(report(value)) == nil)
        }
        #expect(try await read(Data("{}".utf8)) == nil)
        #expect(try await read(Data("not JSON".utf8)) == nil)
    }

    @Test
    func testReadFailuresTimeoutCancellationAndBatteryRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.CapacityTests.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("system_profiler")
        func write(_ body: String) throws {
            try ("#!/bin/sh\n" + body + "\n").write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        }
        let report = #"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"91%"}}]}"#
        let reader = BatteryCapacityReader(systemProfilerURL: helper)
        defer { reader.cancel() }
        var replies: [Int?] = []
        @MainActor func refresh(hasInternalBattery: Bool = true) {
            reader.refresh(hasInternalBattery: hasInternalBattery) { replies.append($0) }
        }
        @MainActor func waitForReply(_ count: Int, capacity: Int?) async throws {
            for _ in 0..<200 where replies.count < count { try await Task.sleep(for: .milliseconds(20)) }
            try #require(replies.count == count, "Reader must deliver exactly one reply per completed read")
            #expect(replies[count - 1] == capacity)
        }
        try write("echo read >> \"$0.calls\"\nsleep 0.05\necho '\(report)'")
        refresh()
        refresh()
        try await waitForReply(1, capacity: 91)
        #expect(try String(contentsOfFile: helper.path + ".calls", encoding: .utf8) == "read\n",
                "Overlapping refreshes must share one read")
        for body in ["echo '\(report)'\nexit 1", "echo '{}'", "exec /bin/sleep 30"] {
            try write(body)
            let count = replies.count + 1
            refresh()
            try await waitForReply(count, capacity: nil)
        }
        try write("exec /bin/sleep 30")
        refresh()
        reader.cancel()
        try write("echo '\(report)'")
        let countAfterCancel = replies.count + 1
        refresh()
        try await waitForReply(countAfterCancel, capacity: 91)
        try await Task.sleep(for: .milliseconds(100))
        #expect(replies.count == countAfterCancel, "A cancelled read must not complete after its replacement")

        try FileManager.default.removeItem(at: helper)
        let countAfterMissingReader = replies.count + 1
        refresh()
        try await waitForReply(countAfterMissingReader, capacity: nil)

        try write("sleep 0.1\necho '\(report)'")
        refresh()
        let countAfterRemoval = replies.count + 1
        refresh(hasInternalBattery: false)
        try await waitForReply(countAfterRemoval, capacity: nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(replies.count == countAfterRemoval, "A missing battery must cancel the in-flight read")
    }
}
