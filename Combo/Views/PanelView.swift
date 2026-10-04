import SwiftUI
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
    @State private var detailHeaderHeight: CGFloat = 36
    var body: some View {
        Group {
            if mode == .overview { panel { overview } }
            else if let section = store.detailSection { detailPanel(section).id(section).transition(.opacity) }
        }
        .scaleEffect(mode == .detail && !store.reduceMotion && !store.detailRevealed ? 0.96 : 1, anchor: .topTrailing)
        .offset(x: mode == .detail && !store.reduceMotion && !store.detailRevealed ? 8 : 0)
        .animation(Motion.animation(store.reduceMotion ? Motion.reducedFade : (store.detailRevealed ? Motion.detailShow : Motion.detailHide)), value: store.detailRevealed)
        // Switching sections cross-fades, the way the reference's detail window swaps pages.
        .animation(Motion.animation(store.reduceMotion ? 0.12 : 0.25), value: store.detailSection)
        .frame(width: Self.width, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .tint(palette.accent)
        .environment(\.comboPalette, palette)
        .environment(\.panelReduceMotion, store.reduceMotion)
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
        panel(header: AnyView(detailHeader(section))) { detail(section) }
    }
    private func detailHeader(_ section: PanelSection) -> some View {
        HStack {
            Text(section.title).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { store.detailSection = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(PanelIconButtonStyle()).foregroundStyle(mutedText).padding(-8)
                .help(L("关闭")).accessibilityLabel(L("关闭"))
        }.padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { detailHeaderHeight = $0 }
    }
    private func panel<Content: View>(header: AnyView? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        let measured = overviewContentHeight
        let scrolling = header != nil && measured > maxHeight
        return VStack(spacing: 0) {
            if scrolling, let header { header.padding(.horizontal, 18).padding(.top, 18) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !scrolling, let header { header }
                    content()
                }.padding(.horizontal, 18).padding(.top, scrolling ? 0 : 18).padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { value in
                        let height = ceil(value + (scrolling ? detailHeaderHeight + 18 : 0))
                        overviewContentHeight = height
                        reportHeight(height)
                    }
            }.scrollEdgeEffectStyle(scrolling ? .hard : .automatic, for: .top)
        }.frame(width: Self.width, height: min(maxHeight, measured > 0 ? measured : 500))
            .modifier(PanelSurface(tinted: mode == .overview))
    }

    private func tile<Content: View>(interactive: Bool = false, hoverID: String? = nil, action: (() -> Void)? = nil,
                                     actionLabel: String = "", inset: CGFloat = PanelGeometry.cardInset, @ViewBuilder _ content: () -> Content) -> some View {
        let hovered = hoverID.map(hoveredCards.contains) ?? false
        return content().foregroundStyle(palette.primaryText).frame(maxWidth: .infinity, alignment: .leading).padding(inset)
            .background {
                if let action {
                    Button(action: action) { Color.clear.contentShape(RoundedRectangle(cornerRadius: PanelGeometry.cardRadius)) }
                        .buttonStyle(.plain).accessibilityLabel(actionLabel)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: PanelGeometry.cardRadius)
                    .fill(hovered ? palette.primaryText.opacity(0.12) : .clear)
                    .allowsHitTesting(false)
            }
            .modifier(OverviewCardMaterial(interactive: interactive))
            .contentShape(RoundedRectangle(cornerRadius: PanelGeometry.cardRadius))
            .onHover { inside in
                guard let hoverID else { return }
                // Feedback is symmetric: the highlight eases in as well as out.
                if inside { withAnimation(Motion.animation(0.16)) { _ = hoveredCards.insert(hoverID) } }
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
                    Text("Combo").font(.system(size: 24, weight: .semibold)).tracking(-0.36)
                    Text(L("状态，合而为一")).font(.system(size: 11)).foregroundStyle(mutedText)
                }
                Spacer()
                Text(store.scene == .live ? L("本机状态") : L("部分演示"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(mutedText)
            }.padding(.horizontal, 4).padding(.bottom, 6)
            if store.mediaVisible { mediaCard(store.mediaTrack).modifier(cardIn(0)) }
            HStack(alignment: .center, spacing: 10) {
                sectionCard(.battery, snapshot: s).modifier(cardIn(1))
                sectionCard(.wifi, snapshot: s).modifier(cardIn(2))
            }.fixedSize(horizontal: false, vertical: true)
            soundCard(snapshot: s).modifier(cardIn(3))
            if !store.message.isEmpty { Text(store.message.string).font(.caption).foregroundStyle(.orange) }
            Divider().padding(.top, 9)
            HStack {
                Button { NSApp.terminate(nil) } label: { Label(L("退出 Combo"), systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(.plain).frame(minHeight: 28).padding(.vertical, -5).help(L("退出 Combo"))
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape.fill").font(.system(size: 17)) }
                    .buttonStyle(PanelIconButtonStyle(size: CGSize(width: 32, height: 32))).padding(-7.5).help(L("设置…")).accessibilityLabel(L("设置"))
            }.foregroundStyle(mutedText).font(.system(size: 13)).padding(.horizontal, 4)
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
                    .font(.system(size: section == .wifi ? 15 : 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    if section == .battery {
                        Text(store.scene == .live ? battery.statusText : L("演示数据"))
                            .font(.system(size: 11)).foregroundStyle(mutedText).lineLimit(2)
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: PanelGeometry.cardRadius + 2).strokeBorder(store.detailSection == section ? palette.accent : .clear, lineWidth: 1.5).padding(-2).allowsHitTesting(false))
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
                Text(s.output.string).font(.system(size: 11)).foregroundStyle(mutedText).lineLimit(1).allowsHitTesting(false)
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
        .overlay(RoundedRectangle(cornerRadius: PanelGeometry.cardRadius + 2).strokeBorder(store.detailSection == .sound ? palette.accent : .clear, lineWidth: 1.5).padding(-2).allowsHitTesting(false))
        .accessibilityAddTraits(store.detailSection == .sound ? .isSelected : [])

    }
    private func mediaCard(_ track: MediaTrack?) -> some View {
        tile(interactive: true, hoverID: "媒体", action: track?.bundleIdentifier == nil ? nil : { store.openMediaSource() },
             actionLabel: L("打开\(track?.source ?? L("媒体来源"))"), inset: 16) {
            PanelMediaContent(store: store, track: track)
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
            BatteryDetail(store: store)
        case .wifi:
            WiFiSection(wifi: store.wifi, hotspots: store.hotspots, connection: LKey(s.network), active: store.screenActive,
                        systemMessage: store.message.string, openSettings: { store.openSystemSettings("wifi") })
        case .sound:
            VStack(alignment: .leading, spacing: PanelGeometry.groupSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(s.muted ? L("静音") : s.volumeText)
                            .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-0.64)
                        Spacer()
                        Button { audio.toggleMute(isLive: store.scene == .live) } label: {
                            Image(systemName: s.muted ? "speaker.slash" : "speaker.wave.3").font(.system(size: 17))
                        }.buttonStyle(PanelIconButtonStyle()).disabled(store.scene != .live || !audio.canMute)
                            .accessibilityLabel(s.muted ? L("取消静音") : L("静音"))
                    }
                    Slider(value: Binding(get: { store.snapshot.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1)
                        .disabled(store.scene != .live || !audio.canVolume || s.volume == nil)
                        .accessibilityLabel(L("系统音量")).overlay(volumeScroll)
                    Text(s.output.string).font(.system(size: 12)).foregroundStyle(mutedText)
                    if store.scene != .live {
                        Text(L("演示数据 · 不改变系统状态")).font(.system(size: 11)).foregroundStyle(mutedText)
                    } else if !audio.canVolume || !audio.canMute {
                        Text(audio.canVolume && !audio.canMute ? L("当前设备不支持此设置。") : audio.currentRouteInfo?.family == .appleTV ? L("电视音量请用遥控器") : L("设备音量请在设备上调节"))
                            .font(.system(size: 11)).foregroundStyle(mutedText)
                    }
                }.modifier(DetailWell()).accessibilityElement(children: .combine)
                SoundOutputs(store: store)
            }
        }
    }
}

private struct OverviewCardMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let interactive: Bool
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: PanelGeometry.cardRadius))
            } else {
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: RoundedRectangle(cornerRadius: PanelGeometry.cardRadius))
            }
        }.overlay {
            if contrast == .increased { RoundedRectangle(cornerRadius: PanelGeometry.cardRadius).strokeBorder(Color.primary, lineWidth: 1) }
        }
    }
}

