import AppKit
import CoreBluetooth
import CoreLocation
import SwiftUI
import Inject

struct OnboardingView: View {
    @ObserveInjection var inject
    @ObservedObject var store: Store
    @ObservedObject var setup: MenuBarSetup
    @ObservedObject var wifi: WiFiControl
    @ObservedObject var bluetooth: BluetoothPermission
    let finish: () -> Void
    @State private var step = 0
    @State private var settingsError = false
    @Environment(\.comboPalette) private var palette

    init(store: Store, finish: @escaping () -> Void) {
        self.store = store
        self.setup = store.menuSetup
        self.wifi = store.wifi
        self.bluetooth = store.bluetoothPermission
        self.finish = finish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(nsImage: brandImage).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("开始使用 Combo").font(.system(size: 25, weight: .semibold))
                        Text("第 \(step + 1) 步，共 2 步").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(step == 0 ? "整理菜单栏" : "按需授权")
                        .font(.caption).foregroundStyle(palette.accent)
                }
                if step == 0 { menuStep } else { permissionStep }
            }
            .padding(32)
            .frame(maxWidth: 730, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.canvasTop)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            wifi.refresh()
            bluetooth.refresh()
        }
        .enableInjection()
    }

    private var menuStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(store.hasInternalBattery ? "一个图标，查看 Wi‑Fi、电池和声音" : "一个图标，查看 Wi‑Fi 和声音")
                .font(.system(size: 18, weight: .semibold))
            Text("Combo 集中了这些菜单栏功能。你可以隐藏系统原图标，让菜单栏更简洁；保留它们也不影响 Combo 使用。隐藏图标不会关闭 Wi‑Fi、声音或控制中心的功能。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            HStack {
                Label("系统设置 → 菜单栏", systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("打开菜单栏设置") { settingsError = !setup.openWithoutCapture() }
            }
            .padding(15)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
            Text(store.hasInternalBattery ? "取消 Wi‑Fi、电池、声音左侧的勾选：" : "取消 Wi‑Fi、声音左侧的勾选：")
                .font(.system(size: 13, weight: .medium))
            HStack(alignment: .top, spacing: 12) {
                menuScreenshot("关闭前 · 蓝色勾选", image: "MenuBarBefore")
                menuScreenshot("关闭后 · 取消勾选", image: "MenuBarAfter")
            }
            if !store.hasInternalBattery {
                Text("图中电池项目仅适用于有内置电池的 Mac。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("不同 macOS 版本的排列可能略有差异，以项目名称和左侧勾选为准。")
                .font(.caption).foregroundStyle(.secondary)
            if settingsError {
                Text("无法打开系统设置。请从苹果菜单手动进入“系统设置 → 菜单栏”。")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("跳过这一步") { settingsError = false; step = 1 }
                Spacer()
                Button("已设置，继续") { settingsError = false; step = 1 }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func menuScreenshot(_ title: String, image: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let path = Bundle.main.path(forResource: image, ofType: "png"),
               let screenshot = NSImage(contentsOfFile: path) {
                Image(nsImage: screenshot).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("按需开启耳机与网络信息")
                .font(.system(size: 18, weight: .semibold))
            Text("两项权限各有用途。请在了解用途后分别点击申请；跳过也能使用 Combo 的基本功能。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Card {
                Label("蓝牙", systemImage: "headphones").font(.headline)
                Text("用于读取已连接耳机的电量与聆听模式，并提供受支持的耳机模式控制。不授权仍可使用 Wi‑Fi、Mac 电池和系统音量。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                permissionAction(bluetooth.authorization == .allowedAlways,
                                 denied: bluetooth.authorization == .denied || bluetooth.authorization == .restricted,
                                 request: { bluetooth.request() }, path: "隐私与安全性 → 蓝牙",
                                 success: "蓝牙权限已开启", detail: "可以查看已连接耳机的状态")
            }
            Card {
                Label("定位", systemImage: "location").font(.headline)
                Text("macOS 将当前 Wi‑Fi 名称和附近网络纳入定位权限保护。Combo 用它显示网络信息；当前版本不请求坐标，也不上传扫描结果。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                permissionAction(wifi.nameAccess,
                                 denied: wifi.locationAuthorizationStatus == .denied || wifi.locationAuthorizationStatus == .restricted,
                                 request: { wifi.requestLocationAccess() }, path: "隐私与安全性 → 定位服务 → Combo",
                                 success: "定位权限已开启", detail: "可以显示 Wi‑Fi 网络信息")
            }
            if settingsError {
                Text("无法打开系统设置。请从苹果菜单手动进入对应的隐私与安全性页面。")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("返回上一步") { step = 0 }
                Spacer()
                Button("稍后再说", action: finish)
                Button("完成引导", action: finish).keyboardShortcut(.defaultAction)
            }
        }
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
                    Label(denied ? "尚未允许" : "尚未请求", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(denied ? "打开系统设置" : "请求权限") {
                        if denied { openSystemSettings() } else { request() }
                    }
                }
                if denied { Text("系统设置 → \(path)").foregroundStyle(.secondary) }
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
