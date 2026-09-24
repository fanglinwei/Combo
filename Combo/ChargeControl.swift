import Foundation
import Combine

@MainActor final class ChargeControl: ObservableObject {
    @Published private(set) var snapshot: ChargeHelperReply?
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    private let helperURL: URL
    private var process: Process?
    private var requestTask: Task<Void, Never>?
    private var stopped = false

    init(helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboChargeHelper")) {
        self.helperURL = helperURL
    }
    func refresh() {
        guard !busy, !stopped else { return }
        busy = true
        Task {
            let previousState = snapshot?.manualState
            snapshot = await run(["--status"])
            if previousState == 3, snapshot?.manualState == 1 { message = "" }
            busy = false
        }
    }
    func request(expectedLimit: Int, refreshBattery: @escaping () -> Void) {
        guard !busy, !stopped, snapshot?.canRequest == true, snapshot?.limit == expectedLimit else { return }
        busy = true
        message = "正在请求临时解除充电上限…"
        requestTask = Task {
            defer { busy = false; requestTask = nil; if !stopped { refreshBattery() } }
            // The helper rechecks battery and private state immediately before the one write.
            let result = await run(["--charge", String(expectedLimit)])
            guard !Task.isCancelled else { return }
            snapshot = nil
            guard let result, result.accepted, result.attempted, result.supported, result.error == nil else {
                message = result?.error == "not_eligible"
                    ? "电池状态已变化，本次未执行。请重新检查或打开电池设置。"
                    : "未能确认操作结果，系统状态可能已改变。请在电池设置中检查。"
                snapshot = await run(["--status"])
                return
            }
            message = "请求已接受，正在确认是否开始充电…"
            refreshBattery()
            // Observe for about one minute; never retry the mutation automatically.
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                snapshot = await run(["--status"])
                guard !Task.isCancelled else { return }
                guard snapshot != nil else { break }
                if snapshot?.onAC == true, snapshot?.charging == true,
                   snapshot?.manualState == 3, snapshot?.limit == 100 {
                    message = "已确认开始充电。"
                    return
                }
                if snapshot?.onAC == false { break }
            }
            message = "请求已接受，但尚未确认开始充电。请在电池设置中检查。"
        }
    }
    func stop() {
        stopped = true; requestTask?.cancel()
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    private func run(_ arguments: [String]) async -> ChargeHelperReply? {
        guard !stopped, process == nil else { return nil }
        return await withCheckedContinuation { continuation in
            let child = Process(), pipe = Pipe()
            child.executableURL = helperURL; child.arguments = arguments
            child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
            let timeout = DispatchWorkItem { [weak self, weak child] in
                guard let self, let child, self.process === child else { return }
                self.process = nil
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                continuation.resume(returning: nil)
            }
            child.terminationHandler = { [weak self] finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let value = finished.terminationStatus == 0 ? try? JSONDecoder().decode(ChargeHelperReply.self, from: data) : nil
                Task { @MainActor in
                    guard let self, self.process === finished else { return }
                    timeout.cancel(); self.process = nil
                    continuation.resume(returning: value)
                }
            }
            process = child
            do { try child.run() } catch {
                process = nil; continuation.resume(returning: nil); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        }
    }
}
