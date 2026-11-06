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
        .defaultSize(width: SettingsLayout.width, height: SettingsLayout.height)
        .windowResizability(.contentMinSize)
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
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var palette: ComboPalette { .settings(isDark: colorScheme == .dark) }

    var body: some View {
        appDelegate.settingsView()
            .preferredColorScheme(appearanceMode.colorScheme)
            .frame(minWidth: SettingsLayout.width, minHeight: SettingsLayout.minHeight - titlebarHeight)
            .toolbarBackground(reduceTransparency ? palette.canvasTop : palette.settingsToolbar, for: .windowToolbar)
            .background(SettingsWindowReader { window in
                titlebarHeight = window.frame.height - window.contentLayoutRect.height
                // Apply content constraints before setting the native window's final frame.
                DispatchQueue.main.async {
                    appDelegate.configureSettingsWindow(window)
                    appDelegate.updateSettingsLayout()
                }
            })
            .onChange(of: appearanceMode) { _, _ in appDelegate.updateWindowAppearance() }
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
            if let window { DispatchQueue.main.async { [configure] in configure(window) } }
        }
    }
}
