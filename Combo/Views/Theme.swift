import SwiftUI
import AppKit

/// 动效 token 集中处：曲线 + 时长都从这里取，避免动画参数散落到业务文件里。
enum Motion {
    /// 强 ease-out：用于"出现/消失"。首帧行程大、收尾快。
    static let out = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    /// 面板进/出：out 首帧太冲，长行程看着是一闪而过。这条平缓得多，进出共用所以来去对称。
    static let panelEase = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

    // 时长（秒）。进慢出快是有意的：打开值得看，关闭不该等人。
    static let panelReveal: TimeInterval = 0.3   // 面板滑入 + 淡入
    static let panelSweep: TimeInterval = 0.4    // 收起：整组右扫一个面板宽，行程长所以比进场更慢
    static let panelOffset: CGFloat = 12
    static let cardOffset: CGFloat = 16
    static let cardShow: TimeInterval = 0.2
    static let cardStep: TimeInterval = 0.03     // 四张卡片的完整入场为 290ms
    static let detailResize: TimeInterval = 0.18  // 内容变化时的高度缓动，防止高度瞬跳
    static let reducedFade: TimeInterval = 0.12   // 减弱动态：只淡入，不位移不缩放

    static func animation(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }
}

private func themeColor(_ rgb: UInt32) -> Color {
    Color(red: Double((rgb >> 16) & 0xFF) / 255,
          green: Double((rgb >> 8) & 0xFF) / 255,
          blue: Double(rgb & 0xFF) / 255)
}
struct ComboPalette {
    let primaryText: Color
    var iconBlue: Color { themeColor(isDark ? 0x2184DB : 0x0876D4) }
    var iconGreen: Color { themeColor(isDark ? 0x339C4F : 0x26863D) }
    var iconPurple: Color { themeColor(isDark ? 0x8963D3 : 0x7754C8) }
    var iconRed: Color { themeColor(isDark ? 0xD8424C : 0xD83B43) }
    var iconSlate: Color { themeColor(isDark ? 0x718098 : 0x627188) }
    var toggle: Color { themeColor(isDark ? 0x2DA54B : 0x248A3D) }
    let separator: Color
    var module: Color { .white.opacity(isDark ? 0.075 : 0.47) }
    var hover: Color { .white.opacity(isDark ? 0.13 : 0.75) }
    var field: Color { .white.opacity(isDark ? 0.085 : 0.65) }
    var selected: Color { .white.opacity(isDark ? 0.11 : 0.58) }
    var inset: Color { isDark ? .white.opacity(0.045) : themeColor(0x4B6A94).opacity(0.065) }
    var previewSurface: Color { .white.opacity(isDark ? 0.10 : 0.67) }
    var panelGlass: Color { themeColor(isDark ? 0x1D222B : 0xF4F7FC).opacity(isDark ? 0.80 : 0.76) }
    var panelRim: Color { .white.opacity(isDark ? 0.28 : 0.72) }
    var settingsCanvas: Color { themeColor(isDark ? 0x202631 : 0xF4F8FD).opacity(isDark ? 0.87 : 0.83) }
    var settingsContent: Color { isDark ? themeColor(0x0F1620).opacity(0.24) : .white.opacity(0.24) }
    var settingsToolbar: Color { .white.opacity(isDark ? 0.035 : 0.16) }
    let canvasTop: Color
    let canvasBottom: Color
    let surface: Color
    let mutedText: Color
    let accent: Color
    let isDark: Bool

    static func standard(isDark: Bool) -> ComboPalette {
        if isDark {
            let accent = themeColor(0xEDEDEE)
            return ComboPalette(primaryText: themeColor(0xF6F8FC), separator: .white.opacity(0.16),
                                canvasTop: themeColor(0x282E38), canvasBottom: themeColor(0x252B35),
                                surface: themeColor(0x343A44),
                                mutedText: themeColor(0xD2D9E5), accent: accent, isDark: true)
        }
        return ComboPalette(primaryText: themeColor(0x20252D), separator: themeColor(0x29394E).opacity(0.14),
                            canvasTop: themeColor(0xEDF1F7), canvasBottom: themeColor(0xE6EBF2),
                            surface: themeColor(0xF4F6FA),
                            mutedText: themeColor(0x414B59), accent: themeColor(0x3B3B3D), isDark: false)
    }

    static func settings(isDark: Bool) -> ComboPalette {
        let palette = standard(isDark: isDark)
        return ComboPalette(primaryText: themeColor(isDark ? 0xF4F7FC : 0x222A35),
                            separator: isDark ? .white.opacity(0.13) : themeColor(0x2E3D54).opacity(0.14),
                            canvasTop: themeColor(isDark ? 0x282F3A : 0xEDF2F8), canvasBottom: palette.canvasBottom,
                            surface: palette.surface, mutedText: themeColor(isDark ? 0xC2CAD6 : 0x4E5A6B),
                            accent: palette.accent, isDark: isDark)
    }
}
private struct ComboPaletteKey: EnvironmentKey {
    static let defaultValue = ComboPalette.standard(isDark: false)
}
extension EnvironmentValues {
    var comboPalette: ComboPalette {
        get { self[ComboPaletteKey.self] }
        set { self[ComboPaletteKey.self] = newValue }
    }
}
let brandImage = NSImage(named: NSImage.applicationIconName)
    ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: nil)!
