import Testing
import Foundation

struct MediaPlaybackTests {
    @Test
    @MainActor
    func testReplyValidationAndMetadataPreservation() async throws {
        let decoder = JSONDecoder()
        for (json, expected) in [
            (#"{"available":true,"playing":true}"#, true),
            (#"{"available":true,"playing":false}"#, false),
            (#"{"available":false,"playing":true}"#, false),
            (#"{"available":false,"playing":false}"#, false)
        ] {
            let state = try decoder.decode(MediaPlaybackState.self, from: Data(json.utf8))
            #expect(state.isPlaying == expected)
        }
        for invalid in ["{}", #"{"available":true,"playing":1}"#, #"{"available":true,"playing":null}"#, "not JSON"] {
            #expect((try? decoder.decode(MediaPlaybackState.self, from: Data(invalid.utf8))) == nil)
        }
        let track = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":true,"track":{"title":"Song","artist":"Artist","source":"Music","bundleIdentifier":"com.apple.Music","playing":false,"artwork":"AQID"}}"#.utf8))
        #expect(track.track?.title == "Song" && track.track?.artist == "Artist" && track.track?.source == "Music")
        #expect(track.track?.bundleIdentifier == "com.apple.Music")
        #expect(track.track?.playing == false && track.track?.artwork == Data([1, 2, 3]))
        let missingMetadata = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":false,"track":{"title":"","artist":"","source":"Music","playing":false}}"#.utf8))
        let retained = missingMetadata.preservingMetadata(from: track)
        #expect(retained.track?.title == "Song" && retained.track?.artist == "Artist" && retained.track?.artwork == Data([1, 2, 3]))
        #expect(retained.track?.playing == false && retained.track?.bundleIdentifier == nil)
        let nextSong = try decoder.decode(MediaPlaybackState.self, from: Data(#"{"available":true,"playing":true,"track":{"title":"Next","artist":"","source":"Music","playing":true}}"#.utf8))
        #expect(nextSong.preservingMetadata(from: track).track?.artwork == nil)
    }

    @Test
    @MainActor
    func testDisplayExpiryAndPlaybackStates() async throws {
        let current = MediaPlaybackState(available: true, playing: true,
                                         track: MediaTrack(title: "Song", artist: "Artist", source: "Music", bundleIdentifier: "com.apple.Music", playing: true, artwork: nil))
        let shown = current.display(previous: nil, metadataAt: 100, now: 100, canSend: true)
        #expect(shown.playing && shown.visible && shown.controlsAvailable && shown.track?.title == "Song")
        let unavailable = MediaPlaybackState(available: false, playing: false, track: nil)
        let reconnecting = unavailable.display(previous: shown, metadataAt: 100, now: 102, canSend: true)
        #expect(reconnecting.playing && reconnecting.visible && !reconnecting.controlsAvailable && reconnecting.track?.title == "Song")
        let placeholder = unavailable.display(previous: reconnecting, metadataAt: 100, now: 106, canSend: true)
        #expect(placeholder.playing && placeholder.visible && placeholder.track == nil && !placeholder.controlsAvailable)
        let paused = MediaPlaybackState(available: true, playing: true,
                                        track: MediaTrack(title: "Song", artist: "Artist", source: "Music", bundleIdentifier: "com.apple.Music", playing: false, artwork: nil))
            .display(previous: placeholder, metadataAt: 106, now: 107, canSend: true)
        #expect(!paused.playing && paused.visible && paused.controlsAvailable)
        let stopped = MediaPlaybackState(available: true, playing: false, track: nil)
            .display(previous: paused, metadataAt: 106, now: 108, canSend: true)
        #expect(!stopped.playing && !stopped.visible && stopped.track == nil)
    }

    @Test
    @MainActor
    func testMissingHelperAndRepeatedShutdown() async throws {
        let missing = MediaPlayback(helper: URL(fileURLWithPath: "/nonexistent/ComboMediaPlayback.dylib"))
        missing.update = { #expect(!$0.playing && $0.track == nil) }
        missing.setEnabled(true); missing.setEnabled(true)
        missing.setEnabled(false); missing.stop()
    }
}
