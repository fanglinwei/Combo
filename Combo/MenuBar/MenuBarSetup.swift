import AppKit
import ApplicationServices
import IOKit.ps

enum MenuIconState: String {
    var title: String { LKey(rawValue) }
    case shown = "设置为显示", hidden = "设置为隐藏", unknown = "无法判断"
}

@MainActor final class MenuBarSetup: ObservableObject {
    @Published var states: [String: MenuIconState] = [:]
    @Published var busy = false
    @Published var message: LocalizedText = "尚未读取系统设置；结果只作辅助确认。"
    @Published private(set) var baseline: [String: Bool]
    @Published private(set) var recordedAt: Date?
    @Published private(set) var failedKeys: Set<String> = []
    private let defaults: UserDefaults
    private let ids: [String: String]
    private let baselineKey = "menuSetupBaseline"
    private let dateKey = "menuSetupRecordedAt"
    private let menuBarURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?MenuBar")
    var hasBaseline: Bool { Set(baseline.keys).isSuperset(of: ids.keys) }
    var supportedKeys: [String] { ["wifi", "sound", "battery"].filter { ids[$0] != nil } }

    init(defaults: UserDefaults = .standard, hasInternalBattery: Bool? = nil) {
        self.defaults = defaults
        let hasBattery = hasInternalBattery ?? Self.hasBattery()
        var ids = ["wifi": "controlcenter-wifi-id", "sound": "controlcenter-sound-id"]
        if hasBattery { ids["battery"] = "controlcenter-battery-id" }
        self.ids = ids
        baseline = defaults.dictionary(forKey: "menuSetupBaseline") as? [String: Bool] ?? [:]
        recordedAt = defaults.object(forKey: "menuSetupRecordedAt") as? Date
    }

    private static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }

    func openWithoutCapture() -> Bool {
        if let menuBarURL, NSWorkspace.shared.open(menuBarURL) { return true }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return false }
        return NSWorkspace.shared.open(app)
    }

    /// Only a complete, explicitly requested read establishes the first baseline.
    @discardableResult func recordBaseline(_ values: [String: Bool]) -> Bool {
        guard !hasBaseline else { return true }
        guard Set(values.keys).isSuperset(of: ids.keys) else { return false }
        baseline = values.filter { ids[$0.key] != nil }
        recordedAt = Date()
        defaults.set(baseline, forKey: baselineKey)
        defaults.set(recordedAt, forKey: dateKey)
        return true
    }

    func openAndCapture() {
        guard !busy else { return }
        guard AXIsProcessTrusted() else { message = "读取图标显示设置需要辅助功能权限。"; return }
        guard openWithoutCapture() else { message = "无法打开菜单栏设置。请手动进入“系统设置 → 菜单栏”。"; return }
        busy = true
        Task {
            let values = await waitForValues(keys: Set(ids.keys))
            updateStates(values)
            busy = false
            guard recordBaseline(values) else {
                message = "无法完整读取适用项目，未记录；请手动确认，Combo 不会猜测原始状态。"
                return
            }
            message = "已保留首次记录的设置。请手动隐藏图标，返回后重新检测；记录前已隐藏的项目不会被猜成显示。"
        }
    }

    func check() {
        guard !busy else { return }
        busy = true
        Task {
            let values = readValues()
            updateStates(values)
            busy = false
            message = values.count == ids.count ? "已读取系统设置的勾选状态；仍请在菜单栏上人工确认。" : "无法完整读取设置；请先打开“系统设置 → 菜单栏”，并确认辅助功能权限。"
        }
    }

    /// Retry targets only the items that failed verification; the baseline survives both outcomes.
    func restore(retryOnly: Bool = false) async -> Bool {
        guard !busy, hasBaseline else { message = "没有完整的原始状态记录，请在系统设置中手动恢复。"; return false }
        let keys = retryOnly ? failedKeys : Set(ids.keys)
        guard !keys.isEmpty else { return true }
        guard AXIsProcessTrusted(), openWithoutCapture() else {
            message = "无法恢复；请检查辅助功能权限和系统菜单栏设置。"
            return false
        }
        busy = true
        defer { busy = false }
        let before = await waitForValues(keys: keys)
        guard let changes = menuBarRestoreKeys(original: baseline, current: before, keys: keys) else {
            failedKeys.formUnion(keys)
            message = "无法完整读取待恢复项目，未作修改；请重试或手动恢复。"
            return false
        }
        for key in changes {
            guard let identifier = ids[key], let desired = baseline[key],
                  let (element, current) = findCheckbox(identifier) else { continue }
            if current != desired { _ = AXUIElementPerformAction(element, kAXPressAction as CFString) }
        }
        try? await Task.sleep(for: .milliseconds(300))
        let verified = readValues()
        updateStates(verified)
        failedKeys.subtract(keys)
        failedKeys.formUnion(keys.filter { verified[$0] != baseline[$0] })
        if failedKeys.isEmpty {
            message = "已恢复到记录的菜单栏图标设置；记录仍保留。"
        } else {
            message = "部分项目未能确认恢复；可只重试失败项，也可在系统设置中手动检查。"
        }
        return failedKeys.isEmpty
    }

    private func waitForValues(keys: Set<String>) async -> [String: Bool] {
        for _ in 0..<4 {
            let values = readValues()
            if Set(values.keys).isSuperset(of: keys) { return values }
            try? await Task.sleep(for: .milliseconds(350))
        }
        return readValues()
    }
    private func updateStates(_ values: [String: Bool]) {
        states = ids.keys.reduce(into: [:]) { $0[$1] = values[$1].map { $0 ? .shown : .hidden } ?? .unknown }
    }
    private func readValues() -> [String: Bool] {
        guard AXIsProcessTrusted(), let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier else { return [:] }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        let names = Dictionary(uniqueKeysWithValues: ids.map { ($0.value, $0.key) })
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var values: [String: Bool] = [:]
        var seen = 0
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 14, seen < 500, values.count < ids.count,
                  ProcessInfo.processInfo.systemUptime < deadline else { return }
            seen += 1
            AXUIElementSetMessagingTimeout(element, 0.15)
            var id: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &id) == .success,
               let id = id as? String, let key = names[id] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
                   let number = value as? NSNumber { values[key] = number.boolValue }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let items = children as? [AXUIElement] {
                for child in items { visit(child, depth: depth + 1) }
            }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
           let items = windows as? [AXUIElement] {
            for window in items { visit(window, depth: 0) }
        } else { visit(root, depth: 0) }
        return values
    }
    private func findCheckbox(_ identifier: String) -> (AXUIElement, Bool)? {
        guard AXIsProcessTrusted(), let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var seen = 0
        func visit(_ element: AXUIElement, depth: Int) -> (AXUIElement, Bool)? {
            guard depth < 14, seen < 500, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            seen += 1
            AXUIElementSetMessagingTimeout(element, 0.15)
            var id: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &id) == .success,
               id as? String == identifier {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
                   let number = value as? NSNumber { return (element, number.boolValue) }
            }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                  let items = children as? [AXUIElement] else { return nil }
            for child in items { if let match = visit(child, depth: depth + 1) { return match } }
            return nil
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
           let items = windows as? [AXUIElement] {
            for window in items { if let match = visit(window, depth: 0) { return match } }
            return nil
        }
        return visit(root, depth: 0)
    }
}
