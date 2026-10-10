import AppKit
import SwiftUI
@testable import Combo

@main struct AppLifecycleCheck {
    @MainActor static func main() {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.combo.lifecycle-check.") else {
            fatalError("Run this check through check-app-lifecycle.py with an isolated app bundle")
        }
        let fresh = CommandLine.arguments.contains("--fresh")
        let showsSettings = fresh || CommandLine.arguments.contains("--settings")
        UserDefaults.standard.set(!fresh, forKey: OnboardingState.completedKey)
        UserDefaults.standard.set("en", forKey: Localization.preferenceKey)
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
                func check(_ condition: Bool, _ message: String) throws {
                    guard condition else { throw NSError(domain: message, code: 1) }
                    print("PASS:", message)
                }
                @MainActor func settingsItem() throws -> (NSMenu, Int) {
                    guard let menu = NSApp.mainMenu?.items.first?.submenu else {
                        throw NSError(domain: "Missing application menu", code: 1)
                    }
                    menu.delegate?.menuNeedsUpdate?(menu)
                    menu.update()
                    guard let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else {
                        throw NSError(domain: "Missing Settings command", code: 1)
                    }
                    return (menu, index)
                }
                let visible = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
                try check(visible.count == (showsSettings ? 1 : 0), "Launch opens settings only for guide or --settings")
                try check(NSApp.activationPolicy() == (showsSettings ? .regular : .accessory), "Launch preserves Dock policy")
                if fresh {
                    guard let guide = visible.first else { throw NSError(domain: "Missing guide window", code: 1) }
                    try check(guide.frame.height == 620, "First-launch guide keeps its compact height (actual: \(guide.frame.height))")
                    UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
                    try await Task.sleep(for: .milliseconds(500))
                    try check(guide.frame.height == 690, "Leaving guide restores settings height")
                }
                let (menu, index) = try settingsItem()
                try check(menu.items.filter { $0.keyEquivalent == "," }.count == 1, "Exactly one Settings shortcut")
                try check(menu.items.contains { $0.title == "Check for Updates…" && !$0.isEnabled }, "Debug update command is disabled")
                try check(menu.items.contains { $0.title == "Services" && $0.submenu === NSApp.servicesMenu }, "Native Services menu follows app language")
                menu.performActionForItem(at: index)
                try await Task.sleep(for: .milliseconds(500))
                guard let window = NSApp.windows.first(where: { $0.title == "Combo Settings" }) else {
                    throw NSError(domain: "Missing settings scene", code: 1)
                }
                try check(window.isVisible && NSApp.activationPolicy() == .regular, "Settings scene opens with Dock icon")
                let (openedMenu, _) = try settingsItem()
                try check(openedMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
                    "About Combo", "Settings…", "Check for Updates…", "Services", "Hide Combo", "Hide Others", "Show All", "Quit Combo"
                ], "All application commands retain English titles after opening settings")
                try check(window.frame.size == NSSize(width: 850, height: 690), "Settings keeps original size")
                try check(window.minSize == NSSize(width: 780, height: 620), "Settings keeps original minimum size")
                try check(window.delegate != nil && !(window.delegate is AppDelegate), "SwiftUI retains its window delegate")
                window.miniaturize(nil)
                try await Task.sleep(for: .milliseconds(500))
                try check(window.isMiniaturized, "Settings supports minimization")
                menu.performActionForItem(at: index)
                try await Task.sleep(for: .milliseconds(500))
                try check(!window.isMiniaturized && window.isVisible, "Settings command restores minimized scene")
                window.miniaturize(nil)
                try await Task.sleep(for: .milliseconds(500))
                let reopened = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
                try await Task.sleep(for: .milliseconds(500))
                try check(reopened == true && !window.isMiniaturized && window.isVisible,
                          "SwiftUI app delegate forwards reopen and restores minimized settings")
                window.close()
                try check(NSApp.activationPolicy() == .accessory, "Closing settings restores menu-bar-only behavior")
                menu.performActionForItem(at: index)
                try await Task.sleep(for: .milliseconds(500))
                try check(window.isVisible && NSApp.activationPolicy() == .regular, "Settings scene reopens after close")
                Localization.shared.selection = .simplifiedChinese
                try await Task.sleep(for: .milliseconds(500))
                let (chineseMenu, _) = try settingsItem()
                try check(chineseMenu.items.contains { $0.title == "设置…" }, "Settings command updates language")
                try check(chineseMenu.items.contains { $0.title == "检查更新…" }, "Update command updates language")
                try check(chineseMenu.items.contains { $0.title == "服务" && $0.submenu === NSApp.servicesMenu }, "Language changes keep native Services menu")
                try check(window.title == "Combo 设置", "Settings window title updates language")
                try check(chineseMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
                    "关于 Combo", "设置…", "检查更新…", "服务", "隐藏 Combo", "隐藏其他", "显示全部", "退出 Combo"
                ], "All application commands update Chinese titles")
                window.close()
                print("SwiftUI lifecycle checks passed")
            } catch {
                print("FAIL:", error)
            }
            UserDefaults.standard.removePersistentDomain(forName: domain)
            NSApp.terminate(nil)
        }
        ComboApp.main()
    }
}
