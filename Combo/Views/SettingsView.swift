import SwiftUI
import Inject
import AppKit

enum Page: String, CaseIterable, Identifiable {
    var title: String { LKey(rawValue) }
    case general = "通用", appearance = "外观与动效", integration = "系统菜单整合", media = "媒体来源", experimental = "实验性项目", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .integration: "menubar.rectangle"; case .media: "waveform"; case .experimental: "flask"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: L("让 Combo 按你的习惯工作。")
        case .appearance: L("让外观、图标与动效都按你的习惯呈现。")
        case .integration: L("查看 Wi-Fi、声音与电池的日常功能。")
        case .media: L("只看现在在播什么。")
        case .experimental: L("自动隐藏与原生菜单实验，仍在验证中。")
        case .about: L("轻一点的菜单栏，清楚一点的状态。")
        }
    }
}
struct Tag: View {
    @ObserveInjection var inject
    let text: String
    @Environment(\.comboPalette) private var palette
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(palette.accent).background(palette.accent.opacity(0.1), in: Capsule()) }
}
struct Card<Content: View>: View {
    @ObserveInjection var inject
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
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var setup: MenuBarSetup
    /// 引导是否在屏幕上。它决定窗口要不要抬到浮动层，逻辑留在 AppDelegate。
    let setGuideOnTop: (Bool) -> Void
    init(store: Store, setGuideOnTop: @escaping (Bool) -> Void) {
        self.store = store; self.battery = store.battery; self.setup = store.menuSetup; self.setGuideOnTop = setGuideOnTop
    }
    @State private var page: Page = .appearance
    @State private var preview: Scene = .wired
    @State private var reset = false
    @State private var showingOnboarding = false
    @State private var thresholdDraft: Int?
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
    /// 引导在屏幕上：首次没走完也没被“稍后再说”放行，或从“通用”里重新打开。
    private var guideVisible: Bool { (!onboardingCompleted && !onboardingPostponed) || showingOnboarding }

