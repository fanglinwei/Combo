import Foundation

@main struct MediaPlaybackCheck {
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
        let track = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":true,"track":{"title":"Song","artist":"Artist","source":"Music","playing":false,"artwork":"AQID"}}"#.utf8))
        assert(track.track?.title == "Song" && track.track?.artist == "Artist" && track.track?.source == "Music")
        assert(track.track?.playing == false && track.track?.artwork == Data([1, 2, 3]))
        let missingMetadata = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":false,"track":{"title":"","artist":"","source":"Music","playing":false}}"#.utf8))
        let retained = missingMetadata.preservingMetadata(from: track)
        assert(retained.track?.title == "Song" && retained.track?.artist == "Artist" && retained.track?.artwork == Data([1, 2, 3]))
        assert(retained.track?.playing == false)
        let nextSong = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":true,"track":{"title":"Next","artist":"","source":"Music","playing":true}}"#.utf8))
        assert(nextSong.preservingMetadata(from: track).track?.artwork == nil)
        let current = MediaPlaybackState(available: true, playing: true,
                                         track: MediaTrack(title: "Song", artist: "Artist", source: "Music", playing: true, artwork: nil))
        let shown = current.display(previous: nil, metadataAt: 100, now: 100, canSend: true)
        assert(shown.playing && shown.visible && shown.controlsAvailable && shown.track?.title == "Song")
        let unavailable = MediaPlaybackState(available: false, playing: false, track: nil)
        let reconnecting = unavailable.display(previous: shown, metadataAt: 100, now: 102, canSend: true)
        assert(reconnecting.playing && reconnecting.visible && !reconnecting.controlsAvailable && reconnecting.track?.title == "Song")
        let placeholder = unavailable.display(previous: reconnecting, metadataAt: 100, now: 106, canSend: true)
        assert(placeholder.playing && placeholder.visible && placeholder.track == nil && !placeholder.controlsAvailable)
        let paused = MediaPlaybackState(available: true, playing: true,
                                        track: MediaTrack(title: "Song", artist: "Artist", source: "Music", playing: false, artwork: nil))
            .display(previous: placeholder, metadataAt: 106, now: 107, canSend: true)
        assert(!paused.playing && paused.visible && paused.controlsAvailable)
        let stopped = MediaPlaybackState(available: true, playing: false, track: nil)
            .display(previous: paused, metadataAt: 106, now: 108, canSend: true)
        assert(!stopped.playing && !stopped.visible && stopped.track == nil)
        let missing = MediaPlayback(helper: URL(fileURLWithPath: "/nonexistent/ComboMediaPlayback.dylib"))
        missing.update = { assert(!$0.playing && $0.track == nil) }
        missing.setEnabled(true); missing.setEnabled(true)
        missing.setEnabled(false); missing.stop()
        print("PASS: media status requires valid affirmative data; missing helper and repeated shutdown are safe")
    }
}
