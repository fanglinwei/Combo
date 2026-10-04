import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    var title: String { LKey(rawValue) }
    case general = "通用", appearance = "外观与动效", integration = "菜单栏与控制", media = "媒体来源", experimental = "实验性项目", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .integration: "menubar.rectangle"; case .media: "waveform"; case .experimental: "flask"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: L("设置 Combo 的启动方式与语言。")
        case .appearance: L("选择外观，预览图标与播放效果。")
        case .integration: L("设置 Combo 的显示与连接偏好。")
        case .media: L("只看现在在播什么。")
        case .experimental: L("尚在验证中的菜单栏功能。")
        case .about: L("轻一点的菜单栏，清楚一点的状态。")
        }
    }
}
struct Tag: View {
    let text: String
    @Environment(\.comboPalette) private var palette
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(palette.accent).background(palette.accent.opacity(0.1), in: Capsule()) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.comboPalette) private var palette
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055))) }
}
/// 状态行里的四柱，规则和菜单栏图标底部是同一条（docs/combo-design.md 5.2）：
/// 播放中错峰起伏，减少动态效果时停在高低柱上、不做循环。暂停由 MediaDots 表达。
private struct MediaBars: View {
    let animating: Bool
    @Environment(\.comboPalette) private var palette
    @State private var raised = false
    private let heights: [CGFloat] = [6, 12, 8, 5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 3, height: heights[index])
                    .scaleEffect(y: animating && !raised ? 0.4 : 1, anchor: .bottom)
                    .animation(animating ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.15) : nil, value: raised)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .onAppear { raised = true }
        .accessibilityHidden(true)
    }
}
/// 音柱收回四点：暂停、以及关闭播放动效时底部显示的样子。
private struct MediaDots: View {
    @Environment(\.comboPalette) private var palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { _ in
                Circle().fill(palette.accent.opacity(0.5)).frame(width: 3, height: 3)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
struct SettingsView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var setup: MenuBarSetup
    /// 引导是否在屏幕上。它决定窗口要不要抬到浮动层，逻辑留在 AppDelegate。
    let setGuideOnTop: (Bool) -> Void
    init(store: Store, page: Page = .general, setGuideOnTop: @escaping (Bool) -> Void) {
        self.store = store
        self.battery = store.battery
        self.setup = store.menuSetup
        self.setGuideOnTop = setGuideOnTop
        _page = State(initialValue: page)
    }
    @State private var page: Page
    @State private var hoveredPage: Page?
    @State private var preview: Scene = .wired
    @State private var reset = false
    @State private var showingOnboarding = false
    @State private var thresholdText = ""
    @FocusState private var isThresholdFocused: Bool
    @State private var showingIconGuide = false
    @State private var restoreConfirmation = false
    @State private var confirmAfterPermission = false
    @State private var retryRestore = false
    @State private var pendingMenuAction: MenuAction?
    @State private var loginFeedback: LocalizedText = ""
    @State private var settingsErrors: [String: LocalizedText] = [:]
    private enum MenuAction { case record, check, restore, retry, inspect }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @AppStorage(OnboardingState.postponedKey) private var onboardingPostponed = false
    @AppStorage(OnboardingState.stepKey) private var onboardingStep = 0
    @AppStorage("foldWifi") var foldWifi = true
    @AppStorage("foldSound") var foldSound = true
    @AppStorage("foldBattery") var foldBattery = true
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
    private var colors: SettingsColors { SettingsColors(isDark: palette.isDark) }
    private var labelColor: Color { colors.label }
    /// 引导在屏幕上：首次没走完也没被“稍后再说”放行，或从“通用”里重新打开。
    private var guideVisible: Bool { (!onboardingCompleted && !onboardingPostponed) || showingOnboarding }

    var body: some View {
        Group {
            if guideVisible {
                OnboardingView(store: store, step: $onboardingStep) { completed in
                    onboardingCompleted = completed
                    onboardingPostponed = !completed
                    if completed { onboardingStep = 0; page = .general }
                    showingOnboarding = false
                }
            } else {
                HStack(spacing: 0) {
                    sidebar.padding(.leading, 10).padding(.vertical, 10)
                    VStack(spacing: 0) {
                        if store.scene != .live {
                            HStack(spacing: 12) {
                                Label(L("正在演示 · \(store.scene.title)"), systemImage: "play.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Button(L("结束演示")) { store.scene = .live }
                            }.padding(16).background(palette.accent.opacity(0.08))
                            Divider()
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(page.title).font(.system(size: 24, weight: .semibold))
                                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(palette.mutedText)
                                }.padding(.bottom, 2)
                                switch page {
                                case .appearance: appearance
                                case .general: general
                                case .integration: integration
                                case .media: media
                                case .experimental: experimental
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
            .onAppear {
                setGuideOnTop(guideVisible)
                thresholdText = String(battery.lastDisplayThreshold)
            }
            .onChange(of: guideVisible) { _, visible in setGuideOnTop(visible) }
            .onChange(of: store.login) { _, enabled in if enabled { loginFeedback = "" } }
            .onChange(of: battery.lastDisplayThreshold) { _, value in
                if !isThresholdFocused { thresholdText = String(value) }
            }
            .onChange(of: isThresholdFocused) { _, focused in
                if !focused { saveThreshold() }
            }
            .alert(L("恢复显示偏好？"), isPresented: $reset) {
                Button(L("取消"), role: .cancel) {}
                Button(L("恢复")) { store.resetDisplay(); thresholdText = String(battery.lastDisplayThreshold) }
            } message: {
                Text(L("播放动效开启，低电量显示开启且阈值恢复为 20%。其他偏好和系统图标记录保持不变。"))
            }
            .alert(L("恢复已记录设置？"), isPresented: $restoreConfirmation) {
                Button(L("取消"), role: .cancel) {}
                Button(L("恢复")) { Task { _ = await setup.restore(retryOnly: retryRestore) } }
            } message: {
                Text(recordedSummary(retryOnly: retryRestore))
            }
            .sheet(isPresented: $showingIconGuide, onDismiss: { pendingMenuAction = nil }) { iconGuide }
            .sheet(isPresented: Binding(
                get: { store.showMenuPermission && !showingIconGuide },
                set: { store.showMenuPermission = $0; if !$0 { pendingMenuAction = nil } }
            ), onDismiss: {
                if confirmAfterPermission { confirmAfterPermission = false; restoreConfirmation = true }
                pendingMenuAction = nil
            }) { menuPermissionGuide }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshMenuAccess()
                if store.menuAccessGranted { continueMenuAction() }
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
            Text("PREVIEW \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0")")
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
                HStack {
                    Text(L("主题色"))
                    Spacer(minLength: 12)
                    Picker(L("主题色"), selection: $themeFamily) {
                        ForEach(ComboTheme.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }.padding(16)
                Divider()
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
            HStack {
                groupHeader(L("效果预览"))
                Text(L("窗口内预览")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(colors.surface, in: Capsule()).overlay(Capsule().stroke(colors.line))
            }
            SettingsGroup {
                HStack(spacing: 40) {
                    Spacer()
                    VStack(spacing: 8) {
                        ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 112, previewScene: preview)
                        Text(preview.title).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }
                    VStack(spacing: 12) {
                        ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 22, previewScene: preview)
                        Text(L("菜单栏尺寸")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }
                    Spacer()
                }.padding(20)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach([Scene.wired, .wifi, .music, .paused, .airpods, .adjusting, .mute, .wifiMute, .low, .charging, .offline, .connecting, .wifiOff, .plug, .unplug, .reduced]) { scene in
                        Button { preview = scene } label: {
                            Text(scene.title).font(.system(size: 11, weight: preview == scene ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(SettingsButtonStyle(isEmphasized: preview == scene, isScene: true))
                            .accessibilityAddTraits(preview == scene ? .isSelected : [])
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("在菜单栏演示"))
                        note(L("临时替换 Combo 的实时显示；关闭设置窗口后结束。"))
                    }
                    Spacer()
                    Button(store.scene == .live ? L("开始演示") : L("结束演示")) {
                        store.scene = store.scene == .live ? preview : .live
                    }
                }.padding(16)
            }
            note(L("选择场景只改变窗口内预览；点击开始演示后才切换菜单栏显示。"))
            groupHeader(L("播放动效"))
            SettingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsToggleRow(title: L("播放时显示音柱"), isOn: $store.animate)
                    note(L("固定循环，不录制声音，也不跟随音乐节奏。"))
                }.padding(16)
                Divider()
                LabeledContent(L("减少动态效果"), value: store.reduceMotion ? L("系统已开启 · 静态音柱") : L("跟随系统设置")).padding(16)
            }
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
            groupHeader(L("使用帮助"))
            SettingsGroup { helpRow }
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
                note(L("回顾功能与操作步骤。"))
            }
            Spacer()
            Button(L("查看引导")) { store.scene = .live; showingOnboarding = true }
        }.padding(16)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(palette.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    var integration: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupHeader(L("系统菜单栏图标"))
            SettingsGroup {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("手动隐藏系统图标"))
                        note(L("对照图片，在系统设置中手动取消勾选。"))
                    }
                    Spacer()
                    Button(L("查看指引")) { showingIconGuide = true }.buttonStyle(SettingsButtonStyle(isEmphasized: true))
                }.padding(16)
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(setup.hasBaseline ? L("已记录设置") : L("尚未记录"))
                        note(setup.hasBaseline ? recordedSummary() : L("先记录，再隐藏，之后可按需恢复。"))
                    }
                    Spacer()
                    if setup.hasBaseline {
                        Button(L("恢复已记录设置…")) { requestMenuAction(.restore) }.disabled(setup.busy)
                    }
                }.padding(16)
            }
            note(L("退出 Combo 不会恢复系统图标；只有点击恢复按钮才会更改。"))
            note(setup.message.string)
            if !setup.failedKeys.isEmpty {
                Button(L("重试失败项")) { requestMenuAction(.retry) }.disabled(setup.busy)
            }
            groupHeader(L("Wi‑Fi 连接"), systemSection: "wifi")
            SettingsGroup { WiFiPasswordSettings(wifi: store.wifi).padding(16) }
            if let error = settingsErrors["wifi"] { note(error.string) }
            groupHeader(L("电量显示"), systemSection: "battery")
            SettingsGroup {
                SettingsToggleRow(title: L("低电量时显示百分比"), isOn: Binding(
                    get: { battery.displayEnabled },
                    set: { saveThreshold(); battery.displayEnabled = $0; thresholdText = String(battery.lastDisplayThreshold) }
                )).padding(16)
                Divider()
                HStack(spacing: 8) {
                    Text(L("显示阈值"))
                    Spacer()
                    Text(L("低于"))
                    TextField(L("显示阈值"), text: $thresholdText).textFieldStyle(.roundedBorder)
                        .frame(width: 60).monospacedDigit()
                        .focused($isThresholdFocused)
                        .onSubmit { saveThreshold() }
                    Text("%")
                }.padding(16).disabled(!battery.displayEnabled)
                if battery.displayEnabled && (Int(thresholdText).map { !(1...100).contains($0) } ?? true) {
                    note(L("请输入 1–100 的整数；当前输入尚未保存。"))
                        .accessibilityLabel(L("阈值无效，请输入 1–100 的整数。"))
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }
                Divider()
                HStack {
                    Text(L("电池详情的高耗能应用"))
                    Spacer(minLength: 12)
                    Picker(L("电池详情的高耗能应用"), selection: $battery.energyAppLimit) {
                        ForEach(1...3, id: \.self) { Text(L("最多 \($0) 个")).tag($0) }
                    }.labelsHidden()
                }.padding(16)
            }
            note(L("Wi‑Fi 正常连接时生效。充电显示与电源变化提示不受此开关影响。"))
            note(L("高耗能应用按系统结果显示，数量不足时不补齐。"))
            if let error = settingsErrors["battery"] { note(error.string) }
        }
    }

    /// Commit the complete draft; invalid input never changes the persisted threshold.
    private func saveThreshold() {
        guard battery.displayEnabled, let value = Int(thresholdText), (1...100).contains(value) else { return }
        battery.displayThreshold = value
    }

    var experimental: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { groupHeader(L("系统菜单整合")); Tag(text: L("已暂停 · macOS 27 实验")) }
            SettingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsToggleRow(title: L("自动折叠系统图标"), isOn: .constant(false)).disabled(true)
                    note(L("现有方式会同时隐藏 Combo 图标。恢复入口的可见性确认前暂停启用。"))
                }.padding(16)
                Divider()
                DisclosureGroup(L("准备折叠的项目")) {
                    VStack(alignment: .leading, spacing: 12) {
                        note(L("仅保存选择，当前不执行折叠。系统日期尚未纳入。"))
                        SettingsToggleRow(title: "Wi‑Fi", isOn: $foldWifi)
                        SettingsToggleRow(title: L("声音 / AirPods"), isOn: $foldSound)
                        SettingsToggleRow(title: L("电池"), isOn: $foldBattery)
                    }.toggleStyle(.switch).padding(.top, 12)
                }.padding(16)
            }
            groupHeader(L("原生菜单访问"))
            SettingsGroup {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("检查菜单访问"))
                        note(L("只读取菜单栏，不启用自动折叠，不触发系统菜单。"))
                    }
                    Spacer()
                    Button(L("开始检查")) { requestMenuAction(.inspect) }.disabled(store.checkingMenus)
                    if store.checkingMenus { ProgressView().controlSize(.small) }
                }.padding(16)
                Divider()
                DisclosureGroup(L("检查结果与权限说明")) {
                    VStack(alignment: .leading, spacing: 8) {
                        note(L("读到项目不代表图标实际可见或原生菜单可以打开；不按缓存坐标触发菜单。"))
                        note(store.menuDiagnostic.string).textSelection(.enabled)
                    }.padding(.top, 12)
                }.padding(16)
            }
            Divider()
            DisclosureGroup(L("8 秒单项折叠实验 · 已暂停")) {
                VStack(alignment: .leading, spacing: 12) {
                    note(L("原实验一次仅折叠一项，8 秒后释放。目前三个试验入口均不可用。"))
                    HStack {
                        Button(L("试 Wi-Fi")) {}.disabled(true)
                        Button(L("试声音")) {}.disabled(true)
                        Button(L("试电池")) {}.disabled(true)
                    }
                    Button(L("立即释放限制")) { store.foldExperiment.release(); store.foldExperimentMessage = "实验限制已释放。" }
                    note(store.foldExperimentMessage.string)
                }.padding(.top, 12)
            }
        }
    }

    private func recordedSummary(retryOnly: Bool = false) -> String {
        let rows = setup.supportedKeys.filter { !retryOnly || setup.failedKeys.contains($0) }.map { key in
            let title = key == "wifi" ? "Wi‑Fi" : key == "sound" ? L("声音") : L("电池")
            return title + " · " + (setup.baseline[key] == true ? L("设置为显示") : L("设置为隐藏"))
        }
        let date = setup.recordedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L("此前记录")
        return date + "\n" + rows.joined(separator: "\n")
    }

    private func requestMenuAction(_ action: MenuAction) {
        pendingMenuAction = action
        store.refreshMenuAccess()
        if store.menuAccessGranted { continueMenuAction() }
        else if !showingIconGuide { store.showMenuPermission = true }
    }

    private func continueMenuAction() {
        guard store.menuAccessGranted, let action = pendingMenuAction else { return }
        let wasShowingPermission = store.showMenuPermission
        pendingMenuAction = nil
        store.showMenuPermission = false
        switch action {
        case .record: setup.openAndCapture()
        case .check: setup.check()
        case .inspect: store.checkMenus()
        case .restore, .retry:
            retryRestore = action == .retry
            if wasShowingPermission { confirmAfterPermission = true }
            else { restoreConfirmation = true }
        }
    }

    private var iconGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("手动隐藏系统图标")).font(.system(size: 20, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("1 · 先记录当前设置")).font(.headline)
                    note(L("记录只保留现在的勾选状态。此前已隐藏且未记录时，如需恢复请在系统设置中手动调整。"))
                    if setup.hasBaseline { note(recordedSummary()) }
                    Button(setup.hasBaseline ? L("已有记录，保留原值") : L("记录当前设置")) { requestMenuAction(.record) }
                        .disabled(setup.busy || setup.hasBaseline)
                    if pendingMenuAction == .record && !store.menuAccessGranted { inlineMenuPermission }
                    if setup.busy { ProgressView().controlSize(.small) }
                    note(setup.message.string)
                    Text(L("2 · 在系统设置中手动隐藏")).font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        guideScreenshot(L("隐藏前 · 左侧为蓝色勾选"), image: "MenuBarBefore")
                        guideScreenshot(L("隐藏后 · 左侧取消勾选"), image: "MenuBarAfter")
                    }
                    note(battery.hasInternalBattery ? L("取消 Wi‑Fi、电池、声音左侧的勾选。") : L("此 Mac 无内置电池，只需处理 Wi‑Fi 与声音；图片中的电池项目仅作参照。"))
                    note(L("不同 macOS 版本的排列可能不同，以项目名称和左侧勾选为准。"))
                    Button(L("打开菜单栏设置")) {
                        if !setup.openWithoutCapture() { settingsErrors["menu"] = "无法打开菜单栏设置，请手动进入系统设置。" }
                        else { settingsErrors["menu"] = nil }
                    }
                    if let error = settingsErrors["menu"] { note(error.string) }
                    Text(L("3 · 返回并核对")).font(.headline)
                    Button(L("重新检测")) { requestMenuAction(.check) }.disabled(setup.busy)
                    if pendingMenuAction == .check && !store.menuAccessGranted { inlineMenuPermission }
                    ForEach(setup.supportedKeys, id: \.self) { key in
                        let title = key == "wifi" ? "Wi‑Fi" : key == "sound" ? L("声音") : L("电池")
                        let state = (setup.states[key] ?? .unknown).title
                        LabeledContent(title, value: state)
                            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(state)
                    }
                    note(L("检测只读取设置勾选，不能证明图标在屏幕上可见。请人工确认系统图标已隐藏，Combo 图标仍在。"))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 16)
            }
            HStack { Spacer(); Button(L("关闭指引")) { showingIconGuide = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 590, height: 540).buttonStyle(SettingsButtonStyle()).foregroundStyle(labelColor).tint(palette.accent)
    }

    private func guideScreenshot(_ title: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(title)
            Image(image).resizable().scaledToFit().accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionExplanation: some View {
        note(L("读取图标显示设置需要辅助功能权限。恢复记录时，Combo 会修改这些设置；实验检查仅读取菜单栏。授权本身不会修改图标，你可以随时撤销权限。"))
    }
    private var inlineMenuPermission: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionExplanation
            HStack {
                Button(L("打开辅助功能设置")) { store.requestMenuAccess() }
                Button(L("重新检查")) { store.refreshMenuAccess(); continueMenuAction() }
                Button(L("稍后设置")) { pendingMenuAction = nil }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var menuPermissionGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: store.menuAccessGranted ? "checkmark.shield" : "hand.raised")
                            .font(.system(size: 30)).foregroundStyle(palette.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.menuAccessGranted ? L("辅助功能已授权") : L("管理系统菜单栏图标"))
                                .font(.system(size: 21, weight: .semibold))
                            Text(L("一步设置 · 授权由你决定")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    permissionExplanation
                    Card {
                        Text(L("在辅助功能列表中开启 Combo")).font(.headline)
                        Text(L("系统设置 → 隐私与安全性 → 辅助功能")).font(.subheadline)
                        Text(L("若列表中没有 Combo，点击“＋”，选择当前运行的 Combo.app。系统可能要求你输入密码或使用 Touch ID。")).font(.caption).foregroundStyle(.secondary)
                        Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Label(store.menuAccessGranted ? L("已确认授权，可以继续检测。") : L("系统尚未允许当前进程访问；不一定是开关未开启。"), systemImage: store.menuAccessGranted ? "checkmark.circle.fill" : "info.circle")
                        .font(.subheadline).foregroundStyle(store.menuAccessGranted ? palette.accent : .secondary)
                    if !store.menuPermissionMessage.isEmpty {
                        Text(store.menuPermissionMessage.string).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L("如果系统开关已开启：先退出并重新打开 Combo。仍无效时，请在系统权限列表中移除旧 Combo，再用上方路径添加当前应用并开启。开发预览版重新编译后，旧授权可能不再匹配。系统新版也可能将此项称为“设备控制和数据访问”。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(L("你可以随时在同一页面关闭权限。稍后授权不影响电量、网络与音量显示，但 Combo 将无法自动读取或恢复系统图标设置。")).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 16)
            }
            HStack {
                Button(L("稍后设置")) { pendingMenuAction = nil; store.showMenuPermission = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("重新检查")) { store.refreshMenuAccess() }
                if store.menuAccessGranted {
                    Button(L("继续原任务")) {
                        continueMenuAction()
                    }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L("打开辅助功能设置")) { store.requestMenuAccess() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 540, height: 510).buttonStyle(SettingsButtonStyle()).foregroundStyle(labelColor).tint(palette.accent)
            .onAppear { store.refreshMenuAccess() }
    }
    var media: some View {
        MediaPage(store: store)
    }

/// 媒体来源页：当前在播来源、菜单栏四个状态的对照、状态是怎么读到的。
/// 单独成视图便于渲染核对与媒体音柱回归检查（见 Tests/MediaBarsCheck.swift）。
struct MediaPage: View {
    @ObservedObject var store: Store
    @Environment(\.comboPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            nowPlaying
            soundSection
            menuBarSection
            readingSection
        }
    }

    @State private var soundError: LocalizedText = ""

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("声音")).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.mutedText)
                Spacer()
                Button(L("打开系统声音设置")) {
                    soundError = store.openSystemSettings("sound") ? "" : "无法打开系统声音设置，请手动进入系统设置。"
                }.buttonStyle(SettingsButtonStyle())
            }
            Text(L("在 macOS 中管理声音输入、输出与其他系统选项。"))
                .font(.system(size: 12)).foregroundStyle(palette.mutedText)
            if !soundError.isEmpty { Text(soundError.string).font(.caption).foregroundStyle(palette.mutedText) }
        }
    }

    /// 整页唯一一块 surface。状态用图标底部那一套：播放中四柱，其余四点。
    private var nowPlaying: some View {
        Card {
            HStack(spacing: 7) {
                if store.mediaVisible {
                    if store.live.playing && store.animate {
                        // 重建音柱，让动态效果重新开启时从入场状态启动循环。
                        MediaBars(animating: !store.reduceMotion).id(store.reduceMotion)
                    } else { MediaDots() }
                }
                Text(mediaStatusText)
                    .font(.system(size: 13, weight: store.mediaVisible ? .semibold : .medium))
                    .foregroundStyle(store.mediaVisible ? Color.primary : Color.secondary)
            }
            if store.mediaVisible { mediaTrack } else { mediaIdle }
        }.buttonStyle(.automatic)
    }

    private var mediaStatusText: String {
        if !store.mediaControlsAvailable && store.mediaVisible { return L("重新连接中") }
        guard store.mediaVisible else { return L("未检测到播放") }
        return store.live.playing ? L("正在播放") : L("已暂停")
    }

    private var mediaTrack: some View {
        HStack(spacing: 16) {
            artwork(store.mediaTrack?.artwork)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.mediaTitle).font(.system(size: 16.5, weight: .semibold)).lineLimit(1)
                if let artist = store.mediaTrack?.artist, !artist.isEmpty {
                    Text(artist).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let source = store.mediaTrack?.source, !source.isEmpty {
                    HStack(spacing: 5) {
                        if let icon = appIcon(store.mediaTrack?.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 17, height: 17).accessibilityHidden(true)
                        }
                        Text(source).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 12)
            if let source = store.mediaTrack?.source, !source.isEmpty {
                Button(L("打开\(source)")) { store.openMediaSource() }
                    .controlSize(.small)
                    .disabled(store.mediaTrack?.bundleIdentifier == nil)
            }
        }
    }

    private var mediaIdle: some View {
        HStack(spacing: 16) {
            placeholderArtwork
            VStack(alignment: .leading, spacing: 3) {
                Text(L("现在没有东西在播放。")).font(.system(size: 15, weight: .medium))
                Text(L("Combo 只显示向系统报告播放状态的应用。")).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// 面板里封面只有 40pt，这里按 80pt 展示；没有封面时用同尺寸占位，卡片高度不跳。
    @ViewBuilder private func artwork(_ data: Data?) -> some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
                .accessibilityHidden(true)
        } else {
            placeholderArtwork
        }
    }

    private var placeholderArtwork: some View {
        Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.tertiary)
            .frame(width: 80, height: 80)
            .background(palette.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }

    /// 来源 App 的真实图标。系统查不到（或在跑的副本已挪走）时返回 nil，不猜一个通用图形。
    private func appIcon(_ bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 四个真实状态的对照。规则来自 docs/combo-design.md 第 5.2、5.3 节，示例数据用应用自己的 demo 场景。
    private var menuBarSection: some View {
        let playing = Snapshot.demo(.music)
        let paused = Snapshot.demo(.paused)
        let airPods = Snapshot.demo(.airpods)
        var airPodsIdle = airPods
        airPodsIdle.playing = false
        let onAirPods = store.live.outputIsAirPods
        let live = store.mediaVisible
        return VStack(alignment: .leading, spacing: 0) {
            rule.padding(.bottom, 15)
            HStack(spacing: 12) {
                ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 22).accessibilityHidden(true)
                Text(L("菜单栏会怎么变")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.mutedText)
                Spacer(minLength: 12)
                Button(store.scene != .live ? L("结束演示") : L("演示播放状态")) { store.scene = store.scene != .live ? .live : .music }
                    .controlSize(.small).buttonStyle(SettingsButtonStyle())
            }
            VStack(spacing: 14) {
                HStack(spacing: 26) {
                    legendTile(snapshot: playing, title: L("正在播放"), note: L("四点伸长成四柱，循环起伏"),
                               animate: true, isCurrent: live && store.live.playing && !onAirPods)
                    legendTile(snapshot: paused, title: L("已暂停"), note: L("音柱收回四点，静止不动"),
                               animate: false, isCurrent: live && !store.live.playing && !onAirPods)
                }
                HStack(spacing: 26) {
                    legendTile(snapshot: airPods, title: L("AirPods 播放"), note: L("中央变成耳机图标，底部照旧起伏"),
                               animate: true, isCurrent: live && store.live.playing && onAirPods)
                    legendTile(snapshot: airPodsIdle, title: L("AirPods 已连接"), note: L("只连接、未播放时，底部回到音量圆点"),
                               animate: false, isCurrent: live && !store.live.playing && onAirPods)
                }
            }.padding(.top, 14)
            Text(L("系统静音优先于播放；开启减少动态效果时，音柱不再循环。"))
                .font(.system(size: 10.5)).foregroundStyle(palette.mutedText).padding(.top, 10)
        }
    }

    /// 图例只演示规则，所以两格播放态固定动画；系统开了减少动态效果时 ComboIcon 自己会停。
    private func legendTile(snapshot: Snapshot, title: String, note: String, animate: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            ComboIcon(snapshot: snapshot, animate: animate, size: 64).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(isCurrent ? palette.accent : Color.primary)
                Text(note).font(.system(size: 10.5)).foregroundStyle(palette.mutedText).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            rule
            DisclosureGroup(L("Combo 怎么读到这些")) {
                VStack(spacing: 0) {
                    factRow(key: L("读取"), text: L("只读取系统的播放状态：不采集声音、不录音，也不读取网页内容。"), first: true)
                    factRow(key: L("识别"), text: L("未向系统报告播放状态的播放器不会出现在这里。"))
                    factRow(key: L("保留"), text: L("曲目信息在播放结束后保留约 5 秒，切歌时不会闪空。"))
                }.padding(.top, 10)
            }.font(.system(size: 12))
        }
    }

    private func factRow(key: String, text: String, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { rule }
            HStack(alignment: .top, spacing: 14) {
                Text(key).font(.system(size: 11.5)).foregroundStyle(palette.mutedText).frame(width: 34, alignment: .leading)
                Text(text).font(.system(size: 11.5)).foregroundStyle(palette.mutedText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(.vertical, 7)
        }
    }

    private var rule: some View {
        Rectangle().fill(Color.primary.opacity(0.055)).frame(height: 1)
    }
}

    var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                HStack(spacing: 20) {
                    Image(nsImage: brandImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Combo").font(.system(size: 24, weight: .semibold))
                        note(L("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0") · 三合一预览版"))
                        note("macOS 26+ · MacBook")
                    }
                    Spacer()
                }.padding(16)
                Divider()
                note(L("电量、连接与音量，合在一个安静的图标里。")).padding(16)
            }
            HStack {
                groupHeader(L("当前能力"))
                Button(L("刷新本机状态")) { store.refresh() }
            }
            SettingsGroup {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("本机电池、Wi‑Fi 与声音操作"), systemImage: "checkmark.circle")
                    Label(L("菜单栏图标、点击面板与六组设置"), systemImage: "checkmark.circle")
                    Label(L("媒体播放状态与音柱动画"), systemImage: "checkmark.circle")
                    Label(L("自动折叠：尚未启用"), systemImage: "clock")
                }.padding(16)
            }
            note(store.observation.string)
            groupHeader(L("使用帮助"))
            SettingsGroup {
                helpRow
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("系统图标隐藏指引"))
                        note(L("对照图片，先记录再手动隐藏。"))
                    }
                    Spacer()
                    Button(L("查看指引")) { showingIconGuide = true }.buttonStyle(SettingsButtonStyle(isEmphasized: true))
                }.padding(16)
            }
            Divider()
            DisclosureGroup(L("隐私与状态边界")) {
                note(L("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网连通性尚未检测。读取系统保存的 Wi‑Fi 密码与辅助功能授权，在相关操作中单独说明。"))
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
    var isScene = false
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
            .padding(.horizontal, isScene ? 6 : 12).padding(.vertical, 6)
            .frame(minHeight: isScene ? 36 : 32)
            .background(!isEnabled ? colors.surface : solid || configuration.isPressed ? colors.field : colors.controlGlass, in: shape)
        Group {
            if solid { label }
            else { label.glassEffect(.regular.interactive(), in: shape) }
        }
        .overlay(shape.stroke(border))
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}
