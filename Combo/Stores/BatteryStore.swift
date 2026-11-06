import AppKit
import Combine
import IOKit.ps

@MainActor final class BatteryStore: ObservableObject {
    @Published var level: Double?
    @Published var charging = false
    @Published var plugged = false
    @Published var health = "未提供"
    @Published var maximumCapacity: Int?
    @Published var lowPowerMode = false
    @Published var onAC: Bool?
    @Published var hasInternalBattery = false
    @Published var isCharging: Bool?
    @Published var isCharged: Bool?
    @Published var limitBlocked: Bool?
    @Published var chargeLimit: ChargeLimit = .unknown
    @Published var displayEnabled: Bool {
        didSet {
            defaults.set(displayEnabled, forKey: "batteryDisplayEnabled")
            onDisplayChange?()
        }
    }
    private let defaults: UserDefaults
    private let systemProfilerURL: URL
    let energyApps = EnergyApps()
    let powerMode = PowerModeControl()
    let chargeControl = ChargeControl()
    var onUpdate: (() -> Void)?
    var onPowerChange: (() -> Void)?
    var onDisplayChange: (() -> Void)?
    private var powerChange = PowerChange()
    private var batterySource: CFRunLoopSource?
    private var powerObserver: NSObjectProtocol?
    private var chargeLimitProcess: Process?
    private var chargeLimitTimeout: DispatchWorkItem?
    private var capacityProcess: Process?
    private var capacityTimeout: DispatchWorkItem?
    var monitoringAvailable: Bool { batterySource != nil }
    var sourceText: String { onAC.map { $0 ? L("电源适配器") : L("电池") } ?? L("无法判断") }
    var statusText: String {
        batteryChargeText(onAC: onAC, charging: isCharging, charged: isCharged, limitBlocked: limitBlocked, limit: chargeLimit)
    }
    func canRequestFullCharge(scene: Scene) -> Bool {
        canChargeToFull(scene: scene, onAC: onAC, charging: isCharging,
                        battery: level, limitBlocked: limitBlocked, limit: chargeLimit)
    }
    func requestFullCharge(scene: Scene) {
        guard canRequestFullCharge(scene: scene), case .value(let limit) = chargeLimit else { return }
        chargeControl.request(expectedLimit: limit) { [weak self] in self?.refreshBattery() }
    }
    init(defaults: UserDefaults = .standard, systemProfilerURL: URL = URL(fileURLWithPath: "/usr/sbin/system_profiler")) {
        self.defaults = defaults
        self.systemProfilerURL = systemProfilerURL
        displayEnabled = defaults.object(forKey: "batteryDisplayEnabled") as? Bool ?? true
    }
    func start() {
        batterySource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let battery = Unmanaged<BatteryStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in battery.refreshBattery() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let batterySource { CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .commonModes) }
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        }
    }
    func refreshBattery() {
        hasInternalBattery = false
        level = nil; charging = false; plugged = false
        health = "未提供"
        onAC = nil; isCharging = nil; isCharged = nil; limitBlocked = nil
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            var found = false
            for item in list {
                guard let d = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                found = true
                if let current = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 { level = min(1, Swift.max(0, current / max)) } else { level = nil }
                isCharging = d[kIOPSIsChargingKey] as? Bool
                isCharged = d[kIOPSIsChargedKey] as? Bool
                if let source = d[kIOPSPowerSourceStateKey] as? String {
                    onAC = source == kIOPSACPowerValue ? true : source == kIOPSBatteryPowerValue ? false : nil
                }
                charging = isCharging ?? false
                plugged = onAC ?? false
                if let healthValue = d[kIOPSBatteryHealthKey] as? String {
                    health = healthValue == kIOPSGoodValue ? "良好" : healthValue == kIOPSFairValue ? "一般" : healthValue == kIOPSPoorValue ? "需检修" : "未提供"
                }
            }
            hasInternalBattery = found
            if !found { level = nil }
        }
        let powerChanged = powerChange.update(onAC: onAC)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let data = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let reason = data["NotChargingReason"] as? NSNumber {
                // Community-observed bit (OpenDente BatteryState); absent data stays unknown.
                limitBlocked = reason.uint64Value & 0x1000000 != 0
            }
        }
        refreshChargeLimit()
        refreshMaximumCapacity()
        Task { await powerMode.refresh() }
        chargeControl.refresh()
        onUpdate?()
        if powerChanged { onPowerChange?() }
    }
    nonisolated static func parseMaximumCapacity(_ data: Data) -> Int? {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = report["SPPowerDataType"] as? [[String: Any]],
              let health = items.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first,
              let text = health["sppower_battery_health_maximum_capacity"] as? String,
              text.hasSuffix("%"), let value = Int(text.dropLast()), (0...100).contains(value) else { return nil }
        return value
    }
    func refreshMaximumCapacity() {
        guard hasInternalBattery else { maximumCapacity = nil; return }
        guard capacityProcess == nil else { return }
        // Use macOS's health estimate; raw charge-capacity ratios are not the same measurement.
        let process = Process(), pipe = Pipe()
        process.executableURL = systemProfilerURL
        process.arguments = ["SPPowerDataType", "-json", "-detailLevel", "mini", "-timeout", "2"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; process.environment = environment
        process.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = finished.terminationStatus == 0 ? Self.parseMaximumCapacity(data) : nil
            Task { @MainActor in
                guard let self, self.capacityProcess === finished else { return }
                self.capacityTimeout?.cancel(); self.capacityTimeout = nil
                self.capacityProcess = nil
                self.maximumCapacity = self.hasInternalBattery ? value : nil
            }
        }
        capacityProcess = process
        do { try process.run() } catch { capacityProcess = nil; maximumCapacity = nil; return }
        let timeout = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, self.capacityProcess === process else { return }
            self.maximumCapacity = nil
            self.capacityProcess = nil; self.capacityTimeout = nil
            if process.isRunning { process.terminate() }
        }
        capacityTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }
    private func refreshChargeLimit() {
        guard chargeLimitProcess == nil else { return }
        chargeLimit = .loading
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment; environment["LC_ALL"] = "C"; process.environment = environment
        process.terminationHandler = { [weak self] finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = finished.terminationStatus == 0 ? parseChargeLimit(String(decoding: data, as: UTF8.self)) : .unknown
            Task { @MainActor in
                guard let self, self.chargeLimitProcess === finished else { return }
                self.chargeLimitTimeout?.cancel(); self.chargeLimitTimeout = nil
                self.chargeLimitProcess = nil; self.chargeLimit = result
            }
        }
        chargeLimitProcess = process
        do { try process.run() } catch { chargeLimitProcess = nil; chargeLimit = .unknown; return }
        let timeout = DispatchWorkItem { [weak self, weak process] in
            guard let self, let process, self.chargeLimitProcess === process else { return }
            self.chargeLimit = .unknown
            self.chargeLimitProcess = nil; self.chargeLimitTimeout = nil
            if process.isRunning { process.terminate() }
        }
        chargeLimitTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    }
    func stop() {
        capacityTimeout?.cancel(); capacityTimeout = nil
        if let capacityProcess, capacityProcess.isRunning { capacityProcess.terminate() }
        capacityProcess = nil
        chargeControl.stop()
        energyApps.cancel()
        chargeLimitTimeout?.cancel()
        if let process = chargeLimitProcess, process.isRunning { process.terminate() }
        chargeLimitProcess = nil
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes); CFRunLoopSourceInvalidate(batterySource) }
    }
}
