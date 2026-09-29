import SwiftUI
import AppKit

private func themeColor(_ rgb: UInt32) -> Color {
    Color(red: Double((rgb >> 16) & 0xFF) / 255,
          green: Double((rgb >> 8) & 0xFF) / 255,
          blue: Double(rgb & 0xFF) / 255)
}
struct ComboPalette {
    let canvasTop: Color
    let canvasBottom: Color
    let surface: Color
    let tileTop: Color
    let tileBottom: Color
    let mutedText: Color
    let accent: Color
    let isDark: Bool
}
enum ComboTheme: String, CaseIterable, Identifiable {
    case blue, purple, gold
    var id: String { rawValue }
    var title: String {
        switch self { case .blue: "蓝色"; case .purple: "紫色"; case .gold: "暖金色" }
    }
    func palette(isDark: Bool) -> ComboPalette {
        switch (self, isDark) {
        case (.blue, false):
            return ComboPalette(canvasTop: themeColor(0xB5D1EB), canvasBottom: themeColor(0x91BADB),
                                surface: themeColor(0xDBEBF7), tileTop: themeColor(0xDEEDF7), tileBottom: themeColor(0xC2DBF0),
                                mutedText: themeColor(0x364D63), accent: themeColor(0x2B6196), isDark: false)
        case (.blue, true):
            let accent = themeColor(0x78C6FF)
            return ComboPalette(canvasTop: themeColor(0x17263C), canvasBottom: themeColor(0x0E1B2B),
                                surface: themeColor(0x263D55), tileTop: accent.opacity(0.23), tileBottom: accent.opacity(0.10),
                                mutedText: themeColor(0xD1E3F5), accent: accent, isDark: true)
        case (.purple, false):
            return ComboPalette(canvasTop: themeColor(0xFBF9FD), canvasBottom: themeColor(0xF1ECF7),
                                surface: themeColor(0xF4EDF9), tileTop: themeColor(0xFFFEFF), tileBottom: themeColor(0xF4EDF9),
                                mutedText: themeColor(0x61546E), accent: themeColor(0x785C9C), isDark: false)
        case (.purple, true):
            return ComboPalette(canvasTop: themeColor(0x241C2D), canvasBottom: themeColor(0x130F1C),
                                surface: themeColor(0x3B3049), tileTop: themeColor(0x3B3049), tileBottom: themeColor(0x2B2538),
                                mutedText: themeColor(0xD4CCDE), accent: themeColor(0xC9B0DE), isDark: true)
        case (.gold, false):
            return ComboPalette(canvasTop: themeColor(0xFDFBF6), canvasBottom: themeColor(0xF3EDE3),
                                surface: themeColor(0xF9F2E9), tileTop: themeColor(0xFFFEFC), tileBottom: themeColor(0xF9F2E9),
                                mutedText: themeColor(0x695C4F), accent: themeColor(0x966E47), isDark: false)
        case (.gold, true):
            return ComboPalette(canvasTop: themeColor(0x212124), canvasBottom: themeColor(0x121215),
                                surface: themeColor(0x363637), tileTop: themeColor(0x363637), tileBottom: themeColor(0x29292C),
                                mutedText: themeColor(0xD6D1C9), accent: themeColor(0xDBC4A3), isDark: true)
        }
    }
}
private struct ComboPaletteKey: EnvironmentKey {
    static let defaultValue = ComboTheme.blue.palette(isDark: false)
}
extension EnvironmentValues {
    var comboPalette: ComboPalette {
        get { self[ComboPaletteKey.self] }
        set { self[ComboPaletteKey.self] = newValue }
    }
}
let brandImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "Combo", ofType: "icns") ?? "")
    ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: nil)!
enum ComboAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
    var nsAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}
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
    let text: String
    @Environment(\.comboPalette) private var palette
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(palette.accent).background(palette.accent.opacity(0.1), in: Capsule()) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.comboPalette) private var palette
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055))) }
}
private final class HoverScroller: NSScroller {
    var accent = NSColor.controlAccentColor
    private var hovered = false