enum ComboAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: L("跟随系统"); case .light: L("浅色"); case .dark: L("深色") }
    }
    var nsAppearance: NSAppearance? {
        switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

// The overview and its detail pages share one glass surface.
enum PanelGeometry {
    static let radius: CGFloat = 30
    static let inset: CGFloat = 19
    static let groupSpacing: CGFloat = 23
}

struct GlassBackdrop: View {
    let blur: CGFloat

    var body: some View {
        Color.clear.glassEffect(.clear, in: Rectangle())
            // Extend the sample so the blur does not fade the surface edges.
            .padding(-3 * blur).blur(radius: blur).saturation(1.25).clipped()
    }
}

struct PanelSurface: ViewModifier {
    @Environment(\.comboPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = PanelGeometry.radius

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(palette.canvasTop, in: RoundedRectangle(cornerRadius: radius))
            } else {
                content.background {
                    GlassBackdrop(blur: 28).overlay(palette.panelGlass)
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(palette.panelRim, lineWidth: 1) }
                }
            }
        }.overlay {
            if contrast == .increased { RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary, lineWidth: 1) }
        }
    }
}

struct CategoryIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol).resizable().scaledToFit().symbolRenderingMode(.hierarchical)
            .fontWeight(.medium).frame(width: size * 0.7, height: size * 0.7)
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct DetailFloating: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            } else {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            }
        }.overlay {
            if contrast == .increased { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 1) }
        }
    }
}

struct PanelRowSurface: ViewModifier {
    @Environment(\.comboPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var hovered: Bool
    var pressed = false

    func body(content: Content) -> some View {
        content.padding(.horizontal, 8).padding(.vertical, 6).frame(minHeight: 40)
            .background(isEnabled ? (pressed ? palette.module : hovered ? palette.hover : .clear) : .clear,
                        in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label.modifier(PanelRowSurface(hovered: hovered, pressed: configuration.isPressed))
                .onHover { hovered = $0 }
        }
    }
}

struct PanelButtonStyle: ButtonStyle {
    @Environment(\.comboPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration, palette: palette, isEnabled: isEnabled, prominent: prominent)
    }

    private struct PanelButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let palette: ComboPalette
        let isEnabled: Bool
        let prominent: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: prominent ? .semibold : .regular))
                .padding(.horizontal, 10).frame(minWidth: 28, minHeight: 28)
                .foregroundStyle(prominent && isEnabled ? (palette.isDark ? Color.black : .white) : palette.primaryText)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(prominent && isEnabled ? palette.accent : isEnabled && hovered ? palette.hover : palette.field)
                }
                .overlay {
                    if !prominent { RoundedRectangle(cornerRadius: 9).strokeBorder(palette.separator, lineWidth: 0.5) }
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.55)
                .onHover { hovered = $0 }
        }
    }
}

struct PanelIconButtonStyle: ButtonStyle {
    var size: CGSize = CGSize(width: 28, height: 28)
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, size: size)
    }
    private struct IconBody: View {
        @Environment(\.comboPalette) private var palette
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyle.Configuration
        let size: CGSize
        @State private var hovered = false
        var body: some View {
            configuration.label.frame(width: size.width, height: size.height)
                .background(isEnabled && hovered ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: 9))
                .opacity(configuration.isPressed ? 0.65 : 1)
                .contentShape(Rectangle()).onHover { hovered = $0 }
        }
    }
}

struct DetailFacts: View {
    @Environment(\.comboPalette) private var palette
    let facts: [(String, String)]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(facts.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(facts[index].0).foregroundStyle(palette.mutedText)
                    Spacer(minLength: 16)
                    Text(facts[index].1).monospacedDigit().multilineTextAlignment(.trailing)
                }.font(.system(size: 12)).frame(minHeight: 38).accessibilityElement(children: .combine)
                if index < facts.count - 1 { Rectangle().fill(palette.separator).frame(height: 0.5) }
            }
        }
    }
}

struct DetailFooter: View {
    @Environment(\.comboPalette) private var palette
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Rectangle().fill(palette.separator).frame(height: 0.5)
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11))
                }.font(.system(size: 12)).frame(minHeight: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.accent).pointerStyle(.link)
        }
    }
}

struct DetailSituation: View {
    @Environment(\.comboPalette) private var palette
    @Environment(\.panelReduceMotion) private var reduceMotion
    let text: String
    var busy = false
    var warning = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if busy { ProgressView().controlSize(.small) }
            else { Image(systemName: warning ? "exclamationmark.triangle" : "info.circle").foregroundStyle(warning ? Color.orange : palette.mutedText) }
            Text(text).font(.system(size: 11)).foregroundStyle(palette.mutedText).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Spacer(minLength: 0)
                Button(actionTitle, action: action).buttonStyle(PanelButtonStyle(prominent: true))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).modifier(DetailFloating())
            .transition(.opacity)
            .animation(Motion.animation(reduceMotion ? Motion.reducedFade : Motion.detailResize), value: text)
            .onChange(of: text) { _, value in
                guard !value.isEmpty else { return }
                AccessibilityNotification.Announcement(value).post()
            }
    }
}

struct DetailMore<Content: View>: View {
    @Environment(\.panelReduceMotion) private var reduceMotion
    @Environment(\.comboPalette) private var palette
    @State private var expanded = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.animation(0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(L("更多"))
                }.font(.system(size: 12)).frame(minHeight: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.mutedText)
                .accessibilityValue(expanded ? L("已展开") : L("已收起"))
            if expanded { content.font(.system(size: 11)).foregroundStyle(palette.mutedText) }
        }
    }
}

private struct PanelReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var panelReduceMotion: Bool {
        get { self[PanelReduceMotionKey.self] }
        set { self[PanelReduceMotionKey.self] = newValue }
    }
}
