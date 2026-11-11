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
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var localization = Localization.shared
    @AppStorage("appearanceMode") private var appearanceMode: ComboAppearance = .system
    static let width: CGFloat = 352
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette { ComboPalette.standard(isDark: colorScheme == .dark) }
    @ObservedObject private var store: Store
    @ObservedObject private var battery: BatteryStore
    @ObservedObject private var audio: AudioStore
    @ObservedObject private var airpods: AirPodsControl
    @ObservedObject private var bluetoothPermission: BluetoothPermission
    let showSettings: () -> Void
    let maxHeight: CGFloat
    let reportHeight: (CGFloat) -> Void
    @State private var hoveredSection: PanelSection?
    @State private var settled = false
    @State private var contentHeight: CGFloat = 0
    private enum FocusTarget: Hashable { case section(PanelSection), back, settings }
    @FocusState private var focusedControl: FocusTarget?
    private var headerHeight: CGFloat { store.detailSection == nil ? 0 : 69 }

    init(store: Store, airpods: AirPodsControl? = nil, showSettings: @escaping () -> Void,
         maxHeight: CGFloat, reportHeight: @escaping (CGFloat) -> Void) {
        self.store = store
        battery = store.battery
        audio = store.audio
        self.airpods = airpods ?? store.audio.airpods
        bluetoothPermission = store.audio.bluetoothPermission
        self.showSettings = showSettings
        self.maxHeight = maxHeight
        self.reportHeight = reportHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            if let section = store.detailSection { detailHeader(section) }
            ScrollView {
                Group {
                    if let section = store.detailSection { detail(section) }
                    else { overview }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, store.detailSection == nil ? PanelGeometry.inset : 26)
                .padding(.top, store.detailSection == nil ? 17 : 0)
                .padding(.bottom, 18)
                .background(HoverScrollerBridge(accent: NSColor(palette.accent)))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { value in
                    let height = ceil(value + headerHeight)
                    contentHeight = height
                    reportHeight(height)
                }
            }.scrollBounceBehavior(.basedOnSize).scrollEdgeEffectStyle(.hard, for: .top)
                .id(store.detailSection)
        }
        .frame(width: Self.width, height: min(maxHeight, contentHeight > 0 ? contentHeight : 500))
        .modifier(PanelSurface())
        .frame(maxHeight: .infinity, alignment: .top)
        .font(.system(size: 13)).foregroundStyle(palette.primaryText).tint(palette.accent)
        .environment(\.comboPalette, palette).environment(\.panelReduceMotion, store.reduceMotion)
        .preferredColorScheme(appearanceMode.colorScheme)
        .onChange(of: store.panelRevealed) { _, revealed in settled = revealed }
        .onChange(of: store.panelExpanded && store.panelSettingsFocusRequested) { _, requested in
            if requested {
                focusedControl = .settings
                store.panelSettingsFocusRequested = false
            }
        }
        .onChange(of: store.detailSection) { previous, section in
            if section != nil { focusedControl = .back }
            else if let previous { focusedControl = .section(previous) }
        }
        .task(id: store.panelVisible && store.detailSection == .battery && store.scene == .live) {
            guard store.panelVisible, store.detailSection == .battery, store.scene == .live else { battery.energyApps.cancel(); return }
            while !Task.isCancelled {
                battery.energyApps.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private struct CardIn: ViewModifier {
        let index: Int
        let done: Bool
        let reduced: Bool
        func body(content: Content) -> some View {
            content.opacity(done ? 1 : 0).offset(x: reduced || done ? 0 : Motion.cardOffset)
                .animation(Motion.animation(reduced ? Motion.reducedFade : Motion.cardShow)
                    .delay(done && !reduced ? Double(index) * Motion.cardStep : 0), value: done)
        }
    }
    private func cardIn(_ index: Int) -> some ViewModifier {
        CardIn(index: index, done: settled, reduced: store.reduceMotion)
    }
    private func detailHeader(_ section: PanelSection) -> some View {
        HStack(spacing: 9) {
            Button { store.detailSection = nil } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    .frame(width: 29, height: 29).background(palette.module, in: Circle())
            }.buttonStyle(.plain).pointerStyle(.link).focused($focusedControl, equals: .back)
                .help(L("返回主面板")).accessibilityLabel(L("返回主面板"))
            Text(section.title).font(.system(size: 14, weight: .semibold))
            Spacer()
        }.frame(height: 29).padding(.horizontal, 22).padding(.top, 19).padding(.bottom, 21)
    }
    private var separator: some View { Rectangle().fill(palette.separator).frame(height: 0.5) }

    private var overview: some View {
        let snapshot = store.snapshot
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Combo").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: showSettings) {
                    Image(systemName: "gearshape.fill").font(.system(size: 13))
                        .overlay(alignment: .topTrailing) {
                            if updater.availableVersion != nil {
                                Circle().fill(palette.accent).frame(width: 6, height: 6).offset(x: 3, y: -3)
                            }
                        }
                }.buttonStyle(PanelIconButtonStyle(size: CGSize(width: 30, height: 30)))
                    .focusable().focusEffectDisabled().focused($focusedControl, equals: .settings).accessibilityIdentifier("panel-settings")
                    .onKeyPress(.space, phases: .down) { _ in
                        DispatchQueue.main.async { showSettings() }
                        return .handled
                    }
                    .foregroundStyle(palette.mutedText).help(L("设置…"))
                    .accessibilityLabel(L(updater.availableVersion == nil ? "设置" : "设置，有新版本可用"))
            }.frame(height: 30).padding(.bottom, 14)
            if store.mediaVisible {
                PanelMediaContent(store: store, track: store.mediaTrack).padding(.bottom, 20).modifier(cardIn(0))
                separator.padding(.bottom, 20)
            }
            HStack(alignment: .center, spacing: 0) {
                sectionEntry(.battery, snapshot: snapshot).frame(minWidth: 0, maxWidth: .infinity).modifier(cardIn(1))
                Rectangle().fill(palette.separator).frame(width: 0.5)
                sectionEntry(.wifi, snapshot: snapshot).padding(.leading, 19).frame(minWidth: 0, maxWidth: .infinity).modifier(cardIn(2))
            }.fixedSize(horizontal: false, vertical: true).padding(.bottom, 15)
            separator
            soundSection(snapshot: snapshot).padding(.top, 20).modifier(cardIn(3))
            if !store.message.isEmpty {
                Text(store.message.string).font(.system(size: 11)).foregroundStyle(.orange).padding(.top, 12)
            }
        }
    }
    private var airPodsBattery: AirPodsReply? {
        guard store.panelExpanded, store.scene == .live, store.snapshot.outputIsAirPods,
              let state = airpods.snapshot, state.available, state.deviceID == audio.selectedOutputID,
              state.left != nil || state.right != nil || state.caseBattery != nil || state.single != nil else { return nil }
        return state
    }
    private func sectionEntry(_ section: PanelSection, snapshot: Snapshot) -> some View {
        Button { store.detailSection = section } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    CategoryIcon(symbol: section.symbol, color: section == .battery ? palette.iconGreen : palette.iconBlue)
                    Text(section.title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }.padding(.bottom, 10)
                Group {
                    if section == .wifi { WiFiName(wifi: store.wifi) }
                    else { Text(snapshot.batteryText).lineLimit(1) }
                }.font(.system(size: section == .wifi ? 16 : 24, weight: section == .wifi ? .semibold : .medium))
                    .monospacedDigit().frame(height: section == .wifi ? 24 : 27, alignment: .topLeading)
                Text(section == .battery ? (store.scene == .live ? battery.statusText : L("演示数据")) : LKey(snapshot.network))
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText).lineLimit(2).padding(.top, 4)
            }.frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(hoveredSection == section ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).pointerStyle(.link).focused($focusedControl, equals: .section(section))
            .onHover { hoveredSection = $0 ? section : nil }
    }
    private func soundSection(snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { store.detailSection = .sound } label: {
                HStack(spacing: 13) {
                    DeviceGlyphIcon(glyph: OutputDeviceClassifier.glyph(for: snapshot.deviceKind))
                        .font(.system(size: 31)).symbolRenderingMode(.hierarchical).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(palette.iconPurple, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.output.string).font(.system(size: 15, weight: .semibold)).lineLimit(1).help(snapshot.output.string)
                        Text(L("声音输出")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.mutedText)
                }.frame(minHeight: 55).padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                    .background(hoveredSection == .sound ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).pointerStyle(.link).focused($focusedControl, equals: .section(.sound))
                .onHover { hoveredSection = $0 ? .sound : nil }.accessibilityLabel(L("声音详情"))
            HStack(spacing: 8) {
                muteButton(snapshot: snapshot, size: 28)
                volumeSlider(snapshot: snapshot)
                Text(snapshot.silenced ? L("静音") : snapshot.volume == nil ? "—" : snapshot.volumeText)
                    .font(.system(size: 11)).foregroundStyle(palette.mutedText).monospacedDigit()
                    .frame(width: 34, alignment: .trailing).allowsHitTesting(false)
            }
            if store.scene == .live && !audio.canVolume { volumeNote }
            if let state = airPodsBattery { AirPodsBatterySummary(state: state) }
        }
    }
    private func muteButton(snapshot: Snapshot, size: CGFloat) -> some View {
        Button { audio.toggleMute(isLive: store.scene == .live) } label: {
            Image(systemName: snapshot.silenced ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: size == 28 ? 12 : 16)).foregroundStyle(palette.mutedText)
                .frame(width: size, height: size)
                .background(size == 28 ? .clear : palette.module, in: Circle())
        }.buttonStyle(.plain).disabled(store.scene != .live || !audio.canMute)
            .accessibilityLabel(snapshot.silenced ? L("取消静音") : L("静音"))
    }
    private func volumeSlider(snapshot: Snapshot) -> some View {
        Slider(value: Binding(get: { store.snapshot.volume ?? 0 }, set: { audio.setVolume($0, isLive: store.scene == .live) }), in: 0...1)
            .disabled(store.scene != .live || !audio.canVolume || snapshot.volume == nil)
            .accessibilityLabel(L("系统音量")).overlay(volumeScroll)
    }
    private var volumeNote: some View {
        Text(audio.currentRouteInfo?.family == .appleTV ? L("电视音量请用遥控器") : L("设备音量请在设备上调节"))
            .font(.system(size: 11)).foregroundStyle(palette.mutedText)
    }
    private var volumeScroll: some View {
        VolumeScroll { event in
            guard store.scene == .live, audio.canVolume, let current = audio.volume else { return }
            audio.setVolume(scrollVolume(current: current, scrollingDelta: event.scrollingDeltaY,
                                         precise: event.hasPreciseScrollingDeltas,
                                         inverted: event.isDirectionInvertedFromDevice), isLive: true)
        }.padding(-6)
    }
    @ViewBuilder private func detail(_ section: PanelSection) -> some View {
        let snapshot = store.snapshot
        switch section {
        case .battery:
            BatteryDetail(store: store)
        case .wifi:
            WiFiSection(wifi: store.wifi, hotspots: store.hotspots, connection: LKey(snapshot.network), active: store.screenActive,
                        systemMessage: store.message.string, openSettings: { store.openSystemSettings("wifi") })
        case .sound:
            VStack(alignment: .leading, spacing: PanelGeometry.groupSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(snapshot.silenced ? L("静音") : snapshot.volumeText)
                            .font(.system(size: 38, weight: .semibold)).monospacedDigit().tracking(-0.95)
                        Spacer()
                        muteButton(snapshot: snapshot, size: 32)
                    }
                    volumeSlider(snapshot: snapshot)
                    HStack(spacing: 7) {
                        DeviceGlyphIcon(glyph: OutputDeviceClassifier.glyph(for: snapshot.deviceKind)).font(.system(size: 15))
                        Text(snapshot.output.string).lineLimit(2)
                    }.font(.system(size: 12)).foregroundStyle(palette.mutedText)
                    if let state = airPodsBattery { AirPodsBatterySummary(state: state, detailed: true).padding(.top, 6) }
                    if store.scene != .live {
                        Text(L("演示数据 · 不改变系统状态")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    } else if !audio.canVolume { volumeNote }
                    else if !audio.canMute {
                        Text(L("当前设备不支持此设置。")).font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }
                }
                SoundOutputs(store: store)
                DetailFooter(title: L("声音设置")) { store.openSystemSettings("sound") }
            }
        }
    }
}

