import SwiftUI
import Inject
import AppKit

struct SoundOutputs: View {
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var audio: AudioStore
    @ObservedObject var control: AirPodsControl
    @ObservedObject var bluetooth: BluetoothPermission
    @ObservedObject var discovery: AirPlayDiscovery
    @State private var expanded = true
    @State private var hoveredOutput: UInt32?
    init(store: Store) { self.store = store; self.audio = store.audio; self.control = store.audio.airpods; self.bluetooth = store.audio.bluetoothPermission; self.discovery = store.audio.discovery }
    private var active: Bool { store.scene == .live && store.panelVisible && store.screenActive }
    private var state: AirPodsReply? {
        guard store.scene == .live, audio.outputIsAirPods, bluetooth.authorization == .allowedAlways, let state = control.snapshot,
              state.available, state.deviceID == audio.selectedOutputID else { return nil }
        return state
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.bottom, 10)
            Text(L("输出")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 4)
            if audio.outputDevices.isEmpty { Text(L("暂无可用输出设备")).font(.caption).foregroundStyle(.secondary) }
            ForEach(audio.outputDevices) { output in
                let selected = output.id == audio.selectedOutputID
                HStack(spacing: 0) {
                    Button { audio.setOutput(output.id) } label: {
                        HStack(spacing: 8) {
                            DeviceGlyphIcon(glyph: output.glyph).font(.system(size: 16))
                                .foregroundStyle(selected ? Color.white : Color.secondary)
                                .frame(width: 26, height: 26)
                                .background(selected ? Color.blue : Color.primary.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(output.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if selected, let state { battery(state) }
                                if selected, let caption = routeCaption {
                                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }.frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.scene != .live)
                    .accessibilityLabel(output.name)
                    .accessibilityValue(selected ? L("当前输出") + (state.map { L("，") + $0.batteryText } ?? "")
                                        + (audio.isRouteInfoUnavailable ? L("，") + L("设备信息暂不可用") : "") : "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    if selected, let state, !state.modes.isEmpty || state.conversation != nil {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 28, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(expanded ? L("收起耳机选项") : L("展开耳机选项"))
                        .accessibilityValue(expanded ? L("已展开") : L("已收起"))
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
            if active, audio.isRouteInfoUnavailable {
                Button(L("重新读取 AirPlay 信息")) { audio.retryRoute() }.font(.caption).padding(.top, 6)
            }
            nearbyAirPlaySection
            if active && audio.deviceKind.isBluetooth && bluetooth.authorization != .allowedAlways {
                Text(L("允许蓝牙后可读取设备类别；支持的耳机还可显示电量与聆听模式。"))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                if bluetooth.authorization == .notDetermined {
                    Button(L("请求蓝牙权限")) { bluetooth.request() }.font(.caption)
                } else {
                    Text(L("系统设置 → 隐私与安全性 → 蓝牙 → Combo"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("打开系统设置")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }.font(.caption)
                }
            }
            if active && audio.outputIsAirPods && bluetooth.authorization == .allowedAlways && control.snapshot == nil {
                Text(control.unavailable ? L("耳机控制暂不可用") : L("正在读取耳机状态…"))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            if audio.outputIsAirPods && !control.message.isEmpty {
                Text(control.message.string).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            if audio.outputIsAirPods && bluetooth.authorization == .allowedAlways && control.unavailable {
                Button(L("重新读取耳机状态")) { control.refresh(deviceID: audio.selectedOutputID) }
                    .font(.caption).disabled(control.busy).padding(.top, 6)
            }
        }
        .onChange(of: audio.selectedOutputID) { _, _ in expanded = true }
    }
    private var nearbyAirPlaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.top, 8)
            Text(L("附近 AirPlay")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            switch discovery.state {
            case .idle:
                Text(L("查找附近设备需要本地网络权限，连接将在系统声音设置中完成。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("查找附近 AirPlay 设备")) { discovery.request() }.font(.caption).disabled(!active)
            case .searching:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("正在查找附近 AirPlay 设备…")).font(.caption).foregroundStyle(.secondary)
                }
            case .denied:
                Text(L("需要本地网络权限才能显示附近设备"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("系统设置 → 隐私与安全性 → 本地网络 → Combo"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("打开本地网络设置")) { store.openSystemSettings("local-network") }
                    Button(L("重新查找")) { discovery.request() }.disabled(!active)
                }.font(.caption)
            case .failed:
                Text(L("附近设备发现暂不可用，请检查网络后重试。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("重新查找")) { discovery.request() }.font(.caption).disabled(!active)
            case .ready:
                if audio.nearbyAirPlay.isEmpty {
                    Text(L("未发现附近的 AirPlay 设备"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(audio.nearbyAirPlay) { device in
                    Button { store.openSystemSettings("sound") } label: {
                        HStack(spacing: 8) {
                            DeviceGlyphIcon(glyph: OutputDeviceClassifier.glyph(for: .airPlay(device.family)))
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                                .frame(width: 26, height: 26)
                                .background(Color.primary.opacity(0.06), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(device.name)\(L("（AirPlay）"))").font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(audio.nearbyAirPlayCaption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(!active)
                    .accessibilityLabel("\(device.name)\(L("（AirPlay）"))")
                    .accessibilityValue(audio.nearbyAirPlayCaption)
                    .padding(.vertical, 1)
                }
                Button(L("重新查找")) { discovery.request() }.font(.caption).disabled(!active)
            }
        }
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
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: AirPodsControl
    let state: AirPodsReply
    @State private var hoveredOption: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.modes.isEmpty {
                heading(L("聆听模式"))
                let modes = state.modes.filter { $0 != .off }
                AirPodsSegmentTrack(count: modes.count, selected: modes.firstIndex { $0 == control.displayedMode },
                                    enabled: state.canSetMode && !control.busy && !control.unavailable,
                                    select: { control.setMode(modes[$0]) }) {
                    ForEach(modes) { mode in
                        option(mode.title, symbol: symbol(mode), selected: control.displayedMode == mode, pending: control.pendingMode == mode,
                               enabled: state.canSetMode) { control.setMode(mode) }
                    }
                }
                if state.mode == nil { Text(L("当前模式暂不可用")).font(.caption).foregroundStyle(.secondary) }
            }
            if let conversation = control.displayedConversation {
                if !state.modes.isEmpty { Divider().padding(.vertical, 10) }
                heading(L("对话感知"))
                AirPodsSegmentTrack(count: 2, selected: conversation ? 1 : 0,
                                    enabled: state.canSetConversation && !control.busy && !control.unavailable,
                                    select: { control.setConversation($0 == 1) }) {
                    option(L("关闭"), symbol: "person.wave.2.fill", selected: !conversation, pending: control.pendingConversation == false,
                           enabled: state.canSetConversation) { control.setConversation(false) }
                    option(L("打开"), symbol: "person.wave.2.fill", selected: conversation, pending: control.pendingConversation == true,
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
        .accessibilityValue(selected ? (pending ? L("正在切换") : L("已选中")) : L("未选中"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(control.busy || control.unavailable || !enabled)
    }
}
struct AirPodsSegmentTrack<Content: View>: View {
    @ObserveInjection var inject
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

/// 当前 AirPlay 路由的副标题：设备类别 + 设备音量是否可调（Apple TV 实测不可调，由电视遥控）。
extension SoundOutputs {
    var routeCaption: String? {
        if audio.isRouteInfoUnavailable { return L("设备信息暂不可用") }
        guard let info = audio.currentRouteInfo else { return nil }
        var parts: [String] = []
        if let label = info.family.label { parts.append(label) }
        if info.canSetVolume == false {
            parts.append(L(info.family == .appleTV ? "电视音量请用遥控器" : "设备音量请在设备上调节"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 设备字形在 SwiftUI 里的呈现：SF Symbol 走 `systemName`，第三方厂商矢量图走资源目录
/// （`Media.xcassets` 里的 SVG/PDF imageset）。解析失败统一退到兜底符号，不留空白。
struct DeviceGlyphIcon: View {
    let glyph: DeviceGlyph

    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: DeviceGlyphImage.symbolName(name))
        case .asset(let name):
            if let image = NSImage(named: name) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 25, height: 25)
            } else {
                Image(systemName: DeviceGlyphImage.fallbackName)
            }
        }
    }
}
