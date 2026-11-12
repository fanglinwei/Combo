import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    case general = "通用", appearance = "外观", about = "关于"
    var title: String { LKey(rawValue) }
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "gearshape.fill"; case .appearance: "circle.lefthalf.filled"; case .about: "info.circle" }
    }
    func toolbarImage(palette: ComboPalette) -> NSImage {
        let badge: Color = switch self { case .general: palette.iconSlate; case .appearance: palette.iconPurple; case .about: palette.iconBlue }
        let color = NSColor(badge)
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            let rect = rect.insetBy(dx: 4, dy: 4)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white]))?
                .draw(in: rect.insetBy(dx: 5, dy: 5))
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum SettingsLayout {
    static let width: CGFloat = 560
    static let height: CGFloat = 640
    static let minHeight: CGFloat = 240
}

struct SettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    let setGuideOnTop: (Bool) -> Void
    let closeGuide: () -> Void
    let contentHeightChanged: (CGFloat) -> Void
    let guideHeightChanged: (CGFloat) -> Void

    init(store: Store, page: Page = .general, closeGuide: @escaping () -> Void = {},
         contentHeightChanged: @escaping (CGFloat) -> Void = { _ in },
         guideHeightChanged: @escaping (CGFloat) -> Void = { _ in }, setGuideOnTop: @escaping (Bool) -> Void) {
        self.store = store
        self.battery = store.battery
        self.setGuideOnTop = setGuideOnTop
        self.closeGuide = closeGuide
        self.contentHeightChanged = contentHeightChanged
        self.guideHeightChanged = guideHeightChanged
        _page = State(initialValue: page)
    }

    @State private var page: Page
    @State private var contentHeights: [Page: CGFloat] = [:]
    @State private var reset = false
    @State private var showingOnboarding = false
    @State private var showingIconPreview = false
    @State private var loginFeedback: LocalizedText = ""
    @State private var settingsErrors: [String: LocalizedText] = [:]
    @FocusState private var previewButtonFocused: Bool
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var palette: ComboPalette { ComboPalette.settings(isDark: colorScheme == .dark) }
    private var guideVisible: Bool { !onboardingCompleted || showingOnboarding }
    private var contentHeight: CGFloat? { guideVisible ? nil : contentHeights[page] }

    var body: some View {
        Group {
            if guideVisible {
                OnboardingView(store: store, contentHeightChanged: guideHeightChanged) {
                    closeGuide()
                    onboardingCompleted = true
                    showingOnboarding = false
                }
            } else {
                TabView(selection: $page) {
                    ForEach(Page.allCases) { item in
                        Tab(value: item) {
                            settingsPage(item)
                                .background(reduceTransparency ? .clear : palette.settingsContent)
                        } label: {
                            Label { Text(item.title) } icon: { Image(nsImage: item.toolbarImage(palette: palette)) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: guideVisible ? OnboardingLayout.width : SettingsLayout.width).tint(palette.accent)
        .font(.system(size: 13)).foregroundStyle(palette.primaryText).controlSize(.small)
        .background(reduceTransparency ? palette.canvasTop : .clear)
        .containerBackground(for: .window) {
            if reduceTransparency { palette.canvasTop }
            else if guideVisible {
                GlassBackdrop(blur: 32).overlay(palette.onboardingGlass)
            } else { GlassBackdrop(blur: 34).overlay(palette.settingsCanvas) }
        }
        .onAppear { setGuideOnTop(guideVisible) }
        .onChange(of: guideVisible) { _, visible in setGuideOnTop(visible) }
        .onChange(of: contentHeight) { _, height in
            if let height { contentHeightChanged(height) }
        }
        .onChange(of: store.login) { _, enabled in if enabled { loginFeedback = "" } }
        .alert(L("恢复显示偏好？"), isPresented: $reset) {
            Button(L("取消"), role: .cancel) {}
            Button(L("恢复")) { store.resetDisplay() }
        } message: {
            Text(L("将开启播放动效与低电量显示。其他偏好保持不变。"))
        }
        .environment(\.comboPalette, palette)
    }

    private func settingsPage(_ item: Page) -> some View {
        ScrollView {
            Group {
                if item == .appearance && showingIconPreview {
                    IconPreviewView(store: store) {
                        showingIconPreview = false
                        previewButtonFocused = true
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        switch item {
                        case .general: general
                        case .appearance: appearance
                        case .about: about
                        }
                    }.padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 24)
                        .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
                        .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                }
            }
            .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeights[item] = $0 }
        }.scrollBounceBehavior(.basedOnSize)
            .clipped()
            .accessibilityIdentifier("settings-\(item.id)")
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }

    @ViewBuilder private var separator: some View {
        if contrast == .increased { Divider() }
        else { Rectangle().fill(palette.separator).frame(height: 0.5) }
    }

    var appearance: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                groupHeader(L("显示模式"))
                HStack(spacing: 12) {
                    ForEach(ComboAppearance.allCases) { mode in
                        Button { appearanceMode = mode } label: {
                            AppearanceOption(mode: mode, selected: appearanceMode == mode)
                        }.buttonStyle(.plain).accessibilityLabel(mode.title)
                            .accessibilityAddTraits(appearanceMode == mode ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain).accessibilityLabel(L("外观模式"))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    groupHeader(L("菜单栏图标"))
                    Spacer(minLength: 8)
                    Button { showingIconPreview = true } label: {
                        Label(L("预览 \(IconPreviewGroup.sceneCount) 种效果"), systemImage: "chevron.right").labelStyle(.trailingIcon)
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.accent)
                        .focused($previewButtonFocused).accessibilityIdentifier("open-icon-preview")
                }
                HStack {
                    HStack(spacing: 14) {
                        Text("Combo").font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                        ComboIcon(snapshot: store.snapshot(for: .live), animate: store.animate, size: 22)
                        Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute()).font(.system(size: 11)).monospacedDigit()
                    }.padding(.horizontal, 12).padding(.vertical, 6).frame(width: 280)
                        .background(palette.previewSurface, in: RoundedRectangle(cornerRadius: 9))
                }.frame(maxWidth: .infinity).padding(16)
                    .background(palette.inset, in: RoundedRectangle(cornerRadius: 14))
                SettingsGroup {
                    SettingsToggleRow(title: L("播放时显示音柱"), detail: L("固定节奏，不录音"), isOn: $store.animate).padding(.vertical, 12)
                    separator
                    SettingsToggleRow(title: L("低电量时显示百分比"), detail: L("电量低于 20% 时，优先显示电量百分比。"),
                                      isOn: $battery.displayEnabled).padding(.vertical, 12)
                }
                note(store.reduceMotion ? L("系统已开启 · 静态音柱") : L("动态效果跟随 macOS“减少动态效果”设置。"))
            }
            VStack(spacing: 12) {
                separator
                HStack {
                    Button(L("恢复显示偏好…")) { reset = true }.buttonStyle(.plain).foregroundStyle(palette.mutedText)
                    Spacer()
                    Button { openSystemSettings("battery") } label: {
                        Label(L("电池设置"), systemImage: "arrow.up.right").labelStyle(.trailingIcon)
                    }.buttonStyle(.plain).foregroundStyle(palette.accent)
                }.font(.system(size: 12))
            }
            if let error = settingsErrors["battery"] { note(error.string) }
        }
    }

    var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                SettingsToggleRow(title: L("登录时启动 Combo"), isOn: Binding(
                    get: { store.login }, set: { store.setLogin($0); loginFeedback = store.message })).padding(.vertical, 12)
                separator
                HStack {
                    Text(L("语言"))
                    Spacer(minLength: 12)
                    Picker(L("语言"), selection: Binding(get: { localization.selection }, set: { localization.selection = $0 })) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }.frame(minHeight: 60)
            }
            if !loginFeedback.isEmpty { note(loginFeedback.string) }
            VStack(alignment: .leading, spacing: 12) {
                groupHeader(L("系统连接"))
                HStack(spacing: 12) {
                    CategoryIcon(symbol: "wifi", color: palette.iconBlue, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wi-Fi").font(.system(size: 13, weight: .medium))
                        note(L("连接和开关由 macOS 管理"))
                    }
                    Spacer(minLength: 8)
                    Button { openSystemSettings("wifi") } label: {
                        Label(L("系统设置"), systemImage: "arrow.up.right").labelStyle(.trailingIcon)
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(palette.accent)
                }
                if let error = settingsErrors["wifi"] { note(error.string) }
            }
            separator
            HStack {
                note(L("关闭设置窗口后，Combo 继续运行。"))
                Spacer(minLength: 12)
                Button(L("退出 Combo")) { NSApp.terminate(nil) }.buttonStyle(PanelButtonStyle())
            }
        }.font(.system(size: 13))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSystemSettings(_ section: String) {
        settingsErrors[section] = store.openSystemSettings(section) ? nil : "无法打开系统设置，请手动进入对应页面。"
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
            }.buttonStyle(.link)
            if let error = settingsErrors["menu"] { note(error.string) }
            note(L("请确认系统图标已隐藏，Combo 图标仍在。如需重新显示，请在系统设置中重新勾选。"))
        }
    }

    private func guideScreenshot(_ title: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(title)
            Image(image).resizable().scaledToFit().accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateSettings: some View {
        SettingsGroup {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("软件更新")).font(.system(size: 13, weight: .medium))
                    if let version = updater.availableVersion {
                        note(L("有新版本可用") + " · " + version)
                    } else if !updater.isEnabled {
                        note(L("开发版本已停用更新检查"))
                    } else if updater.hasCheckError {
                        note(L("更新检查未完成，请稍后重试。"))
                    } else if let date = updater.lastSuccessfulCheck {
                        note(L("上次检查时间") + " · " + date.formatted(date: .numeric, time: .shortened))
                    } else {
                        note(L("尚未检查"))
                    }
                }
                Spacer(minLength: 8)
                Button(L(updater.availableVersion == nil ? "检查更新…" : "查看更新…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates).buttonStyle(PanelButtonStyle())
            }.padding(.vertical, 12)
            separator
            SettingsToggleRow(title: L("自动检查更新"), detail: L("每天在后台检查。下载、安装和重启前会征求你的确认。"),
                              isOn: Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.setAutomaticChecks($0) }))
                .disabled(!updater.isStarted).padding(.vertical, 12)
        }
    }

    var about: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Image(nsImage: brandImage).resizable().frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Combo").font(.system(size: 22, weight: .semibold))
                    note("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.1") · macOS 26+")
                }
            }
            updateSettings
            VStack(alignment: .leading, spacing: 0) {
                separator
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        note(L("回顾菜单栏图标的基本操作。"))
                        Button(L("查看引导")) { showingOnboarding = true }.buttonStyle(.link)
                    }
                } label: {
                    HStack(spacing: 11) {
                        CategoryIcon(symbol: "book", color: palette.iconBlue)
                        Text(L("使用引导"))
                    }
                }
                separator
                DisclosureGroup { iconGuide } label: {
                    HStack(spacing: 11) {
                        CategoryIcon(symbol: "menubar.rectangle", color: palette.iconSlate)
                        Text(L("系统图标隐藏指引"))
                    }
                }
                separator
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        note(L("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网连通性尚未检测。"))
                        note(L("仅显示向 macOS 报告播放状态的应用。静音时显示静音图标；开启“减少动态效果”后，播放音柱保持静止。"))
                        note(L("更新检查会连接 GitHub 获取版本信息；不上传本机状态，也不发送系统概况。"))
                        note(store.observation.string)
                        Button(L("刷新本机状态")) { store.refresh() }.buttonStyle(.link)
                    }
                } label: {
                    HStack(spacing: 11) {
                        CategoryIcon(symbol: "checkmark.shield", color: palette.iconGreen)
                        Text(L("隐私与状态边界"))
                    }
                }
                separator
            }.disclosureGroupStyle(SettingsHelpDisclosureStyle(reduceMotion: store.reduceMotion))
        }
    }
}

