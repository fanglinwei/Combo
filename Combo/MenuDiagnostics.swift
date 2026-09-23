import AppKit
import ApplicationServices

// Read-only and explicitly initiated. Never press controls or change menu-bar layout.
func inspectSystemMenus(pid: pid_t, source: String) -> String {
    guard AXIsProcessTrusted() else { return "需要辅助功能授权。未读取菜单、未触发权限弹窗。" }
    let root = AXUIElementCreateApplication(pid)
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var visited: [AXUIElement] = []
    var identifiers: [String] = []
    var count = 0
    var pressable = 0
    var roots: [String] = []
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    func visit(_ element: AXUIElement, depth: Int) {
        guard depth <= 4, visited.count < 120, ProcessInfo.processInfo.systemUptime < deadline,
              !visited.contains(where: { CFEqual($0,element) }) else { return }
        visited.append(element); AXUIElementSetMessagingTimeout(element, 0.2)
        if attribute(element,kAXRoleAttribute) as? String == kAXMenuBarItemRole {
            count += 1
            if let identifier = attribute(element,kAXIdentifierAttribute) as? String { identifiers.append(identifier) }
            var actions: CFArray?
            if AXUIElementCopyActionNames(element,&actions) == .success, (actions as? [String] ?? []).contains(kAXPressAction) { pressable += 1 }
            return
        }
        for child in attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child,depth:depth+1) }
    }
    AXUIElementSetMessagingTimeout(root, 0.2)
    for key in [kAXMenuBarAttribute,kAXExtrasMenuBarAttribute] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, key as CFString, &value)
        let kind = key == kAXMenuBarAttribute ? "主菜单" : "状态菜单"
        if error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            roots.append("\(kind)：可读")
            visit(unsafeBitCast(value,to:AXUIElement.self),depth:0)
        } else { roots.append("\(kind)：不可读（AX \(error.rawValue)）") }
    }
    guard ProcessInfo.processInfo.systemUptime < deadline, visited.count < 120 else { return "\(source)：检测超时或超过读取上限，结果未采用；未执行点击。" }
    guard count > 0 else { return "\(source)：未发现公开 AX 菜单栏项目；\(roots.joined(separator: "、"))。不能据此启用折叠。" }
    // Candidate identity is diagnostic evidence only, not a supported system contract.
    let targets: [(String,[String])] = [("Wi-Fi",["com.apple.menuextra.wifi","com.apple.controlcenter.wifi","WiFi"]), ("声音",["com.apple.menuextra.volume","com.apple.controlcenter.sound","Sound"]), ("电池",["com.apple.menuextra.battery","com.apple.controlcenter.battery","Battery"])]
    let rows = targets.map { title, names in
        let matches = identifiers.filter { names.contains($0) }.count
        return "\(title)：\(matches == 1 ? "发现标识候选，尚未验证点击" : matches > 1 ? "标识存在歧义" : "未定位，需进一步适配")"
    }
    return "\(source)：读取到 \(count) 个菜单项，\(pressable) 个声明支持点击。\n" + rows.joined(separator:"\n") + "\n只读检测完成；不代表折叠或恢复已可用。"
}

extension Store {
    func checkMenus() {
        guard !checkingMenus else { return }
        refreshMenuAccess()
        guard menuAccessGranted else { menuDiagnostic = "系统未允许当前进程访问。若开关已开启，请查看引导中的重启与旧授权排查步骤。"; showMenuPermission = true; return }
        let sources = [("控制中心", "com.apple.controlcenter"), ("系统菜单栏", "com.apple.systemuiserver")]
            .compactMap { name, bundle -> (String, pid_t)? in
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
                return (name, app.processIdentifier)
            }
        guard !sources.isEmpty else { menuDiagnostic = "控制中心与系统菜单栏进程均不可用。"; return }
        checkingMenus = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                sources.map { inspectSystemMenus(pid: $0.1, source: $0.0) }.joined(separator: "\n")
            }.value
            self?.menuDiagnostic = result; self?.checkingMenus = false
        }
    }
    func refreshMenuAccess() {
        menuAccessGranted = AXIsProcessTrusted()
    }
    func requestMenuAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshMenuAccess()
        guard !menuAccessGranted else { return }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        menuPermissionMessage = NSWorkspace.shared.open(url)
            ? "已尝试打开系统设置。开启 Combo 后返回此页；若未跳到目标页面，请手动进入“隐私与安全性 → 辅助功能”。"
            : "未能打开系统设置，请手动进入“系统设置 → 隐私与安全性 → 辅助功能”。"
    }
}
