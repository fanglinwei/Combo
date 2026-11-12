import Foundation
import Combine
import CoreBluetooth

@MainActor final class BluetoothPermission: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var authorization = CBManager.authorization
    private var manager: CBCentralManager?

    /// 请求时刻：面板据此认出"这次失焦是蓝牙弹窗造成的"，不当成点了面板外面。
    var askedAt: TimeInterval?
    var isRequestingPermission: Bool { askedAt != nil && CBManager.authorization == .notDetermined }
    func request() {
        guard authorization == .notDetermined, manager == nil else { return }
        askedAt = ProcessInfo.processInfo.systemUptime
        manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    func refresh() { authorization = CBManager.authorization }
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
}

enum ListeningMode: String, CaseIterable, Codable, Identifiable {
    case transparency, adaptive, noiseCancellation = "noise-cancellation", off
    var id: String { rawValue }
    var title: String {
        switch self { case .transparency: L("通透模式"); case .adaptive: L("自适应"); case .noiseCancellation: L("降噪"); case .off: L("关闭") }
    }
}

// Return a fractional option index; the gesture commits its nearest index only on release.
func airPodsDragPosition(selected: Int?, count: Int, width: Double,
                         startX: Double, startY: Double, translation: Double) -> Double? {
    guard let selected, count > 1, (0..<count).contains(selected),
          width.isFinite, width > 0, startX.isFinite, startY.isFinite, translation.isFinite else { return nil }
    let column = width / Double(count)
    guard (3...34).contains(startY), abs(startX - column * (Double(selected) + 0.5)) <= column / 2 - 3 else { return nil }
    return min(Double(count - 1), max(0, Double(selected) + translation / column))
}

struct AirPodsReply: Decodable, Equatable {
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
    let classOfDevice: UInt32?
    let attempted: Bool
    let verified: Bool
    let error: String?
    var vendorID: UInt32?
    var productID: UInt32?
    var deviceName: String?
    var leftCharge: AudioChargeState?
    var rightCharge: AudioChargeState?
    var caseCharge: AudioChargeState?
    var singleCharge: AudioChargeState?
    var leftInCase: Bool?
    var rightInCase: Bool?

    var valid: Bool {
        guard target.isEmpty || (target.count == 64 && target.allSatisfy({ $0.isHexDigit })),
              !available || (deviceID != 0 && target.count == 64), Set(modes).count == modes.count,
              [left, right, caseBattery, single].compactMap({ $0 }).allSatisfy({ (0...100).contains($0) }),
              [vendorID, productID].compactMap({ $0 }).allSatisfy({ $0 <= 0xffff }),
              deviceName.map({ !$0.isEmpty && $0.count <= 512 }) ?? true,
              zip([left, right, caseBattery, single], [leftCharge, rightCharge, caseCharge, singleCharge])
                .allSatisfy({ $0.1 != .full || $0.0 == 100 }),
              classOfDevice == nil || (1...0xffffff).contains(classOfDevice ?? 0),
              !canSetMode || (available && !modes.isEmpty),
              !canSetConversation || (available && conversation != nil) else { return false }
        return true
    }
    var iconFamily: AudioIconFamily? { .matching(vendorID: vendorID, productID: productID) }

    func batteryDevice(family: AudioIconFamily, name: String, previous: AudioBatteryDevice?) -> AudioBatteryDevice {
        let previous = previous?.target == target ? previous : nil
        let classified = classOfDevice.flatMap(BluetoothFamily.matching(classOfDevice:))
        let fallback = family == .headphones ? classified.map { OutputDeviceKind.bluetooth($0).batteryIconFamily } ?? family : family
        let remembered = previous?.family == .headphones ? nil : previous?.family
        let family = iconFamily ?? remembered
            ?? (fallback == .headphones && (left != nil || right != nil || caseBattery != nil) ? .earbuds : fallback)
        var readings: [AudioBatteryReading] = []
        let hasEars = !family.isSingleBattery && (left != nil || right != nil || previous?.readings.contains { $0.part == .left || $0.part == .right } == true)
        if hasEars {
            readings.append(.init(part: .left, percent: left, charge: leftCharge ?? .unknown, inCase: leftInCase))
            readings.append(.init(part: .right, percent: right, charge: rightCharge ?? .unknown, inCase: rightInCase))
        } else if single != nil || previous?.readings.contains(where: { $0.part == .device }) == true {
            readings.append(.init(part: .device, percent: single, charge: singleCharge ?? .unknown))
        }
        if family.hasCaseBattery, caseBattery != nil || previous?.readings.contains(where: { $0.part == .chargingCase }) == true {
            readings.append(.init(part: .chargingCase, percent: caseBattery, charge: caseCharge ?? .unknown))
        }
        return .init(target: target, name: deviceName ?? name, family: family, readings: readings)
    }
    var batteryText: String {
        let parts: [(String, Int?)] = [(L("左"), left), (L("右"), right), (L("充电盒"), caseBattery)]
        let values = parts.compactMap { name, value in value.map { "\(name) \($0)%" } }
        if !values.isEmpty { return values.joined(separator: " · ") }
        return single.map { L("电量 \($0)%") } ?? L("电量暂不可用")
    }
}

