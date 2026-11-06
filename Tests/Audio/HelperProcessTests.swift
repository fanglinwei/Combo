import Testing
import Foundation

private final class HelperTestResources: NSObject {}

struct HelperProcessTests {
    @Test
    func testMediaPlaybackHelper() async throws {
        try await check("MediaPlaybackHelperCheck", message: "PASS: all-client aggregation")
    }

    @Test
    func testAirPlayHelper() async throws {
        try await check("AirPlayHelperCheck", message: "PASS: AirPods status and writes")
    }

    private func check(_ name: String, message: String) async throws {
        let resources = try #require(Bundle(for: HelperTestResources.self).resourceURL)
        let executable = resources.appendingPathComponent("Helpers/\(name)")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("Combo.HelperTests.\(UUID()).log")
        try Data().write(to: log)
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable
        process.standardOutput = output
        process.standardError = output
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            do { Attachment.record(try Data(contentsOf: log), named: "\(name).log") }
            catch { Issue.record(error) }
        }
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning else {
            Issue.record("\(name) did not finish within 20 seconds")
            return
        }
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(process.terminationReason == .exit, Comment(rawValue: text))
        #expect(process.terminationStatus == 0, Comment(rawValue: text))
        #expect(text.contains(message), Comment(rawValue: text))
    }
}
