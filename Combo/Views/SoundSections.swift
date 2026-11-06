import SwiftUI
import AppKit

struct SoundOutputs: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var audio: AudioStore
    @ObservedObject var control: AirPodsControl
    @ObservedObject var bluetooth: BluetoothPermission
    @ObservedObject var discovery: AirPlayDiscovery
    @Environment(\.comboPalette) private var palette
    init(store: Store) { self.store = store; self.audio = store.audio; self.control = store.audio.airpods; self.bluetooth = store.audio.bluetoothPermission; self.discovery = store.audio.discovery }
    private var active: Bool { store.scene == .live && store.panelVisible && store.screenActive }
    private var state: AirPodsReply? {
        guard store.scene == .live, audio.outputIsAirPods, bluetooth.authorization == .allowedAlways, let state = control.snapshot,
              state.available, state.deviceID == audio.selectedOutputID else { return nil }
        return state
    }
    var body: some View {
        VStack(alignment: .leading, spacing: PanelGeometry.groupSpacing) {
            situation
            if let state, !state.modes.isEmpty || state.conversation != nil {
                AirPodsSection(control: control, state: state)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L("输出设备")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText)
                if audio.outputDevices.isEmpty { Text(L("暂无可用输出设备")).font(.system(size: 11)).foregroundStyle(palette.mutedText) }
                ForEach(audio.outputDevices) { output in
                    let selected = output.id == audio.selectedOutputID
                    Button { audio.setOutput(output.id) } label: {
                        HStack(spacing: 12) {
                            DeviceGlyphIcon(glyph: output.glyph).font(.system(size: 19)).foregroundStyle(selected ? palette.primaryText : palette.mutedText)
                                .frame(width: 23)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(output.name).font(.system(size: 12)).lineLimit(2).help(output.name)
                                if selected, let caption = routeCaption { Text(caption).font(.system(size: 11)).foregroundStyle(palette.mutedText) }
                            }
                            Spacer(minLength: 0)
                            if selected { Image(systemName: "checkmark").foregroundStyle(palette.accent).accessibilityHidden(true) }
                        }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    }.buttonStyle(PanelRowButtonStyle()).disabled(store.scene != .live).pointerStyle(.link)
                        .background(selected ? palette.module : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityLabel(output.name)
                        .accessibilityValue(selected ? L("当前输出") + (state.map { L("，") + $0.batteryText } ?? "")
                                            + (audio.isRouteInfoUnavailable ? L("，") + L("设备信息暂不可用") : "") : "")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
                nearbyAirPlaySection
            }
            if active && audio.deviceKind.isBluetooth && bluetooth.authorization != .allowedAlways { bluetoothPermission }
            if active && audio.outputIsAirPods && bluetooth.authorization == .allowedAlways && control.snapshot == nil {
                Text(control.unavailable ? L("耳机控制暂不可用") : L("正在读取耳机状态…"))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText)
            }
            if active, audio.isRouteInfoUnavailable {
                Button(L("重新读取 AirPlay 信息")) { audio.retryRoute() }.buttonStyle(PanelButtonStyle())
            }
            if audio.outputIsAirPods && bluetooth.authorization == .allowedAlways && control.unavailable {
                Button(L("重新读取耳机状态")) {
                    control.refresh(deviceID: audio.selectedOutputID, target: AudioOutputIdentity.target(for: audio.selectedOutputID))
                }.buttonStyle(PanelButtonStyle()).disabled(control.busy)
            }
        }
    }
    @ViewBuilder private var situation: some View {
        if !store.message.isEmpty { DetailSituation(text: store.message.string, warning: true) }
        else if audio.outputIsAirPods && !control.message.isEmpty { DetailSituation(text: control.message.string, busy: control.busy, warning: !control.busy) }
        else if !audio.message.isEmpty { DetailSituation(text: audio.message.string, warning: true) }
        else if active {
            switch discovery.state {
            case .searching: DetailSituation(text: L("正在查找附近 AirPlay 设备…"), busy: true)
            case .denied:
                DetailSituation(text: L("需要本地网络权限才能显示附近设备"), actionTitle: L("打开本地网络设置"), action: { store.openSystemSettings("local-network") })
            case .failed:
                DetailSituation(text: L("附近设备发现暂不可用，请检查网络后重试。"), warning: true, actionTitle: L("重新查找"), action: { discovery.request() })
            default: EmptyView()
            }
        }
    }
    private var bluetoothPermission: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("允许蓝牙后可读取设备类别；支持的耳机还可显示电量与聆听模式。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText)
            if bluetooth.authorization == .notDetermined {
                Button(L("请求蓝牙权限")) { bluetooth.request() }.buttonStyle(PanelButtonStyle())
            } else {
                Text(L("系统设置 → 隐私与安全性 → 蓝牙 → Combo")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                Button(L("打开系统设置")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
                    .buttonStyle(PanelButtonStyle())
            }
        }.padding(.vertical, 6)
    }
    private var nearbyAirPlaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch discovery.state {
            case .idle:
                Button { discovery.request() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "airplay.audio").font(.system(size: 19)).frame(width: 23)
                        Text(L("查找附近 AirPlay 设备")).font(.system(size: 12))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 11))
                    }.foregroundStyle(palette.mutedText).frame(minHeight: 32)
                }.buttonStyle(PanelRowButtonStyle()).disabled(!active).pointerStyle(.link)
                    .help(L("查找附近设备需要本地网络权限；连接在系统声音设置中完成。"))
            case .searching:
                EmptyView()
            case .denied:
                Text(L("系统设置 → 隐私与安全性 → 本地网络 → Combo"))
                    .font(.caption).foregroundStyle(palette.mutedText)
                HStack {
                    Button(L("重新查找")) { discovery.request() }.disabled(!active)
                }.font(.caption)
            case .failed:
                if !store.message.isEmpty || !control.message.isEmpty || !audio.message.isEmpty {
                    Button(L("重新查找")) { discovery.request() }.font(.caption).disabled(!active)
                }
            case .ready:
                if audio.nearbyAirPlay.isEmpty {
                    Text(L("未发现附近的 AirPlay 设备"))
                        .font(.caption).foregroundStyle(palette.mutedText)
                }
                ForEach(audio.nearbyAirPlay) { device in
                    Button { store.openSystemSettings("sound") } label: {
                        HStack(spacing: 8) {
                            DeviceGlyphIcon(glyph: OutputDeviceClassifier.glyph(for: .airPlay(device.family)))
                                .font(.system(size: 19)).foregroundStyle(palette.mutedText)
                                .frame(width: 23)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(device.name)\(L("（AirPlay）"))").font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(audio.nearbyAirPlayCaption).font(.system(size: 11)).foregroundStyle(palette.mutedText).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 12)).foregroundStyle(palette.mutedText)
                        }
                    }
                    .buttonStyle(PanelRowButtonStyle()).disabled(!active)
                    .accessibilityLabel("\(device.name)\(L("（AirPlay）"))")
                    .accessibilityValue(audio.nearbyAirPlayCaption)
                    .padding(.vertical, 1)
                }
                Button(L("重新查找")) { discovery.request() }.font(.caption).disabled(!active)
            }
        }.buttonStyle(PanelButtonStyle())
    }
}

