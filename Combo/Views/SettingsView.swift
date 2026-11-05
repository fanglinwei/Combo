import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    var title: String { LKey(rawValue) }
    case general = "通用", appearance = "外观与动效", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: L("设置启动、语言与连接偏好。")
        case .appearance: L("调整图标外观、动效与电量显示。")
        case .about: L("轻一点的菜单栏，清楚一点的状态。")
        }
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.comboPalette) private var palette
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055))) }
}
struct SettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    /// 引导是否在屏幕上。它决定窗口要不要抬到浮动层，逻辑留在 AppDelegate。
    let setGuideOnTop: (Bool) -> Void
    let closeGuide: () -> Void
    init(store: Store, page: Page = .general, closeGuide: @escaping () -> Void = {}, setGuideOnTop: @escaping (Bool) -> Void) {
        self.store = store
        self.battery = store.battery
        self.setGuideOnTop = setGuideOnTop
        self.closeGuide = closeGuide
        _page = State(initialValue: page)
    }
    @State private var page: Page
    @State private var hoveredPage: Page?
    @State private var reset = false
    @State private var showingOnboarding = false
    @State private var loginFeedback: LocalizedText = ""
    @State private var settingsErrors: [String: LocalizedText] = [:]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette {
        ComboPalette.standard(isDark: colorScheme == .dark)
    }
    private var colors: SettingsColors { SettingsColors(isDark: palette.isDark) }
    private var labelColor: Color { colors.label }
    /// 首次使用显示欢迎页，也可从“关于与帮助”重新打开。
    private var guideVisible: Bool { !onboardingCompleted || showingOnboarding }

    var body: some View {
        Group {
            if guideVisible {
                OnboardingView(store: store) {
                    closeGuide()
                    onboardingCompleted = true
                    showingOnboarding = false
                }
            } else {
                HStack(spacing: 0) {
                    sidebar.padding(.leading, 10).padding(.vertical, 10)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(page.title).font(.system(size: 24, weight: .semibold))
                                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(palette.mutedText)
                                }.padding(.bottom, 2)
                                switch page {
                                case .appearance: appearance
                                case .general: general
                                case .about: about
                                }
                            }.padding(28).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
                                .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                        }.id(page)
                    }.buttonStyle(SettingsButtonStyle()).controlSize(.small).font(.system(size: 13)).foregroundStyle(labelColor)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 580).tint(palette.accent)
        .background(settingsCanvas)
            .onAppear { setGuideOnTop(guideVisible) }
            .onChange(of: guideVisible) { _, visible in setGuideOnTop(visible) }
            .onChange(of: store.login) { _, enabled in if enabled { loginFeedback = "" } }
            .alert(L("恢复显示偏好？"), isPresented: $reset) {
                Button(L("取消"), role: .cancel) {}
                Button(L("恢复")) { store.resetDisplay() }
            } message: {
                Text(L("将开启播放动效与低电量显示。其他偏好保持不变。"))
            }
            .environment(\.comboPalette, palette)
    }

    private var settingsCanvas: some View {
        LinearGradient(colors: [colors.canvasTop, colors.canvasBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(nsImage: brandImage).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                Text("Combo").font(.system(size: 20, weight: .semibold))
            }.padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 24)
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol).frame(width: 16)
                        Text(item.title).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 12, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 2)
                        .foregroundStyle(page == item ? palette.accent : labelColor)
                        .background(page == item || hoveredPage == item ? colors.field : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(page == item || hoveredPage == item ? colors.line : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).onHover { hoveredPage = $0 ? item : nil }
                    .accessibilityAddTraits(page == item ? .isSelected : [])
            }
            Spacer()
            Text("PREVIEW \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0")")
                .font(.system(size: 11)).foregroundStyle(palette.mutedText).padding(12)
        }.foregroundStyle(labelColor).padding(.horizontal, 8).padding(.bottom, 12).frame(width: 192)
            .modifier(SettingsSidebarSurface(solid: reduceTransparency, increasedContrast: contrast == .increased))
    }

    private func groupHeader(_ title: String, systemSection: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.mutedText)
            Spacer(minLength: 8)
            if let systemSection {
                Button(systemSection == "wifi" ? L("打开系统 Wi‑Fi 设置") : systemSection == "battery" ? L("打开系统电池设置") : L("打开系统声音设置")) {
                    settingsErrors[systemSection] = store.openSystemSettings(systemSection) ? nil : "无法打开系统设置，请手动进入对应页面。"
                }
            }
        }
    }

    var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupHeader(L("外观"))
            SettingsGroup {
                HStack(spacing: 16) {
                    Text(L("外观模式"))
                    Spacer(minLength: 12)
                    HStack(spacing: 4) {
                        ForEach(ComboAppearance.allCases) { mode in
                            Button { appearanceMode = mode } label: {
                                Text(mode.title).font(.system(size: 12, weight: appearanceMode == mode ? .semibold : .regular))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(appearanceMode == mode ? palette.accent : colors.label)
                                    .background(appearanceMode == mode ? colors.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(appearanceMode == mode ? .isSelected : [])
                        }
                    }.padding(4).background(colors.field, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.line))
                        .accessibilityElement(children: .contain).accessibilityLabel(L("外观模式"))
                }.padding(16)
            }
            note(L("更改立即生效。跟随系统时随 macOS 外观切换。"))
            groupHeader(L("效果预览"))
            SettingsGroup {
                VStack(spacing: 8) {
                    ComboIcon(snapshot: store.snapshot(for: .live), animate: store.animate, size: 80)
                    note(L("本机状态"))
                }.frame(maxWidth: .infinity).padding(20)
            }
            groupHeader(L("播放动效"))
            SettingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsToggleRow(title: L("播放时显示音柱"), isOn: $store.animate)
                    note(L("固定循环，不录制声音，也不跟随音乐节奏。"))
                }.padding(16)
                Divider()
                LabeledContent(L("减少动态效果"), value: store.reduceMotion ? L("系统已开启 · 静态音柱") : L("跟随系统设置")).padding(16)
            }
            batterySettings
        }
    }
    var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                SettingsToggleRow(title: L("登录时启动 Combo"), isOn: Binding(get: { store.login }, set: { store.setLogin($0); loginFeedback = store.message })).padding(16)
                Divider()
                HStack {
                    Text(L("语言"))
                    Spacer(minLength: 12)
                    Picker(L("语言"), selection: Binding(get: { localization.selection }, set: { localization.selection = $0 })) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }.padding(16)
            }
            note(L("更改立即生效。"))
            if !loginFeedback.isEmpty { note(loginFeedback.string) }
            connectionSettings
            Divider()
            DisclosureGroup(L("恢复偏好")) {
                VStack(alignment: .leading, spacing: 12) {
                    note(L("仅重置播放动效与低电量显示，其他设置不变。"))
                    Button(L("恢复动效与电量显示偏好…")) { reset = true }
                }.padding(.top, 12)
            }
            HStack {
                note(L("关闭设置窗口后，Combo 继续运行。"))
                Spacer()
                Button(L("退出 Combo")) { NSApp.terminate(nil) }
            }
        }
    }

    private var helpRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("重新查看使用引导"))
                note(L("回顾菜单栏图标的基本操作。"))
            }
            Spacer()
            Button(L("查看引导")) { store.scene = .live; showingOnboarding = true }
        }.padding(16)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupHeader(L("Wi‑Fi"), systemSection: "wifi")
            SettingsGroup { note(L("仅展示无线网络信息；请在系统 Wi‑Fi 设置中连接或开关 Wi‑Fi。")).padding(16) }
            if let error = settingsErrors["wifi"] { note(error.string) }
        }
    }

    private var batterySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupHeader(L("电量显示"), systemSection: "battery")
            SettingsGroup {
                SettingsToggleRow(title: L("低电量时显示百分比"), isOn: Binding(
                    get: { battery.displayEnabled },
                    set: { battery.displayEnabled = $0 }
                )).padding(16)
            }
            note(L("电量低于 20% 时，优先显示电量百分比。"))
            if let error = settingsErrors["battery"] { note(error.string) }
        }
    }

    private var iconGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                guideScreenshot(L("隐藏前 · 左侧为蓝色勾选"), image: "MenuBarBefore")
                guideScreenshot(L("隐藏后 · 左侧取消勾选"), image: "MenuBarAfter")
            }
            note(battery.hasInternalBattery ? L("取消 Wi‑Fi、电池、声音左侧的勾选。") : L("此 Mac 无内置电池，只需处理 Wi‑Fi 与声音；图片中的电池项目仅作参照。"))
            note(L("不同 macOS 版本的排列可能不同，以项目名称和左侧勾选为准。"))
            Button(L("打开菜单栏设置")) {
                if !store.openSystemSettings("menu") { settingsErrors["menu"] = "无法打开菜单栏设置，请手动进入系统设置。" }
                else { settingsErrors["menu"] = nil }
            }
            if let error = settingsErrors["menu"] { note(error.string) }
            note(L("请确认系统图标已隐藏，Combo 图标仍在。如需重新显示，请在系统设置中重新勾选。"))
        }.padding(.top, 12)
    }

    private func guideScreenshot(_ title: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(title)
            Image(image).resizable().scaledToFit().accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader(L("软件更新"))
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let version = updater.availableVersion {
                                Text(L("有新版本可用") + " · " + version)
                            } else {
                                Text(L("保持 Combo 为最新版本"))
                            }
                            if !updater.isEnabled {
                                note(L("开发版本已停用更新检查"))
                            } else if updater.hasCheckError {
                                note(L("更新检查未完成，请稍后重试。"))
                            }
                        }
                        Spacer()
                        Button(L(updater.availableVersion == nil ? "检查更新…" : "查看更新…")) {
                            updater.checkForUpdates()
                        }.disabled(!updater.canCheckForUpdates)
                            .buttonStyle(SettingsButtonStyle(isEmphasized: true))
                    }
                    Divider()
                    Toggle(L("自动检查更新"), isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticChecks($0) }))
                        .disabled(!updater.isStarted)
                    note(L("每天在后台检查。下载、安装和重启前会征求你的确认。"))
                    note(L("更新检查会连接 GitHub 获取版本信息；不上传本机状态，也不发送系统概况。"))
                    Divider()
                    HStack {
                        note(L("上次检查时间"))
                        Spacer()
                        if let date = updater.lastSuccessfulCheck {
                            Text(date.formatted(date: .numeric, time: .shortened))
                                .font(.system(size: 12)).foregroundStyle(palette.mutedText)
                        } else {
                            note(L("尚未检查"))
                        }
                    }
                }.padding(16)
            }
        }
    }

    var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                HStack(spacing: 20) {
                    Image(nsImage: brandImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Combo").font(.system(size: 24, weight: .semibold))
                        note(L("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0") · 三合一预览版"))
                        note("macOS 26+ · MacBook")
                    }
                    Spacer()
                }.padding(16)
                Divider()
                note(L("电量、连接与音量，合在一个安静的图标里。")).padding(16)
            }
            updateSettings
            HStack {
                groupHeader(L("当前能力"))
                Button(L("刷新本机状态")) { store.refresh() }
            }
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("本机电池、Wi‑Fi 与声音操作"), systemImage: "checkmark.circle")
                    Label(L("菜单栏图标、点击面板与设置"), systemImage: "checkmark.circle")
                    Label(L("媒体播放状态与音柱动画"), systemImage: "checkmark.circle")
                }.padding(16)
            }
            note(store.observation.string)
            groupHeader(L("使用帮助"))
            SettingsGroup {
                helpRow
                Divider()
                DisclosureGroup(L("系统图标隐藏指引")) { iconGuide }.padding(16)
            }
            Divider()
            DisclosureGroup(L("媒体播放说明")) {
                note(L("仅显示向 macOS 报告播放状态的应用。静音时显示静音图标；开启“减少动态效果”后，播放音柱保持静止。"))
                    .padding(.top, 12)
            }
            DisclosureGroup(L("隐私与状态边界")) {
                note(L("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网连通性尚未检测。"))
                    .padding(.top, 12)
            }
        }
    }
}

