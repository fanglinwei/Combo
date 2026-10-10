import Testing
import Foundation
import AppKit
@testable import ComboTestHost

extension IntegrationTests {
    struct ApplicationMenuTests {
        @Test
        @MainActor
        func testBilingualMenuActionsShortcutsAndAvailability() throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            let delegate = AppDelegate(store: store)
            for (language, titles) in [
                (AppLanguage.simplifiedChinese, ["关于 Combo", "设置…", "检查更新…", "服务", "隐藏 Combo", "隐藏其他", "显示全部", "退出 Combo"]),
                (AppLanguage.english, ["About Combo", "Settings…", "Check for Updates…", "Services", "Hide Combo", "Hide Others", "Show All", "Quit Combo"])
            ] {
                Localization.shared.selection = language
                delegate.buildApplicationMenu()
                let menu = try #require(NSApp.mainMenu?.items.first?.submenu)
                let items = menu.items.filter { !$0.isSeparatorItem }
                guard items.count == 8 else {
                    Issue.record("Expected 8 menu items, got \(items.count)")
                    return
                }
                #expect(items.map(\.title) == titles)
                #expect(items.filter { $0.submenu == nil }.map(\.action) == [
                    #selector(NSApplication.orderFrontStandardAboutPanel(_:)), #selector(AppDelegate.openSettings),
                    #selector(AppDelegate.checkForUpdates), #selector(NSApplication.hide(_:)),
                    #selector(NSApplication.hideOtherApplications(_:)), #selector(NSApplication.unhideAllApplications(_:)),
                    #selector(NSApplication.terminate(_:))
                ], "Unexpected menu actions: \(items.map { String(describing: $0.action) })")
                #expect(items[1].target === delegate && items[2].target === delegate)
                for index in [0, 4, 5, 6, 7] { #expect(items[index].target === NSApp) }
                #expect(items[1].keyEquivalent == "," && items[1].keyEquivalentModifierMask == .command)
                #expect(items[4].keyEquivalent == "h" && items[4].keyEquivalentModifierMask == .command)
                #expect(items[5].keyEquivalent == "h" && items[5].keyEquivalentModifierMask == [.command, .option])
                #expect(items[7].keyEquivalent == "q" && items[7].keyEquivalentModifierMask == .command)
                #expect(items[3].submenu === NSApp.servicesMenu, "Services menu: \(String(describing: NSApp.servicesMenu)); item submenu: \(String(describing: items[3].submenu))")
                menu.update()
                #expect(items[1].isEnabled && items[7].isEnabled)
                #expect(items[2].isEnabled == AppUpdater.shared.canCheckForUpdates,
                       "Update checks must be disabled when Sparkle cannot check, including Debug builds")
            }
        }

        @Test
        @MainActor
        func testSettingsSceneActionPreservesWindowDelegateAndCloseBehavior() throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            let delegate = AppDelegate(store: store)
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            final class WindowDelegate: NSObject, NSWindowDelegate {}
            let windowDelegate = WindowDelegate()
            window.delegate = windowDelegate
            defer { window.close(); window.contentView = nil }
            var openings = 0
            delegate.installSettingsAction {
                openings += 1
                delegate.configureSettingsWindow(window)
            }
            delegate.openSettings()
            #expect(openings == 1 && delegate.settings === window)
            #expect(window.delegate === windowDelegate, "The bridge must preserve SwiftUI's window delegate")
            #expect(window.styleMask.contains([.miniaturizable, .resizable]))
            #expect(window.frame.size == NSSize(width: 850, height: 690))
            #expect(window.minSize == NSSize(width: 780, height: 620))
            window.setFrame(NSRect(x: -9000, y: -9000, width: 900, height: 720), display: false)
            delegate.openSettings()
            #expect(openings == 2 && window.frame.size == NSSize(width: 900, height: 720),
                    "Reattaching the same scene window must preserve the user's size")
            store.scene = .music
            store.showMenuPermission = true
            window.close()
            #expect(NSApp.activationPolicy() == .accessory && store.scene == .live && !store.showMenuPermission)
            delegate.openSettings()
            #expect(openings == 3 && window.isVisible && NSApp.activationPolicy() == .regular)
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            store.scene = .music
            window.close()
            #expect(store.scene == .music, "Termination must remove the scene-window close observer")
        }

        @Test
        @MainActor
        func testSettingsDockLifecycleAndMinimizedWindowReopen() async throws {
            let store = Store(monitorsSystem: false)
            defer { store.stop() }
            let delegate = AppDelegate(store: store)
            NSApp.setActivationPolicy(.accessory)
            UserDefaults.standard.set(true, forKey: OnboardingState.completedKey)
            delegate.openSettings()
            let window = try #require(delegate.settings)
            defer { window.close(); window.contentView = nil }
            window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
            #expect(NSApp.activationPolicy() == .regular && window.isVisible)
            window.resignKey()
            #expect(NSApp.activationPolicy() == .regular, "Losing settings focus must keep the Dock icon")
            window.miniaturize(nil)
            try await Task.sleep(for: .milliseconds(500))
            #expect(window.isMiniaturized && NSApp.activationPolicy() == .regular,
                   "Minimized settings must remain reachable from the Dock")
            #expect(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
            try await Task.sleep(for: .milliseconds(500))
            #expect(delegate.settings === window && !window.isMiniaturized && window.isVisible)
            let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            defer { other.close() }
            delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: other))
            #expect(NSApp.activationPolicy() == .regular, "Closing another window must keep the settings Dock icon")
            store.scene = .music
            window.close()
            #expect(NSApp.activationPolicy() == .accessory && !window.isVisible && store.scene == .live)
            delegate.openSettings()
            #expect(delegate.settings === window && NSApp.activationPolicy() == .regular && window.isVisible)
            window.close()
            #expect(NSApp.activationPolicy() == .accessory)
        }
    }
}
