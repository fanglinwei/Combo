import SwiftUI
import AppKit

let accent = Color(nsColor: NSColor(name: NSColor.Name("ComboAccent")) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return dark ? NSColor(srgbRed: 185/255, green: 165/255, blue: 245/255, alpha: 1)
                : NSColor(srgbRed: 102/255, green: 80/255, blue: 180/255, alpha: 1)
})
let canvas = Color(nsColor: NSColor(name: NSColor.Name("ComboCanvas")) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return dark ? NSColor(srgbRed: 38/255, green: 34/255, blue: 47/255, alpha: 1)
                : NSColor(srgbRed: 245/255, green: 243/255, blue: 248/255, alpha: 1)
})
let brandImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "Combo", ofType: "icns") ?? "")
    ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: nil)!
enum Page: String, CaseIterable, Identifiable {
    case general = "通用", appearance = "图标与动效", integration = "系统菜单整合", media = "媒体来源", experimental = "实验性项目", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .integration: "menubar.rectangle"; case .media: "waveform"; case .experimental: "flask"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: "让 Combo 按你的习惯工作。"
        case .appearance: "一个图标，刚好装下你需要的状态。"
        case .integration: "查看 Wi-Fi、声音与电池的日常功能。"
        case .media: "查看媒体适配计划与播放演示。"
        case .experimental: "自动隐藏与原生菜单实验，仍在验证中。"
        case .about: "轻一点的菜单栏，清楚一点的状态。"
        }
    }
}
struct Tag: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(accent).background(accent.opacity(0.1), in: Capsule()) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055))) }
}
struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var setup: MenuBarSetup
    init(store: Store) { self.store = store; self.setup = store.menuSetup }
    @State private var page: Page = .appearance
    @State private var preview: Scene = .wired
    @State private var reset = false
    @State private var thresholdDraft: Int?
    @AppStorage("foldWifi") var foldWifi = true
    @AppStorage("foldSound") var foldSound = true
    @AppStorage("foldBattery") var foldBattery = true
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(nsImage: brandImage)
                        .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) { Text("Combo").font(.system(size: 20, weight: .semibold)); Text("状态，合而为一").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 14).padding(.top, 22).padding(.bottom, 26)
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).font(.system(size: 12, weight: page == item ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 11)
                            .foregroundStyle(page == item ? accent : .primary).background(page == item ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) { Tag(text: "PREVIEW 0.3"); Text("为 MacBook 而设计").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(14)
            }.padding(.horizontal, 10).frame(width: 180).background(.thinMaterial)
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
            }.background(canvas)
        }.frame(minWidth: 760, minHeight: 580).tint(accent)
            .alert("恢复显示偏好？", isPresented: $reset) { Button("取消", role: .cancel) {}; Button("恢复") { store.resetDisplay() } } message: { Text("播放动效开启，电池显示阈值恢复为 50%。登录项和折叠选择保持不变。") }
            .sheet(isPresented: $store.showMenuPermission) { menuPermissionGuide }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshMenuAccess()
            }
            .alert("上次可能未恢复系统图标", isPresented: $setup.needsRecovery) {
                Button("尝试恢复") { Task { _ = await setup.restore() } }
                Button("稍后检查", role: .cancel) {}
            } message: { Text("请检查三枚系统图标；Combo 只能在读到原始状态时尝试恢复。") }
    }
    var appearance: some View {
        VStack(spacing: 18) {
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
                                .background(preview == scene ? accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(preview == scene ? accent : .secondary)
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
    var general: some View {
        VStack(spacing: 18) {
            Card {
                Toggle("登录时启动 Combo", isOn: Binding(get: { store.login }, set: { store.setLogin($0) })).toggleStyle(.switch)
                Text("登录后显示菜单栏图标，不增加独立后台服务。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label("手动隐藏系统图标", systemImage: "menubar.rectangle").font(.headline)
                Text("在“系统设置 → 菜单栏”中，由你亲自关闭 Wi‑Fi、声音、电池的菜单栏显示。Combo 不会自动隐藏图标，也不会影响控制中心。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("先打开设置以记录原始状态；改完后返回这里重新检测。正常退出时 Combo 会尝试恢复原状，异常退出后可能需要手动恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开菜单栏设置并记录原状态") { setup.openAndCapture() }
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
                let threshold = thresholdDraft ?? store.batteryDisplayThreshold
                HStack(spacing: 8) {
                    Text("优先显示电量的阈值").fixedSize()
                    Spacer(minLength: 12)
                    Slider(value: Binding(
                        get: { Double(thresholdDraft ?? store.batteryDisplayThreshold) },
                        set: { value in
                            if thresholdDraft != nil { thresholdDraft = Int(value.rounded()) }
                            else { store.batteryDisplayThreshold = Int(value.rounded()) }
                        }
                    ), in: 0...100, onEditingChanged: { editing in
                        if editing { thresholdDraft = store.batteryDisplayThreshold }
                        else {
                            if let thresholdDraft { store.batteryDisplayThreshold = thresholdDraft }
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
                Picker("高耗能应用显示上限", selection: $store.energyAppLimit) {
                    ForEach(1...3, id: \.self) { Text("\($0) 个").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("高耗能应用显示上限")
                Text("默认最多 1 个，按系统数据源顺序显示；没有高耗能应用时不补充其他应用。无法获取时会明确提示。")
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
                    .font(.system(size: 30)).foregroundStyle(accent).accessibilityHidden(true)
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
                .font(.subheadline).foregroundStyle(store.menuAccessGranted ? accent : .secondary)
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
        }.padding(28).frame(width: 510).tint(accent)
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
                HStack { Text("媒体来源").font(.system(size: 13, weight: .semibold)); Spacer(); Tag(text: "适配准备中") }
                ForEach(["Safari", "Chrome", "网易云音乐", "QQ 音乐"], id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: name == "Safari" || name == "Chrome" ? "globe" : "music.note").font(.system(size: 18)).foregroundStyle(accent).frame(width: 34, height: 36).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 5) { Text(name); Text(name == "Safari" || name == "Chrome" ? "通过配套扩展读取已授权页面" : "需验证辅助功能播放状态").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Toggle("启用 \(name)", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).disabled(true)
                    }.padding(.vertical, 5)
                }
            }
            Card {
                Label("先看看播放效果", systemImage: "waveform").font(.system(size: 13, weight: .semibold))
                Text("媒体尚未接入，当前不会自动识别播放器。可以用演示模式查看菜单栏音柱；没有采集任何系统声音。").font(.caption).foregroundStyle(.secondary)
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
                Label("媒体适配、自动折叠尚未接入", systemImage: "clock")
                Divider(); Text("不上传状态，不读取网页，不录音或截图。无线图标只表示路径类型，不代表信号格数；互联网未检测。").font(.caption).foregroundStyle(.secondary)
                Text(store.observation).font(.caption).foregroundStyle(.secondary)
                Button("刷新本机状态") { store.refresh() }
            }
        }
    }
}
struct PanelView: View {
    @ObservedObject var store: Store
    let showSettings: () -> Void
    let height: CGFloat?
    @ViewBuilder var body: some View {
        if let height {
            ScrollView { content }.frame(width: 340, height: height).tint(accent)
        } else {
            content.frame(width: 340).tint(accent)
        }
    }
    var content: some View {
        let s = store.snapshot
        return VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Combo · 三合一").font(.system(size: 16, weight: .semibold)); Spacer(); Button(action: showSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置…").accessibilityLabel("设置") }
            HStack(spacing: 16) {
                ComboIcon(snapshot: s, animate: store.animate, size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.batteryText).font(.system(size: 28, weight: .medium, design: .rounded))
                    if store.scene == .live {
                        Text("电源：\(store.batterySourceText)").font(.caption).foregroundStyle(.secondary)
                        Text(store.batteryStatusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("演示数据 · 不改变系统状态").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.scene == .live {
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前充电上限：\(store.chargeLimit.text)")
                    Text("健康：\(store.batteryHealth) · 低电量模式：\(store.lowPowerMode ? "开" : "关")")
                }.font(.caption).foregroundStyle(.secondary)
                ChargeFullSection(control: store.chargeControl, eligible: store.canRequestFullCharge,
                                  expectedLimit: store.chargeLimit, action: store.requestFullCharge)
                PowerModeSection(control: store.powerMode, source: store.batteryOnAC.map { $0 ? .adapter : .battery }) {
                    store.refreshBattery()
                }
                EnergyAppsSection(control: store.energyApps, limit: store.energyAppLimit, active: store.screenActive)
            } else {
                Button("返回本机状态") { store.scene = .live }.font(.caption)
            }
            HStack { Button("电池设置") { store.openSystemSettings("battery") }; Button("耗电应用") { store.openActivityMonitor() } }.font(.caption)
            Divider()
            WiFiSection(wifi: store.wifi, hotspots: store.hotspots, connection: s.network, active: store.screenActive,
                        openSettings: { store.openSystemSettings("wifi") })
            Divider()
            Label("声音", systemImage: "speaker.wave.2").font(.headline)
            HStack { Text(s.muted ? "静音" : "音量"); Spacer(); Text(s.volumeText).foregroundStyle(.secondary) }.font(.caption)
            Slider(value: Binding(get: { s.volume ?? 0 }, set: { store.setVolume($0) }), in: 0...1).disabled(store.scene != .live || !store.canVolume).accessibilityLabel("系统音量")
            SoundOutputs(store: store)
            HStack { Button(s.muted ? "取消静音" : "静音") { store.toggleMute() }.disabled(store.scene != .live || !store.canMute); Button("声音设置 / AirPods") { store.openSystemSettings("sound") } }.font(.caption)
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack { Spacer(); Button("退出 Combo") { NSApp.terminate(nil) }; Button("设置…", action: showSettings) }.font(.caption)
        }.padding(20)
    }
}
struct SoundOutputs: View {
    @ObservedObject var store: Store
    @ObservedObject var control: AirPodsControl
    @State private var expanded = true
    @State private var hoveredOutput: UInt32?
    init(store: Store) { self.store = store; self.control = store.airpods }
    private var active: Bool { store.scene == .live && store.panelVisible && store.screenActive }
    private var state: AirPodsReply? {
        guard store.scene == .live, let state = control.snapshot,
              state.available, state.deviceID == store.selectedOutputID else { return nil }
        return state
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.bottom, 10)
            Text("输出").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            if store.outputDevices.isEmpty { Text("暂无可用输出设备").font(.caption).foregroundStyle(.secondary) }
            ForEach(store.outputDevices) { output in
                let selected = output.id == store.selectedOutputID
                HStack(spacing: 0) {
                    Button { store.setOutput(output.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: output.symbol).font(.system(size: 16))
                                .foregroundStyle(selected ? Color.white : Color.secondary)
                                .frame(width: 26, height: 26)
                                .background(selected ? Color.blue : Color.primary.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(output.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if selected, let state { battery(state) }
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.scene != .live)
                    .accessibilityLabel(output.name)
                    .accessibilityValue(selected ? "当前输出" + (state.map { "，" + $0.batteryText } ?? "") : "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    if selected, let state, !state.modes.isEmpty || state.conversation != nil {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 28, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? "收起耳机选项" : "展开耳机选项")
                        .accessibilityValue(expanded ? "已展开" : "已收起")
                    }
                }.padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(hoveredOutput == output.id && store.scene == .live ? 0.10 : 0))
                            .padding(.horizontal, -5)
                    }
                    .onHover { hoveredOutput = $0 ? output.id : nil }
                if selected, let state, expanded, !state.modes.isEmpty || state.conversation != nil {
                    AirPodsSection(control: control, state: state)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.16))
                        .padding(.horizontal, -14).padding(.top, 5).padding(.bottom, 4)
                }
            }
            if active && control.snapshot == nil {
                Text(control.unavailable ? "耳机控制暂不可用" : "正在读取耳机状态…")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            if !control.message.isEmpty {
                Text(control.message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            if control.unavailable {
                Button("重新读取耳机状态") { control.refresh(deviceID: store.selectedOutputID) }
                    .font(.caption).disabled(control.busy).padding(.top, 6)
            }
        }
        .onChange(of: store.selectedOutputID) { _, _ in expanded = true }
        .task(id: "\(active)-\(store.selectedOutputID)") {
            guard active else { control.cancel(); return }
            // ponytail: poll only while visible; replace with private notifications if measured cost warrants it.
            while !Task.isCancelled {
                control.refresh(deviceID: store.selectedOutputID)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .onDisappear { control.cancel() }
    }
    private func battery(_ state: AirPodsReply) -> some View {
        HStack(spacing: 8) {
            if let left = state.left { Label("\(left)%", systemImage: "airpods.pro.left") }
            if let right = state.right { Label("\(right)%", systemImage: "airpods.pro.right") }
            if let charge = state.caseBattery { Label("\(charge)%", systemImage: "airpodspro.chargingcase.wireless") }
            if state.left == nil && state.right == nil && state.caseBattery == nil { Text(state.batteryText) }
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore).accessibilityLabel(state.batteryText)
    }
}
struct AirPodsSection: View {
    @ObservedObject var control: AirPodsControl
    let state: AirPodsReply
    @State private var hoveredOption: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.modes.isEmpty {
                heading("聆听模式")
                let modes = state.modes.filter { $0 != .off }
                segmentTrack(count: modes.count) {
                    ForEach(modes) { mode in
                        option(mode.title, symbol: symbol(mode), selected: state.mode == mode,
                               enabled: state.canSetMode) { control.setMode(mode) }
                    }
                }
                if state.mode == nil { Text("当前模式暂不可用").font(.caption).foregroundStyle(.secondary) }
            }
            if let conversation = state.conversation {
                if !state.modes.isEmpty { Divider().padding(.vertical, 10) }
                heading("对话感知")
                segmentTrack(count: 2) {
                    option("关闭", symbol: "person.wave.2.fill", selected: !conversation,
                           enabled: state.canSetConversation) { control.setConversation(false) }
                    option("打开", symbol: "person.wave.2.fill", selected: conversation,
                           enabled: state.canSetConversation) { control.setConversation(true) }
                }
            }
        }
    }
    private func segmentTrack<Content: View>(count: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .background(alignment: .top) {
                GeometryReader { geometry in
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.75))
                        .padding(.horizontal, max(0, (geometry.size.width / CGFloat(max(1, count)) - 62) / 2 - 2))
                }.frame(height: 48)
            }
    }
    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 5)
    }
    private func symbol(_ mode: ListeningMode) -> String {
        switch mode {
        case .transparency: "person.open.fill"
        case .adaptive: "person.and.sparkles.fill"
        case .noiseCancellation: "person.closed.fill"
        case .off: "person.fill"
        }
    }
    private func option(_ title: String, symbol: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        // These three listening glyphs are shipped in macOS's private symbol bundle.
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? Bundle(path: "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle")?.image(forResource: symbol)
            ?? NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)!
        return Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: glyph).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 62, height: 44)
                    .background {
                        Capsule().fill(selected ? Color.blue : Color.primary.opacity(hoveredOption == title ? 0.12 : 0))
                    }
                    .overlay(Capsule().strokeBorder(selected ? Color.white.opacity(0.55) : .clear, lineWidth: 0.75))
                    .padding(.top, 2)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredOption = $0 ? title : nil }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选中" : "未选中")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(control.busy || control.unavailable || !enabled)
    }
}
struct EnergyAppsSection: View {
    @ObservedObject var control: EnergyApps
    let limit: Int
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("高耗能应用").font(.caption).foregroundStyle(.secondary)
            switch control.state {
            case .loading:
                Text("正在获取能耗信息…").foregroundStyle(.secondary)
            case .unavailable:
                Text("暂时无法获取能耗信息").foregroundStyle(.secondary)
            case .available(let apps):
                if apps.isEmpty {
                    Text("没有使用大量能耗的 App").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(apps.prefix(EnergyApps.displayLimit(limit)))) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                            }
                            Text(app.name).lineLimit(1).help(app.name)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .font(.caption)
        .task(id: active) {
            guard active else { control.cancel(); return }
            while !Task.isCancelled {
                control.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onDisappear { control.cancel() }
    }
}
struct ChargeFullSection: View {
    @ObservedObject var control: ChargeControl
    let eligible: Bool
    let expectedLimit: ChargeLimit
    let action: () -> Void
    private var enabled: Bool {
        guard eligible, !control.busy, control.snapshot?.canRequest == true,
              case .value(let limit) = expectedLimit else { return false }
        return control.snapshot?.limit == limit
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button("立即充满电", action: action).disabled(!enabled)
                if control.busy { ProgressView().controlSize(.small).accessibilityLabel("正在检查充电状态") }
            }
            Text("临时解除手动充电上限；恢复由 macOS 管理，退出 Combo 不会取消。")
                .foregroundStyle(.secondary)
            if !control.message.isEmpty {
                Text(control.message).foregroundStyle(.secondary)
            } else if !control.busy && control.snapshot?.supported != true {
                Text("当前系统无法提供此操作，请使用下方电池设置入口。").foregroundStyle(.secondary)
            } else if !control.busy && !enabled {
                Text("仅在接电且手动上限暂停充电时可用。").foregroundStyle(.secondary)
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
struct PowerModeSection: View {
    @ObservedObject var control: PowerModeControl
    let source: PowerSource?
    let refresh: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let source, let policy = control.policies[source] {
                Picker("能耗模式 · \(source.title)", selection: Binding(get: { policy.mode }, set: { mode in
                    Task { await control.set(mode, source: source); refresh() }
                })) {
                    ForEach(PowerMode.allCases.filter { policy.supportsHigh || $0 != .high }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.disabled(control.busy)
                Text("更改需要管理员授权，仅影响\(source.title)时的设置。")
                    .foregroundStyle(.secondary)
            } else {
                Text(control.busy ? "正在读取能耗模式…" : "能耗模式无法读取，请打开电池设置。")
                    .foregroundStyle(.secondary)
            }
            if !control.message.isEmpty {
                Text(control.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.caption)
    }
}

struct WiFiPasswordSettings: View {
    @ObservedObject var wifi: WiFiControl
    @State private var showExplanation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("使用系统保存的 Wi‑Fi 密码", isOn: $wifi.useSystemPasswords)
            Text("仅在你点击已知网络时，读取该网络的密码用于 Wi‑Fi 切换；不读取其他钥匙串项目，不另存系统密码，不上传网络名称或密码。")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("钥匙串授权与隐私", isExpanded: $showExplanation) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("开启此开关不代表已获系统授权。下次点击已知网络时，macOS 可能询问是否允许访问该密码；可选择允许一次、始终允许或拒绝。")
                    Text("拒绝或取消后，本次运行不再请求。关闭开关会停止后续读取，但不会撤销 macOS 已授予的访问权限；如需撤销，可在“钥匙串访问”中管理对应项目。")
                    Text("不授权也可手动输入密码。默认在连接成功后保存到本机的 Combo 钥匙串项目；可取消“在本机记住密码”，也可在连接表单删除 Combo 已存密码。密码不会上传服务器。")
                    Button("允许下次请求授权") { wifi.allowSystemPasswordRequests() }
                        .disabled(wifi.busy)
                    Text("此按钮只恢复请求资格；请回到 Wi‑Fi 面板点击要连接的已知网络。")
                        .foregroundStyle(.secondary)
                }.font(.caption).padding(.top, 6)
            }
            if wifi.systemAccessDeclined {
                Text("本次运行已停止请求系统密码。可展开上方授权入口，重新允许下次请求。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HotspotStatusIcons: View {
    let signal: Int?
    let battery: Int?
    var body: some View {
        HStack(spacing: 7) {
            if let signal {
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.secondary.opacity(index < signal ? 1 : 0.3))
                            .frame(width: 3, height: CGFloat(4 + index * 3))
                    }
                }.frame(height: 13)
            }
            if let battery {
                HStack(spacing: 1) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.secondary.opacity(0.8), lineWidth: 1)
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.secondary.opacity(0.25))
                                .frame(width: 21 * CGFloat(battery) / 100)
                            Spacer(minLength: 0)
                        }.frame(width: 21, height: 9)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        Text("\(battery)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.primary.opacity(0.85))
                    }.frame(width: 25, height: 13)
                    Capsule().fill(Color.secondary.opacity(0.8)).frame(width: 1.5, height: 5)
                }
            }
        }.fixedSize()
    }
}

