import Testing
import Foundation

struct AirPlayRouteTests {
    @Test
    @MainActor
    func testIdentityCancellationTimeoutRecoveryAndMonitoring() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.RouteCheck.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let token = String(repeating: "a", count: 64)
        var route = AirPlayRoute()
        let first = route.begin(deviceID: 1, target: token)
        let second = route.begin(deviceID: 2, target: token)
        let reply = AirPlayRouteReply(deviceID: 2, target: token, endpointID: "receiver", model: "AppleTV14,1", name: "客厅", canSetVolume: nil)
        #expect(reply.info(for: first) == nil)
        #expect(reply.info(for: second)?.canSetVolume == nil, "Unknown volume capability must stay unknown")
        #expect(AirPlayRouteReply(deviceID: 2, target: token, endpointID: " ", model: "", name: "", canSetVolume: false).info(for: second) == nil)
        #expect(AirPlayRouteReply(deviceID: 2, target: String(repeating: "b", count: 64), endpointID: "receiver", model: "", name: "", canSetVolume: false).info(for: second) == nil)

        func script(_ text: String) throws {
            try ("#!/bin/sh\n" + text).write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        }
        let probe = AirPlayRouteProbe(helperURL: helper, libraryURL: URL(fileURLWithPath: "/usr/lib/libSystem.B.dylib"), timeoutSeconds: 1)
        defer { probe.cancel(); probe.update = nil }
        var updates: [(AirPlayRoute.Request, AirPlayRoute.Info?)] = []
        probe.update = { request, info in updates.append((request, info)); route.record(info, for: request) }
        func settle(_ count: Int) async throws {
            for _ in 0..<100 {
                if updates.count == count { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw NSError(domain: "AirPlayRouteTests.wait", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for helper result \(count)"])
        }
        try script("""
        if [ "$2" = 1 ]; then exec /bin/sleep 2; fi
        printf '{"deviceID":%s,"target":"%s","endpointID":"receiver","model":"AppleTV14,1","name":"客厅","canSetVolume":null}' "$2" "$3"
        """)
        probe.read(first)
        probe.read(second)
        try await settle(1)
        #expect(updates[0].0 == second && route.info?.name == "客厅", "A busy helper must accept the replacement request: \(updates)")
        try await Task.sleep(for: .milliseconds(300))
        #expect(updates.count == 1, "Cancelled helpers and their timeouts must not publish stale results")

        try script("printf '{\"deviceID\":999,\"target\":\"%s\",\"endpointID\":\"wrong\",\"model\":\"AppleTV14,1\",\"name\":\"wrong\"}' \"$3\"")
        probe.read(second)
        try await settle(2)
        #expect(updates[1].1 == nil, "A mismatched reply must fall back")

        try script("exec /bin/sleep 2")
        probe.read(second)
        try await settle(3)
        #expect(updates[2].1 == nil, "Timeout must produce a fallback")
        probe.read(second)
        probe.cancel(); route.clear()
        try await Task.sleep(for: .milliseconds(350))
        #expect(updates.count == 3 && route.info == nil, "Cancellation must not publish any result")

        try script("printf 'not-json'")
        probe.read(second)
        try await settle(4)
        #expect(updates[3].1 == nil)
        try FileManager.default.removeItem(at: helper)
        probe.read(second)
        #expect(updates.count == 5 && updates.last?.1 == nil, "Missing helpers must fail immediately")

        let automatic = AirPlayRouteProbe(helperURL: helper, libraryURL: URL(fileURLWithPath: "/usr/lib/libSystem.B.dylib"),
                                          timeoutSeconds: 1, retryDelays: [0.04, 0.08], refreshInterval: 0.08)
        defer { automatic.cancel(); automatic.update = nil }
        var automaticRoute = AirPlayRoute()
        var automaticUpdates: [(AirPlayRoute.Request, AirPlayRoute.Info?)] = []
        automatic.update = { request, info in
            automaticUpdates.append((request, info))
            automaticRoute.record(info, for: request)
        }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<150 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw NSError(domain: "AirPlayRouteTests.wait", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for automatic route refresh"])
        }
        let attempt = directory.appendingPathComponent("attempt").path
        try script("""
        if [ ! -f "\(attempt)" ]; then /usr/bin/touch "\(attempt)"; exit 1; fi
        printf '{"deviceID":%s,"target":"%s","endpointID":"living-room","model":"AppleTV14,1","name":"客厅","canSetVolume":false}' "$2" "$3"
        """)
        let recovering = automaticRoute.begin(deviceID: 2, target: token)
        automatic.read(recovering, automaticallyRefresh: true)
        try await waitFor { automaticUpdates.count >= 2 }
        #expect(automaticUpdates.count == 2 && automaticUpdates[0].1 == nil && automaticRoute.info?.name == "客厅",
               "A failed first read must recover automatically without changing CoreAudio identity: \(automaticUpdates)")
        try await Task.sleep(for: .milliseconds(200))
        #expect(automaticUpdates.count == 2, "A successful hidden-panel read must stop polling")

        automatic.setMonitoring(true)
        let monitored = automaticRoute.begin(deviceID: 2, target: token)
        automatic.read(monitored, automaticallyRefresh: true)
        try await waitFor { automaticRoute.info?.name == "客厅" }
        try script("printf '{\"deviceID\":%s,\"target\":\"%s\",\"endpointID\":\"study\",\"model\":\"AudioAccessory5,1\",\"name\":\"书房\",\"canSetVolume\":true}' \"$2\" \"$3\"")
        try await waitFor { automaticRoute.info?.endpointID == "study" }
        #expect(automaticRoute.info?.name == "书房" && automaticRoute.info?.family == .homePodMini,
               "Monitoring must replace the receiver name and model even when device ID and UID stay unchanged")

        try script("exit 1")
        try await waitFor { automaticRoute.info == nil }
        #expect(automaticRoute.name(for: 2) == nil, "A failed refresh must remove the old receiver identity")
        try script("printf '{\"deviceID\":%s,\"target\":\"%s\",\"endpointID\":\"living-room\",\"model\":\"AppleTV14,1\",\"name\":\"客厅\"}' \"$2\" \"$3\"")
        try await waitFor { automaticRoute.info?.name == "客厅" }
        automatic.setMonitoring(false)
        let afterClose = automaticUpdates.count
        try await Task.sleep(for: .milliseconds(250))
        #expect(automaticUpdates.count == afterClose, "Closing the panel must stop periodic route reads")

        try script("exit 1")
        let failing = automaticRoute.begin(deviceID: 2, target: token)
        let beforeFailure = automaticUpdates.count
        automatic.read(failing, automaticallyRefresh: true)
        try await waitFor { automaticUpdates.count >= beforeFailure + 3 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(automaticUpdates.count == beforeFailure + 3 && automaticRoute.info == nil,
               "Hidden-panel retries must be bounded when all attempts fail")

        let cancelled = automaticRoute.begin(deviceID: 2, target: token)
        let beforeCancel = automaticUpdates.count
        automatic.read(cancelled, automaticallyRefresh: true)
        try await waitFor { automaticUpdates.count > beforeCancel }
        automatic.cancel(); automaticRoute.clear()
        let afterCancel = automaticUpdates.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(automaticUpdates.count == afterCancel && automaticRoute.info == nil,
               "Leaving AirPlay must cancel scheduled retries as well as running helpers")

        automatic.setMonitoring(true)
        automatic.update = { request, _ in
            automaticUpdates.append((request, nil))
            automatic.cancel() // Store can invalidate the request while publishing its result.
        }
        automatic.read(cancelled, automaticallyRefresh: true)
        try await waitFor { automaticUpdates.count > afterCancel }
        let afterInvalidation = automaticUpdates.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(automaticUpdates.count == afterInvalidation, "An invalidated callback cannot schedule another old read")
    }
}
