import Foundation

struct MediaPlaybackState: Decodable, Equatable {
    let available: Bool
    let playing: Bool
    var isPlaying: Bool { available && playing }
}

@MainActor final class MediaPlayback {
    var update: ((Bool) -> Void)?
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var watchdog: Task<Void, Never>?
    private var lastReply = ProcessInfo.processInfo.systemUptime
    private var enabled = false
    private var playing = false
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
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-MDynaLoader", "-e", "DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();", helper.path]
        child.standardOutput = output
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
        process = child; pipe = output; lastReply = ProcessInfo.processInfo.systemUptime
        do { try child.run() } catch { disconnect() }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty, buffer.count + data.count <= 4096 else { disconnect(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            guard let state = try? JSONDecoder().decode(MediaPlaybackState.self, from: line) else { disconnect(); return }
            buffer.removeSubrange(...newline)
            lastReply = ProcessInfo.processInfo.systemUptime
            publish(state.isPlaying)
        }
    }

    private func publish(_ value: Bool) {
        guard playing != value else { return }
        playing = value; update?(value)
    }

    private func disconnect() {
        let child = process
        process = nil
        pipe?.fileHandleForReading.readabilityHandler = nil
        try? pipe?.fileHandleForReading.close()
        pipe = nil; buffer.removeAll()
        child?.terminationHandler = nil
        if let child, child.isRunning { child.terminate() }
        publish(false)
    }

    func stop() {
        enabled = false
        watchdog?.cancel(); watchdog = nil
        disconnect()
    }
}