struct PersonalHotspotSection: View {
    @ObservedObject var control: HotspotControl
    let openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("个人热点").foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) { Image(systemName: "arrow.up.forward") }
                    .buttonStyle(.plain).accessibilityLabel("打开个人热点系统设置")
                    .help("打开系统 Wi‑Fi 设置")
            }
            switch control.state {
            case .loading:
                Text("正在查找个人热点…").foregroundStyle(.secondary)
            case .unavailable:
                HStack {
                    Text("暂时无法读取手机信息").foregroundStyle(.secondary)
                    Button("重试") { control.start() }.buttonStyle(.plain)
                }
            case .available(let phones):
                if phones.isEmpty {
                    Text("未发现可用个人热点").foregroundStyle(.secondary)
                }
                ForEach(phones) { phone in
                    Button(action: openSettings) {
                        HStack(spacing: 9) {
                            Image(systemName: "personalhotspot")
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.08), in: Circle())
                            Text(phone.name).lineLimit(1).help(phone.name)
                            Spacer(minLength: 4)
                            HotspotStatusIcons(signal: phone.signal, battery: phone.battery)
                                .accessibilityHidden(true)
                        }.padding(.vertical, 2).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(phone.name
                            + (phone.signal.map { "，蜂窝信号等级 \($0)" } ?? "")
                            + (phone.battery.map { "，电量 \($0)%" } ?? ""))
                        .accessibilityHint("打开系统 Wi‑Fi 设置，由你选择连接")
                        .help("在系统 Wi‑Fi 设置中连接此手机")
                }
            }
        }.font(.caption)
    }
}

