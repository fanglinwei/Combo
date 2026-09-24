import AppKit
import Combine

struct EnergyApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
}

enum EnergyAppsState {
    case loading, unavailable, available([EnergyApp])
}

struct EnergyReply: Decodable {
    let bundle_identifiers: [String]
    let responsible_bundle_identifiers: [String]
    let display_names: [String]
    let energy_impacts: [Double]
    let report_duration: Double

    // Keep source order; the scores are neither watts nor a separate ranking.
    func apps(resolve: (String) -> EnergyApp?) -> [EnergyApp]? {
        let count = bundle_identifiers.count
        guard report_duration == 120,
              responsible_bundle_identifiers.count == count, display_names.count == count,
              energy_impacts.count == count, energy_impacts.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        var result: [EnergyApp] = [], seen = Set<String>()
        for index in bundle_identifiers.indices {
            let responsible = responsible_bundle_identifiers[index]
            let identifier = responsible.isEmpty ? bundle_identifiers[index] : responsible
            // Unknown attribution must not silently become an empty or partial list.
            guard !identifier.isEmpty, let app = resolve(identifier) else { return nil }
            if seen.insert(app.id).inserted { result.append(app) }
        }
        return result
    }
}

@MainActor final class EnergyApps: ObservableObject {
    @Published private(set) var state: EnergyAppsState = .loading
    private let helperURL: URL
    private var process: Process?
    private var timeout: DispatchWorkItem?

    init(helperURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ComboEnergyHelper")) {
        self.helperURL = helperURL
    }
    static func displayLimit(_ value: Int) -> Int { min(3, max(1, value)) }

    func refresh() {
        guard process == nil else { return }
        state = .loading
        let child = Process(), pipe = Pipe()
        child.executableURL = helperURL
        child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] finished in
            // The helper bounds JSON to 8 KiB, below the pipe capacity.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let reply = finished.terminationStatus == 0 ? try? JSONDecoder().decode(EnergyReply.self, from: data) : nil
            Task { @MainActor in
                guard let self, self.process === finished else { return }
                self.timeout?.cancel(); self.timeout = nil; self.process = nil
                let apps = reply?.apps { identifier in
                    // ponytail: only regular running apps are supported; extensions need verified ControlCenter attribution.
                    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                        .first(where: { !$0.isTerminated && $0.activationPolicy == .regular }),
                          let name = app.localizedName, !name.isEmpty else { return nil }
                    return EnergyApp(id: identifier, name: name, icon: app.icon)
                }
                self.state = apps.map(EnergyAppsState.available) ?? .unavailable
            }
        }
        process = child
        do { try child.run() } catch { process = nil; state = .unavailable; return }
        let timeout = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.cancel(); self.state = .unavailable
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }
    func cancel() {
        timeout?.cancel(); timeout = nil
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process = nil
        state = .loading
    }
}
