import Foundation

struct MediaTrack: Decodable, Equatable {
    let title: String
    let artist: String
    let source: String
    let bundleIdentifier: String?
    let playing: Bool
    let artwork: Data?
}

struct MediaPlaybackState: Decodable, Equatable {
    let available: Bool
    let playing: Bool
    let track: MediaTrack?
    var isPlaying: Bool { available && playing }
    func preservingMetadata(from previous: Self?) -> Self {
        guard let old = previous?.track, let track, old.source == track.source else { return self }
        let title = track.title.isEmpty ? old.title : track.title
        let sameTitle = title == old.title
        let merged = MediaTrack(title: title, artist: track.artist.isEmpty && sameTitle ? old.artist : track.artist,
                                source: track.source, bundleIdentifier: track.bundleIdentifier, playing: track.playing,
                                artwork: sameTitle ? track.artwork ?? old.artwork : track.artwork)
        return Self(available: available, playing: playing, track: merged)
    }
    func display(previous: MediaPlaybackViewState?, metadataAt: TimeInterval, now: TimeInterval, canSend: Bool) -> MediaPlaybackViewState {
        let current = track != nil
        let known = available || current
        let visible = known ? (current || playing) : (previous?.visible ?? false)
        let playing = known ? (track?.playing ?? self.playing) : (previous?.playing ?? false)
        let recent = now - metadataAt < 5
        let old = previous?.track
        let merged = preservingMetadata(from: recent ? Self(available: true, playing: playing, track: old) : nil).track
        return MediaPlaybackViewState(playing: playing, visible: visible,
                                      track: visible ? (merged ?? (recent ? old : nil)) : nil,
                                      controlsAvailable: current && canSend)
    }
}

struct MediaPlaybackViewState: Equatable {
    let playing: Bool
    let visible: Bool
    let track: MediaTrack?
    let controlsAvailable: Bool
}

enum MediaCommand: UInt8 { case previous = 98, toggle = 116, next = 110 }

@MainActor final class MediaPlayback {
    var update: ((MediaPlaybackViewState) -> Void)?
    private var process: Process?
    private var pipe: Pipe?
    private var input: Pipe?
    private var buffer = Data()
    private var watchdog: Task<Void, Never>?
    private var metadataExpiry: Task<Void, Never>?
    private var lastReply = ProcessInfo.processInfo.systemUptime
    private var enabled = false
    private var state: MediaPlaybackViewState?
    private var lastMetadataAt: TimeInterval = 0
    private let helper: URL?

    init(helper: URL? = Bundle.main.executableURL?.deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Helpers/ComboMediaPlayback.dylib")) {
        self.helper = helper
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value { stop(); return }
        launch()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.enabled else { return }
                if self.process != nil && ProcessInfo.processInfo.systemUptime - self.lastReply > 5 {
                    self.disconnect()
                }
                if self.process == nil { self.launch() }
            }
        }
    }

    private func launch() {
        guard enabled, process == nil, let helper, FileManager.default.fileExists(atPath: helper.path) else { return }
        let child = Process(), output = Pipe(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-MDynaLoader", "-e", "my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error(); my $s = DynaLoader::dl_find_symbol($h, 'combo_media_stream') or die 'missing entry'; DynaLoader::dl_install_xsub('main::entry', $s); main::entry();", helper.path]
        child.standardOutput = output
        child.standardInput = input
        child.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                self.receive(data)
            }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.disconnect()
            }
        }
        process = child; pipe = output; self.input = input; lastReply = ProcessInfo.processInfo.systemUptime
        do { try child.run() } catch { disconnect() }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty, buffer.count + data.count <= 1024 * 1024 else { disconnect(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            guard let state = try? JSONDecoder().decode(MediaPlaybackState.self, from: line) else { disconnect(); return }
            buffer.removeSubrange(...newline)
            lastReply = ProcessInfo.processInfo.systemUptime
            publish(state)
        }
    }

    private func publish(_ value: MediaPlaybackState) {
        let now = ProcessInfo.processInfo.systemUptime
        if let title = value.track?.title, !title.isEmpty { lastMetadataAt = now }
        let next = value.display(previous: state, metadataAt: lastMetadataAt, now: now, canSend: input != nil)
        if value.track != nil || next.track == nil {
            metadataExpiry?.cancel(); metadataExpiry = nil
        } else if metadataExpiry == nil {
            let delay = max(0, 5 - (now - lastMetadataAt))
            metadataExpiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                self?.metadataExpiry = nil
                self?.publish(MediaPlaybackState(available: false, playing: false, track: nil))
            }
        }
        if !next.visible { lastMetadataAt = 0 }
        guard state != next else { return }
        state = next; update?(next)
    }

    func command(_ command: MediaCommand) {
        guard state?.controlsAvailable == true, let input else { return }
        do { try input.fileHandleForWriting.write(contentsOf: Data([command.rawValue])) }
        catch { disconnect() }
    }

    private func disconnect() {
        let child = process
        process = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? pipe?.fileHandleForReading.close()
        pipe = nil; buffer.removeAll()
        try? input?.fileHandleForWriting.close()
        input = nil
        child?.terminationHandler = nil
        if let child, child.isRunning { child.terminate() }
        if enabled { publish(MediaPlaybackState(available: false, playing: false, track: nil)) }
        else {
            metadataExpiry?.cancel(); metadataExpiry = nil
            lastMetadataAt = 0; state = nil
            update?(MediaPlaybackViewState(playing: false, visible: false, track: nil, controlsAvailable: false))
        }
    }

    func stop() {
        enabled = false
        watchdog?.cancel(); watchdog = nil
        disconnect()
    }
}