    override class var isCompatibleWithOverlayScrollers: Bool { self == HoverScroller.self }

    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsDisplay = true
    }

    override func drawKnob() {
        guard hovered else { super.drawKnob(); return }
        let knob = rect(for: .knob).insetBy(dx: 2, dy: 1)
        accent.setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }
}

private struct HoverScrollerBridge: NSViewRepresentable {
    let accent: NSColor

    func makeNSView(context: Context) -> InstallerView { InstallerView() }
    func updateNSView(_ view: InstallerView, context: Context) { view.accent = accent; view.install() }

    final class InstallerView: NSView {
        var accent = NSColor.controlAccentColor
        private weak var scroller: HoverScroller?
        private var monitor: Any?

        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); install() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                scroller?.setHovered(false)
                scroller = nil
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            } else { install() }
        }

        func install() {
            DispatchQueue.main.async { [weak self] in self?.installNow() }
        }

        private func installNow() {
            guard window != nil else { return }
            var parent = superview
            while let view = parent {
                if let scrollView = view as? NSScrollView {
                    if let scroller = scrollView.verticalScroller as? HoverScroller {
                        if !scroller.accent.isEqual(accent) {
                            scroller.accent = accent
                            scroller.needsDisplay = true
                        }
                        self.scroller = scroller
                    } else {
                        let scroller = HoverScroller()
                        scroller.accent = accent
                        scrollView.verticalScroller = scroller
                        self.scroller = scroller
                    }
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in
                            self?.updateHover(event)
                            return event
                        }
                    }
                    return
                }
                parent = view.superview
            }
        }

        private func updateHover(_ event: NSEvent) {
            guard let scroller else { return }
            let inside = event.window === scroller.window && scroller.bounds.contains(scroller.convert(event.locationInWindow, from: nil))
            scroller.setHovered(inside)
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
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
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
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
                Picker("电池详情高耗能应用上限", selection: $store.energyAppLimit) {
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
enum PanelSection: String {
    case battery = "电池", wifi = "Wi‑Fi", sound = "声音"
    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .wifi: "wifi"
        case .sound: "speaker.wave.2"
        }
    }
}
private struct WiFiName: View {
    @ObservedObject var wifi: WiFiControl
    var body: some View {
        Text(name).lineLimit(1).minimumScaleFactor(0.8).help(name)
    }
    private var name: String {
        if wifi.powerOn == false { return "Wi‑Fi 已关闭" }
        if wifi.powerOn == nil { return "Wi‑Fi 不可用" }
        if let ssid = wifi.currentSSID, !ssid.isEmpty { return ssid }
        return wifi.nameAccess ? "未连接或名称不可用" : "允许定位以显示名称"
    }
}