@MainActor final class AirPodsControl: ObservableObject {
    @Published private(set) var snapshot: AirPodsReply?
    @Published private(set) var batteryDevice: AudioBatteryDevice?
    private(set) var batteryReadAt: TimeInterval?
    static let batteryFreshness: TimeInterval = 15
    @Published private(set) var busy = false
    private(set) var refreshing = false
    @Published private(set) var pendingMode: ListeningMode?
    @Published private(set) var pendingConversation: Bool?
    var displayedMode: ListeningMode? { pendingMode ?? snapshot?.mode }
    var displayedConversation: Bool? { pendingConversation ?? snapshot?.conversation }
    @Published private(set) var message: LocalizedText = ""
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
    func refresh(deviceID: UInt32, target: String? = nil, family: AudioIconFamily = .earbuds, name: String = "") {
        let arguments = target.map { ["--status", String(deviceID), $0] } ?? ["--status"]
        run(arguments, deviceID: deviceID, target: target, mutation: false, family: family, name: name)
    }
    func setMode(_ mode: ListeningMode) {
        guard !busy, !unavailable, let snapshot, snapshot.canSetMode, snapshot.modes.contains(mode), snapshot.mode != mode else { return }
        pendingMode = mode
        write("--mode", mode.rawValue, snapshot: snapshot)
    }
    func setConversation(_ enabled: Bool) {
        guard !busy, !unavailable, let snapshot, snapshot.canSetConversation, snapshot.conversation != enabled else { return }
        pendingConversation = enabled
        write("--conversation", enabled ? "on" : "off", snapshot: snapshot)
    }
    private func write(_ command: String, _ value: String, snapshot: AirPodsReply) {
        guard !busy, !unavailable else { return }
        if refreshing { stopProcess() }
        run([command, value, String(snapshot.deviceID), snapshot.target], deviceID: snapshot.deviceID, target: snapshot.target, mutation: true)
    }
    private func run(_ arguments: [String], deviceID: UInt32, target: String?, mutation: Bool,
                     family: AudioIconFamily = .headphones, name: String = "") {
        guard process == nil else { return }
        refreshing = !mutation
        if mutation { busy = true; message = "正在确认耳机状态…" }
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
                defer { if mutation { self.clearPending() } }
                self.timeout?.cancel(); self.timeout = nil; self.process = nil; self.refreshing = false
                if self.busy { self.busy = false }
                guard let reply, reply.valid, reply.deviceID == deviceID,
                      target == nil || reply.target == target else {
                    if !mutation { self.snapshot = nil }
                    self.unavailable = true
                    self.batteryReadAt = nil
                    if mutation { self.message = "未能确认结果，请刷新或在声音设置中检查。" }
                    return
                }
                let confirmed = reply.verified && reply.attempted && reply.error == nil
                if (!mutation || confirmed), self.snapshot != reply { self.snapshot = reply }
                if !mutation, reply.available {
                    let battery = reply.batteryDevice(family: family, name: name, previous: self.batteryDevice)
                    self.batteryReadAt = ProcessInfo.processInfo.systemUptime
                    if self.batteryDevice != battery { self.batteryDevice = battery }
                } else if !mutation { self.batteryReadAt = nil }
                let unavailable = reply.error != nil || (mutation && !confirmed)
                if self.unavailable != unavailable { self.unavailable = unavailable }
                if mutation {
                    self.message = reply.verified && reply.attempted && reply.error == nil ? "" :
                        reply.error == "device_changed" ? "输出设备已变化，请重新选择。" : "耳机未确认切换，请重试或在声音设置中检查。"
                }
            }
        }
        process = child
        do { try child.run() } catch {
            process = nil; refreshing = false; busy = false; unavailable = true
            if !mutation { snapshot = nil }
            batteryReadAt = nil
            clearPending()
            if mutation { message = "耳机控制暂不可用。" }
            return
        }
        let timeout = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.stopProcess(); self.clearPending(); self.unavailable = true
            if !mutation { self.snapshot = nil }
            self.batteryReadAt = nil
            if mutation { self.message = "确认超时，请刷新或在声音设置中检查。" }
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
    }
    private func stopProcess() {
        timeout?.cancel(); timeout = nil
        let previous = process; process = nil
        if let previous, previous.isRunning { kill(previous.processIdentifier, SIGKILL) }
        refreshing = false
        if busy { busy = false }
    }
    private func clearPending() {
        if pendingMode != nil { pendingMode = nil }
        if pendingConversation != nil { pendingConversation = nil }
    }
    func cancel(preservingBattery: Bool = false) {
        stopProcess(); clearPending()
        snapshot = nil; unavailable = false; message = ""
        if !preservingBattery { batteryDevice = nil; batteryReadAt = nil }
    }

    func batteryIsStale(at time: TimeInterval) -> Bool {
        guard let batteryReadAt else { return true }
        return time - batteryReadAt >= Self.batteryFreshness
    }
}
