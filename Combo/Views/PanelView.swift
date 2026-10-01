import SwiftUI
import Inject
import AppKit

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
    @ObserveInjection var inject
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
    @ObserveInjection var inject
    static let width: CGFloat = 420
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
    private var mutedText: Color { palette.mutedText }
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var audio: AudioStore
    @ObservedObject var bluetoothPermission: BluetoothPermission
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
            guard store.panelVisible && store.screenActive && store.scene == .live && selected == .battery else { battery.energyApps.cancel(); return }
            while !Task.isCancelled {
                battery.energyApps.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: "\(store.panelVisible && store.screenActive && store.scene == .live && bluetoothPermission.authorization == .allowedAlways && (store.live.outputIsAirPods || selected == .sound))-\(audio.selectedOutputID)") {
            guard store.panelVisible && store.screenActive && store.scene == .live && bluetoothPermission.authorization == .allowedAlways && (store.live.outputIsAirPods || selected == .sound) else { audio.airpods.cancel(); return }
            while !Task.isCancelled {
                audio.airpods.refresh(deviceID: audio.selectedOutputID)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .enableInjection()
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
                        Text(store.scene == .live ? battery.statusText : "演示数据")
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
                    Slider(value: Binding(get: { store.snapshot.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1)
                        .disabled(store.scene != .live || !audio.canVolume || s.volume == nil)
                        .accessibilityLabel("系统音量")
                        .tint(.gray)
                    Text(s.muted ? "静音" : s.volumeText).allowsHitTesting(false)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                Text(s.output).font(.system(size: 12)).foregroundStyle(mutedText).lineLimit(1).allowsHitTesting(false)
                if store.scene == .live, s.outputIsAirPods, let state = audio.airpods.snapshot,
                   state.available, state.deviceID == audio.selectedOutputID,
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
                            Text("电源：\(battery.sourceText)").font(.caption).foregroundStyle(.secondary)
                            Text(battery.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else { Text("演示数据 · 不改变系统状态").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if store.scene == .live {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("当前充电上限：\(battery.chargeLimit.text)")
                        Text("健康：\(battery.health) · 低电量模式：\(battery.lowPowerMode ? "开" : "关")")
                    }.font(.caption).foregroundStyle(.secondary)
                    ChargeFullSection(control: battery.chargeControl, eligible: battery.canRequestFullCharge(scene: store.scene),
                                      expectedLimit: battery.chargeLimit, action: { battery.requestFullCharge(scene: store.scene) })
                    PowerModeSection(control: battery.powerMode, source: battery.onAC.map { $0 ? .adapter : .battery }) { battery.refreshBattery() }
                    EnergyAppsSection(control: battery.energyApps, limit: battery.energyAppLimit)
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
                Slider(value: Binding(get: { s.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1).disabled(store.scene != .live || !audio.canVolume).accessibilityLabel("系统音量")
                    .tint(.gray)
                SoundOutputs(store: store)
                HStack { Button(s.muted ? "取消静音" : "静音") { audio.toggleMute(isLive: store.scene == .live) }.disabled(store.scene != .live || !audio.canMute); Button("声音设置 / AirPods") { store.openSystemSettings("sound") } }.font(.caption)
            }
        }
    }
}
