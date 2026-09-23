import AppKit
import ApplicationServices

// Capability probe only: no screenshot, layout changes, or permission prompt.
let usage = """
MenuProbe --list | --press <exact-AXIdentifier> | --self-test
Keep Wi-Fi, Sound and Battery enabled in macOS Menu Bar settings.
--list reads Control Center menu-bar items only; --press explicitly clicks one.
No permission is requested automatically. This CLI is not the signed Combo app.
"""
func stop(_ message: String, _ code: Int32) -> Never {
    print(message)
    exit(code)
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}
// Refuse empty or ambiguous identifiers. Never select by an array position.
func uniqueIndex(_ identifiers: [String], _ wanted: String) -> Int? {
    guard !wanted.isEmpty else { return nil }
    let matches = identifiers.indices.filter { identifiers[$0] == wanted }
    return matches.count == 1 ? matches[0] : nil
}
let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--help"] { stop(usage, 0) }
if args == ["--self-test"] {
    assert(uniqueIndex(["wifi", "battery"], "battery") == 1)
    assert(uniqueIndex(["wifi", "wifi"], "wifi") == nil)
    assert(uniqueIndex([""], "") == nil)
    assert(uniqueIndex(["wifi"], "sound") == nil)
    stop("PASS: exact, missing, empty and ambiguous identifiers", 0)
}
let listing = args == ["--list"]
let pressing = args.count == 2 && args.first == "--press" && !args[1].isEmpty
 guard listing || pressing else { stop(usage, 64) }
guard AXIsProcessTrusted() else {
    stop("UNAVAILABLE: Accessibility is not granted to this execution context. No prompt or action was performed.", 2)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
    stop("UNAVAILABLE: Control Center is not running; it was not launched.", 3)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 1)
var roots: [AXUIElement] = []
for key in [kAXMenuBarAttribute, kAXExtrasMenuBarAttribute] {
    if let value = attribute(root, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
        roots.append(unsafeBitCast(value, to: AXUIElement.self))
    }
}
var visited: [AXUIElement] = []
var items: [AXUIElement] = []
let deadline = Date().addingTimeInterval(8)
func visit(_ element: AXUIElement, _ depth: Int) {
    guard depth <= 4, visited.count < 120, Date() < deadline,
          !visited.contains(where: { CFEqual($0, element) }) else { return }
    visited.append(element)
    AXUIElementSetMessagingTimeout(element, 0.3)
    if attribute(element, kAXRoleAttribute) as? String == kAXMenuBarItemRole {
        items.append(element)
        return // Do not inspect dropdown contents or network names.
    }
    for child in children(element) { visit(child, depth + 1) }
}
for bar in roots { visit(bar, 0) }
guard Date() < deadline, visited.count < 120 else {
    stop("UNAVAILABLE: traversal limit reached; refusing an incomplete selection.", 4)
}
guard !items.isEmpty else { stop("UNAVAILABLE: no menu-bar items exposed through these public AX attributes.", 3) }
let identifiers = items.map { attribute($0, kAXIdentifierAttribute) as? String ?? "" }
if listing {
    for (index, item) in items.enumerated() {
        // JSON escaping prevents control characters from becoming terminal commands.
        let record: [String: Any] = [
            "identifier": identifiers[index],
            "role": attribute(item, kAXRoleAttribute) as? String ?? "",
            "actions": actions(item)
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    exit(0)
}
guard let index = uniqueIndex(identifiers, args[1]) else {
    stop("REFUSED: identifier absent, empty or ambiguous; no click performed.", 4)
}
let target = items[index]
guard actions(target).contains(kAXPressAction) else {
    stop("UNAVAILABLE: target does not expose AXPress; no coordinate fallback.", 4)
}
let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
stop("AXPress result: \(result.rawValue). Success means action accepted; visually verify the intended menu opened.", result == .success ? 0 : 5)
