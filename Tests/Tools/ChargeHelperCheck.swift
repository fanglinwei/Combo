import Foundation

@main struct ChargeHelperCheck {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw NSError(domain: "ChargeHelperCheck", code: 1) }
        let live = ChargeControl(helperURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { live.stop() }
        live.refresh()
        let deadline = Date().addingTimeInterval(15)
        while live.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        assert(!live.busy, "helper must finish or time out")
        assert(live.snapshot != nil, "packaged helper must emit valid JSON, including when unsupported")
        print("Packaged helper: supported=\(live.snapshot?.supported == true), eligible=\(live.snapshot?.canRequest == true)")
    }
}
