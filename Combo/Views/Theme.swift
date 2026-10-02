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