/// The settings content is a stable surface; glass belongs to navigation and actions.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.comboPalette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast
    private var colors: SettingsColors { SettingsColors(isDark: palette.isDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(contrast == .increased ? palette.mutedText : colors.line))
    }
}

private struct SettingsSidebarSurface: ViewModifier {
    let solid: Bool
    let increasedContrast: Bool
    @Environment(\.comboPalette) private var palette
    private var colors: SettingsColors { SettingsColors(isDark: palette.isDark) }

    func body(content: Content) -> some View {
        Group {
            if solid {
                content.background(colors.surface, in: RoundedRectangle(cornerRadius: 16))
            } else {
                GlassEffectContainer {
                    content.background(colors.sidebarGlass, in: RoundedRectangle(cornerRadius: 16))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.overlay(RoundedRectangle(cornerRadius: 16).stroke(increasedContrast ? palette.mutedText : colors.edge))
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title).accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// Neutral settings colors from the approved v2 design; the media card keeps its theme palette.
private struct SettingsColors {
    let isDark: Bool
    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
    var label: Color { color(isDark ? 0xF5F5F7 : 0x1C1C1E) }
    var canvasTop: Color { color(isDark ? 0x25282D : 0xF4F7FA) }
    var canvasBottom: Color { color(isDark ? 0x15171B : 0xE6EDF3) }
    var surface: Color { color(isDark ? 0x303339 : 0xF6F8FA) }
    var field: Color { color(isDark ? 0x41454C : 0xFFFFFF) }
    var sidebarGlass: Color { color(isDark ? 0x2C2F36 : 0xF6F9FC).opacity(0.78) }
    var controlGlass: Color { field.opacity(isDark ? 0.86 : 0.9) }
    var line: Color { isDark ? Color.white.opacity(0.12) : color(0x203448).opacity(0.14) }
    var edge: Color { Color.white.opacity(isDark ? 0.24 : 0.8) }
}

private struct SettingsButtonStyle: ButtonStyle {
    var isEmphasized = false
    @Environment(\.comboPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let colors = SettingsColors(isDark: palette.isDark)
        let shape = RoundedRectangle(cornerRadius: 10)
        let solid = reduceTransparency || contrast == .increased || !isEnabled
        let foreground = !isEnabled ? palette.mutedText : isEmphasized ? palette.accent : colors.label
        let border = !isEnabled ? colors.line : isEmphasized ? palette.accent : contrast == .increased ? palette.mutedText : colors.edge
        let label = configuration.label
            .font(.system(size: 12, weight: isEmphasized ? .semibold : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(!isEnabled ? colors.surface : solid || configuration.isPressed ? colors.field : colors.controlGlass, in: shape)
        Group {
            if solid { label }
            else { label.glassEffect(.regular.interactive(), in: shape) }
        }
        .overlay(shape.stroke(border))
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}
