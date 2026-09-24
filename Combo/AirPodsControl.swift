import Foundation
import Combine

enum ListeningMode: String, CaseIterable, Codable, Identifiable {
    case transparency, adaptive, noiseCancellation = "noise-cancellation", off
    var id: String { rawValue }
    var title: String {
        switch self { case .transparency: "通透模式"; case .adaptive: "自适应"; case .noiseCancellation: "降噪"; case .off: "关闭" }
    }
}

struct AirPodsReply: Decodable {
    let deviceID: UInt32
    let target: String
    let available: Bool
    let modes: [ListeningMode]
    let mode: ListeningMode?
    let canSetMode: Bool
    let conversation: Bool?
    let canSetConversation: Bool
    let left: Int?
    let right: Int?
    let caseBattery: Int?
    let single: Int?
    let attempted: Bool
    let verified: Bool
    let error: String?

    var valid: Bool {
        guard target.isEmpty || (target.count == 64 && target.allSatisfy({ $0.isHexDigit })),
              !available || (deviceID != 0 && target.count == 64), Set(modes).count == modes.count,
              [left, right, caseBattery, single].compactMap({ $0 }).allSatisfy({ (1...100).contains($0) }),
              !canSetMode || (available && !modes.isEmpty),
              !canSetConversation || (available && conversation != nil) else { return false }
        return true
    }
    var batteryText: String {
        let parts: [(String, Int?)] = [("左", left), ("右", right), ("充电盒", caseBattery)]
        let values = parts.compactMap { name, value in value.map { "\(name) \($0)%" } }
        if !values.isEmpty { return values.joined(separator: " · ") }
        return single.map { "电量 \($0)%" } ?? "电量暂不可用"
    }
}

@MainActor final class AirPodsControl: ObservableObject {
    @Published private(set) var snapshot: AirPodsReply?
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var unavailable = false
    private let helperURL: URL
    private let libraryURL: URL
    private let timeoutSeconds: Double
    private var process: Process?
    private var timeout: DispatchWorkItem?

    init(helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboAirPodsHelper"),
         libraryURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboAirPodsContext.dylib"),
         timeoutSeconds: Double = 5) {
        self.helperURL = helperURL; self.libraryURL = libraryURL; self.timeoutSeconds = timeoutSeconds
    }
    func refresh(deviceID: UInt32) {
        run(["--status"], deviceID: deviceID, mutation: false)
    }
    func setMode(_ mode: ListeningMode) {
        guard let snapshot, snapshot.canSetMode, snapshot.modes.contains(mode), snapshot.mode != mode else { return }
        write("--mode", mode.rawValue, snapshot: snapshot)
    }
    func setConversation(_ enabled: Bool) {
        guard let snapshot, snapshot.canSetConversation, snapshot.conversation != enabled else { return }
        write("--conversation", enabled ? "on" : "off", snapshot: snapshot)
    }
    private func write(_ command: String, _ value: String, snapshot: AirPodsReply) {
        guard !busy, !unavailable else { return }
        run([command, value, String(snapshot.deviceID), snapshot.target], deviceID: snapshot.deviceID, mutation: true)
    }
    private func run(_ arguments: [String], deviceID: UInt32, mutation: Bool) {
        guard process == nil else { return }
        busy = true
        if mutation { message = "正在确认耳机状态…" }
        let child = Process(), pipe = Pipe()
        child.executableURL = helperURL; child.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = libraryURL.path
        child.environment = environment
        child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let reply = finished.terminationStatus == 0 && data.count <= 8192 ? try? JSONDecoder().decode(AirPodsReply.self, from: data) : nil
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.timeout?.cancel(); self.timeout = nil; self.process = nil; self.busy = false
                guard let reply, reply.valid, reply.deviceID == deviceID else {
                    self.snapshot = nil; self.unavailable = true
                    if mutation { self.message = "未能确认结果，请刷新或在声音设置中检查。" }
                    return
                }
                self.snapshot = reply; self.unavailable = reply.error != nil
                if mutation {
                    self.message = reply.verified && reply.attempted && reply.error == nil ? "" :
                        reply.error == "device_changed" ? "输出设备已变化，请重新选择。" : "耳机未确认切换，请重试或在声音设置中检查。"
                }
            }
        }
        process = child
        do { try child.run() } catch {
            process = nil; busy = false; snapshot = nil; unavailable = true
            if mutation { message = "耳机控制暂不可用。" }
            return
        }
        let timeout = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.cancel(); self.unavailable = true
            if mutation { self.message = "确认超时，请刷新或在声音设置中检查。" }
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    }
    func cancel() {
        timeout?.cancel(); timeout = nil
        let previous = process; process = nil
        if let previous, previous.isRunning { kill(previous.processIdentifier, SIGKILL) }
        busy = false; snapshot = nil; unavailable = false; message = ""
    }
}
