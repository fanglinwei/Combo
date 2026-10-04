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
    static let detailShow: TimeInterval = 0.28    // 详情窗淡入
    static let detailHide: TimeInterval = 0.15    // 详情窗淡出
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
    var primaryText: Color { isDark ? .white : .black }
    let canvasTop: Color
    let canvasBottom: Color
    let surface: Color
    let tileTop: Color
    let tileBottom: Color
    let mutedText: Color
    let accent: Color
    let isDark: Bool
}
enum ComboTheme: String, CaseIterable, Identifiable {
    case blue, purple, gold
    var id: String { rawValue }
    var title: String {
        switch self { case .blue: L("蓝色"); case .purple: L("紫色"); case .gold: L("暖金色") }
    }
    func palette(isDark: Bool) -> ComboPalette {
        switch (self, isDark) {
        case (.blue, false):
            return ComboPalette(canvasTop: themeColor(0xB5D1EB), canvasBottom: themeColor(0x91BADB),
                                surface: themeColor(0xDBEBF7), tileTop: themeColor(0xDEEDF7), tileBottom: themeColor(0xC2DBF0),
                                mutedText: themeColor(0x364D63), accent: themeColor(0x2B6196), isDark: false)
        case (.blue, true):
            let accent = themeColor(0x78C6FF)
            return ComboPalette(canvasTop: themeColor(0x17263C), canvasBottom: themeColor(0x0E1B2B),
                                surface: themeColor(0x263D55), tileTop: accent.opacity(0.23), tileBottom: accent.opacity(0.10),
                                mutedText: themeColor(0xD1E3F5), accent: accent, isDark: true)
        case (.purple, false):
            return ComboPalette(canvasTop: themeColor(0xFBF9FD), canvasBottom: themeColor(0xF1ECF7),
                                surface: themeColor(0xF4EDF9), tileTop: themeColor(0xFFFEFF), tileBottom: themeColor(0xF4EDF9),
                                mutedText: themeColor(0x61546E), accent: themeColor(0x785C9C), isDark: false)
        case (.purple, true):
            return ComboPalette(canvasTop: themeColor(0x241C2D), canvasBottom: themeColor(0x130F1C),
                                surface: themeColor(0x3B3049), tileTop: themeColor(0x3B3049), tileBottom: themeColor(0x2B2538),
                                mutedText: themeColor(0xD4CCDE), accent: themeColor(0xC9B0DE), isDark: true)
        case (.gold, false):
            return ComboPalette(canvasTop: themeColor(0xFDFBF6), canvasBottom: themeColor(0xF3EDE3),
                                surface: themeColor(0xF9F2E9), tileTop: themeColor(0xFFFEFC), tileBottom: themeColor(0xF9F2E9),
                                mutedText: themeColor(0x695C4F), accent: themeColor(0x966E47), isDark: false)
        case (.gold, true):
            return ComboPalette(canvasTop: themeColor(0x212124), canvasBottom: themeColor(0x121215),
                                surface: themeColor(0x363637), tileTop: themeColor(0x363637), tileBottom: themeColor(0x29292C),
                                mutedText: themeColor(0xD6D1C9), accent: themeColor(0xDBC4A3), isDark: true)
        }
    }
}
private struct ComboPaletteKey: EnvironmentKey {
    static let defaultValue = ComboTheme.blue.palette(isDark: false)
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
}

// Panel and detail specifications: one surface, content wells, and one optional floating layer.
enum PanelGeometry {
    static let radius: CGFloat = 22
    static let inset: CGFloat = 18
    static let cardRadius: CGFloat = 16
    static let cardInset: CGFloat = 12
    static let groupSpacing: CGFloat = 18
}

struct PanelSurface: ViewModifier {
    @Environment(\.comboPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var tinted = false
    var radius: CGFloat = PanelGeometry.radius

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius)
            ZStack {
                if reduceTransparency {
                    shape.fill(tinted ? palette.canvasBottom : Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                    if tinted {
                        shape.fill(LinearGradient(colors: [palette.canvasTop.opacity(0.72), palette.canvasBottom.opacity(0.82)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.30 : 0.85),
                                                               .white.opacity(0.14), .black.opacity(colorScheme == .dark ? 0.22 : 0.06)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    shape.inset(by: 1).strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.60), lineWidth: 0.5)
                }
                if contrast == .increased { shape.strokeBorder(Color.primary, lineWidth: 1) }
            }
        }
    }
}

struct DetailWell: ViewModifier {
    @Environment(\.comboPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background {
                let shape = RoundedRectangle(cornerRadius: PanelGeometry.cardRadius)
                if reduceTransparency { shape.fill(Color(nsColor: .controlBackgroundColor)) }
                shape.fill(LinearGradient(colors: [palette.accent.opacity(0.15), palette.accent.opacity(0.05)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.strokeBorder(contrast == .increased ? Color.primary : palette.accent.opacity(0.20), lineWidth: 1)
            }
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
            .background(palette.primaryText.opacity(isEnabled ? (pressed ? 0.14 : hovered ? 0.09 : 0) : 0),
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
                .foregroundStyle(prominent && isEnabled ? (palette.isDark ? Color.black : .white) : palette.mutedText)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(prominent && isEnabled ? palette.accent : palette.primaryText.opacity(isEnabled ? (configuration.isPressed ? 0.18 : hovered ? 0.12 : 0.10) : 0.10))
                }
                .opacity(isEnabled ? 1 : 0.55)
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
                .background(palette.primaryText.opacity(isEnabled ? (configuration.isPressed ? 0.18 : hovered ? 0.12 : 0) : 0), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle()).onHover { hovered = $0 }
        }
    }
}

struct DetailFacts: View {
    @Environment(\.comboPalette) private var palette
    let facts: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(facts.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(facts[index].0).foregroundStyle(palette.mutedText)
                    Text(facts[index].1)
                }.font(.system(size: 11)).accessibilityElement(children: .combine)
            }
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
