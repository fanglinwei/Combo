import AppKit
import Combine

@MainActor final class PowerModeControl: ObservableObject {
    @Published private(set) var policies: [PowerSource: PowerModePolicy] = [:]
    @Published private(set) var busy = false
    @Published private(set) var message: LocalizedText = ""

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        policies = await Self.readPolicies()
    }

    func set(_ mode: PowerMode, source: PowerSource) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // Read again at click time; never write the other power source's policy.
        policies = await Self.readPolicies()
        guard let policy = policies[source], let command = policy.command(source: source, mode: mode) else {
            message = "无法读取此电源类型的模式，请在电池设置中操作。"; return
        }
        guard policy.mode != mode else { message = LocalizedText { L("\(source.title)已设为\(mode.title)。") }; return }
        message = LocalizedText { L("正在请求授权：\(source.title) → \(mode.title)…") }
        // Only enum-derived, fixed command text reaches the privileged shell.
        let prompt = L("Combo：将\(source.title)时的能耗模式设为\(mode.title)。此设置在退出 Combo 后保留。")
        let script = """
        with timeout of 120 seconds
            do shell script "\(command)" with administrator privileges with prompt "\(prompt)"
        end timeout
        """
        let result = await Self.run("/usr/bin/osascript", ["-e", script], timeout: 130)
        policies = await Self.readPolicies()
        if result.status == 0, policies[source]?.mode == mode {
            message = LocalizedText { L("\(source.title)已设为\(mode.title)；退出 Combo 后保留。") }
        } else if result.output.contains("(-128)") {
            message = "已取消授权。"
        } else {
            message = "未能确认模式切换完成，请检查电池设置后重试。"
        }
    }

    private nonisolated static func readPolicies() async -> [PowerSource: PowerModePolicy] {
        let result = await run("/usr/bin/pmset", ["-g", "custom"], timeout: 3)
        return result.status == 0 ? parsePowerModes(result.output) : [:]
    }

    private nonisolated static func run(_ executable: String, _ arguments: [String], timeout: Double) async -> (status: Int32, output: String) {
        await Task.detached {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe; process.standardError = pipe
            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"; process.environment = environment
            do { try process.run() } catch { return (Int32(-1), "") }
            let expiry = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiry)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); expiry.cancel()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
