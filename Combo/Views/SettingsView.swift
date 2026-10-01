import SwiftUI
import Inject
import AppKit

enum Page: String, CaseIterable, Identifiable {
    case general = "通用", appearance = "外观与动效", integration = "系统菜单整合", media = "媒体来源", experimental = "实验性项目", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .integration: "menubar.rectangle"; case .media: "waveform"; case .experimental: "flask"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: "让 Combo 按你的习惯工作。"
        case .appearance: "让外观、图标与动效都按你的习惯呈现。"
        case .integration: "查看 Wi-Fi、声音与电池的日常功能。"
        case .media: "查看媒体播放检测与动画演示。"
        case .experimental: "自动隐藏与原生菜单实验，仍在验证中。"
        case .about: "轻一点的菜单栏，清楚一点的状态。"
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
struct SettingsView: View {
    @ObserveInjection var inject
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var setup: MenuBarSetup
    init(store: Store) { self.store = store; self.battery = store.battery; self.setup = store.menuSetup }
    @State private var page: Page = .appearance
    @State private var preview: Scene = .wired
    @State private var reset = false
    @State private var showingOnboarding = false
    @State private var thresholdDraft: Int?
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @AppStorage("foldWifi") var foldWifi = true
    @AppStorage("foldSound") var foldSound = true
    @AppStorage("foldBattery") var foldBattery = true
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
    var body: some View {
        HStack(spacing: 0) {
            if !onboardingCompleted || showingOnboarding {
                OnboardingView(store: store) {
                    onboardingCompleted = true
                    showingOnboarding = false
                    page = .general
                }
            } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(nsImage: brandImage)
                        .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) { Text("Combo").font(.system(size: 20, weight: .semibold)); Text("状态，合而为一").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 26)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).font(.system(size: 12, weight: page == item ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
                            .foregroundStyle(page == item ? palette.accent : .primary).background(page == item ? palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) { Tag(text: "PREVIEW 0.3"); Text("为 MacBook 而设计").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(14)
            }.padding(.horizontal, 10).frame(width: 180).background(palette.surface)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Text(page.rawValue).font(.system(size: 25, weight: .semibold)); Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }.padding(.bottom, 4)
                    switch page {
                    case .appearance: appearance
                    case .general: general
                    case .integration: integration
                    case .media: media
                    case .experimental: experimental
                    case .about: about
                    }
                    if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
                    .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
            }.background(palette.canvasTop)
            }
        }.frame(minWidth: 760, minHeight: 580).tint(palette.accent)
            .alert("恢复显示偏好？", isPresented: $reset) { Button("取消", role: .cancel) {}; Button("恢复") { store.resetDisplay() } } message: { Text("播放动效开启，电池显示阈值恢复为 50%。登录项和折叠选择保持不变。") }
            .sheet(isPresented: $store.showMenuPermission) { menuPermissionGuide }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshMenuAccess()
            }
            .alert("上次可能未恢复系统图标", isPresented: $setup.needsRecovery) {
                Button("尝试恢复") { Task { _ = await setup.restore() } }
                Button("稍后检查", role: .cancel) {}
            } message: { Text("请检查三枚系统图标；Combo 只能在读到原始状态时尝试恢复。") }
            .environment(\.comboPalette, palette)
            .enableInjection()
    }
    var appearance: some View {
        VStack(spacing: 18) {
            Card {
                Text("主题色").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) { ForEach(ComboTheme.allCases) { themeOption($0) } }
                Divider()
                Text("外观模式").font(.system(size: 13, weight: .semibold))
                Picker("外观模式", selection: $appearanceMode) {
                    ForEach(ComboAppearance.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                Text("跟随系统时，Combo 会随 macOS 的外观设置切换。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) { Text("效果预览").font(.system(size: 13, weight: .semibold)); Text("示例数据 · 不改变系统状态").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Tag(text: "实时预览")
                }
                HStack(spacing: 42) {
                    Spacer()
                    ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 112, previewScene: preview)
                    VStack(spacing: 12) { ComboIcon(snapshot: store.snapshot(for: preview), animate: store.animate, size: 22, previewScene: preview); Text("菜单栏尺寸").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.vertical, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(Scene.allCases.filter { $0 != .live }) { scene in
                        Button { preview = scene } label: {
                            Text(scene.rawValue).font(.system(size: 10)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(preview == scene ? palette.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(preview == scene ? palette.accent : .secondary)
                        }.buttonStyle(.plain).accessibilityAddTraits(preview == scene ? .isSelected : [])
                    }
                }
            }
            Card {
                Toggle("播放时显示音柱", isOn: $store.animate).toggleStyle(.switch)
                Text("固定循环，不录制声音，也不跟随音乐节奏。").font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack { Text("减少动态效果"); Spacer(); Text(store.reduceMotion ? "系统已开启 · 静态音柱" : "跟随系统设置").foregroundStyle(.secondary) }.font(.caption)
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
                Toggle("登录时启动 Combo", isOn: Binding(get: { store.login }, set: { store.setLogin($0) })).toggleStyle(.switch)
                Text("登录后显示菜单栏图标，不增加独立后台服务。").font(.caption).foregroundStyle(.secondary)
            }
            Card { Button("重新查看首次使用引导") { showingOnboarding = true } }
            Card {
                Label("手动隐藏系统图标", systemImage: "menubar.rectangle").font(.headline)
                Text("在“系统设置 → 菜单栏”中，由你亲自关闭 Wi‑Fi、声音，以及有内置电池的 Mac 上的电池图标显示。Combo 不会自动隐藏图标，也不会影响控制中心。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("这里的状态记录和检测需要辅助功能权限。若已在引导中隐藏图标，Combo 没有更改前的记录；需要恢复时请手动操作。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开设置并记录当前状态") { setup.openAndCapture() }
                    Button("重新检测") { setup.check() }.disabled(setup.busy)
                    if setup.busy { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 22) {
                    setupRow("Wi‑Fi", key: "wifi", symbol: "wifi")
                    setupRow("声音", key: "sound", symbol: "speaker.wave.2")
                    setupRow("电池", key: "battery", symbol: "battery.75percent")
                }
                Text("检测仅读取系统设置控件，不能证明图标此刻在屏幕上可见；请在菜单栏人工复核。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("尝试恢复原来的图标设置") { Task { _ = await setup.restore() } }
                Text(setup.message).font(.caption).foregroundStyle(.secondary)
            }
            Card { Button("辅助功能权限…") { store.refreshMenuAccess(); store.showMenuPermission = true } }
            Card {
                Text("预览版体验").font(.system(size: 13, weight: .semibold))
                Picker("菜单栏数据", selection: $store.scene) { ForEach(Scene.allCases) { Text($0 == .live ? $0.rawValue : "演示 · \($0.rawValue)").tag($0) } }
                Text("选择演示场景，可以在真实菜单栏查看播放、静音与充电效果。退出后恢复本机状态。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("恢复显示偏好"); Text("仅重置播放动效和电池显示阈值").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("恢复…") { reset = true } }
                Divider(); HStack { Text("关闭设置窗口后，Combo 继续运行。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("退出 Combo") { NSApp.terminate(nil) } }
            }
        }
    }
    var integration: some View {
        VStack(spacing: 18) {
            Card {
                Label { Text("Wi‑Fi") } icon: { WiFiIcon() }.font(.headline)
                Text("主面板显示已连接、已知与其他网络，支持开关、信号强弱和基础安全提示。首次查找会请求定位权限；个人热点与企业认证使用系统 Wi‑Fi 设置。")
                    .font(.caption).foregroundStyle(.secondary)
                WiFiPasswordSettings(wifi: store.wifi)
                Button("打开 Wi‑Fi 设置") { store.openSystemSettings("wifi") }
            }
            Card {
                Label("声音", systemImage: "speaker.wave.2").font(.headline)
                Text("主面板可切换可用输出设备、调节音量与静音。AirPods 降噪等高级控制使用系统声音设置或控制中心。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开声音设置") { store.openSystemSettings("sound") }
            }
            Card {
                Label("电池", systemImage: "battery.75percent").font(.headline)
                let threshold = thresholdDraft ?? battery.displayThreshold
                HStack(spacing: 8) {
                    Text("优先显示电量的阈值").fixedSize()
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
                    .accessibilityLabel("优先显示电量的阈值")
                    .accessibilityValue(threshold == 0 ? "0%，关闭" : "\(threshold)%")
                    .frame(width: 160)
                    Text(threshold == 0 ? "关闭" : "\(threshold)%")
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                Text("Wi-Fi 正常连接且电量低于此值时，中央显示电量百分比。设为 0% 可关闭低电量自动显示；正在充电时仍优先显示电量；拔插电源或充电状态变化时仍会播放临时提示。").font(.caption).foregroundStyle(.secondary)
                Text("主面板显示电量、电源来源、充电状态、当前充电上限、低电量模式和系统提供的粗略健康状态。能耗模式仅修改点击时的电源类型，需要管理员授权，退出 Combo 后保留。接电且确认被手动上限暂停充电时，可点击“立即充满电”；临时解除限制后的恢复由 macOS 管理，退出 Combo 不会取消。暂不支持仅优化充电暂缓的情况，无法操作时请使用系统电池设置。高耗能应用显示在主面板，可在活动监视器查看详细能耗。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("电池详情高耗能应用上限", selection: $battery.energyAppLimit) {
                    ForEach(1...3, id: \.self) { Text("\($0) 个").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("电池详情高耗能应用上限")
                Text("概览固定显示 1 个；电池详情默认最多 1 个，按系统数据源顺序显示。没有高耗能应用时不补充其他应用，无法获取时会明确提示。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Button("打开电池设置") { store.openSystemSettings("battery") }; Button("查看耗电应用") { store.openActivityMonitor() } }
            }
        }
    }
    var experimental: some View {
        VStack(spacing: 18) {
            Card {
                HStack { Text("系统菜单整合").font(.system(size: 13, weight: .semibold)); Spacer(); Tag(text: "macOS 27 实验") }
                Toggle("整合系统菜单", isOn: .constant(false)).toggleStyle(.switch).disabled(true)
                Text("自动折叠已暂停：现有方式会同时隐藏 Combo 图标。确认恢复入口始终可见前，总开关与单项实验均不启用。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("准备折叠的项目").font(.system(size: 13, weight: .semibold))
                foldRow("Wi-Fi", symbol: "wifi", binding: $foldWifi)
                Divider(); foldRow("声音／AirPods", symbol: "headphones", binding: $foldSound)
                Divider(); foldRow("电池", symbol: "battery.75percent", binding: $foldBattery)
                Text("选择会保存，但当前不执行折叠。系统日期尚未纳入。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("8 秒单项折叠实验").font(.system(size: 13, weight: .semibold))
                Text("实验暂停中。原实验一次仅折叠一项，8 秒后释放；仍保留“立即恢复”入口。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("试 Wi-Fi") { store.foldExperiment.preview(systemID: 6) { store.foldExperimentMessage = $0 } }
                    Button("试声音") { store.foldExperiment.preview(systemID: 5) { store.foldExperimentMessage = $0 } }
                    Button("试电池") { store.foldExperiment.preview(systemID: 0) { store.foldExperimentMessage = $0 } }
                }.disabled(!MenuFoldExperiment.available)
                Button("立即恢复") { store.foldExperiment.release(); store.foldExperimentMessage = "实验限制已释放。" }
                Text(store.foldExperimentMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Card {
                Label("原生菜单入口 · 尚待验证", systemImage: "cursorarrow.click").font(.system(size: 13, weight: .semibold))
                Text("目标交互：打开 Combo → 选择 Wi-Fi、声音或电池 → 临时展开系统菜单 → 关闭后收起。只有确认 Combo 图标持续可见后才会启用折叠。").font(.caption).foregroundStyle(.secondary)
                Text("只有点击授权按钮时才会请求辅助功能。检查仅读取菜单栏，不会启用自动折叠。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("检查菜单访问") { store.checkMenus() }.disabled(store.checkingMenus)
                    Button("授权辅助功能…") { store.refreshMenuAccess(); store.showMenuPermission = true }
                    if store.checkingMenus { ProgressView().controlSize(.small) }
                }
                Text("本机已读到三个系统项目的辅助功能候选；实际可见性和原生菜单打开仍待验证。为避免误点，不按缓存坐标触发菜单。").font(.caption).foregroundStyle(.secondary)
                Text(store.menuDiagnostic).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    func setupRow(_ title: String, key: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(title) } icon: {
                if symbol == "wifi" { WiFiIcon() } else { Image(systemName: symbol) }
            }
            Text((setup.states[key] ?? .unknown).rawValue).foregroundStyle(.secondary)
        }.font(.caption)
    }
    var menuPermissionGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: store.menuAccessGranted ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 30)).foregroundStyle(palette.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.menuAccessGranted ? "辅助功能已授权" : "允许 Combo 检查菜单栏与图标设置")
                        .font(.system(size: 21, weight: .semibold))
                    Text("一步设置 · 授权由你决定").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("辅助功能是一项广泛的系统权限。Combo 用它读取系统设置中的三项勾选状态，并在正常退出时尝试恢复原状；实验性项目还可只读检查菜单栏访问；自动折叠已暂停。不截图或移动图标。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Card {
                Text("在辅助功能列表中开启 Combo").font(.headline)
                Text("系统设置 → 隐私与安全性 → 辅助功能").font(.subheadline)
                Text("若列表中没有 Combo，点击“＋”，选择当前运行的 Combo.app。系统可能要求你输入密码或使用 Touch ID。").font(.caption).foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Label(store.menuAccessGranted ? "已确认授权，可以继续检测。" : "系统尚未允许当前进程访问；不一定是开关未开启。", systemImage: store.menuAccessGranted ? "checkmark.circle.fill" : "info.circle")
                .font(.subheadline).foregroundStyle(store.menuAccessGranted ? palette.accent : .secondary)
            if !store.menuPermissionMessage.isEmpty {
                Text(store.menuPermissionMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("如果系统开关已开启：先退出并重新打开 Combo。仍无效时，请在系统权限列表中移除旧 Combo，再用上方路径添加当前应用并开启。开发预览版重新编译后，旧授权可能不再匹配。系统新版也可能将此项称为“设备控制和数据访问”。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("你可以随时在同一页面关闭权限。稍后授权不影响电量、网络与音量显示，但 Combo 将无法自动读取或恢复系统图标设置。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("稍后再说") { store.showMenuPermission = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("重新检查") { store.refreshMenuAccess() }
                if store.menuAccessGranted {
                    Button("继续检测") {
                        store.showMenuPermission = false
                        if page == .experimental { store.checkMenus() } else { setup.check() }
                    }.keyboardShortcut(.defaultAction)
                } else {
                    Button("打开系统设置并授权") { store.requestMenuAccess() }.keyboardShortcut(.defaultAction)
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
            Toggle(title, isOn: binding).toggleStyle(.checkbox); Spacer(); Text("未启用").font(.caption).foregroundStyle(.tertiary)
        }
    }
    var media: some View {
        VStack(spacing: 18) {
            Card {
                HStack { Text("媒体来源").font(.system(size: 13, weight: .semibold)); Spacer(); Tag(text: !store.mediaControlsAvailable && store.mediaVisible ? "重新连接中" : store.live.playing ? "正在播放" : store.mediaVisible ? "已暂停" : "未检测到播放") }
                if store.mediaVisible {
                    HStack(spacing: 12) {
                        if let artwork = store.mediaTrack?.artwork, let image = NSImage(data: artwork) {
                            Image(nsImage: image).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                        } else { Image(systemName: "music.note").frame(width: 40, height: 40).foregroundStyle(palette.accent).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.mediaTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            if let artist = store.mediaTrack?.artist, !artist.isEmpty { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            if let source = store.mediaTrack?.source, !source.isEmpty { Text(source).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                } else { Text("当前没有可识别的媒体").font(.caption).foregroundStyle(.secondary) }
                ForEach(["Safari", "Chrome", "网易云音乐", "QQ 音乐"], id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: name == "Safari" || name == "Chrome" ? "globe" : "music.note").font(.system(size: 18)).foregroundStyle(palette.accent).frame(width: 34, height: 36).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) { Text(name); Text("应用向系统提供播放状态时自动识别").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }.padding(.vertical, 5)
                }
            }
            Card {
                Label("先看看播放效果", systemImage: "waveform").font(.system(size: 13, weight: .semibold))
                Text("检测到音乐或视频播放时，底部圆点自动变为起伏音柱；音量为零或静音时显示静音图标。只读取播放状态，不采集声音；未向系统提供状态的播放器可能无法识别。").font(.caption).foregroundStyle(.secondary)
                Button(store.scene == .music ? "结束演示，返回本机状态" : "在菜单栏演示播放") { store.scene = store.scene == .music ? .live : .music }
            }
        }
    }
    var about: some View {
        VStack(spacing: 18) {
            Card {
                HStack(spacing: 22) { Image(nsImage: brandImage).resizable().frame(width: 80, height: 80).accessibilityHidden(true); VStack(alignment: .leading, spacing: 8) { Text("Combo").font(.system(size: 25, weight: .semibold)); Text("0.3.0 · 三合一预览版").foregroundStyle(.secondary); Tag(text: "macOS 26+ · MacBook") } }
                Divider(); Text("电量、连接与音量，合在一个安静的图标里。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("当前能力").font(.system(size: 13, weight: .semibold))
                Label("本机电池、Wi‑Fi 与声音操作", systemImage: "checkmark.circle")
                Label("菜单栏图标、点击面板与六组设置", systemImage: "checkmark.circle")
                Label("媒体播放状态与音柱动画", systemImage: "checkmark.circle")
                Label("自动折叠尚未接入", systemImage: "clock")
                Divider(); Text("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网未检测。").font(.caption).foregroundStyle(.secondary)
                Text(store.observation).font(.caption).foregroundStyle(.secondary)
                Button("刷新本机状态") { store.refresh() }
            }
        }
    }
}
