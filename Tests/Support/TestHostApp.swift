import AppKit

@main
struct TestHostApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            app.run()
        }
    }
}

// The AppKit host exercises shared actions without installing product SwiftUI scenes.
extension AppDelegate {
    func buildApplicationMenu() {
        let menu = NSMenu()
        let root = menu.addItem(withTitle: "Combo", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Combo")
        submenu.addItem(withTitle: L("关于 Combo"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "").target = NSApp
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: L("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        submenu.addItem(.separator())
        let services = NSApp.servicesMenu ?? NSMenu()
        services.supermenu?.items.first(where: { $0.submenu === services })?.submenu = nil
        services.title = L("服务")
        submenu.addItem(withTitle: L("服务"), action: nil, keyEquivalent: "").submenu = services
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L("隐藏 Combo"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h").target = NSApp
        let hideOthers = submenu.addItem(withTitle: L("隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.target = NSApp
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        submenu.addItem(withTitle: L("显示全部"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "").target = NSApp
        submenu.addItem(.separator())
        submenu.addItem(withTitle: L("退出 Combo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        root.submenu = submenu
        NSApp.mainMenu = menu
        NSApp.servicesMenu = services
    }

}
