import AppKit
@testable import Combo

@main struct ApplicationMenuCheck {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let store = Store()
        store.stop()
        let delegate = AppDelegate(store: store)
        let defaults = UserDefaults.standard
        let previousGuide = defaults.object(forKey: OnboardingState.completedKey)
        let previousLanguage = defaults.object(forKey: Localization.preferenceKey)
        defaults.set(true, forKey: OnboardingState.completedKey)
        defer {
            defaults.set(previousGuide, forKey: OnboardingState.completedKey)
            defaults.set(previousLanguage, forKey: Localization.preferenceKey)
            Localization.shared.refresh()
            store.stop()
        }

        for (language, titles) in [
            (AppLanguage.simplifiedChinese, ["关于 Combo", "设置…", "检查更新…", "服务", "隐藏 Combo", "隐藏其他", "显示全部", "退出 Combo"]),
            (AppLanguage.english, ["About Combo", "Settings…", "Check for Updates…", "Services", "Hide Combo", "Hide Others", "Show All", "Quit Combo"])
        ] {
            Localization.shared.selection = language
            delegate.buildApplicationMenu()
            guard let menu = NSApp.mainMenu?.items.first?.submenu else { throw Failure.menu }
            let items = menu.items.filter { !$0.isSeparatorItem }
            assert(items.map(\.title) == titles)
            assert(items.filter { $0.submenu == nil }.map(\.action) == [
                #selector(NSApplication.orderFrontStandardAboutPanel(_:)), #selector(AppDelegate.openSettings),
                #selector(AppDelegate.checkForUpdates), #selector(NSApplication.hide(_:)),
                #selector(NSApplication.hideOtherApplications(_:)), #selector(NSApplication.unhideAllApplications(_:)),
                #selector(NSApplication.terminate(_:))
            ], "Unexpected menu actions: \(items.map { String(describing: $0.action) })")
            assert(items[1].target === delegate && items[2].target === delegate)
            for index in [0, 4, 5, 6, 7] { assert(items[index].target === NSApp) }
            assert(items[1].keyEquivalent == "," && items[1].keyEquivalentModifierMask == .command)
            assert(items[4].keyEquivalent == "h" && items[4].keyEquivalentModifierMask == .command)
            assert(items[5].keyEquivalent == "h" && items[5].keyEquivalentModifierMask == [.command, .option])
            assert(items[7].keyEquivalent == "q" && items[7].keyEquivalentModifierMask == .command)
            assert(items[3].submenu === NSApp.servicesMenu, "Services menu: \(String(describing: NSApp.servicesMenu)); item submenu: \(String(describing: items[3].submenu))")
            menu.update()
            assert(items[1].isEnabled && items[7].isEnabled)
            assert(items[2].isEnabled == AppUpdater.shared.canCheckForUpdates,
                   "Update checks must be disabled when Sparkle cannot check, including Debug builds")
        }

        delegate.openSettings()
        guard let window = delegate.settings else { throw Failure.window }
        window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        assert(NSApp.activationPolicy() == .regular && window.isVisible)
        window.resignKey()
        assert(NSApp.activationPolicy() == .regular, "Losing settings focus must keep the Dock icon")
        window.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(500))
        assert(window.isMiniaturized && NSApp.activationPolicy() == .regular,
               "Minimized settings must remain reachable from the Dock")
        assert(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        try await Task.sleep(for: .milliseconds(500))
        assert(delegate.settings === window && !window.isMiniaturized && window.isVisible)
        let other = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: other))
        assert(NSApp.activationPolicy() == .regular, "Closing another window must keep the settings Dock icon")
        store.scene = .music
        window.close()
        assert(NSApp.activationPolicy() == .accessory && !window.isVisible && store.scene == .live)
        delegate.openSettings()
        assert(delegate.settings === window && NSApp.activationPolicy() == .regular && window.isVisible)
        window.close()
        assert(NSApp.activationPolicy() == .accessory)
        print("PASS: bilingual application menu, native actions and shortcuts, Services registration, update availability, settings Dock lifecycle and minimized-window reopen")
    }

    enum Failure: Error { case menu, window }
}