struct PanelView: View {
    static let width: CGFloat = 420
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
    private var mutedText: Color { palette.mutedText }
    @ObservedObject var store: Store
    let showSettings: () -> Void
    let compact: Bool
    let maxHeight: CGFloat
    let resize: (PanelSection?) -> Void
    let reportHeight: (PanelSection?, CGFloat) -> Void
    @State private var selected: PanelSection?
    @State private var hoveredCards: Set<String> = []
    @State private var displayedSection: PanelSection?
    @State private var detailVisible = false
    @State private var expanded = false
    @State private var detailTask: Task<Void, Never>?
    @State private var overviewContentHeight: CGFloat = 0
    @State private var detailContentHeights: [PanelSection: CGFloat] = [:]
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !compact && expanded {
                ZStack {
                    if let displayedSection { detailPanel(displayedSection) }
                }.frame(width: Self.width)
            }
            if compact, let displayedSection { detailPanel(displayedSection) }
            if displayedSection == nil || !compact { panel(for: nil) { overview } }
        }
        .frame(width: !compact && expanded ? Self.width * 2 + 10 : Self.width, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(palette.accent)
        .onDisappear { detailTask?.cancel() }
        .onChange(of: store.panelVisible) { _, visible in if !visible { detailTask?.cancel() } }
        .task(id: store.panelVisible && store.screenActive && store.scene == .live && selected == .battery) {
            guard store.panelVisible && store.screenActive && store.scene == .live && selected == .battery else { store.energyApps.cancel(); return }
            while !Task.isCancelled {
                store.energyApps.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: "\(store.panelVisible && store.screenActive && store.scene == .live && (store.live.outputIsAirPods || selected == .sound))-\(store.selectedOutputID)") {
            guard store.panelVisible && store.screenActive && store.scene == .live && (store.live.outputIsAirPods || selected == .sound) else { store.airpods.cancel(); return }
            while !Task.isCancelled {
                store.airpods.refresh(deviceID: store.selectedOutputID)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private var detailEnterAnimation: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: store.reduceMotion ? 0.12 : 0.23)
    }
    private var detailExitAnimation: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: store.reduceMotion ? 0.12 : 0.16)
    }
    private func detailPanel(_ section: PanelSection) -> some View {
        panel(for: section) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if compact { Button("返回总览") { choose(section) }.font(.caption) }
                    else { Text(section.rawValue).font(.headline) }
                    Spacer()
                }
                tile { detail(section) }
                if compact && !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange) }
            }
        }
        .opacity(detailVisible ? 1 : 0)
        .scaleEffect(store.reduceMotion || detailVisible ? 1 : 0.98, anchor: .bottom)
        .allowsHitTesting(detailVisible)
        .onAppear {
            guard displayedSection == section else { return }
            withAnimation(detailEnterAnimation) { detailVisible = true }
        }
        .id(section)
    }
    private func panel<Content: View>(for section: PanelSection?, @ViewBuilder _ content: () -> Content) -> some View {
        let measured = section.flatMap { detailContentHeights[$0] } ?? (section == nil ? overviewContentHeight : 0)
        let initial = section == nil ? 500 : (overviewContentHeight > 0 ? overviewContentHeight : 500)
        return ScrollView {
            content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { value in
                    let height = ceil(value)
                    if let section { detailContentHeights[section] = height }
                    else { overviewContentHeight = height }
                    reportHeight(section, height)
                }
        }
            .frame(width: Self.width, height: min(maxHeight, measured > 0 ? measured : initial))
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(colors: [palette.canvasTop.opacity(0.72), palette.canvasBottom.opacity(0.82)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
    }
    private func tile<Content: View>(interactive: Bool = false, hoverID: String? = nil, action: (() -> Void)? = nil,
                                     actionLabel: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        let hovered = hoverID.map(hoveredCards.contains) ?? false
        return content().frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                if let action {
                    Button(action: action) { Color.clear.contentShape(RoundedRectangle(cornerRadius: 18)) }
                        .buttonStyle(.plain).accessibilityLabel(actionLabel)
                }
            }
            .glassEffect(interactive ? .regular.interactive() : .regular, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .fill(hovered ? palette.accent.opacity(palette.isDark ? 0.18 : 0.12) : .clear)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onHover { inside in
                guard let hoverID else { return }
                if inside { hoveredCards.insert(hoverID) }
                else {
                    withAnimation(store.reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        _ = hoveredCards.remove(hoverID)
                    }
                }
            }
    }
    private var overview: some View {
        let s = store.snapshot
        return GlassEffectContainer(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ComboIcon(snapshot: s, animate: store.animate, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Combo").font(.system(size: 24, weight: .semibold))
                        Text("状态，合而为一").font(.system(size: 12)).foregroundStyle(mutedText)
                    }
                    Spacer()
                    Text(store.scene == .live ? "本机状态" : "部分演示")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(mutedText)
                }.padding(.horizontal, 4).padding(.bottom, 6)
                if store.mediaVisible { mediaCard(store.mediaTrack) }
                HStack(alignment: .top, spacing: 10) {
                    sectionCard(.battery, snapshot: s)
                    sectionCard(.wifi, snapshot: s)
                }.fixedSize(horizontal: false, vertical: true)
                soundCard(snapshot: s)
                if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button { NSApp.terminate(nil) } label: { Label("退出 Combo", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(.plain).help("退出 Combo")
                    Spacer()
                    Button(action: showSettings) { Image(systemName: "gearshape.fill").font(.system(size: 17)) }
                        .buttonStyle(.plain).help("设置…").accessibilityLabel("设置")
                }.foregroundStyle(mutedText).font(.system(size: 12, weight: .medium)).padding(.horizontal, 4).padding(.top, 9)
            }
        }
    }
    private func sectionCard(_ section: PanelSection, snapshot s: Snapshot) -> some View {
        Button { choose(section) } label: {
            tile(interactive: true, hoverID: section.rawValue) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        Image(systemName: section.symbol).frame(width: 20)
                            .foregroundStyle(palette.accent)
                        Text(section.rawValue).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    Group {
                        if section == .wifi { WiFiName(wifi: store.wifi) }
                        else { Text(s.batteryText).lineLimit(1) }
                    }
                    .font(.system(size: section == .wifi ? 17 : 21, weight: .semibold, design: .rounded))
                    if section == .battery {
                        Text(store.scene == .live ? store.batteryStatusText : "演示数据")
                            .font(.system(size: 11)).foregroundStyle(mutedText).lineLimit(2)
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected == section ? palette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
        .accessibilityAddTraits(selected == section ? .isSelected : [])
    }
    private func soundCard(snapshot s: Snapshot) -> some View {
        tile(interactive: true, hoverID: PanelSection.sound.rawValue,
             action: { choose(.sound) }, actionLabel: "声音详情") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: PanelSection.sound.symbol).frame(width: 20).foregroundStyle(palette.accent)
                    Text("声音").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }.allowsHitTesting(false)
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { store.snapshot.volume ?? 0 }, set: { store.setVolume($0) }), in: 0...1)
                        .disabled(store.scene != .live || !store.canVolume || s.volume == nil)
                        .accessibilityLabel("系统音量")
                        .tint(.gray)
                    Text(s.muted ? "静音" : s.volumeText).allowsHitTesting(false)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                Text(s.output).font(.system(size: 12)).foregroundStyle(mutedText).lineLimit(1).allowsHitTesting(false)
                if store.scene == .live, s.outputIsAirPods, let state = store.airpods.snapshot,
                   state.available, state.deviceID == store.selectedOutputID,
                   state.left != nil || state.right != nil || state.caseBattery != nil || state.single != nil {
                    HStack(spacing: 8) {
                        if let left = state.left { Label("\(left)%", systemImage: "airpods.pro.left") }
                        if let right = state.right { Label("\(right)%", systemImage: "airpods.pro.right") }
                        if let charge = state.caseBattery { Label("\(charge)%", systemImage: "airpodspro.chargingcase.wireless") }
                        if let single = state.single, state.left == nil && state.right == nil { Text("电量 \(single)%") }
                    }.font(.system(size: 11)).foregroundStyle(mutedText).allowsHitTesting(false)
                        .accessibilityElement(children: .ignore).accessibilityLabel(state.batteryText)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected == .sound ? palette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
        .accessibilityAddTraits(selected == .sound ? .isSelected : [])
    }
    private func mediaCard(_ track: MediaTrack?) -> some View {
        tile(interactive: true, hoverID: "媒体", action: track?.bundleIdentifier == nil ? nil : { store.openMediaSource() },
             actionLabel: "打开\(track?.source ?? "媒体来源")") {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 11) {
                    Group {
                        if let artwork = track?.artwork, let image = NSImage(data: artwork) {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.system(size: 21)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(palette.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05))
                        }
                    }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.mediaTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if let artist = track?.artist, !artist.isEmpty { Text(artist).font(.system(size: 12)).foregroundStyle(mutedText).lineLimit(1) }
                        if let source = track?.source, !source.isEmpty { Text(source).font(.system(size: 11)).foregroundStyle(mutedText).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Text(store.mediaControlsAvailable ? (store.live.playing ? "播放中" : "已暂停") : "重新连接中").font(.system(size: 11)).foregroundStyle(mutedText)
                }.allowsHitTesting(false)
                HStack(spacing: 18) {
                    Spacer()
                    Button { store.controlMedia(.previous) } label: { Image(systemName: "backward.end.fill").frame(width: 30, height: 28) }
                        .help("上一首").accessibilityLabel("上一首")
                    Button { store.controlMedia(.toggle) } label: { Image(systemName: store.live.playing ? "pause.fill" : "play.fill").frame(width: 30, height: 28) }
                        .help(store.live.playing ? "暂停" : "播放").accessibilityLabel(store.live.playing ? "暂停" : "播放")
                    Button { store.controlMedia(.next) } label: { Image(systemName: "forward.end.fill").frame(width: 30, height: 28) }
                        .help("下一首").accessibilityLabel("下一首")
                    Spacer()
                }.buttonStyle(.plain).font(.system(size: 15)).disabled(!store.mediaControlsAvailable)
            }
        }
    }
    private func choose(_ section: PanelSection) {
        detailTask?.cancel()
        let next = selected == section ? nil : section
        selected = next
        if displayedSection == section, !detailVisible, next == section {
            withAnimation(detailEnterAnimation) { detailVisible = true }
            return
        }
        guard displayedSection != nil else {
            if let next { showDetail(next) }
            return
        }
        withAnimation(detailExitAnimation) { detailVisible = false }
        detailTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(store.reduceMotion ? 120 : next == nil ? 160 : 200))
            guard !Task.isCancelled else { return }
            displayedSection = nil
            if let next { showDetail(next) }
            else { expanded = false; resize(nil) }
        }
    }
    private func showDetail(_ section: PanelSection) {
        expanded = true
        displayedSection = section
        detailVisible = false
        resize(section)
    }
    @ViewBuilder private func detail(_ section: PanelSection) -> some View {
        let s = store.snapshot
        switch section {
        case .battery:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ComboIcon(snapshot: s, animate: store.animate, size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.batteryText).font(.system(size: 28, weight: .medium, design: .rounded))
                        if store.scene == .live {
                            Text("电源：\(store.batterySourceText)").font(.caption).foregroundStyle(.secondary)
                            Text(store.batteryStatusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else { Text("演示数据 · 不改变系统状态").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if store.scene == .live {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("当前充电上限：\(store.chargeLimit.text)")
                        Text("健康：\(store.batteryHealth) · 低电量模式：\(store.lowPowerMode ? "开" : "关")")
                    }.font(.caption).foregroundStyle(.secondary)
                    ChargeFullSection(control: store.chargeControl, eligible: store.canRequestFullCharge,
                                      expectedLimit: store.chargeLimit, action: store.requestFullCharge)
                    PowerModeSection(control: store.powerMode, source: store.batteryOnAC.map { $0 ? .adapter : .battery }) { store.refreshBattery() }
                    EnergyAppsSection(control: store.energyApps, limit: store.energyAppLimit)
                } else { Button("返回本机状态") { store.scene = .live }.font(.caption) }
                HStack { Button("电池设置") { store.openSystemSettings("battery") }; Button("耗电应用") { store.openActivityMonitor() } }.font(.caption)
            }
        case .wifi:
            WiFiSection(wifi: store.wifi, hotspots: store.hotspots, connection: s.network, active: store.screenActive,
                        openSettings: { store.openSystemSettings("wifi") })
        case .sound:
            VStack(alignment: .leading, spacing: 16) {
                Label("声音", systemImage: "speaker.wave.2").font(.headline)
                HStack { Text(s.muted ? "静音" : "音量"); Spacer(); Text(s.volumeText).foregroundStyle(.secondary) }.font(.caption)
                Slider(value: Binding(get: { s.volume ?? 0 }, set: { store.setVolume($0) }), in: 0...1).disabled(store.scene != .live || !store.canVolume).accessibilityLabel("系统音量")
                    .tint(.gray)
                SoundOutputs(store: store)
                HStack { Button(s.muted ? "取消静音" : "静音") { store.toggleMute() }.disabled(store.scene != .live || !store.canMute); Button("声音设置 / AirPods") { store.openSystemSettings("sound") } }.font(.caption)
            }
        }
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
                AirPodsSegmentTrack(count: modes.count, selected: modes.firstIndex { $0 == control.displayedMode },
                                    enabled: state.canSetMode && !control.busy && !control.unavailable,
                                    select: { control.setMode(modes[$0]) }) {
                    ForEach(modes) { mode in
                        option(mode.title, symbol: symbol(mode), selected: control.displayedMode == mode, pending: control.pendingMode == mode,
                               enabled: state.canSetMode) { control.setMode(mode) }
                    }
                }
                if state.mode == nil { Text("当前模式暂不可用").font(.caption).foregroundStyle(.secondary) }
            }
            if let conversation = control.displayedConversation {
                if !state.modes.isEmpty { Divider().padding(.vertical, 10) }
                heading("对话感知")
                AirPodsSegmentTrack(count: 2, selected: conversation ? 1 : 0,
                                    enabled: state.canSetConversation && !control.busy && !control.unavailable,
                                    select: { control.setConversation($0 == 1) }) {
                    option("关闭", symbol: "person.wave.2.fill", selected: !conversation, pending: control.pendingConversation == false,
                           enabled: state.canSetConversation) { control.setConversation(false) }
                    option("打开", symbol: "person.wave.2.fill", selected: conversation, pending: control.pendingConversation == true,
                           enabled: state.canSetConversation) { control.setConversation(true) }
                }
            }
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
    private func option(_ title: String, symbol: String, selected: Bool, pending: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
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
                        Capsule().fill(Color.primary.opacity(!selected && hoveredOption == title ? 0.12 : 0))
                    }
                    .padding(.top, 2)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredOption = $0 ? title : nil }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? (pending ? "正在切换" : "已选中") : "未选中")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(control.busy || control.unavailable || !enabled)
    }
}
struct AirPodsSegmentTrack<Content: View>: View {
    let count: Int
    let selected: Int?
    let enabled: Bool
    let select: (Int) -> Void
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0
    @GestureState private var draggedPosition: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var position: Double? { draggedPosition ?? selected.map(Double.init) }
    private func position(for value: DragGesture.Value) -> Double? {
        guard enabled else { return nil }
        return airPodsDragPosition(selected: selected, count: count, width: Double(width),
                                   startX: Double(value.startLocation.x), startY: Double(value.startLocation.y),
                                   translation: Double(value.translation.width))
    }
    var body: some View {
        HStack(spacing: 0) { content }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(alignment: .top) {
                let columnWidth = width / CGFloat(max(1, count))
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.75))
                        .padding(.horizontal, max(0, (columnWidth - 62) / 2 - 2))
                    if let position {
                        Capsule().fill(Color.blue)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75))
                            .frame(width: 62, height: 44)
                            .offset(x: columnWidth * (position + 0.5) - 31, y: 2)
                            .animation(reduceMotion || draggedPosition != nil ? nil : .easeInOut(duration: 0.22), value: position)
                    }
                }.frame(height: 48).allowsHitTesting(false)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .updating($draggedPosition) { value, position, transaction in
                        transaction.animation = nil
                        position = self.position(for: value)
                    }
                    .onEnded { value in
                        guard let position = position(for: value) else { return }
                        let index = Int(position.rounded())
                        if index != selected { select(index) }
                    },
                including: enabled ? .all : .none
            )
    }
}
struct EnergyAppsSection: View {
    @ObservedObject var control: EnergyApps
    let limit: Int
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