private struct PanelMediaContent: View {
    @ObservedObject var store: Store
    let track: MediaTrack?
    @Environment(\.comboPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var artworkColor: NSColor?
    @State private var tilt = CGPoint.zero
    @State private var entered = true
    @State private var sweep = false
    @State private var sweepPosition: CGFloat = -48
    @State private var previousBounce = 0
    @State private var toggleBounce = 0
    @State private var nextBounce = 0
    private var identity: String { [track?.source, track?.title, track?.artist].compactMap { $0 }.joined(separator: "\n") }
    private var metadata: String { [track?.artist, track?.source].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    private var animated: Bool { !store.reduceMotion && store.animate && store.screenActive && store.panelVisible }

    var body: some View {
        let tint = MediaArtworkTint.resolved(artworkColor, palette: palette, increasedContrast: contrast == .increased)
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                artwork
                    .scaleEffect(animated && !entered ? 0.96 : 1)
                    .rotation3DEffect(.degrees(animated ? Double(tilt.y) * -8 : 0), axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(.degrees(animated ? Double(tilt.x) * 8 : 0), axis: (x: 0, y: 1, z: 0))
                    .overlay {
                        if animated && sweep {
                            GeometryReader { _ in
                                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 24).rotationEffect(.degrees(20))
                                    .offset(x: sweepPosition)
                            }.clipShape(RoundedRectangle(cornerRadius: 12)).allowsHitTesting(false)
                        }
                    }
                    .onContinuousHover { phase in
                        guard animated else { tilt = .zero; return }
                        switch phase {
                        case .active(let location): tilt = CGPoint(x: min(1, max(-1, (location.x - 32) / 32)), y: min(1, max(-1, (location.y - 32) / 32)))
                        case .ended: withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tilt = .zero }
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.mediaTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(store.mediaTitle)
                    if !metadata.isEmpty { Text(metadata).font(.system(size: 11)).foregroundStyle(palette.mutedText).lineLimit(1).help(metadata) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: animated && !entered ? 6 : 0).opacity(animated && !entered ? 0 : 1)
                    .animation(animated ? Motion.animation(0.34) : nil, value: entered)
                    .allowsHitTesting(false)
                PanelMediaBars(playing: store.mediaControlsAvailable && store.live.playing, animated: animated)
                    .frame(width: 36.5, height: 16)
                    .accessibilityLabel(store.mediaControlsAvailable ? (store.live.playing ? L("播放中") : L("已暂停")) : L("重新连接中"))
            }
            HStack(spacing: 26) {
                Button { store.controlMedia(.previous); previousBounce += 1 } label: {
                    Image(systemName: "backward.end.fill").symbolEffect(.bounce, value: animated ? previousBounce : 0)
                }.help(L("上一首")).accessibilityLabel(L("上一首"))
                Button { store.controlMedia(.toggle); toggleBounce += 1 } label: {
                    Image(systemName: store.live.playing ? "pause.fill" : "play.fill")
                        .contentTransition(animated ? .symbolEffect(.replace) : .identity)
                        .symbolEffect(.bounce, value: animated ? toggleBounce : 0)
                }.help(store.live.playing ? L("暂停") : L("播放")).accessibilityLabel(store.live.playing ? L("暂停") : L("播放"))
                Button { store.controlMedia(.next); nextBounce += 1 } label: {
                    Image(systemName: "forward.end.fill").symbolEffect(.bounce, value: animated ? nextBounce : 0)
                }.help(L("下一首")).accessibilityLabel(L("下一首"))
            }.buttonStyle(PanelIconButtonStyle(size: CGSize(width: 34, height: 32)))
                .font(.system(size: 17)).disabled(!store.mediaControlsAvailable)
        }
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: tint.color).opacity(tint.alpha)).padding(-16).allowsHitTesting(false)
            if track?.artwork != nil && !reduceTransparency {
                RadialGradient(colors: [Color(nsColor: tint.color).opacity(tint.alpha), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(-16).allowsHitTesting(false)
            }
        }
        .onAppear { artworkColor = MediaArtworkTint.sample(track?.artwork) }
        .onChange(of: track?.artwork) { _, value in artworkColor = MediaArtworkTint.sample(value) }
        .task(id: identity) {
            guard animated else { entered = true; sweep = false; return }
            entered = false; sweep = true; sweepPosition = -48
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 1)) { entered = true }
            withAnimation(Motion.animation(0.6)) { sweepPosition = 88 }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            sweep = false
        }
    }

    private var artwork: some View {
        Group {
            if let data = track?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 24)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.10))
            }
        }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}

