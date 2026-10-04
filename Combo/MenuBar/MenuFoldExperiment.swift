import AppKit
import ApplicationServices

@objc private protocol MenuRestriction: AnyObject {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(with configuration: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

// macOS 27 private API experiment. It is deliberately time-limited until native
// menu reopening and visible-state checks can be verified on this machine.
@MainActor final class MenuFoldExperiment {
    static let available = false
    private var assertion: MenuRestriction?
    private var expiry: Task<Void, Never>?

    func preview(systemID: Int, report: @escaping @MainActor (LocalizedText) -> Void) {
        release()
        guard Self.available else {
            report("折叠已暂停：实验会隐藏 Combo 图标，无法保证恢复入口始终可见。")
            return
        }
        guard [0, 5, 6].contains(systemID) else {
            report("仅支持 Wi-Fi、声音和电池图标。")
            return
        }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            report("此实验仅支持 macOS 27。")
            return
        }
        guard AXIsProcessTrusted() else {
            report("当前 Combo.app 尚未取得辅助功能权限。")
            return
        }
        let managers = NSWorkspace.shared.runningApplications.filter {
            let name = $0.localizedName ?? ""
            return name.hasPrefix("Bartender") || name == "Ice" || name == "Thaw"
        }
        guard managers.isEmpty else {
            report("请先退出 \(managers.map { $0.localizedName ?? L("菜单栏管理器") }.joined(separator: "、"))，再试验折叠。")
            return
        }
        guard Bundle(path: "/System/Library/PrivateFrameworks/MenuBarClientCore.framework")?.load() == true,
              let configClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              configClass.instancesRespond(to: NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")),
              assertionClass.instancesRespond(to: #selector(MenuRestriction.activate(with:completionHandler:))),
              assertionClass.instancesRespond(to: #selector(MenuRestriction.invalidate)) else {
            report("系统菜单栏实验接口不可用；没有改变图标。")
            return
        }
        let allowedItems = (0..<64).filter { $0 != systemID }.map { NSNumber(value: $0) } as NSArray
        let allowedBundles = Array(Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) + [
            "com.apple.controlcenter", "com.apple.MenuBarAgent", "com.apple.systemuiserver",
            "com.apple.TextInputMenuAgent", "com.apple.UserNotificationCenter", Bundle.main.bundleIdentifier ?? ""
        ])) as NSArray
        guard let allocated = (configClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let config = allocated.perform(NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"), with: allowedItems, with: allowedBundles)?.takeRetainedValue() else {
            report("无法配置实验限制；没有改变图标。")
            return
        }
        let candidate = unsafeBitCast(assertionClass.init(), to: MenuRestriction.self)
        assertion = candidate
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.release()
            report("实验限制已释放；请确认系统图标恢复。")
        }
        candidate.activate(with: config) { [weak self] error in
            Task { @MainActor in
                guard let self, self.assertion === candidate else { return }
                if let error {
                    self.release()
                    report("菜单栏代理拒绝请求：\(error.localizedDescription)")
                    return
                }
                report("系统已接受单项限制；请观察菜单栏。8 秒后自动恢复。此结果尚未证明原生菜单可从 Combo 打开。")
            }
        }
    }

    func release() {
        expiry?.cancel()
        expiry = nil
        assertion?.invalidate()
        assertion = nil
    }
}
