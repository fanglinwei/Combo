import AppKit
@testable import Combo

@main struct PanelDismissCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        delegate.status = NSStatusBar.system.statusItem(withLength: 30)
        delegate.store.reduceMotion = false

        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(300))
        let panel = try require(delegate.panel)
        assert(delegate.store.panelVisible)
        assert(panel.isKeyWindow, "面板必须拿到 key，否则点外面无从收起")

        // 点面板外面：面板失去 key，应当收起。
        panel.resignKey()
        try await Task.sleep(for: .milliseconds(300))
        assert(!delegate.store.panelVisible, "点了面板外面应收起面板")

        // 刚请求权限：系统弹窗抢焦点，不该被当成点了外面。
        delegate.store.wifi.locationAskedAt = ProcessInfo.processInfo.systemUptime
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(300))
        assert(delegate.store.panelVisible)
        try require(delegate.panel).resignKey()
        try await Task.sleep(for: .milliseconds(300))
        assert(delegate.store.panelVisible, "权限弹窗造成的失焦不应收起面板")

        // 窗口过期后再失焦：恢复正常收起。
        try require(delegate.panel).makeKeyAndOrderFront(nil)
        delegate.store.wifi.locationAskedAt = ProcessInfo.processInfo.systemUptime - 10
        try await Task.sleep(for: .milliseconds(100))
        try require(delegate.panel).resignKey()
        try await Task.sleep(for: .milliseconds(300))
        assert(!delegate.store.panelVisible, "权限窗口过期后应恢复点外收起")

        // 有详情展开：收起时整组往右扫出一个面板宽度，而不是原地溶解。
        delegate.store.reduceMotion = false
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(500))
        let resting = try require(delegate.panel).frame.minX
        delegate.store.detailSection = .battery
        delegate.store.reduceMotion = false
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(600))
        let swept = try require(delegate.panel).frame.minX - resting
        assert(swept > 300, "详情展开时应收起并往右扫出，实际位移 \(swept)")
        assert(delegate.store.detailSection == nil, "收起面板应同时收起详情")

        // 没有详情：同样往右扫出去。
        delegate.store.reduceMotion = false
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(500))
        let plainResting = try require(delegate.panel).frame.minX
        delegate.store.reduceMotion = false
        delegate.togglePanel()
        try await Task.sleep(for: .milliseconds(600))
        let plain = try require(delegate.panel).frame.minX - plainResting
        assert(plain > 300, "没有详情时也应往右扫出，实际位移 \(plain)")

        delegate.panel?.orderOut(nil)
        delegate.store.stop()
        NSStatusBar.system.removeStatusItem(delegate.status)
        print("Panel dismiss: outside click closes; permission prompt, expired window and detail sweep behave")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "PanelDismissCheck", code: 1) }
        return value
    }
}