struct PanelMediaBars: View {
    let playing: Bool
    let animated: Bool
    @Environment(\.comboPalette) private var palette
    private let count = 6
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || !animated)) { timeline in
            let phase = playing && animated ? timeline.date.timeIntervalSinceReferenceDate / 1.2 : 0.3
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill(palette.accent).frame(width: 4, height: 16)
                        .scaleEffect(y: playing ? 0.3 + 0.7 * (sin(phase * .pi * 2 + Double(index) * .pi / 3) + 1) / 2 : 0.25, anchor: .bottom)
                }
            }.frame(height: 16, alignment: .bottom)
        }.animation(animated ? .spring(response: 0.35, dampingFraction: 0.8) : nil, value: playing)
    }
}

// Artwork is sampled on metadata changes; UI animation never processes image pixels.
enum MediaArtworkTint {
    static func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    private static func srgb(_ value: Double) -> Double { value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055 }
    static func sample(_ data: Data?) -> NSColor? {
        guard let data, let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        guard drawn else { return nil }
        var all = [Double](repeating: 0, count: 3)
        var filtered = all
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            let rgb = (0..<3).map { linear(Double(pixels[index + $0]) / 255 + 0.5 * (1 - alpha)) }
            for channel in 0..<3 { all[channel] += rgb[channel] }
            let luminance = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
            if (0.08...0.95).contains(luminance) {
                for channel in 0..<3 { filtered[channel] += rgb[channel] }
                count += 1
            }
        }
        let mean = (count > 0 ? filtered : all).map { srgb($0 / Double(count > 0 ? count : 64)) }
        let color = NSColor(srgbRed: mean[0], green: mean[1], blue: mean[2], alpha: 1)
        guard color.saturationComponent >= 0.08 else { return nil }
        return NSColor(calibratedHue: color.hueComponent, saturation: min(color.saturationComponent, 0.55),
                       brightness: min(0.70, max(0.42, color.brightnessComponent)), alpha: 1).usingColorSpace(.sRGB)
    }
    static func contrast(_ text: NSColor, _ background: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
            return linear(rgb.redComponent) * 0.2126 + linear(rgb.greenComponent) * 0.7152 + linear(rgb.blueComponent) * 0.0722
        }
        let a = luminance(text), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    static func mixed(_ color: NSColor, over base: NSColor, alpha: Double) -> NSColor {
        let color = color.usingColorSpace(.sRGB) ?? color
        let base = base.usingColorSpace(.sRGB) ?? base
        return NSColor(srgbRed: color.redComponent * alpha + base.redComponent * (1 - alpha),
                       green: color.greenComponent * alpha + base.greenComponent * (1 - alpha),
                       blue: color.blueComponent * alpha + base.blueComponent * (1 - alpha), alpha: 1)
    }
    static func resolved(_ sample: NSColor?, palette: ComboPalette, increasedContrast: Bool = false) -> (color: NSColor, alpha: Double) {
        var color = sample ?? NSColor(palette.accent)
        if !palette.isDark { color = mixed(.white, over: color, alpha: 0.45) }
        var alpha = (palette.isDark ? 0.15 : 0.12) * (sample == nil ? 0.5 : 1) * (increasedContrast ? 0.5 : 1)
        // The static glow shares this budget; the combined overlay must remain below the cap.
        let base = NSColor(palette.surface), text = NSColor(palette.mutedText)
        while alpha > 0 && contrast(text, mixed(color, over: base, alpha: alpha)) < 4.5 { alpha = max(0, alpha - 0.01) }
        return (color, alpha / 2)
    }
}
