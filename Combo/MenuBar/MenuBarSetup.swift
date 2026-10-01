import AppKit
import ApplicationServices

enum MenuIconState: String {
    case shown = "设置为显示", hidden = "设置为隐藏", unknown = "无法判断"
}

@MainActor final class MenuBarSetup: ObservableObject {
    @Published var states: [String: MenuIconState] = [:]
    @Published var busy = false
    @Published var message = "尚未读取系统设置；结果只作辅助确认。"
    @Published var needsRecovery = UserDefaults.standard.bool(forKey: "menuSetupSessionActive")
    private let ids = ["wifi": "controlcenter-wifi-id", "battery": "controlcenter-battery-id", "sound": "controlcenter-sound-id"]
    private let baselineKey = "menuSetupBaseline"
    private let activeKey = "menuSetupSessionActive"
    private let menuBarURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?MenuBar")!

    func openWithoutCapture() -> Bool {
        if NSWorkspace.shared.open(menuBarURL) { return true }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return false }
        return NSWorkspace.shared.open(app)
    }

    func openAndCapture() {
        guard NSWorkspace.shared.open(menuBarURL) else { message = "无法打开菜单栏设置。请手动进入“系统设置 → 菜单栏”。"; return }
        busy = true
        Task {
            let values = await waitForValues()
            busy = false
            updateStates(values)
            guard values.count == ids.count else {
                message = "已打开系统设置，但无法完整读取三项；请手动确认，Combo 不会猜测原始状态。"
                return
            }
            if UserDefaults.standard.bool(forKey: activeKey) {
                message = "已保留首次记录的原始状态；请修改系统设置后点“重新检测”。"
                return
            }
            UserDefaults.standard.set(values, forKey: baselineKey)
            UserDefaults.standard.set(true, forKey: activeKey)
            message = "已记录三项原始设置。请在系统设置中亲自关闭想合并的图标，返回后点“重新检测”。"
        }
    }

    func check() {
        busy = true
        Task {
            let values = readValues()
            busy = false
            updateStates(values)
            message = values.count == ids.count ? "已读取系统设置的勾选状态；仍请在菜单栏上人工确认。" : "无法完整读取设置；请先打开“系统设置 → 菜单栏”，并确认辅助功能权限。"
        }
    }

    func restore() async -> Bool {
        guard let original = UserDefaults.standard.dictionary(forKey: baselineKey) as? [String: Bool], original.count == ids.count else {
            message = "没有完整的原始状态记录，请在系统设置中手动恢复。"
            return false
        }
        guard AXIsProcessTrusted(), NSWorkspace.shared.open(menuBarURL) else {
            message = "无法自动恢复；请授权辅助功能并在系统设置中手动恢复。"
            return false
        }
        busy = true
        let before = await waitForValues()
        guard let changes = menuBarRestoreKeys(original: original, current: before, keys: Set(ids.keys)) else {
            busy = false
            message = "无法完整读取三项设置，未作修改；请手动恢复。"
            return false
        }
        var failed = false
        for key in changes {
            guard let identifier = ids[key] else { continue }
            guard let desired = original[key], let (element, current) = findCheckbox(identifier) else { failed = true; continue }
            if current != desired && AXUIElementPerformAction(element, kAXPressAction as CFString) != .success { failed = true }
        }
        try? await Task.sleep(for: .milliseconds(300))
        let verified = readValues()
        updateStates(verified)
        busy = false
        let complete = !failed && ids.keys.allSatisfy { verified[$0] == original[$0] }
        if complete {
            UserDefaults.standard.removeObject(forKey: activeKey)
            needsRecovery = false
            message = "已恢复到首次记录的菜单栏图标状态。"
        } else {
            UserDefaults.standard.set(true, forKey: activeKey)
            needsRecovery = true
            message = "自动恢复未能确认成功；请在“系统设置 → 菜单栏”手动检查三项。"
        }
        return complete
    }

    private func waitForValues() async -> [String: Bool] {
        for _ in 0..<4 {
            let values = readValues()
            if values.count == ids.count { return values }
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
