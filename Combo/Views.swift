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
    case general = "通用", appearance = "图标与动效", integration = "系统菜单整合", media = "媒体来源", about = "关于与帮助"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .appearance: "circle.dotted.circle"; case .integration: "menubar.rectangle"; case .media: "waveform"; case .about: "info.circle" }
    }
    var subtitle: String {
        switch self {
        case .general: "让 Combo 按你的习惯工作。"
        case .appearance: "一个图标，刚好装下你需要的状态。"
        case .integration: "收起重复的图标，保留熟悉的系统菜单。"
        case .media: "连接你的播放器，点亮固定节奏的音柱。"
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
    @State private var page: Page = .appearance
    @State private var preview: Scene = .wired
    @State private var reset = false
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
                VStack(alignment: .leading, spacing: 8) { Tag(text: "PREVIEW 0.2"); Text("为 MacBook 而设计").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(14)
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
                    case .about: about
                    }
                    if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
            }.background(canvas)
        }.frame(minWidth: 760, minHeight: 580).tint(accent)
            .alert("恢复显示偏好？", isPresented: $reset) { Button("取消", role: .cancel) {}; Button("恢复") { store.resetDisplay() } } message: { Text("中央恢复为电量百分比，播放动效开启。登录项和折叠选择保持不变。") }
            .sheet(isPresented: $store.showMenuPermission) { menuPermissionGuide }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshMenuAccess()
            }
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
                    ComboIcon(snapshot: Snapshot.demo(preview), center: store.center, animate: store.animate, size: 112)
                    VStack(spacing: 12) { ComboIcon(snapshot: Snapshot.demo(preview), center: store.center, animate: store.animate, size: 22); Text("菜单栏尺寸").font(.system(size: 10)).foregroundStyle(.secondary) }
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
                Text("中央内容").font(.system(size: 13, weight: .semibold))
                Picker("有线网络下显示", selection: $store.center) { ForEach(["电量百分比", "当天日期", "音频输出设备"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                Text("Wi-Fi 连接时显示无线图标；外圈始终表示 MacBook 电量。预览版暂不显示无线信号格数。").font(.caption).foregroundStyle(.secondary)
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
                Text("预览版体验").font(.system(size: 13, weight: .semibold))
                Picker("菜单栏数据", selection: $store.scene) { ForEach(Scene.allCases) { Text($0 == .live ? $0.rawValue : "演示 · \($0.rawValue)").tag($0) } }
                Text("选择演示场景，可以在真实菜单栏查看播放、静音与充电效果。退出后恢复本机状态。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                HStack { VStack(alignment: .leading, spacing: 5) { Text("恢复显示偏好"); Text("仅重置中央内容和播放动效").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("恢复…") { reset = true } }
                Divider(); HStack { Text("关闭设置窗口后，Combo 继续运行。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("退出 Combo") { NSApp.terminate(nil) } }
            }
        }
    }
    var integration: some View {
        VStack(spacing: 18) {
            Card {
                HStack { Text("系统菜单整合").font(.system(size: 13, weight: .semibold)); Spacer(); Tag(text: "尚未接入") }
                Toggle("整合系统菜单", isOn: .constant(false)).toggleStyle(.switch).disabled(true)
                Text("先验证系统菜单定位与恢复能力。此预览版不会隐藏或移动你的系统图标。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("准备折叠的项目").font(.system(size: 13, weight: .semibold))
                foldRow("Wi-Fi", symbol: "wifi", binding: $foldWifi)
                Divider(); foldRow("声音／AirPods", symbol: "headphones", binding: $foldSound)
                Divider(); foldRow("电池", symbol: "battery.75percent", binding: $foldBattery)
                Text("选择会保存，但暂不执行折叠。系统日期属于时钟项，尚未纳入。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Label("怎样打开原生菜单？", systemImage: "cursorarrow.click").font(.system(size: 13, weight: .semibold))
                Text("打开 Combo → 选择 Wi-Fi、声音或电池 → 临时展开系统菜单 → 关闭后收起。").font(.caption).foregroundStyle(.secondary)
                Text("只有点击下方授权按钮时才会请求辅助功能。检测只读取菜单栏，不点击或移动图标。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("检查菜单访问") { store.checkMenus() }.disabled(store.checkingMenus)
                    Button("授权辅助功能…") { store.refreshMenuAccess(); store.showMenuPermission = true }
                    if store.checkingMenus { ProgressView().controlSize(.small) }
                }
                Text(store.menuDiagnostic).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    var menuPermissionGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: store.menuAccessGranted ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 30)).foregroundStyle(accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.menuAccessGranted ? "辅助功能已授权" : "允许 Combo 访问系统菜单")
                        .font(.system(size: 21, weight: .semibold))
                    Text("一步设置 · 授权由你决定").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("辅助功能是一项广泛的系统权限。当前版本仅在你点击检测时读取控制中心的菜单栏项目；不读取其他窗口、不截图、不点击或移动图标。授权不会自动开启折叠。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Card {
                Text("在辅助功能列表中开启 Combo").font(.headline)
                Text("系统设置 → 隐私与安全性 → 辅助功能").font(.subheadline)
                Text("若列表中没有 Combo，点击“＋”，选择当前运行的 Combo.app。系统可能要求你输入密码或使用 Touch ID。").font(.caption).foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Label(store.menuAccessGranted ? "已确认授权，可以继续只读菜单检测。" : "系统尚未允许当前进程访问；不一定是开关未开启。", systemImage: store.menuAccessGranted ? "checkmark.circle.fill" : "info.circle")
                .font(.subheadline).foregroundStyle(store.menuAccessGranted ? accent : .secondary)
            if !store.menuPermissionMessage.isEmpty {
                Text(store.menuPermissionMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("如果系统开关已开启：先退出并重新打开 Combo。仍无效时，请在系统权限列表中移除旧 Combo，再用上方路径添加当前应用并开启。开发预览版重新编译后，旧授权可能不再匹配。系统新版也可能将此项称为“设备控制和数据访问”。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("你可以随时在同一页面关闭权限。稍后授权也不影响电量、网络与音量显示。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("稍后再说") { store.showMenuPermission = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("重新检查") { store.refreshMenuAccess() }
                if store.menuAccessGranted {
                    Button("继续检测") { store.showMenuPermission = false; store.checkMenus() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("打开系统设置并授权") { store.requestMenuAccess() }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 510).tint(accent)
            .onAppear { store.refreshMenuAccess() }
    }
    func foldRow(_ title: String, symbol: String, binding: Binding<Bool>) -> some View {
        HStack { Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary); Toggle(title, isOn: binding).toggleStyle(.checkbox); Spacer(); Text("未启用").font(.caption).foregroundStyle(.tertiary) }
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
                HStack(spacing: 22) { Image(nsImage: brandImage).resizable().frame(width: 80, height: 80).accessibilityHidden(true); VStack(alignment: .leading, spacing: 8) { Text("Combo").font(.system(size: 25, weight: .semibold)); Text("0.2.0 · 真实状态预览版").foregroundStyle(.secondary); Tag(text: "macOS 26+ · MacBook") } }
                Divider(); Text("电量、连接与音量，合在一个安静的图标里。").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("当前能力").font(.system(size: 13, weight: .semibold))
                Label("本机电池、网络路径与输出音量", systemImage: "checkmark.circle")
                Label("菜单栏图标、点击面板与五组设置", systemImage: "checkmark.circle")
                Label("媒体适配、系统图标折叠尚未接入", systemImage: "clock")
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
            ScrollView { content }.frame(width: 300, height: height).tint(accent)
        } else {
            content.frame(width: 300).tint(accent)
        }
    }
    var content: some View {
        let s = store.snapshot
        return VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Combo").font(.system(size: 16, weight: .semibold)); Spacer(); Button(action: showSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置…").accessibilityLabel("设置") }
            HStack(spacing: 20) { ComboIcon(snapshot: s, center: store.center, animate: store.animate, size: 72); VStack(alignment: .leading, spacing: 5) { Text(s.batteryText).font(.system(size: 30, weight: .medium, design: .rounded)); Text(s.charging ? "正在充电" : s.plugged ? "已连接电源" : "MacBook 电量").font(.caption).foregroundStyle(.secondary) } }
            if store.scene != .live { HStack { Tag(text: "演示数据"); Spacer(); Button("返回本机") { store.scene = .live }.font(.caption) } }
            Divider()
            row("wifi", "网络", s.network)
            Text("互联网未检测 · 无线信号强度未接入").font(.system(size: 10)).foregroundStyle(.tertiary)
            Divider()
            row("hifispeaker", "输出", s.output)
            HStack { Text(s.muted ? "静音" : "音量"); Spacer(); Text(s.volumeText).foregroundStyle(.secondary) }.font(.caption)
            Slider(value: Binding(get: { s.volume ?? 0 }, set: { store.setVolume($0) }), in: 0...1).disabled(store.scene != .live || !store.canVolume).accessibilityLabel("系统音量")
            HStack { Button(s.muted ? "取消静音" : "静音") { store.toggleMute() }.disabled(store.scene != .live || !store.canMute); Spacer(); Text("媒体识别尚未接入").font(.system(size: 10)).foregroundStyle(.tertiary) }
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.orange) }
            Divider()
            Text("原生菜单整合 · 准备中").font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack { Spacer(); Button("退出 Combo") { NSApp.terminate(nil) }; Button("设置…", action: showSettings) }.font(.caption)
        }.padding(22)
    }
    func row(_ symbol: String, _ title: String, _ detail: String) -> some View { HStack { Label(title, systemImage: symbol); Spacer(); Text(detail).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }.font(.system(size: 12)) }
}
