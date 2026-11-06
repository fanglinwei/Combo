import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    let dismiss: () -> Void
    @FocusState private var primaryFocused: Bool
    @Environment(\.comboPalette) private var palette

    init(store: Store, dismiss: @escaping () -> Void) {
        self.store = store
        self.battery = store.battery
        self.dismiss = dismiss
    }

    private var pointerWanted: Bool { !store.panelVisible }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(nsImage: brandImage).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                Text(L("开始使用 Combo")).font(.system(size: 24, weight: .semibold))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(battery.hasInternalBattery ? L("一个图标，查看 Wi‑Fi、电池和声音") : L("一个图标，查看 Wi‑Fi 和声音"))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L("它只占菜单栏右上角的一个位置：点一下打开面板，再点一下收起。"))
                        .font(.system(size: 13)).foregroundStyle(palette.mutedText)
                    VStack(alignment: .leading, spacing: 12) {
                        menuBarMock
                        Label(store.panelVisible ? L("面板已打开。再点一次图标可以收起。") : L("点一下菜单栏里的 Combo 图标试试。"),
                              systemImage: store.panelVisible ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                            .font(.system(size: 13))
                        Text(L("找不到图标时，可以按住 Command 拖动调整它在菜单栏中的位置。"))
                            .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                    }.modifier(OnboardingWell())
                    Text(L("隐藏系统图标与其他说明，统一在“设置 → 关于”中查看。"))
                        .font(.system(size: 12)).foregroundStyle(palette.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }.scrollBounceBehavior(.basedOnSize)
            HStack {
                Spacer()
                Button(L("开始使用"), action: dismiss)
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .focused($primaryFocused)
            }
        }
        .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 24)
        .foregroundStyle(palette.primaryText).tint(palette.accent)
        .buttonStyle(PanelButtonStyle())
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [palette.canvasTop, palette.canvasBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .contain)
        .defaultFocus($primaryFocused, true)
        .onAppear { store.menuBarPointer = pointerWanted; primaryFocused = true }
        .onChange(of: pointerWanted) { _, wanted in store.menuBarPointer = wanted }
        .onDisappear { store.menuBarPointer = false }
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
}

/// 指向真实菜单栏图标的浮层。窗口本身忽略鼠标事件，这里只画箭头和一句话。
struct MenuBarCallout: View {
    let reduceMotion: Bool
    @ObservedObject private var localization = Localization.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ComboPalette { ComboPalette.standard(isDark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(palette.accent)
            Text(L("点这里打开面板"))
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .modifier(PanelSurface(radius: 9))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(palette.primaryText)
        .environment(\.comboPalette, palette)
        .modifier(OnboardingReveal(reduceMotion: reduceMotion || systemReduceMotion))
        .accessibilityHidden(true)
    }
}

/// A stable surface for the welcome illustration.
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
