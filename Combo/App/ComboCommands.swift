import SwiftUI

struct ComboCommands: Commands {
    let appDelegate: AppDelegate
    // A value input invalidates cached commands when the app language changes.
    let language: String
    @ObservedObject private var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("关于 Combo")) { NSApp.orderFrontStandardAboutPanel(nil) }
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("设置…"), action: appDelegate.openSettings)
                .keyboardShortcut(",")
            Button(L("检查更新…"), action: appDelegate.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .appVisibility) {
            Button(L("隐藏 Combo")) { NSApp.hide(nil) }
                .keyboardShortcut("h")
            Button(L("隐藏其他")) { NSApp.hideOtherApplications(nil) }
                .keyboardShortcut("h", modifiers: [.command, .option])
            Button(L("显示全部")) { NSApp.unhideAllApplications(nil) }
        }
        CommandGroup(replacing: .appTermination) {
            Button(L("退出 Combo")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
