import Testing
import Foundation

struct EnergyAppsTests {
    @Test
    @MainActor
    func testAttributionValidationAndLimits() async throws {
        func reply(_ ids: [String], responsible: [String]? = nil, duration: Double = 120) -> EnergyReply {
            EnergyReply(bundle_identifiers: ids, responsible_bundle_identifiers: responsible ?? ids.map { _ in "" },
                        display_names: ids.map { _ in "" }, energy_impacts: ids.map { _ in 100 }, report_duration: duration)
        }
        let resolve: (String) -> EnergyApp? = { $0 == "unknown" ? nil : EnergyApp(id: $0, name: $0, icon: nil) }
        #expect(reply([]).apps(resolve: resolve)?.isEmpty == true)
        let apps = try #require(reply(["b", "helper", "b", "c"], responsible: ["", "a", "", ""]).apps(resolve: resolve))
        #expect(apps.map(\.id) == ["b", "a", "c"])
        #expect(reply(["unknown"]).apps(resolve: resolve) == nil)
        #expect(reply([""]).apps(resolve: resolve) == nil)
        #expect(reply(["a"], responsible: []).apps(resolve: resolve) == nil)
        #expect(reply([], duration: 0).apps(resolve: resolve) == nil)
        #expect(EnergyApps.displayLimit(0) == 1 && EnergyApps.displayLimit(5) == 3)
        for limit in 1...3 { #expect(apps.prefix(EnergyApps.displayLimit(limit)).count == limit) }
        #expect((try? JSONDecoder().decode(EnergyReply.self, from: Data("{}".utf8))) == nil)
    }

    @Test
    @MainActor
    func testHelperFailuresTimeoutAndCancellation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("helper")
        func write(_ body: String) throws {
            try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        let control = EnergyApps(helperURL: script)
        defer { control.cancel() }
        func settle() async throws {
            for _ in 0..<100 {
                if case .loading = control.state { try await Task.sleep(for: .milliseconds(100)) } else { return }
            }
            Issue.record("helper did not finish within deadline")
            throw NSError(domain: "EnergyAppsTests", code: 1)
        }
        try write("echo '{\"bundle_identifiers\":[],\"responsible_bundle_identifiers\":[],\"display_names\":[],\"energy_impacts\":[],\"report_duration\":120}'")
        control.refresh(); try await settle()
        guard case .available(let empty) = control.state, empty.isEmpty else { Issue.record("empty source failed"); return }
        try write("echo '{}'")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { Issue.record("malformed response became empty"); return }
        try write("exit 1")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { Issue.record("failed helper became empty"); return }
        try write("exec /bin/sleep 30")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { Issue.record("timeout did not fail"); return }
        control.refresh(); control.cancel()
        try write("echo '{}'")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { Issue.record("cancelled result overwrote new request"); return }
        control.cancel()
        try FileManager.default.removeItem(at: script)
        control.refresh()
        guard case .unavailable = control.state else { Issue.record("missing helper did not fail"); return }
    }
}
