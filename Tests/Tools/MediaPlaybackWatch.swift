import Foundation

@main struct MediaPlaybackWatch {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--watch" {
            let monitor = MediaPlayback(helper: URL(fileURLWithPath: CommandLine.arguments[2]))
            monitor.update = { print("playing=\($0.playing), track=\($0.track?.title ?? "none")") }
            monitor.setEnabled(true)
            try await Task.sleep(for: .seconds(12))
            monitor.stop()
            print("watch stopped")
            return
        }
    }
}
