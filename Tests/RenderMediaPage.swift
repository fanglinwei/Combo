import AppKit
import SwiftUI
@testable import Combo

/// 把媒体来源页脱离设置窗单独渲染成 PNG，用来和设计稿逐像素对照。
/// 手动运行（不进 verify.sh，和 RenderIcons.swift 一样是一次性视觉工具）：
///   xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -parse-as-library -I "$PRODUCTS" \
///     Tests/RenderMediaPage.swift "$APP/Contents/MacOS/Combo.debug.dylib" \
///     -Xlinker -rpath -Xlinker "$APP/Contents/MacOS" -o build/checks/render-media-page
@main struct RenderMediaPage {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let store = Store()
        // 示例数据：不依赖此刻真的在播放，也不改变系统状态。
        store.mediaVisible = true
        store.mediaControlsAvailable = true
        store.live.playing = true
        store.mediaTrack = MediaTrack(title: "你知道我最害怕一个人天黑", artist: "金海心", source: "网易云音乐",
                                      bundleIdentifier: "com.netease.163music", playing: true, artwork: nil)

        let palette = ComboTheme.gold.palette(isDark: true)
        // 和真实设置窗一样：内容列 609pt + 四周 30pt 内缩，内容顶对齐。
        let page = SettingsView.MediaPage(store: store)
            .environment(\.comboPalette, palette)
            .frame(width: 609, alignment: .leading)
            .padding(30)
            .frame(width: 669, height: 662, alignment: .top)
            .background(palette.canvasTop)

        let hosting = NSHostingView(rootView: page)
        hosting.frame = NSRect(x: 0, y: 0, width: 669, height: 662)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw Failure.render }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.render }
        let out = URL(fileURLWithPath: "/tmp/media-page-render.png")
        try png.write(to: out)
        print("Rendered \(rep.pixelsWide)x\(rep.pixelsHigh) → \(out.path)")
        store.stop()
    }

    enum Failure: Error { case render }
}
