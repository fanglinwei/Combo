import AppKit
import CoreBluetooth
import CoreLocation
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var setup: MenuBarSetup
    @ObservedObject var wifi: WiFiControl
    @ObservedObject var bluetooth: BluetoothPermission
    /// 绑到 UserDefaults：换一步就存一步，重新打开引导时从上次的位置继续。
    @Binding var step: Int
    let dismiss: (_ completed: Bool) -> Void
    @State private var settingsError = false
    @FocusState private var primaryFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.comboPalette) private var palette

    private static let demos: [Scene] = [.live, .music, .charging, .mute]

    init(store: Store, step: Binding<Int>, dismiss: @escaping (Bool) -> Void) {
        self.store = store
        self.battery = store.battery
        self.setup = store.menuSetup
        self.wifi = store.wifi
        self.bluetooth = store.audio.bluetoothPermission
        self._step = step
        self.dismiss = dismiss
    }

    /// 只有“还没找到图标”的第 1 步需要浮层；面板一打开它就多余了。
    private var pointerWanted: Bool { step == 0 && !store.panelVisible }

    private var reduceMotion: Bool { store.reduceMotion || systemReduceMotion }
    private var stepDescription: String {
        step >= OnboardingState.stepCount ? L("全部完成") : L("第 \(step + 1) 步，共 \(OnboardingState.stepCount) 步")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            GeometryReader { geometry in
                if reduceMotion {
                    ZStack(alignment: .topLeading) {
                        stepPage(step).id(step).transition(.opacity)
                    }
                    .animation(Motion.animation(Motion.reducedFade), value: step)
                } else {
                    // One strip keeps outgoing and incoming pages moving together, even when reversing.
                    HStack(spacing: 0) {
                        ForEach(0...OnboardingState.stepCount, id: \.self) { index in
                            stepPage(index)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .disabled(index != step)
                                .accessibilityHidden(index != step)
                        }
                    }
                    .offset(x: -CGFloat(step) * geometry.size.width)
                    .animation(Motion.animation(0.28), value: step)
                }
            }
            .clipped()
            footer
        }
        .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 24)
        .foregroundStyle(palette.primaryText)
        .tint(palette.accent)
        .buttonStyle(PanelButtonStyle())
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [palette.canvasTop, palette.canvasBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .contain)
        .defaultFocus($primaryFocused, true)
        .onAppear {
            step = min(max(step, 0), OnboardingState.stepCount)
            store.menuBarPointer = pointerWanted
            primaryFocused = true
        }
        .onChange(of: step) { _, _ in
            settingsError = false
            store.scene = .live
            primaryFocused = true
            AccessibilityNotification.Announcement(stepDescription).post()
        }
        .onChange(of: pointerWanted) { _, wanted in store.menuBarPointer = wanted }
        .onDisappear {
            store.scene = .live
            store.menuBarPointer = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            wifi.refresh()
            bluetooth.refresh()
        }
    }

    private func stepPage(_ index: Int) -> some View {
        ScrollView {
            Group {
                switch index {
                case 0: locateStep
                case 1: menuStep
                case 2: permissionStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: brandImage).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("开始使用 Combo")).font(.system(size: 24, weight: .semibold))
                Text(stepDescription).font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<OnboardingState.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? palette.accent : Color.primary.opacity(0.15))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: step)
            .accessibilityHidden(true)
        }
    }

    // Step 1 — 先让用户找到图标并真的点开一次面板，再谈设置。
    private var locateStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(battery.hasInternalBattery ? L("一个图标，查看 Wi‑Fi、电池和声音") : L("一个图标，查看 Wi‑Fi 和声音"))
                .font(.system(size: 20, weight: .semibold))
            Text(L("它只占菜单栏右上角的一个位置：点一下打开面板，再点一下收起。"))
                .font(.system(size: 13)).foregroundStyle(palette.mutedText)
            VStack(alignment: .leading, spacing: 12) {
                menuBarMock
                HStack(spacing: 10) {
                    Image(systemName: store.panelVisible ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(store.panelVisible ? palette.accent : palette.mutedText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.panelVisible ? L("面板已打开。再点一次图标可以收起。") : L("点一下菜单栏里的 Combo 图标试试。"))
                            .font(.system(size: 13, weight: store.panelVisible ? .medium : .regular))
                        if !store.panelVisible {
                            Text(L("找不到图标时，可以按住 Command 拖动调整它在菜单栏中的位置。"))
                                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .modifier(OnboardingWell())
            VStack(alignment: .leading, spacing: 8) {
                Text(L("图标会随状态变化，先看看这几种：")).font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 40, previewScene: store.scene)
                        .accessibilityHidden(true)
                    ForEach(Self.demos, id: \.self) { scene in
                        Button { store.scene = scene } label: {
                            Text(scene.title).font(.system(size: 11))
                                .padding(.horizontal, 10).frame(minHeight: 28)
                                .background(store.scene == scene ? palette.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(store.scene == scene ? palette.accent : palette.mutedText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.scene == scene ? .isSelected : [])
                    }
                }
                Text(L("只是演示，不改动系统设置；离开这一步会恢复本机状态。"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
            .modifier(OnboardingWell())
        }
    }

    private var menuBarMock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                Image(systemName: "wifi").font(.system(size: 13))
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                Text(L("点这里")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.accent)
                ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 20, previewScene: store.scene)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.accent, lineWidth: 1.5))
            }
            .foregroundStyle(palette.mutedText)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(palette.primaryText.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            Text(L("菜单栏中其余图标仅作示意，实际排列由系统决定。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("菜单栏示意：Combo 图标位于系统图标右侧。"))
    }

    // Step 2 — 可选：隐藏系统原图标。
    private var menuStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(L("让菜单栏更简洁")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(L("可以跳过")).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.accent).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.accent.opacity(0.10), in: Capsule())
            }
            Text(L("建议隐藏系统原图标，让菜单栏更简洁。Combo 可替代这些图标的功能，隐藏后仍可照常使用。"))
                .font(.system(size: 13)).foregroundStyle(palette.mutedText)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L("系统设置 → 菜单栏"), systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button(L("打开菜单栏设置")) { settingsError = !setup.openWithoutCapture() }
                }
                Text(battery.hasInternalBattery ? L("取消 Wi‑Fi、电池、声音左侧的勾选：") : L("取消 Wi‑Fi、声音左侧的勾选："))
                    .font(.system(size: 13, weight: .medium))
                HStack(alignment: .top, spacing: 12) {
                    menuScreenshot(L("关闭前 · 蓝色勾选"), image: "MenuBarBefore")
                    menuScreenshot(L("关闭后 · 取消勾选"), image: "MenuBarAfter")
                }
                if !battery.hasInternalBattery {
                    Text(L("图中电池项目仅适用于有内置电池的 Mac。"))
                        .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }
                Text(L("不同 macOS 版本的排列可能略有差异，以项目名称和左侧勾选为准。"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                if settingsError {
                    Text(L("无法打开系统设置。请从苹果菜单手动进入“系统设置 → 菜单栏”。"))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .modifier(OnboardingWell())
        }
    }

    /// 两张图已裁成"只留要取消的三行"，不用整页截图，位置和勾选状态都还对得上。
    private func menuScreenshot(_ title: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let screenshot = NSImage(named: image) {
                Image(nsImage: screenshot).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Step 3 — 可选：两项权限按用途分开申请，授权状态实时回流。
    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("按需授权")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(L("可以跳过")).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.accent).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.accent.opacity(0.10), in: Capsule())
            }
            Text(L("两项权限各有用途，分别点击申请；不授权也能使用 Wi‑Fi、Mac 电池和音量。"))
                .font(.system(size: 13)).foregroundStyle(palette.mutedText)
            VStack(alignment: .leading, spacing: 16) {
                permissionRow(L("蓝牙"), symbol: "headphones",
                              explanation: L("用于读取已连接耳机的电量与聆听模式，并提供受支持的耳机模式控制。不授权仍可使用 Wi‑Fi、Mac 电池和系统音量。"),
                              granted: bluetooth.authorization == .allowedAlways,
                              denied: bluetooth.authorization == .denied || bluetooth.authorization == .restricted,
                              request: { bluetooth.request() }, path: L("隐私与安全性 → 蓝牙"),
                              success: L("蓝牙权限已开启"), detail: L("可以查看已连接耳机的状态"))
                Divider()
                permissionRow(L("定位"), symbol: "location",
                              explanation: L("macOS 将当前 Wi‑Fi 名称和附近网络纳入定位权限保护。Combo 用它显示网络信息；当前版本不请求坐标，也不上传扫描结果。"),
                              granted: wifi.nameAccess,
                              denied: wifi.locationAuthorizationStatus == .denied || wifi.locationAuthorizationStatus == .restricted,
                              request: { wifi.requestLocationAccess() }, path: L("隐私与安全性 → 定位服务 → Combo"),
                              success: L("定位权限已开启"), detail: L("可以显示 Wi‑Fi 网络信息"))
            }
            .modifier(OnboardingWell())
            if settingsError {
                Text(L("无法打开系统设置。请从苹果菜单手动进入对应的隐私与安全性页面。"))
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Text(L("随时可以在“设置 → 通用”中重新打开这份引导。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
        }
    }

    // 各步共用同一组导航按钮；首页保留禁用的“上一步”，完成页改为“完成”。
    private var footer: some View {
        HStack(spacing: 10) {
            Button { changeStep(-1) } label: { Text(L("上一步")).font(.system(size: 13)) }
                .disabled(step == 0)
            Spacer(minLength: 8)
            Button {
                if step < OnboardingState.stepCount { changeStep(1) }
                else { complete() }
            } label: {
                Text(step < OnboardingState.stepCount ? L("下一步") : L("完成"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .focused($primaryFocused)
        }
    }

    private func changeStep(_ delta: Int) {
        step += delta
    }

    // 完成页 — 只做两件事：确认“已经能用了”，并把“登录时启动”放在意图最强的时刻。
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("准备好了")).font(.system(size: 20, weight: .semibold))
                    Text(L("点菜单栏里的 Combo 图标就能用；设置里可以随时调整。"))
                        .font(.system(size: 13)).foregroundStyle(palette.mutedText)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L("登录时启动 Combo"), isOn: Binding(get: { store.login }, set: { store.setLogin($0) })).toggleStyle(.switch)
                Text(L("登录后显示菜单栏图标，不增加独立后台服务。")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
            .modifier(OnboardingWell())
            Text(L("随时可以在“设置 → 通用”中重新打开这份引导。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
        }
    }

    private func complete() {
        store.scene = .live
        dismiss(true)
    }

    private func permissionRow(_ title: String, symbol: String, explanation: String, granted: Bool, denied: Bool,
                               request: @escaping () -> Void, path: String, success: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark" : symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(granted ? palette.accent : palette.mutedText)
                .frame(width: 28, height: 28)
                .background(granted ? palette.accent.opacity(0.20) : palette.primaryText.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if granted {
                    Text(success).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.accent)
                    Text(detail).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }
                Text(explanation).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Text(L("系统设置 → \(path)")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !granted {
                VStack(alignment: .trailing, spacing: 6) {
                    Button(denied ? L("打开系统设置") : L("请求权限")) {
                        if denied { openSystemSettings() } else { request() }
                    }
                    Text(denied ? L("尚未允许") : L("尚未请求"))
                        .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                }
            }
        }
    }

    private func openSystemSettings() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            settingsError = true
            return
        }
        settingsError = !NSWorkspace.shared.open(app)
    }
}