struct WiFiSection: View {
    @ObservedObject var wifi: WiFiControl
    let hotspots: HotspotControl
    let connection: String
    let active: Bool
    let openSettings: () -> Void
    private var selected: WiFiChoice? { wifi.passwordRequest }
    @State private var password = ""
    @State private var remember = true
    @State private var otherExpanded = false
    @State private var useSavedPassword = false
    private var known: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) == true } }
    private var others: [WiFiChoice] { wifi.networks.filter { !wifi.isConnected($0) && wifi.knownNames?.contains($0.name) != true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label { Text("Wi‑Fi") } icon: { WiFiIcon() }.font(.headline)
                Spacer()
                if wifi.busy { ProgressView().controlSize(.small).accessibilityLabel("正在处理 Wi‑Fi 操作") }
                Toggle("Wi‑Fi", isOn: Binding(get: { wifi.powerOn ?? false }, set: { wifi.setPower($0) }))
                    .toggleStyle(.switch).labelsHidden().disabled(wifi.powerOn == nil || wifi.busy)
            }
            if wifi.powerOn == true {
                if let name = wifi.currentSSID {
                    networkLabel(name, rssi: wifi.currentRSSI, secure: false, connected: true)
                    if let warning = WiFiChoice.warning(for: wifi.currentSecurity) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(wifi.nameAccess ? "未连接或网络名称暂不可用" : "允许定位后显示网络名称")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                PersonalHotspotSection(control: hotspots, openSettings: openSettings)
                if !known.isEmpty {
                    Divider()
                    Text("已知网络").font(.caption).foregroundStyle(.secondary)
                    ForEach(known) { networkRow($0) }
                }
                Divider()
                DisclosureGroup(isExpanded: $otherExpanded) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(others) { networkRow($0) }
                        if others.isEmpty {
                            Text(wifi.hasScanned ? "未发现其他网络" : "点击“查找网络”获取列表")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 5)
                } label: {
                    Text(wifi.knownNames == nil ? "附近网络" : "其他网络").font(.caption)
                }
                HStack {
                    Button(wifi.hasScanned ? "刷新网络" : "查找网络") { wifi.scan() }.disabled(wifi.busy)
                    Spacer()
                    Text("默认路径：\(connection)").foregroundStyle(.secondary)
                }.font(.caption)
                if wifi.hasScanned && wifi.knownNames == nil {
                    Text("暂时无法区分已知网络。").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(wifi.powerOn == false ? "Wi‑Fi 已关闭" : "Wi‑Fi 接口不可用").font(.caption).foregroundStyle(.secondary)
            }
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接 \(selected.name)").font(.caption).fontWeight(.semibold)
                    if selected.requiresSystemJoin {
                        Text("此网络的认证需要在系统 Wi‑Fi 设置中完成。").font(.caption).foregroundStyle(.secondary)
                        Button("在系统设置中连接", action: openSettings).font(.caption)
                    } else {
                        if let warning = WiFiChoice.warning(for: selected.security) {
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                        if selected.secure {
                            if useSavedPassword {
                                Text("使用 Combo 记住的密码").font(.caption).foregroundStyle(.secondary)
                                Button("改用其他密码") { useSavedPassword = false }.font(.caption)
                            } else {
                                SecureField("网络密码", text: $password).textFieldStyle(.roundedBorder)
                                    .onSubmit { if !password.isEmpty && !wifi.busy { wifi.connect(selected, password: password, remember: remember) } }
                                Toggle("连接成功后在本机记住密码", isOn: $remember).font(.caption)
                                Text("仅存入本机 Combo 钥匙串，不上传服务器。").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button("连接") { wifi.connect(selected, password: password, remember: remember) }
                                .disabled(wifi.busy || (selected.secure && !useSavedPassword && password.isEmpty))
                            if useSavedPassword {
                                Button("删除已存密码") { wifi.deletePassword(for: selected); useSavedPassword = wifi.hasSavedPassword(for: selected) }
                            }
                        }.font(.caption)
                    }
                    Button("取消") { clearSelection() }.font(.caption).keyboardShortcut(.cancelAction).disabled(wifi.busy)
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).disabled(wifi.busy)
            }
            if !wifi.message.isEmpty { Text(wifi.message).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Button("Wi‑Fi 设置…", action: openSettings).buttonStyle(.plain).font(.caption)
        }.task(id: active) {
            guard active else { return }
            wifi.scan(requestAccess: false)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if !wifi.busy { wifi.refresh() }
            }
        }
        .onChange(of: wifi.powerOn) { _, value in if value != true { clearSelection() } }
        .onChange(of: wifi.networks.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { clearSelection() }
        }
        .onChange(of: wifi.passwordRequest?.id) { _, _ in resetInput() }
        .onAppear { resetInput() }
        .onDisappear { password = "" }
    }
    private func clearSelection() { wifi.passwordRequest = nil; resetInput() }
    private func resetInput() {
        password = ""; remember = true
        useSavedPassword = selected.map { $0.secure && !$0.requiresSystemJoin && wifi.hasSavedPassword(for: $0) } ?? false
    }
    private func networkRow(_ choice: WiFiChoice) -> some View {
        Button {
            clearSelection(); wifi.join(choice)
        } label: {
            networkLabel(choice.name, rssi: choice.network.rssiValue, secure: choice.secure, connected: false)
        }.buttonStyle(.plain).disabled(wifi.busy || wifi.powerOn != true)
    }
    private func networkLabel(_ name: String, rssi: Int, secure: Bool, connected: Bool) -> some View {
        let level = WiFiChoice.signalLevel(rssi)
        return HStack(spacing: 9) {
            WiFiIcon(level: level ?? 0)
                .frame(width: 28, height: 28)
                .foregroundStyle(connected ? Color.white : Color.primary)
                .background(connected ? Color.blue : Color.primary.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            Text(name).lineLimit(1).help(name)
            Spacer(minLength: 4)
            if connected { Text("已连接").foregroundStyle(.secondary) }
            if secure { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
        }.font(.caption).padding(.vertical, 2).contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)，\(connected ? "已连接，" : "")\(secure ? "需要密码，" : "")\(level.map { "信号 \($0) 格" } ?? "信号未知")")
    }
}