    var body: some View {
        HStack(spacing: 0) {
            if guideVisible {
                OnboardingView(store: store, step: $onboardingStep) { completed in
                    onboardingCompleted = completed
                    onboardingPostponed = !completed
                    if completed { onboardingStep = 0; page = .general }
                    showingOnboarding = false
                }
            } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(nsImage: brandImage)
                        .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) { Text("Combo").font(.system(size: 20, weight: .semibold)); Text(L("状态，合而为一")).font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 26)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.title, systemImage: item.symbol).font(.system(size: 12, weight: page == item ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
                            .foregroundStyle(page == item ? palette.accent : .primary).background(page == item ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) { Tag(text: "PREVIEW 0.3"); Text(L("为 MacBook 而设计")).font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(14)
            }.padding(.horizontal, 10).frame(width: 180).background(palette.surface)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Text(page.title).font(.system(size: 25, weight: .semibold)); Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }.padding(.bottom, 4)
                    switch page {
                    case .appearance: appearance
                    case .general: general
                    case .integration: integration
                    case .media: media
                    case .experimental: experimental
                    case .about: about
                    }
                    if !store.message.isEmpty { Text(store.message.string).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
                    .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
            }.background(palette.canvasTop)
            }
        }.frame(minWidth: 760, minHeight: 580).tint(palette.accent)
            .onAppear { setGuideOnTop(guideVisible) }
            .onChange(of: guideVisible) { _, visible in setGuideOnTop(visible) }
            .alert(L("恢复显示偏好？"), isPresented: $reset) { Button(L("取消"), role: .cancel) {}; Button(L("恢复")) { store.resetDisplay() } } message: { Text(L("播放动效开启，电池显示阈值恢复为 50%。登录项和折叠选择保持不变。")) }
            .sheet(isPresented: $store.showMenuPermission) { menuPermissionGuide }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshMenuAccess()
            }
            .alert(L("上次可能未恢复系统图标"), isPresented: $setup.needsRecovery) {
                Button(L("尝试恢复")) { Task { _ = await setup.restore() } }
                Button(L("稍后检查"), role: .cancel) {}
            } message: { Text(L("请检查三枚系统图标；Combo 只能在读到原始状态时尝试恢复。")) }
            .environment(\.comboPalette, palette)
            .enableInjection()
    }
    var appearance: some View {
        VStack(spacing: 18) {
            Card {
                Text(L("主题色")).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) { ForEach(ComboTheme.allCases) { themeOption($0) } }
                Divider()
                Text(L("外观模式")).font(.system(size: 13, weight: .semibold))
                Picker(L("外观模式"), selection: $appearanceMode) {
                    ForEach(ComboAppearance.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                Text(L("跟随系统时，Combo 会随 macOS 的外观设置切换。")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) { Text(L("效果预览")).font(.system(size: 13, weight: .semibold)); Text(L("示例数据 · 不改变系统状态")).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Tag(text: L("实时预览"))
                }
                HStack(spacing: 42) {
                    Spacer()
                    ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 112, previewScene: preview)
                    VStack(spacing: 12) { ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 22, previewScene: preview); Text(L("菜单栏尺寸")).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.vertical, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(Scene.allCases.filter { $0 != .live }) { scene in
                        Button { preview = scene } label: {
                            Text(scene.title).font(.system(size: 10)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(preview == scene ? palette.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(preview == scene ? palette.accent : .secondary)
                        }.buttonStyle(.plain).accessibilityAddTraits(preview == scene ? .isSelected : [])
                    }
                }
            }
            Card {
                Toggle(L("播放时显示音柱"), isOn: $store.animate).toggleStyle(.switch)
                Text(L("固定循环，不录制声音，也不跟随音乐节奏。")).font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack { Text(L("减少动态效果")); Spacer(); Text(store.reduceMotion ? L("系统已开启 · 静态音柱") : L("跟随系统设置")).foregroundStyle(.secondary) }.font(.caption)
            }
        }
    }
    private func themeOption(_ theme: ComboTheme) -> some View {
        let light = theme.palette(isDark: false)
        let dark = theme.palette(isDark: true)
        return Button { themeFamily = theme } label: {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Rectangle().fill(LinearGradient(colors: [light.canvasTop, light.tileBottom], startPoint: .top, endPoint: .bottom))
                    Rectangle().fill(LinearGradient(colors: [dark.canvasTop, dark.tileBottom], startPoint: .top, endPoint: .bottom))
                }.frame(height: 42).clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
                Text(theme.title).font(.system(size: 12, weight: themeFamily == theme ? .semibold : .regular))
            }.padding(9).frame(maxWidth: .infinity)
                .background(themeFamily == theme ? palette.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(themeFamily == theme ? palette.accent : Color.primary.opacity(0.08), lineWidth: themeFamily == theme ? 2 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(themeFamily == theme ? .isSelected : [])
    }
    var general: some View {
        VStack(spacing: 18) {
            Card {
                Picker(L("语言"), selection: Binding(get: { localization.selection }, set: { localization.selection = $0 })) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Text(L("跟随系统时，按系统语言偏好选择简体中文或英文。更改立即生效。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Toggle(L("登录时启动 Combo"), isOn: Binding(get: { store.login }, set: { store.setLogin($0) })).toggleStyle(.switch)
                Text(L("登录后显示菜单栏图标，不增加独立后台服务。")).font(.caption).foregroundStyle(.secondary)
            }
            Card { Button(L("重新查看首次使用引导")) { showingOnboarding = true } }
            Card {
                Label(L("手动隐藏系统图标"), systemImage: "menubar.rectangle").font(.headline)
                Text(L("在“系统设置 → 菜单栏”中，由你亲自关闭 Wi‑Fi、声音，以及有内置电池的 Mac 上的电池图标显示。Combo 不会自动隐藏图标，也不会影响控制中心。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("这里的状态记录和检测需要辅助功能权限。若已在引导中隐藏图标，Combo 没有更改前的记录；需要恢复时请手动操作。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("打开设置并记录当前状态")) { setup.openAndCapture() }
                    Button(L("重新检测")) { setup.check() }.disabled(setup.busy)
                    if setup.busy { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 22) {
                    setupRow("Wi‑Fi", key: "wifi", symbol: "wifi")
                    setupRow(L("声音"), key: "sound", symbol: "speaker.wave.2")
                    setupRow(L("电池"), key: "battery", symbol: "battery.75percent")
                }
                Text(L("检测仅读取系统设置控件，不能证明图标此刻在屏幕上可见；请在菜单栏人工复核。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("尝试恢复原来的图标设置")) { Task { _ = await setup.restore() } }
                Text(setup.message.string).font(.caption).foregroundStyle(.secondary)
            }
            Card { Button(L("辅助功能权限…")) { store.refreshMenuAccess(); store.showMenuPermission = true } }
            Card {
                Text(L("预览版体验")).font(.system(size: 13, weight: .semibold))
                Picker(L("菜单栏数据"), selection: $store.scene) { ForEach(Scene.allCases) { Text($0 == .live ? $0.title : L("演示 · \($0.title)")).tag($0) } }
                Text(L("选择演示场景，可以在真实菜单栏查看播放、静音与充电效果。退出后恢复本机状态。")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack { VStack(alignment: .leading, spacing: 5) { Text(L("恢复显示偏好")); Text(L("仅重置播放动效和电池显示阈值")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(L("恢复…")) { reset = true } }
                Divider(); HStack { Text(L("关闭设置窗口后，Combo 继续运行。")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L("退出 Combo")) { NSApp.terminate(nil) } }
            }
        }
    }
    var integration: some View {
        VStack(spacing: 18) {
            Card {
                Label { Text("Wi‑Fi") } icon: { WiFiIcon() }.font(.headline)
                Text(L("主面板显示已连接、已知与其他网络，支持开关、信号强弱和基础安全提示。首次查找会请求定位权限；个人热点与企业认证使用系统 Wi‑Fi 设置。"))
                    .font(.caption).foregroundStyle(.secondary)
                WiFiPasswordSettings(wifi: store.wifi)
                Button(L("打开 Wi‑Fi 设置")) { store.openSystemSettings("wifi") }
            }
            Card {
                Label(L("声音"), systemImage: "speaker.wave.2").font(.headline)
                Text(L("主面板可切换可用输出设备、调节音量与静音。AirPods 降噪等高级控制使用系统声音设置或控制中心。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("打开声音设置")) { store.openSystemSettings("sound") }
            }
            Card {
                Label(L("电池"), systemImage: "battery.75percent").font(.headline)
                let threshold = thresholdDraft ?? battery.displayThreshold
                HStack(spacing: 8) {
                    Text(L("优先显示电量的阈值")).fixedSize()
                    Spacer(minLength: 12)
                    Slider(value: Binding(
                        get: { Double(thresholdDraft ?? battery.displayThreshold) },
                        set: { value in
                            if thresholdDraft != nil { thresholdDraft = Int(value.rounded()) }
                            else { battery.displayThreshold = Int(value.rounded()) }
                        }
                    ), in: 0...100, onEditingChanged: { editing in
                        if editing { thresholdDraft = battery.displayThreshold }
                        else {
                            if let thresholdDraft { battery.displayThreshold = thresholdDraft }
                            thresholdDraft = nil
                        }
                    })
                    .accessibilityLabel(L("优先显示电量的阈值"))
                    .accessibilityValue(threshold == 0 ? L("0%，关闭") : "\(threshold)%")
                    .frame(width: 160)
                    Text(threshold == 0 ? L("关闭") : "\(threshold)%")
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                Text(L("Wi-Fi 正常连接且电量低于此值时，中央显示电量百分比。设为 0% 可关闭低电量自动显示；正在充电时仍优先显示电量；拔插电源或充电状态变化时仍会播放临时提示。")).font(.caption).foregroundStyle(.secondary)
                Text(L("主面板显示电量、电源来源、充电状态、当前充电上限、低电量模式和系统提供的粗略健康状态。能耗模式仅修改点击时的电源类型，需要管理员授权，退出 Combo 后保留。接电且确认被手动上限暂停充电时，可点击“立即充满电”；临时解除限制后的恢复由 macOS 管理，退出 Combo 不会取消。暂不支持仅优化充电暂缓的情况，无法操作时请使用系统电池设置。高耗能应用显示在主面板，可在活动监视器查看详细能耗。"))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L("电池详情高耗能应用上限"), selection: $battery.energyAppLimit) {
                    ForEach(1...3, id: \.self) { Text(L("\($0) 个")).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(L("电池详情高耗能应用上限"))
                Text(L("概览固定显示 1 个；电池详情默认最多 1 个，按系统数据源顺序显示。没有高耗能应用时不补充其他应用，无法获取时会明确提示。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Button(L("打开电池设置")) { store.openSystemSettings("battery") }; Button(L("查看耗电应用")) { store.openActivityMonitor() } }
            }
        }
    }
    var experimental: some View {
        VStack(spacing: 18) {
            Card {
                HStack { Text(L("系统菜单整合")).font(.system(size: 13, weight: .semibold)); Spacer(); Tag(text: L("macOS 27 实验")) }
                Toggle(L("整合系统菜单"), isOn: .constant(false)).toggleStyle(.switch).disabled(true)
                Text(L("自动折叠已暂停：现有方式会同时隐藏 Combo 图标。确认恢复入口始终可见前，总开关与单项实验均不启用。")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text(L("准备折叠的项目")).font(.system(size: 13, weight: .semibold))
                foldRow("Wi-Fi", symbol: "wifi", binding: $foldWifi)
                Divider(); foldRow(L("声音／AirPods"), symbol: "headphones", binding: $foldSound)
                Divider(); foldRow(L("电池"), symbol: "battery.75percent", binding: $foldBattery)
                Text(L("选择会保存，但当前不执行折叠。系统日期尚未纳入。")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text(L("8 秒单项折叠实验")).font(.system(size: 13, weight: .semibold))
                Text(L("实验暂停中。原实验一次仅折叠一项，8 秒后释放；仍保留“立即恢复”入口。")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("试 Wi-Fi")) { store.foldExperiment.preview(systemID: 6) { store.foldExperimentMessage = $0 } }
                    Button(L("试声音")) { store.foldExperiment.preview(systemID: 5) { store.foldExperimentMessage = $0 } }
                    Button(L("试电池")) { store.foldExperiment.preview(systemID: 0) { store.foldExperimentMessage = $0 } }
                }.disabled(!MenuFoldExperiment.available)
                Button(L("立即恢复")) { store.foldExperiment.release(); store.foldExperimentMessage = "实验限制已释放。" }
                Text(store.foldExperimentMessage.string).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Card {
                Label(L("原生菜单入口 · 尚待验证"), systemImage: "cursorarrow.click").font(.system(size: 13, weight: .semibold))
                Text(L("目标交互：打开 Combo → 选择 Wi-Fi、声音或电池 → 临时展开系统菜单 → 关闭后收起。只有确认 Combo 图标持续可见后才会启用折叠。")).font(.caption).foregroundStyle(.secondary)
                Text(L("只有点击授权按钮时才会请求辅助功能。检查仅读取菜单栏，不会启用自动折叠。")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("检查菜单访问")) { store.checkMenus() }.disabled(store.checkingMenus)
                    Button(L("授权辅助功能…")) { store.refreshMenuAccess(); store.showMenuPermission = true }
                    if store.checkingMenus { ProgressView().controlSize(.small) }
                }
                Text(L("本机已读到三个系统项目的辅助功能候选；实际可见性和原生菜单打开仍待验证。为避免误点，不按缓存坐标触发菜单。")).font(.caption).foregroundStyle(.secondary)
                Text(store.menuDiagnostic.string).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    func setupRow(_ title: String, key: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(title) } icon: {
                if symbol == "wifi" { WiFiIcon() } else { Image(systemName: symbol) }
            }
            Text((setup.states[key] ?? .unknown).title).foregroundStyle(.secondary)
        }.font(.caption)
    }
    var menuPermissionGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: store.menuAccessGranted ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 30)).foregroundStyle(palette.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.menuAccessGranted ? L("辅助功能已授权") : L("允许 Combo 检查菜单栏与图标设置"))
                        .font(.system(size: 21, weight: .semibold))
                    Text(L("一步设置 · 授权由你决定")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L("辅助功能是一项广泛的系统权限。Combo 用它读取系统设置中的三项勾选状态，并在正常退出时尝试恢复原状；实验性项目还可只读检查菜单栏访问；自动折叠已暂停。不截图或移动图标。"))
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Button(L("稍后再说")) { store.showMenuPermission = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("重新检查")) { store.refreshMenuAccess() }
                if store.menuAccessGranted {
                    Button(L("继续检测")) {
                        store.showMenuPermission = false
                        if page == .experimental { store.checkMenus() } else { setup.check() }
                    }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L("打开系统设置并授权")) { store.requestMenuAccess() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 510).tint(palette.accent)
            .onAppear { store.refreshMenuAccess() }
    }
    func foldRow(_ title: String, symbol: String, binding: Binding<Bool>) -> some View {
        HStack {
            Group {
                if symbol == "wifi" { WiFiIcon() } else { Image(systemName: symbol) }
            }.frame(width: 22).foregroundStyle(.secondary)
            Toggle(title, isOn: binding).toggleStyle(.checkbox); Spacer(); Text(L("未启用")).font(.caption).foregroundStyle(.tertiary)
        }
    }
    var media: some View {
        MediaPage(store: store)
    }

/// 媒体来源页：当前在播来源、菜单栏四个状态的对照、状态是怎么读到的。
/// 单独成视图是为了能脱离设置窗渲染核对（见 Tests/RenderMediaPage.swift）。
struct MediaPage: View {
    @ObserveInjection var inject
    @ObservedObject var store: Store
    @Environment(\.comboPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            nowPlaying
            menuBarSection
            readingSection
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
        }
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
                Text(L("菜单栏会怎么变")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button(store.scene == .music ? L("结束演示，返回本机状态") : L("在菜单栏演示播放")) { store.scene = store.scene == .music ? .live : .music }
                    .controlSize(.small)
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
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.top, 10)
        }
    }

    /// 图例只演示规则，所以两格播放态固定动画；系统开了减少动态效果时 ComboIcon 自己会停。
    private func legendTile(snapshot: Snapshot, title: String, note: String, animate: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            ComboIcon(snapshot: snapshot, animate: animate, size: 64).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(isCurrent ? palette.accent : Color.primary)
                Text(note).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            rule.padding(.bottom, 15)
            Text(L("Combo 怎么读到这些")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                factRow(key: L("读取"), text: L("只读取系统的播放状态：不采集声音、不录音，也不读取网页内容。"), first: true)
                factRow(key: L("识别"), text: L("未向系统报告播放状态的播放器不会出现在这里。"))
                factRow(key: L("保留"), text: L("曲目信息在播放结束后保留约 5 秒，切歌时不会闪空。"))
            }.padding(.top, 10)
        }
    }

    private func factRow(key: String, text: String, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { rule }
            HStack(alignment: .top, spacing: 14) {
                Text(key).font(.system(size: 11.5)).foregroundStyle(.tertiary).frame(width: 34, alignment: .leading)
                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(.vertical, 7)
        }
    }

    private var rule: some View {
        Rectangle().fill(Color.primary.opacity(0.055)).frame(height: 1)
    }
}

    var about: some View {
        VStack(spacing: 18) {
            Card {
                HStack(spacing: 22) { Image(nsImage: brandImage).resizable().frame(width: 80, height: 80).accessibilityHidden(true); VStack(alignment: .leading, spacing: 8) { Text("Combo").font(.system(size: 25, weight: .semibold)); Text(L("0.3.0 · 三合一预览版")).foregroundStyle(.secondary); Tag(text: "macOS 26+ · MacBook") } }
                Divider(); Text(L("电量、连接与音量，合在一个安静的图标里。")).font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text(L("当前能力")).font(.system(size: 13, weight: .semibold))
                Label(L("本机电池、Wi‑Fi 与声音操作"), systemImage: "checkmark.circle")
                Label(L("菜单栏图标、点击面板与六组设置"), systemImage: "checkmark.circle")
                Label(L("媒体播放状态与音柱动画"), systemImage: "checkmark.circle")
                Label(L("自动折叠尚未接入"), systemImage: "clock")
                Divider(); Text(L("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网未检测。")).font(.caption).foregroundStyle(.secondary)
                Text(store.observation.string).font(.caption).foregroundStyle(.secondary)
                Button(L("刷新本机状态")) { store.refresh() }
            }
        }
    }
}