/// 指向真实菜单栏图标的浮层。窗口本身忽略鼠标事件，这里只画箭头和一句话。
struct MenuBarCallout: View {
    let reduceMotion: Bool
    @ObservedObject private var localization = Localization.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette { themeFamily.palette(isDark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.accent)
            Text(L("点这里打开面板"))
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .modifier(PanelSurface(tinted: true, radius: 9))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(palette.primaryText)
        .environment(\.comboPalette, palette)
        .modifier(OnboardingReveal(reduceMotion: reduceMotion || systemReduceMotion))
        .accessibilityHidden(true)
    }
}

/// Content wells keep the same styling on every page of the embedded guide.
private struct OnboardingWell: ViewModifier {
    @Environment(\.comboPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16)
                if reduceTransparency { shape.fill(palette.surface) }
                else {
                    shape.fill(LinearGradient(colors: [palette.primaryText.opacity(palette.isDark ? 0.07 : 0.06),
                                                       palette.primaryText.opacity(0.02)],
                                              startPoint: .top, endPoint: .bottom))
                }
                shape.strokeBorder(contrast == .increased ? palette.primaryText : palette.primaryText.opacity(0.08), lineWidth: 1)
            }
    }
}

/// A one-time reveal for the menu-bar pointer.
private struct OnboardingReveal: ViewModifier {
    let reduceMotion: Bool
    @State private var settled = false

    func body(content: Content) -> some View {
        content.opacity(settled ? 1 : 0)
            .scaleEffect(reduceMotion || settled ? 1 : 0.96)
            .blur(radius: reduceMotion || settled ? 0 : 20)
            .onAppear {
                withAnimation(Motion.animation(reduceMotion ? Motion.reducedFade : 0.3)) { settled = true }
            }
    }
}
