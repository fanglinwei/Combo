import AppKit
import ApplicationServices

private let menuTargets: [(String, String)] = [
    ("Wi-Fi", "com.apple.menuextra.wifi"),
    ("声音", "com.apple.menuextra.sound"),
    ("电池", "com.apple.menuextra.battery")
]

// macOS 27 exposes system extras in MenuBarAgent's AX tree with varying wrapper depths.
private func menuBarItems(pid: pid_t, wanted: Set<String>) -> (items: [String: [AXUIElement]], visited: Int, incomplete: Bool) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    var matches: [String: [AXUIElement]] = [:]
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    var visited = 0
    func visit(_ item: AXUIElement, depth: Int) {
        guard depth <= 4, visited < 60, ProcessInfo.processInfo.systemUptime < deadline,
              matches.count < wanted.count else { return }
        visited += 1
        AXUIElementSetMessagingTimeout(item, 0.2)
        var idValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &idValue) == .success,
           let id = idValue as? String, wanted.contains(id) {
            matches[id, default: []].append(item)
        }
        guard depth < 4 else { return }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for child in children.prefix(depth == 0 ? 2 : 16) { visit(child, depth: depth + 1) }
    }
    visit(app, depth: 0)
    return (matches, visited, ProcessInfo.processInfo.systemUptime >= deadline || visited >= 60)
}

private func inspectMenuBarAgent(pid: pid_t) -> String {
    let result = menuBarItems(pid: pid, wanted: Set(menuTargets.map { $0.1 }))
    if result.incomplete { return "MenuBarAgent：扫描超时或超过读取上限；结果未采用。" }
    let rows = menuTargets.map { name, id in
        guard let item = result.items[id]?.first else { return "\(name) 未定位" }
        var actions: CFArray?
        let pressable = AXUIElementCopyActionNames(item, &actions) == .success && (actions as? [String] ?? []).contains(kAXPressAction)
        var position: CFTypeRef?
        let positioned = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success
        return "\(name) 已定位候选；点击\(pressable ? "可用" : "未声明")，位置\(positioned ? "可读" : "不可读")"
    }
    return "MenuBarAgent：" + rows.joined(separator: "、") + "。扫描 \(result.visited) 个节点；仅完成识别，未执行点击。"
}

private func inspectSystemMenus(pid: pid_t, source: String) -> String {
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
              !visited.contains(where: { CFEqual($0, element) }) else { return }
        visited.append(element)
        AXUIElementSetMessagingTimeout(element, 0.2)
        if attribute(element, kAXRoleAttribute) as? String == kAXMenuBarItemRole {
            count += 1
            if let identifier = attribute(element, kAXIdentifierAttribute) as? String { identifiers.append(identifier) }
            var actions: CFArray?
            if AXUIElementCopyActionNames(element, &actions) == .success,
               (actions as? [String] ?? []).contains(kAXPressAction) { pressable += 1 }
            return
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
    }
    AXUIElementSetMessagingTimeout(root, 0.2)
    for key in [kAXMenuBarAttribute, kAXExtrasMenuBarAttribute] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(root, key as CFString, &value)
        let kind = key == kAXMenuBarAttribute ? "主菜单" : "状态菜单"
        if error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            roots.append("\(kind)：可读")
            visit(unsafeBitCast(value, to: AXUIElement.self), depth: 0)
        } else { roots.append("\(kind)：不可读（AX \(error.rawValue)）") }
    }
    guard ProcessInfo.processInfo.systemUptime < deadline, visited.count < 120 else {
        return "\(source)：检测超时或超过读取上限，结果未采用；未执行点击。"
    }
    guard count > 0 else { return "\(source)：未发现公开 AX 菜单栏项目；\(roots.joined(separator: "、"))。" }
    // Candidate identifiers are diagnostic evidence only, not a supported system contract.
    let targets: [(String, [String])] = [
        ("Wi-Fi", ["com.apple.menuextra.wifi", "com.apple.controlcenter.wifi", "WiFi"]),
        ("声音", ["com.apple.menuextra.volume", "com.apple.controlcenter.sound", "Sound"]),
        ("电池", ["com.apple.menuextra.battery", "com.apple.controlcenter.battery", "Battery"])
    ]
    let rows = targets.map { title, names in
        let matches = identifiers.filter { names.contains($0) }.count
        return "\(title)：\(matches == 1 ? "发现标识候选，尚未验证点击" : matches > 1 ? "标识存在歧义" : "未定位，需进一步适配")"
    }
    return "\(source)：读取到 \(count) 个菜单项，\(pressable) 个声明支持点击。\n" + rows.joined(separator: "\n")
        + "\n只读检测完成；不代表点击或恢复已可用。"
}

@main private struct MenuDiagnostics {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "Usage: menu-diagnostics [--help]\n手动只读扫描菜单栏 AX 信息；不点击控件、不修改布局、不请求权限。"
        if arguments == ["--help"] {
            print(usage)
            return
        }
        guard arguments.isEmpty else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(64)
        }
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write(Data("当前进程没有辅助功能权限。未读取菜单、未触发权限弹窗；如需扫描，请手动授权运行此工具的终端或可执行文件。\n".utf8))
            exit(1)
        }
        let sources = [("菜单栏代理", "com.apple.MenuBarAgent"), ("控制中心", "com.apple.controlcenter"), ("系统菜单栏", "com.apple.systemuiserver")]
        var found = false
        for (name, bundle) in sources {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
                print("\(name)：进程不可用。")
                continue
            }
            found = true
            print(bundle == "com.apple.MenuBarAgent"
                  ? inspectMenuBarAgent(pid: app.processIdentifier)
                  : inspectSystemMenus(pid: app.processIdentifier, source: name))
        }
        if !found { exit(1) }
    }
}
