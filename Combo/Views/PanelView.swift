import SwiftUI
import Inject
import AppKit

enum PanelSection: String {
    var title: String { LKey(rawValue) }
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
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var wifi: WiFiControl
    var body: some View {
        Text(name).lineLimit(1).minimumScaleFactor(0.8).help(name)
    }
    private var name: String {
        if wifi.powerOn == false { return L("Wi‑Fi 已关闭") }
        if wifi.powerOn == nil { return L("Wi‑Fi 不可用") }
        if let ssid = wifi.currentSSID, !ssid.isEmpty { return ssid }
        return wifi.nameAccess ? L("未连接或名称不可用") : L("允许定位以显示名称")
    }
}

private struct VolumeScroll: NSViewRepresentable {
    let adjust: (NSEvent) -> Void

    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) { view.adjust = adjust }

    final class Catcher: NSView {
        var adjust: ((NSEvent) -> Void)?
        private var monitor: Any?

        // Transparent to clicks, drags and hovers: only the event monitor reacts.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                    guard let self, let window = self.window, event.window === window,
                          bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
                    adjust?(event)
                    return nil
                }
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct PanelView: View {
    @ObserveInjection var inject
    @ObservedObject private var localization = Localization.shared
    static let width: CGFloat = 420
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("themeFamily") private var themeFamily: ComboTheme = .blue
    private var palette: ComboPalette {
        themeFamily.palette(isDark: colorScheme == .dark)
    }
    private var mutedText: Color { palette.mutedText }
    /// `.overview` is the menu-bar panel; `.detail` is the section window that opens beside it.
    enum Mode { case overview, detail }
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    @ObservedObject var audio: AudioStore
    @ObservedObject var bluetoothPermission: BluetoothPermission
    let mode: Mode
    let showSettings: () -> Void
    let maxHeight: CGFloat
    let reportHeight: (CGFloat) -> Void
    @State private var hoveredCards: Set<String> = []
    @State private var settled = false
    @State private var overviewContentHeight: CGFloat = 0
    var body: some View {
        Group {
            if mode == .overview { panel { overview } }
            else if let section = store.detailSection { detailPanel(section).id(section).transition(.opacity) }
        }
        // Switching sections cross-fades, the way the reference's detail window swaps pages.
        .animation(Motion.animation(store.reduceMotion ? 0.12 : 0.25), value: store.detailSection)
        .frame(width: Self.width, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(palette.accent)
        // 内容必须和窗口同帧起跑：参考录屏里外框落到 1.0 时卡片已到 0.52，任何一帧都不存在
        // “只有框没有内容”。若等到 onAppear 才起跑，面板会先空约 100ms（窗口还没上屏）。
        // 详情窗没有窗口滑入，渲染即入场。
        .task {
            guard mode == .detail else { return }
            settled = true
        }
        .onChange(of: store.panelRevealed) { _, revealed in
            guard mode == .overview else { return }
            settled = revealed
        }
        .task(id: mode == .detail && store.detailSection == .battery && store.scene == .live) {
            guard mode == .detail, store.detailSection == .battery, store.scene == .live else { battery.energyApps.cancel(); return }
            while !Task.isCancelled {
                battery.energyApps.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .task(id: "\(mode == .detail && store.detailSection == .sound && store.scene == .live && bluetoothPermission.authorization == .allowedAlways && (store.live.outputIsAirPods || store.detailSection == .sound))-\(audio.selectedOutputID)") {
            guard mode == .detail, store.detailSection == .sound, store.scene == .live, bluetoothPermission.authorization == .allowedAlways,
                  store.live.outputIsAirPods || store.detailSection == .sound else { audio.airpods.cancel(); return }
            while !Task.isCancelled {
                audio.airpods.refresh(deviceID: audio.selectedOutputID)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .enableInjection()
    }
    // Keep the reference's reading-order reveal, with less travel and a soft ease-out landing.
    private struct CardIn: ViewModifier {
        let index: Int
        let done: Bool
        let reduced: Bool
        func body(content: Content) -> some View {
            content
                .opacity(done ? 1 : 0)
                .offset(x: reduced || done ? 0 : Motion.cardOffset)
                .animation(entry.delay(done && !reduced ? Double(index) * Motion.cardStep : 0), value: done)
        }
        // Reduced motion keeps a plain cross-fade, without travel or stagger.
        private var entry: Animation {
            Motion.animation(reduced ? Motion.reducedFade : Motion.cardShow)
        }
    }
    private func cardIn(_ index: Int) -> some ViewModifier {
        CardIn(index: index, done: settled, reduced: store.reduceMotion)
    }
    private func detailPanel(_ section: PanelSection) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(section.title).font(.headline)
                    Spacer()
                    Button { store.detailSection = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(mutedText)
                        .help(L("关闭")).accessibilityLabel(L("关闭"))
                }
                tile { detail(section) }
                if !store.message.isEmpty { Text(store.message.string).font(.caption).foregroundStyle(.orange) }
            }
        }
    }
    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let measured = overviewContentHeight
        return ScrollView {
            content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { value in
                    overviewContentHeight = ceil(value)
                    reportHeight(ceil(value))
                }
        }
            .frame(width: Self.width, height: min(maxHeight, measured > 0 ? measured : 500))
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
                // Feedback is symmetric: the highlight eases in as well as out.
                if inside { withAnimation(Motion.animation(0.16)) { hoveredCards.insert(hoverID) } }
                else { withAnimation(Motion.animation(0.2)) { _ = hoveredCards.remove(hoverID) } }
            }
    }
    private var overview: some View {
        let s = store.snapshot
        // No GlassEffectContainer here: it renders the tiles in their own compositing pass, which
        // ignores per-card opacity, and this reveal is a per-card fade.
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ComboIcon(snapshot: s, animate: store.animate, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Combo").font(.system(size: 24, weight: .semibold))
                    Text(L("状态，合而为一")).font(.system(size: 12)).foregroundStyle(mutedText)
                }
                Spacer()
                Text(store.scene == .live ? L("本机状态") : L("部分演示"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(mutedText)
            }.padding(.horizontal, 4).padding(.bottom, 6)
            if store.mediaVisible { mediaCard(store.mediaTrack).modifier(cardIn(0)) }
            HStack(alignment: .top, spacing: 10) {
                sectionCard(.battery, snapshot: s).modifier(cardIn(1))
                sectionCard(.wifi, snapshot: s).modifier(cardIn(2))
            }.fixedSize(horizontal: false, vertical: true)
            soundCard(snapshot: s).modifier(cardIn(3))
            if !store.message.isEmpty { Text(store.message.string).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { NSApp.terminate(nil) } label: { Label(L("退出 Combo"), systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(.plain).help(L("退出 Combo"))
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape.fill").font(.system(size: 17)) }
                    .buttonStyle(.plain).help(L("设置…")).accessibilityLabel(L("设置"))
            }.foregroundStyle(mutedText).font(.system(size: 12, weight: .medium)).padding(.horizontal, 4).padding(.top, 9)
        }
    }
    private func sectionCard(_ section: PanelSection, snapshot s: Snapshot) -> some View {
        Button { choose(section) } label: {
            tile(interactive: true, hoverID: section.rawValue) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        Image(systemName: section.symbol).frame(width: 20)
                            .foregroundStyle(palette.accent)
                        Text(section.title).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    Group {
                        if section == .wifi { WiFiName(wifi: store.wifi) }
                        else { Text(s.batteryText).lineLimit(1) }
                    }
                    .font(.system(size: section == .wifi ? 17 : 21, weight: .semibold, design: .rounded))
                    if section == .battery {
                        Text(store.scene == .live ? battery.statusText : L("演示数据"))
                            .font(.system(size: 11)).foregroundStyle(mutedText).lineLimit(2)
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(store.detailSection == section ? palette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
        .accessibilityAddTraits(store.detailSection == section ? .isSelected : [])
    }
    private func soundCard(snapshot s: Snapshot) -> some View {
        tile(interactive: true, hoverID: PanelSection.sound.rawValue,
             action: { choose(.sound) }, actionLabel: L("声音详情")) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: PanelSection.sound.symbol).frame(width: 20).foregroundStyle(palette.accent)
                    Text(L("声音")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                }.allowsHitTesting(false)
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { store.snapshot.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1)
                        .disabled(store.scene != .live || !audio.canVolume || s.volume == nil)
                        .accessibilityLabel(L("系统音量"))
                        .tint(.gray)
                        .overlay(volumeScroll)
                    Text(s.muted ? L("静音") : s.volumeText).allowsHitTesting(false)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                Text(s.output.string).font(.system(size: 12)).foregroundStyle(mutedText).lineLimit(1).allowsHitTesting(false)
                if store.scene == .live, s.outputIsAirPods, let state = audio.airpods.snapshot,
                   state.available, state.deviceID == audio.selectedOutputID,
                   state.left != nil || state.right != nil || state.caseBattery != nil || state.single != nil {
                    HStack(spacing: 8) {
                        if let left = state.left { Label("\(left)%", systemImage: "airpods.pro.left") }
                        if let right = state.right { Label("\(right)%", systemImage: "airpods.pro.right") }
                        if let charge = state.caseBattery { Label("\(charge)%", systemImage: "airpodspro.chargingcase.wireless") }
                        if let single = state.single, state.left == nil && state.right == nil { Text(L("电量 \(single)%")) }
                    }.font(.system(size: 11)).foregroundStyle(mutedText).allowsHitTesting(false)
                        .accessibilityElement(children: .ignore).accessibilityLabel(state.batteryText)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(store.detailSection == .sound ? palette.accent : .clear, lineWidth: 2).padding(-2).allowsHitTesting(false))
        .accessibilityAddTraits(store.detailSection == .sound ? .isSelected : [])
    }
    private func mediaCard(_ track: MediaTrack?) -> some View {
        tile(interactive: true, hoverID: "媒体", action: track?.bundleIdentifier == nil ? nil : { store.openMediaSource() },
             actionLabel: L("打开\(track?.source ?? L("媒体来源"))")) {
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
                    Text(store.mediaControlsAvailable ? (store.live.playing ? L("播放中") : L("已暂停")) : L("重新连接中")).font(.system(size: 11)).foregroundStyle(mutedText)
                }.allowsHitTesting(false)
                HStack(spacing: 18) {
                    Spacer()
                    Button { store.controlMedia(.previous) } label: { Image(systemName: "backward.end.fill").frame(width: 30, height: 28) }
                        .help(L("上一首")).accessibilityLabel(L("上一首"))
                    Button { store.controlMedia(.toggle) } label: { Image(systemName: store.live.playing ? "pause.fill" : "play.fill").frame(width: 30, height: 28) }
                        .help(store.live.playing ? L("暂停") : L("播放")).accessibilityLabel(store.live.playing ? L("暂停") : L("播放"))
                    Button { store.controlMedia(.next) } label: { Image(systemName: "forward.end.fill").frame(width: 30, height: 28) }
                        .help(L("下一首")).accessibilityLabel(L("下一首"))
                    Spacer()
                }.buttonStyle(.plain).font(.system(size: 15)).disabled(!store.mediaControlsAvailable)
            }
        }
    }
    // Two-finger scrolling or a mouse wheel over the volume slider adjusts the system volume.
    // Monitor-based, so the overlay stays click-through: dragging the slider keeps working.
    private var volumeScroll: some View {
        VolumeScroll { event in
            guard store.scene == .live, audio.canVolume, let current = audio.volume else { return }
            audio.setVolume(scrollVolume(current: current, scrollingDelta: event.scrollingDeltaY,
                                         precise: event.hasPreciseScrollingDeltas,
                                         inverted: event.isDirectionInvertedFromDevice), isLive: true)
        }.padding(-6)
    }
    private func choose(_ section: PanelSection) {
        store.detailSection = store.detailSection == section ? nil : section
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
                            Text(L("电源：\(battery.sourceText)")).font(.caption).foregroundStyle(.secondary)
                            Text(battery.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else { Text(L("演示数据 · 不改变系统状态")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if store.scene == .live {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("当前充电上限：\(battery.chargeLimit.text)"))
                        Text(L("健康：\(LKey(battery.health)) · 低电量模式：\(battery.lowPowerMode ? L("开") : L("关"))"))
                    }.font(.caption).foregroundStyle(.secondary)
                    ChargeFullSection(control: battery.chargeControl, eligible: battery.canRequestFullCharge(scene: store.scene),
                                      expectedLimit: battery.chargeLimit, action: { battery.requestFullCharge(scene: store.scene) })
                    PowerModeSection(control: battery.powerMode, source: battery.onAC.map { $0 ? .adapter : .battery }) { battery.refreshBattery() }
                    EnergyAppsSection(control: battery.energyApps, limit: battery.energyAppLimit)
                } else { Button(L("返回本机状态")) { store.scene = .live }.font(.caption) }
                HStack { Button(L("电池设置")) { store.openSystemSettings("battery") }; Button(L("耗电应用")) { store.openActivityMonitor() } }.font(.caption)
            }
        case .wifi:
            WiFiSection(wifi: store.wifi, hotspots: store.hotspots, connection: LKey(s.network), active: store.screenActive,
                        openSettings: { store.openSystemSettings("wifi") })
        case .sound:
            VStack(alignment: .leading, spacing: 16) {
                Label(L("声音"), systemImage: "speaker.wave.2").font(.headline)
                HStack { Text(s.muted ? L("静音") : L("音量")); Spacer(); Text(s.volumeText).foregroundStyle(.secondary) }.font(.caption)
                Slider(value: Binding(get: { s.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1).disabled(store.scene != .live || !audio.canVolume).accessibilityLabel(L("系统音量"))
                    .tint(.gray)
                    .overlay(volumeScroll)
                SoundOutputs(store: store)
                HStack { Button(s.muted ? L("取消静音") : L("静音")) { audio.toggleMute(isLive: store.scene == .live) }.disabled(store.scene != .live || !audio.canMute); Button(L("声音设置 / AirPods")) { store.openSystemSettings("sound") } }.font(.caption)
            }
        }
    }
}