struct SettingsHelpDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.comboPalette) private var palette
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.animation(Motion.detailResize)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    configuration.label
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12)).foregroundStyle(palette.mutedText)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12).accessibilityHidden(true)
                }.font(.system(size: 12)).padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? L("已展开") : L("已收起"))
            if configuration.isExpanded {
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 35).padding(.bottom, 16)
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    @Environment(\.comboPalette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(palette.mutedText) }
            }.fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(palette.toggle)
                .accessibilityHint(detail ?? "")
        }
    }
}

private struct AppearanceOption: View {
    let mode: ComboAppearance
    let selected: Bool
    @Environment(\.comboPalette) private var palette

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                miniature(dark: mode == .dark)
                if mode == .system { miniature(dark: true).mask(alignment: .trailing) { Rectangle().frame(width: 30) } }
            }.frame(width: 60, height: 50).clipShape(RoundedRectangle(cornerRadius: 11))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
                .padding(3).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? palette.accent : .clear, lineWidth: 2))
            Text(mode.title).font(.system(size: 12))
        }.padding(.horizontal, 8).padding(.vertical, 10).frame(maxWidth: .infinity).contentShape(Rectangle())
    }

    private func miniature(dark: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.38, green: 0.55, blue: 0.71)).frame(width: 7, height: 7)
                VStack(spacing: 2) { Capsule().frame(height: 1); Capsule().frame(height: 1) }.frame(width: 22)
                Spacer(minLength: 0)
            }.padding(.horizontal, 3).frame(height: 13).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3); RoundedRectangle(cornerRadius: 3) }.frame(height: 10)
            Capsule().frame(height: 5).padding(.horizontal, 4)
        }.foregroundStyle(dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12))
            .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dark ? Color(red: 0.18, green: 0.22, blue: 0.29) : Color(red: 0.93, green: 0.95, blue: 0.98)).accessibilityHidden(true)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.system(size: 10, weight: .medium)) }
    }
}

private extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: Self { Self() }
}
