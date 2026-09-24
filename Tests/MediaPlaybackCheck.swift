import Foundation

@main struct MediaPlaybackCheck {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--watch" {
            let monitor = MediaPlayback(helper: URL(fileURLWithPath: CommandLine.arguments[2]))
            monitor.update = { print("playing=\($0)") }
            monitor.setEnabled(true)
            try await Task.sleep(for: .seconds(12))
            monitor.stop()
            print("watch stopped")
            return
        }
        let decoder = JSONDecoder()
        for (json, expected) in [
            (#"{"available":true,"playing":true}"#, true),
            (#"{"available":true,"playing":false}"#, false),
            (#"{"available":false,"playing":true}"#, false),
            (#"{"available":false,"playing":false}"#, false)
        ] {
            let state = try decoder.decode(MediaPlaybackState.self, from: Data(json.utf8))
            assert(state.isPlaying == expected)
        }
        for invalid in ["{}", #"{"available":true,"playing":1}"#, #"{"available":true,"playing":null}"#, "not JSON"] {
            assert((try? decoder.decode(MediaPlaybackState.self, from: Data(invalid.utf8))) == nil)
        }
        let missing = MediaPlayback(helper: URL(fileURLWithPath: "/nonexistent/ComboMediaPlayback.dylib"))
        missing.update = { _ in assertionFailure("A missing helper must never manufacture playback") }
        missing.setEnabled(true); missing.setEnabled(true)
        missing.setEnabled(false); missing.stop()
        print("PASS: media status requires valid affirmative data; missing helper and repeated shutdown are safe")
    }
}
