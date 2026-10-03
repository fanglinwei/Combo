import AppKit
import CoreBluetooth
import CoreLocation
import SwiftUI
import Inject

struct OnboardingView: View {
    @ObserveInjection var inject
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
    @State private var pulse = false
    @State private var appeared = false
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                switch step {
                case 0: locateStep
                case 1: menuStep
                case 2: permissionStep
                default: doneStep
                }
            }
            .padding(32)
            .frame(maxWidth: 730, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvasTop)
        .onAppear {
            step = min(max(step, 0), OnboardingState.stepCount)
            store.menuBarPointer = pointerWanted
            guard !store.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onChange(of: step) { _, _ in
            settingsError = false
            store.scene = .live
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
        .enableInjection()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: brandImage).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("开始使用 Combo")).font(.system(size: 25, weight: .semibold))
                Text(step >= OnboardingState.stepCount ? L("全部完成") : L("第 \(step + 1) 步，共 \(OnboardingState.stepCount) 步")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<OnboardingState.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? palette.accent : Color.primary.opacity(0.15))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // Step 1 — 先让用户找到图标并真的点开一次面板，再谈设置。
    private var locateStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center, spacing: 20) {
                ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 84, previewScene: store.scene)
                VStack(alignment: .leading, spacing: 7) {
                    Text(battery.hasInternalBattery ? L("一个图标，查看 Wi‑Fi、电池和声音") : L("一个图标，查看 Wi‑Fi 和声音"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(L("它只占菜单栏右上角的一个位置：点一下打开面板，再点一下收起。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            menuBarMock
            HStack(spacing: 10) {
                Image(systemName: store.panelVisible ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(store.panelVisible ? palette.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.panelVisible ? L("面板已打开。再点一次图标可以收起。") : L("点一下菜单栏里的 Combo 图标试试。"))
                        .font(.system(size: 13, weight: store.panelVisible ? .medium : .regular))
                    if !store.panelVisible {
                        Text(L("找不到图标时，可以按住 Command 拖动调整它在菜单栏中的位置。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(store.panelVisible ? palette.accent.opacity(0.13) : palette.surface, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("图标会随状态变化，先看看这几种：")).font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    ForEach(Self.demos, id: \.self) { scene in
                        Button { store.scene = scene } label: {
                            Text(scene.title).font(.system(size: 11))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(store.scene == scene ? palette.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(store.scene == scene ? palette.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.scene == scene ? .isSelected : [])
                    }
                }
                Text(L("只是演示，不改动系统设置；离开这一步会恢复本机状态。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            footer
        }
    }

    private var menuBarMock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                Image(systemName: "wifi").font(.system(size: 13))
                Image(systemName: "battery.75percent").font(.system(size: 13))
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                Text(L("点这里")).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.accent)
                ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 20, previewScene: store.scene)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.accent, lineWidth: 2).opacity(pulse ? 0.4 : 1))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            Text(L("菜单栏中其余图标仅作示意，实际排列由系统决定。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("菜单栏示意：Combo 图标位于系统图标右侧。"))
    }

    // Step 2 — 可选：隐藏系统原图标。
    private var menuStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(L("让菜单栏更简洁（可选）")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Tag(text: L("可以跳过"))
            }
            Text(L("建议隐藏系统原图标，让菜单栏更简洁。Combo 可替代这些图标的功能，隐藏后仍可照常使用。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Label(L("系统设置 → 菜单栏"), systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(L("打开菜单栏设置")) { settingsError = !setup.openWithoutCapture() }
            }
            .padding(15)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            Text(battery.hasInternalBattery ? L("取消 Wi‑Fi、电池、声音左侧的勾选：") : L("取消 Wi‑Fi、声音左侧的勾选："))
                .font(.system(size: 13, weight: .medium))
            HStack(alignment: .top, spacing: 12) {
                menuScreenshot(L("关闭前 · 蓝色勾选"), image: "MenuBarBefore")
                menuScreenshot(L("关闭后 · 取消勾选"), image: "MenuBarAfter")
            }
            if !battery.hasInternalBattery {
                Text(L("图中电池项目仅适用于有内置电池的 Mac。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L("不同 macOS 版本的排列可能略有差异，以项目名称和左侧勾选为准。"))
                .font(.caption).foregroundStyle(.secondary)
            if settingsError {
                Text(L("无法打开系统设置。请从苹果菜单手动进入“系统设置 → 菜单栏”。"))
                    .font(.caption).foregroundStyle(.orange)
            }
            footer
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
        .padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    // Step 3 — 可选：两项权限按用途分开申请，授权状态实时回流。
    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("按需授权")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Tag(text: L("可以跳过"))
            }
            Text(L("两项权限各有用途，分别点击申请；不授权也能使用 Wi‑Fi、Mac 电池和音量。"))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Card {
                Label(L("蓝牙"), systemImage: "headphones").font(.headline)
                Text(L("用于读取已连接耳机的电量与聆听模式，并提供受支持的耳机模式控制。不授权仍可使用 Wi‑Fi、Mac 电池和系统音量。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                permissionAction(bluetooth.authorization == .allowedAlways,
                                 denied: bluetooth.authorization == .denied || bluetooth.authorization == .restricted,
                                 request: { bluetooth.request() }, path: L("隐私与安全性 → 蓝牙"),
                                 success: L("蓝牙权限已开启"), detail: L("可以查看已连接耳机的状态"))
            }
            Card {
                Label(L("定位"), systemImage: "location").font(.headline)
                Text(L("macOS 将当前 Wi‑Fi 名称和附近网络纳入定位权限保护。Combo 用它显示网络信息；当前版本不请求坐标，也不上传扫描结果。"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                permissionAction(wifi.nameAccess,
                                 denied: wifi.locationAuthorizationStatus == .denied || wifi.locationAuthorizationStatus == .restricted,
                                 request: { wifi.requestLocationAccess() }, path: L("隐私与安全性 → 定位服务 → Combo"),
                                 success: L("定位权限已开启"), detail: L("可以显示 Wi‑Fi 网络信息"))
            }
            if settingsError {
                Text(L("无法打开系统设置。请从苹果菜单手动进入对应的隐私与安全性页面。"))
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(L("随时可以在“设置 → 通用”中重新打开这份引导。"))
                .font(.caption).foregroundStyle(.secondary)
            footer
        }
    }

    // 各步共用同一组按钮：位置固定，用户不用每步重找。完成页没有“稍后再说”。
    private var footer: some View {
        HStack {
            if step < OnboardingState.stepCount {
                Button(L("稍后再说")) { complete(false) }
            }
            Spacer()
            if step > 0 {
                Button(L("上一步")) { step -= 1 }
            }
            if step < OnboardingState.stepCount {
                Button(L("继续")) { step += 1 }.keyboardShortcut(.defaultAction)
            } else {
                Button(L("完成")) { complete(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 3)
    }

    // 完成页 — 只做两件事：确认“已经能用了”，并把“登录时启动”放在意图最强的时刻。
    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(palette.accent)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("准备好了")).font(.system(size: 18, weight: .semibold))
                    Text(L("点菜单栏里的 Combo 图标就能用；设置里可以随时调整。"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Card {
                Toggle(L("登录时启动 Combo"), isOn: Binding(get: { store.login }, set: { store.setLogin($0) })).toggleStyle(.switch)
                Text(L("登录后显示菜单栏图标，不增加独立后台服务。")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("随时可以在“设置 → 通用”中重新打开这份引导。"))
                .font(.caption).foregroundStyle(.secondary)
            footer
        }
        .onAppear {
            guard !store.reduceMotion else {
                appeared = true
                return
            }
            withAnimation(Motion.animation(0.32)) { appeared = true }
        }
    }

    private func complete(_ completed: Bool) {
        store.scene = .live
        dismiss(completed)
    }

    @ViewBuilder
    private func permissionAction(_ granted: Bool, denied: Bool, request: @escaping () -> Void, path: String, success: String, detail: String) -> some View {
        if granted {
            HStack(spacing: 13) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 31))
                VStack(alignment: .leading, spacing: 3) {
                    Text(success).font(.system(size: 16, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(palette.accent)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(denied ? L("尚未允许") : L("尚未请求"), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(denied ? L("打开系统设置") : L("请求权限")) {
                        if denied { openSystemSettings() } else { request() }
                    }
                }
                if denied { Text(L("系统设置 → \(path)")).foregroundStyle(.secondary) }
            }
            .font(.caption)
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
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .offset(y: bounce ? -3 : 3)
            Text(L("点这里打开面板"))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor.opacity(0.45)))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bounce = true }
        }
        .accessibilityElement(children: .combine)
    }
}
