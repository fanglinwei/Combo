import AppKit
import SwiftUI

enum OnboardingLayout {
    static let width: CGFloat = 600
    static let height: CGFloat = 484
}

struct OnboardingView: View {
    @ObservedObject private var localization = Localization.shared
    @ObservedObject var store: Store
    @ObservedObject var battery: BatteryStore
    let dismiss: () -> Void
    let contentHeightChanged: (CGFloat) -> Void
    @State private var helpExpanded = false
    @State private var triedPanel = false
    @FocusState private var primaryFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: ComboPalette { .standard(isDark: colorScheme == .dark) }

    init(store: Store, contentHeightChanged: @escaping (CGFloat) -> Void = { _ in }, dismiss: @escaping () -> Void) {
        self.store = store
        self.battery = store.battery
        self.dismiss = dismiss
        self.contentHeightChanged = contentHeightChanged
    }

    private var pointerWanted: Bool { !store.panelVisible }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 13) {
                    Image(nsImage: brandImage).resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                    Text(L("开始使用 Combo")).font(.system(size: 26, weight: .semibold)).tracking(-0.65)
                }
                Text(battery.hasInternalBattery ? L("一个图标，查看 Wi‑Fi、电池和声音") : L("一个图标，查看 Wi‑Fi 和声音"))
                    .font(.system(size: 18, weight: .medium)).tracking(-0.27)
                    .frame(minHeight: 27, alignment: .leading).padding(.top, 22)
                Text(L("它只占菜单栏右上角的一个位置：点一下打开面板，再点一下收起。"))
                    .font(.system(size: 13)).foregroundStyle(palette.mutedText)
                    .frame(minHeight: 20, alignment: .leading).padding(.top, 7)
                menuBarMock.padding(.top, 25)
                instruction.padding(.top, 23).padding(.bottom, 22)
                Rectangle().fill(contrast == .increased ? palette.primaryText : palette.separator).frame(height: 1)
                DisclosureGroup(isExpanded: $helpExpanded) {
                    Text(L("找不到图标时，可以按住 Command 拖动调整它在菜单栏中的位置。"))
                        .font(.system(size: 12)).foregroundStyle(palette.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    Text(L("找不到菜单栏图标？")).font(.system(size: 12)).padding(.vertical, 3)
                }
                .accessibilityIdentifier("onboarding-help")
                .padding(.top, 13)
                HStack(spacing: 22) {
                    Text(L("隐藏系统图标与其他说明，统一在“设置 → 关于”中查看。"))
                        .font(.system(size: 11)).foregroundStyle(palette.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: dismiss) {
                        Text(L("开始使用")).font(.system(size: 13, weight: .medium)).frame(minWidth: 91, minHeight: 34)
                    }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).focused($primaryFocused)
                }.padding(.top, 22)
            }
            .padding(.horizontal, 34).padding(.top, 25).padding(.bottom, 27)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeightChanged($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(palette.primaryText).tint(palette.accent)
        .environment(\.comboPalette, palette)
        .accessibilityElement(children: .contain)
        .defaultFocus($primaryFocused, true)
        .onAppear { store.menuBarPointer = pointerWanted; triedPanel = store.panelVisible; primaryFocused = true }
        .onChange(of: pointerWanted) { _, wanted in store.menuBarPointer = wanted }
        .onChange(of: store.panelVisible) { _, visible in if visible { triedPanel = true } }
        .onDisappear { store.menuBarPointer = false }
    }

    private var instruction: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: triedPanel ? "checkmark" : "arrow.up.right")
                .font(.system(size: 19)).frame(width: 26, height: 26)
                .background(palette.module, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.panelVisible ? L("面板已打开。再点一次图标可以收起。") :
                        triedPanel ? L("面板已收起，随时可以再次打开") : L("点一下菜单栏里的 Combo 图标试试。"))
                    .font(.system(size: 14, weight: .semibold))
                Text(triedPanel ? L("准备好后，点击「开始使用」结束引导。") : L("面板会从图标下方展开。"))
                    .font(.system(size: 12)).foregroundStyle(palette.mutedText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-instruction")
    }

    private var menuBarMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 15) {
                Text(L("菜单栏右上角")).font(.system(size: 12)).foregroundStyle(palette.mutedText)
                Spacer(minLength: 0)
                Image(systemName: "wifi")
                if battery.hasInternalBattery { Image(systemName: "battery.75percent") }
                Image(systemName: "speaker.wave.2.fill")
                HStack(spacing: 9) {
                    ComboIcon(snapshot: store.snapshot, animate: store.animate, size: 27, previewScene: store.scene)
                    Text("Combo").font(.system(size: 12, weight: .medium))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16).padding(.vertical, 9).frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(palette.module, in: RoundedRectangle(cornerRadius: 12))
            Text(L("菜单栏中其余图标仅作示意，实际排列由系统决定。"))
                .font(.system(size: 11)).foregroundStyle(palette.mutedText).frame(minHeight: 17, alignment: .leading)
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
                .font(.system(size: 13)).foregroundStyle(palette.canvasTop).offset(y: 2)
            Text(L("点这里打开面板"))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(palette.canvasTop, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(palette.primaryText)
        .environment(\.comboPalette, palette)
        .modifier(OnboardingReveal(reduceMotion: reduceMotion || systemReduceMotion))
        .accessibilityHidden(true)
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
