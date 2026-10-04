import Foundation
import CoreAudio
import CryptoKit

/// 默认输出身份与 helper 的 DeviceToken 使用同一份 UID SHA-256。
enum AudioOutputIdentity {
    static func target(for deviceID: AudioDeviceID) -> String? {
        guard deviceID != 0 else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: uid))
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue() as String?, !value.isEmpty else { return nil }
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isCurrent(_ request: AirPlayRoute.Request) -> Bool {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout.size(ofValue: id))
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr
            && id == request.deviceID && target(for: id) == request.target
    }
}

/// helper 回复必须属于请求的设备，且包含可确认的接收端身份。
struct AirPlayRouteReply: Decodable, Equatable {
    /// 回显调用进程的 CoreAudio ID；跨进程设备身份由 UID 哈希 target 确认。
    let deviceID: UInt32
    let target: String
    let endpointID: String
    let model: String
    let name: String
    let canSetVolume: Bool?

    func info(for request: AirPlayRoute.Request) -> AirPlayRoute.Info? {
        guard deviceID != 0, deviceID == request.deviceID, target == request.target,
              target.count == 64, target.allSatisfy(\.isHexDigit),
              !endpointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AirPlayRoute.Info(name: name, model: model, canSetVolume: canSetVolume, endpointID: endpointID)
    }
}

/// 隔离私有接口读取；新请求取消旧进程，失效结果、失败和超时统一退回通用 AirPlay。
@MainActor final class AirPlayRouteProbe {
    var update: ((AirPlayRoute.Request, AirPlayRoute.Info?) -> Void)?
    private let helperURL: URL
    private let libraryURL: URL
    private let timeoutSeconds: Double
    private let retryDelays: [Double]
    private let refreshInterval: Double
    private var process: Process?
    private var timeout: DispatchWorkItem?
    private var refreshTask: Task<Void, Never>?
    private var request: AirPlayRoute.Request?
    private var automaticallyRefresh = false
    private var isMonitoring = false
    private var failedReads = 0

    init(helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboAirPodsHelper"),
         libraryURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboAirPodsContext.dylib"),
         timeoutSeconds: Double = 2, retryDelays: [Double] = [0.5, 1, 2], refreshInterval: Double = 3) {
        self.helperURL = helperURL; self.libraryURL = libraryURL; self.timeoutSeconds = timeoutSeconds
        self.retryDelays = retryDelays; self.refreshInterval = refreshInterval
    }

    /// 首次失败有限重试；面板活动时持续确认接收端，覆盖 CoreAudio 身份不变的切换。
    func read(_ request: AirPlayRoute.Request, automaticallyRefresh: Bool = false) {
        cancel()
        self.request = request
        self.automaticallyRefresh = automaticallyRefresh
        runHelper(for: request)
    }

    func setMonitoring(_ active: Bool) {
        isMonitoring = active
        if !active, failedReads == 0 || failedReads > retryDelays.count {
            refreshTask?.cancel(); refreshTask = nil
        }
    }

    private func runHelper(for request: AirPlayRoute.Request) {
        guard self.request == request else { return }
        let child = Process(), pipe = Pipe()
        child.executableURL = helperURL
        child.arguments = ["--route", String(request.deviceID), request.target]
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = libraryURL.path
        child.environment = environment
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let reply = finished.terminationStatus == 0 && data.count <= 8192
                ? try? JSONDecoder().decode(AirPlayRouteReply.self, from: data) : nil
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.finish(request, info: reply?.info(for: request))
            }
        }
        process = child
        do { try child.run() } catch {
            finish(request, info: nil)
            return
        }
        let timeout = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.finish(request, info: nil)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    }

    private func finish(_ request: AirPlayRoute.Request, info: AirPlayRoute.Info?) {
        guard self.request == request else { return }
        stopProcess()
        failedReads = info?.displayName == nil ? failedReads + 1 : 0
        update?(request, info)
        // 回填可能已切换设备并启动新请求，旧请求不能再安排重试。
        guard self.request == request, automaticallyRefresh else { return }
        let delay: Double
        if failedReads > 0, failedReads <= retryDelays.count {
            delay = retryDelays[failedReads - 1]
        } else if isMonitoring {
            delay = refreshInterval
        } else { return }
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.request == request else { return }
            self.refreshTask = nil
            self.runHelper(for: request)
        }
    }

    func cancel() {
        refreshTask?.cancel(); refreshTask = nil
        request = nil; automaticallyRefresh = false; failedReads = 0
        stopProcess()
    }

    private func stopProcess() {
        timeout?.cancel(); timeout = nil
        let previous = process; process = nil
        if let previous, previous.isRunning { kill(previous.processIdentifier, SIGKILL) }
    }
}