private struct PanelMediaContent: View {
    @ObservedObject var store: Store
    let track: MediaTrack?
    @Environment(\.comboPalette) private var palette
    private var animated: Bool { !store.reduceMotion && store.animate && store.screenActive && store.panelVisible }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 11) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Button { store.openMediaSource() } label: {
                        Text(store.mediaTitle).font(.system(size: 13, weight: .semibold))
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).disabled(track?.bundleIdentifier == nil)
                        .help(store.mediaTitle).accessibilityLabel(L("打开\(track?.source ?? L("媒体来源"))"))
                    if let artist = track?.artist, !artist.isEmpty {
                        Text(artist).font(.system(size: 11)).foregroundStyle(palette.mutedText).lineLimit(1).help(artist)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 13) {
                Button { store.controlMedia(.previous) } label: { Image(systemName: "backward.end.fill") }
                    .help(L("上一首")).accessibilityLabel(L("上一首"))
                Button { store.controlMedia(.toggle) } label: {
                    Image(systemName: store.live.playing ? "pause.fill" : "play.fill")
                        .contentTransition(animated ? .symbolEffect(.replace) : .identity)
                        .frame(width: 34, height: 34).background(palette.hover, in: Circle())
                }.help(store.live.playing ? L("暂停") : L("播放"))
                    .accessibilityLabel(store.live.playing ? L("暂停") : L("播放"))
                Button { store.controlMedia(.next) } label: { Image(systemName: "forward.end.fill") }
                    .help(L("下一首")).accessibilityLabel(L("下一首"))
            }.buttonStyle(PanelIconButtonStyle(size: CGSize(width: 30, height: 34)))
                .font(.system(size: 15)).disabled(!store.mediaControlsAvailable)
                .offset(x: 22.5).frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button { store.openMediaSource() } label: {
                        HStack(spacing: 6) {
                            CategoryIcon(symbol: "music.note", color: palette.iconRed, size: 16)
                            Text(track?.source ?? L("媒体来源")).lineLimit(1)
                        }.font(.system(size: 11)).foregroundStyle(palette.mutedText)
                            .frame(maxWidth: 105, minHeight: 28, alignment: .leading)
                    }.buttonStyle(PanelIconButtonStyle(size: CGSize(width: 105, height: 28)))
                        .disabled(track?.bundleIdentifier == nil).pointerStyle(.link)
                        .help(track?.source ?? L("媒体来源"))
                }
        }
    }
    private var artwork: some View {
        Group {
            if let data = track?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(palette.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.primary.opacity(0.08))
            }
        }.frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
    }
}
