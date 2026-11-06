import Foundation

/// Reads macOS's health estimate; raw charge-capacity ratios measure something else.
@MainActor final class BatteryCapacityReader {
    private let systemProfilerURL: URL
    private var process: Process?
    private var timeout: DispatchWorkItem?

    init(systemProfilerURL: URL = URL(fileURLWithPath: "/usr/sbin/system_profiler")) {
        self.systemProfilerURL = systemProfilerURL
    }

    /// Overlapping refreshes keep the existing read and its completion.
    func refresh(hasInternalBattery: Bool, completion: @escaping @MainActor (Int?) -> Void) {
        guard hasInternalBattery else { cancel(); completion(nil); return }
        guard process == nil else { return }
        let process = Process(), pipe = Pipe()
        process.executableURL = systemProfilerURL
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini", "-timeout", "2"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; process.environment = environment
        process.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = finished.terminationStatus == 0 ? Self.parse(data) : nil
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.timeout?.cancel(); self.timeout = nil
                self.process = nil
                completion(value)
            }
        }
        self.process = process
        do { try process.run() } catch { self.process = nil; completion(nil); return }
        let timeout = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, self.process === process else { return }
            self.cancel()
            completion(nil)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    func cancel() {
        timeout?.cancel(); timeout = nil
        let previous = process
        process = nil
        if let previous, previous.isRunning { previous.terminate() }
    }

    nonisolated private static func parse(_ data: Data) -> Int? {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = report["SPPowerDataType"] as? [[String: Any]],
              let health = items.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first,
              let text = health["sppower_battery_health_maximum_capacity"] as? String,
              text.hasSuffix("%"), let value = Int(text.dropLast()), (0...100).contains(value) else { return nil }
        return value
    }
}