struct AirPodsBatterySummary: View {
    let state: AirPodsReply
    var detailed = false
    @Environment(\.comboPalette) private var palette
    private var values: [(String, Int)] {
        var values: [(String, Int)] = []
        if let left = state.left { values.append((L("左耳"), left)) }
        if let right = state.right { values.append((L("右耳"), right)) }
        if let charge = state.caseBattery { values.append((L("充电盒"), charge)) }
        if values.isEmpty, let single = state.single { values.append((L("电量"), single)) }
        return values
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(values.indices, id: \.self) { index in
                if detailed, index > 0 { Rectangle().fill(palette.separator).frame(width: 0.5) }
                Group {
                    if detailed {
                        VStack(spacing: 4) {
                            Text(values[index].0).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                            Text("\(values[index].1)%").font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Text("\(values[index].0) \(values[index].1)%").font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }
                }.frame(maxWidth: .infinity)
            }
        }.fixedSize(horizontal: false, vertical: true).monospacedDigit()
            .accessibilityElement(children: .ignore).accessibilityLabel(state.batteryText)
    }
}

struct AirPodsSection: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var control: AirPodsControl
    let state: AirPodsReply
    @Environment(\.comboPalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.modes.isEmpty {
                heading(L("聆听模式"))
                let modes = [ListeningMode.noiseCancellation, .transparency, .adaptive, .off].filter { state.modes.contains($0) }
                AirPodsSegmentTrack(count: modes.count, selected: modes.firstIndex { $0 == control.displayedMode },
                                    enabled: state.canSetMode && !control.busy && !control.unavailable,
                                    select: { control.setMode(modes[$0]) }) {
                    ForEach(modes) { mode in
                        option(mode.title, selected: control.displayedMode == mode, pending: control.pendingMode == mode,
                               enabled: state.canSetMode) { control.setMode(mode) }
                    }
                }
                if control.displayedMode == nil { Text(L("当前模式暂不可用")).font(.system(size: 11)).foregroundStyle(palette.mutedText).padding(.top, 8) }
                if !state.canSetMode { Text(L("当前设备不支持此设置。")).font(.system(size: 11)).foregroundStyle(palette.mutedText) }
            }
            if let conversation = control.displayedConversation {
                if !state.modes.isEmpty { Divider().padding(.vertical, 10) }
                heading(L("对话感知"))
                AirPodsSegmentTrack(count: 2, selected: conversation ? 1 : 0,
                                    enabled: state.canSetConversation && !control.busy && !control.unavailable,
                                    select: { control.setConversation($0 == 1) }) {
                    option(L("关闭"), selected: !conversation, pending: control.pendingConversation == false,
                           enabled: state.canSetConversation) { control.setConversation(false) }
                    option(L("打开"), selected: conversation, pending: control.pendingConversation == true,
                           enabled: state.canSetConversation) { control.setConversation(true) }
                }
                if !state.canSetConversation { Text(L("当前设备不支持此设置。")).font(.system(size: 11)).foregroundStyle(palette.mutedText) }
            }
        }
    }
    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.mutedText).padding(.bottom, 7)
    }
    private func option(_ title: String, selected: Bool, pending: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 31).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? (pending ? L("正在切换") : L("已选中")) : L("未选中"))
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
    @Environment(\.panelReduceMotion) private var reduceMotion
    @Environment(\.comboPalette) private var palette
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
            .background(alignment: .leading) {
                if let position {
                    RoundedRectangle(cornerRadius: 7).fill(palette.hover)
                        .frame(width: width / CGFloat(max(1, count)), height: 31)
                        .offset(x: width / CGFloat(max(1, count)) * position)
                        .animation(reduceMotion || draggedPosition != nil ? nil : .easeInOut(duration: 0.22), value: position)
                        .allowsHitTesting(false)
                }
            }.padding(3).background(palette.module, in: RoundedRectangle(cornerRadius: 10))
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
