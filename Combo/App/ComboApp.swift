import SwiftUI

@main
struct ComboApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var localization = Localization.shared

    var body: some SwiftUI.Scene {
        Settings {
            ComboSettingsView(appDelegate: appDelegate)
        }
        .defaultSize(width: 850, height: 690)
        .environment(\.locale, Locale(identifier: localization.language))
        .commands { ComboCommands(appDelegate: appDelegate, language: localization.language) }
        .onChange(of: scenePhase, initial: true) { _, _ in
            appDelegate.installSettingsAction { openSettings() }
        }
        .onChange(of: localization.language, initial: true) { _, _ in
            DispatchQueue.main.async { appDelegate.localizeServicesMenu() }
        }
    }
}

private struct ComboSettingsView: View {
    let appDelegate: AppDelegate
    @State private var titlebarHeight: CGFloat = 0

    var body: some View {
        appDelegate.settingsView()
            .frame(minWidth: 780, minHeight: 620 - titlebarHeight)
            .background(SettingsWindowReader { window in
                appDelegate.configureSettingsWindow(window)
                // Measure after SwiftUI installs its full-size content view and title bar.
                DispatchQueue.main.async {
                    titlebarHeight = window.frame.height - window.contentLayoutRect.height
                    appDelegate.updateSettingsLayout()
                }
            })
    }
}

private struct SettingsWindowReader: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowView { WindowView(configure: configure) }
    func updateNSView(_ view: WindowView, context: Context) {}

    final class WindowView: NSView {
        let configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configure(window) }
        }
    }
}
