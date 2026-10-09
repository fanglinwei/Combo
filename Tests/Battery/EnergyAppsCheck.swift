import Foundation

@main struct EnergyAppsCheck {
    @MainActor static func main() async throws {
        func reply(_ ids: [String], responsible: [String]? = nil, duration: Double = 120) -> EnergyReply {
            EnergyReply(bundle_identifiers: ids, responsible_bundle_identifiers: responsible ?? ids.map { _ in "" },
                        display_names: ids.map { _ in "" }, energy_impacts: ids.map { _ in 100 }, report_duration: duration)
        }
        let resolve: (String) -> EnergyApp? = { $0 == "unknown" ? nil : EnergyApp(id: $0, name: $0, icon: nil) }
        assert(reply([]).apps(resolve: resolve)?.isEmpty == true)
        let apps = reply(["b", "helper", "b", "c"], responsible: ["", "a", "", ""]).apps(resolve: resolve)!
        assert(apps.map(\.id) == ["b", "a", "c"])
        assert(reply(["unknown"]).apps(resolve: resolve) == nil)
        assert(reply([""]).apps(resolve: resolve) == nil)
        assert(reply(["a"], responsible: []).apps(resolve: resolve) == nil)
        assert(reply([], duration: 0).apps(resolve: resolve) == nil)
        assert(EnergyApps.displayLimit(0) == 1 && EnergyApps.displayLimit(5) == 3)
        for limit in 1...3 { assert(apps.prefix(EnergyApps.displayLimit(limit)).count == limit) }
        assert((try? JSONDecoder().decode(EnergyReply.self, from: Data("{}".utf8))) == nil)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("helper")
        func write(_ body: String) throws {
            try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        let control = EnergyApps(helperURL: script)
        func settle() async throws {
            for _ in 0..<100 {
                if case .loading = control.state { try await Task.sleep(for: .milliseconds(100)) } else { return }
            }
            assertionFailure("helper did not finish within deadline")
        }
        try write("echo '{\"bundle_identifiers\":[],\"responsible_bundle_identifiers\":[],\"display_names\":[],\"energy_impacts\":[],\"report_duration\":120}'")
        control.refresh(); try await settle()
        guard case .available(let empty) = control.state, empty.isEmpty else { fatalError("empty source failed") }
        try write("echo '{}'")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { fatalError("malformed response became empty") }
        try write("exit 1")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { fatalError("failed helper became empty") }
        try write("exec /bin/sleep 30")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { fatalError("timeout did not fail") }
        control.refresh(); control.cancel()
        try write("echo '{}'")
        control.refresh(); try await settle()
        guard case .unavailable = control.state else { fatalError("cancelled result overwrote new request") }
        control.cancel()
        try FileManager.default.removeItem(at: script)
        control.refresh()
        guard case .unavailable = control.state else { fatalError("missing helper did not fail") }
        print("Energy apps: source validation, order, attribution, limits, failure, timeout and cancellation passed")
    }
}
