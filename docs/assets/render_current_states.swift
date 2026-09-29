import AppKit
import ImageIO

// Render the current settings scenes with the same resolver, transition, and renderer as Combo.
@main struct RenderCurrentStates {
    struct Clip {
        let name: String
        let from: Scene
        let to: Scene
        let seconds: Double
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let clips: [Clip] = [
            .init(name: "wifi", from: .wired, to: .wifi, seconds: 2.5),
            .init(name: "wired", from: .wifi, to: .wired, seconds: 6),
            .init(name: "music", from: .paused, to: .music, seconds: 2.5),
            .init(name: "adjusting", from: .airpods, to: .adjusting, seconds: 3.7),
            .init(name: "paused", from: .music, to: .paused, seconds: 2.5),
            .init(name: "mute", from: .music, to: .mute, seconds: 2.5),
            .init(name: "low", from: .wired, to: .low, seconds: 2.5),
            .init(name: "charging", from: .music, to: .charging, seconds: 2.5),
            .init(name: "offline", from: .wifi, to: .offline, seconds: 7),
            .init(name: "reduced", from: .music, to: .reduced, seconds: 2.5),
            .init(name: "airpods", from: .wifi, to: .airpods, seconds: 6),
            .init(name: "connecting", from: .wifi, to: .connecting, seconds: 3.5),
            .init(name: "wifi-mute", from: .wifi, to: .wifiMute, seconds: 2.5),
            .init(name: "plug", from: .wired, to: .plug, seconds: 10.8),
            .init(name: "unplug", from: .charging, to: .unplug, seconds: 10.8),
            .init(name: "wifi-off", from: .wifi, to: .wifiOff, seconds: 7),
            .init(name: "connect-success", from: .connecting, to: .wifi, seconds: 7),
            .init(name: "connect-failed", from: .connecting, to: .offline, seconds: 7),
            .init(name: "unmute", from: .wifiMute, to: .wifi, seconds: 2.5),
        ]
        assert(Set(clips.prefix(16).map(\.to)) == Set(Scene.allCases.filter { $0 != .live }))
        let output = URL(fileURLWithPath: "docs/assets/states", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for clip in clips { try render(clip, into: output) }
        try renderLightComparison(into: output)
        print("Rendered \(clips.count) GIFs and one light comparison from the current Combo icon code.")
    }

    @MainActor static func renderLightComparison(into output: URL) throws {
        let scenes: [Scene] = [.wifi, .wired, .charging, .mute]
        let canvas = NSImage(size: NSSize(width: 640, height: 190))
        canvas.lockFocus()
        NSColor(srgbRed: 238/255, green: 238/255, blue: 241/255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 190).fill()
        for (index, scene) in scenes.enumerated() {
            let snapshot = Snapshot.demo(scene).preferringBattery(threshold: 50)
            IconRenderer.image(snapshot, animate: true, size: 110, phase: 0.3, dark: false)
                .draw(in: NSRect(x: CGFloat(index)*160+25, y: 55, width: 110, height: 110))
            let label = NSAttributedString(string: scene.rawValue, attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black
            ])
            label.draw(at: NSPoint(x: CGFloat(index)*160+(160-label.size().width)/2, y: 18))
        }
        canvas.unlockFocus()
        let data = NSBitmapImageRep(data: canvas.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent("light-comparison.png"))
    }

    @MainActor static func render(_ clip: Clip, into output: URL) throws {
        let fps = 20.0
        let count = Int(clip.seconds * fps)
        let url = output.appendingPathComponent("\(clip.name).gif")
        guard let gif = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw NSError(domain: "GIF", code: 1)
        }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var transition = IconTransition()
        let start = Snapshot.demo(clip.from).preferringBattery(threshold: 50)
        transition.update(IconContent(start), at: 0, reducedMotion: start.reducedMotion)
        for index in 0..<count {
            let time = Double(index) / fps
            let entered = time >= 0.5
            let scene = entered ? clip.to : clip.from
            var snapshot = Snapshot.demo(scene)
            if entered && scene == .adjusting && time >= 2.5 {
                snapshot.centerEvent = nil; snapshot.adjusting = false
            }
            if entered && (scene == .plug || scene == .unplug) && time >= 9.7 {
                snapshot.centerEvent = nil
            }
            snapshot = snapshot.preferringBattery(threshold: 50)
            transition.update(IconContent(snapshot), at: time, reducedMotion: snapshot.reducedMotion)
            let canvas = NSImage(size: NSSize(width: 240, height: 260))
            canvas.lockFocus()
            NSColor(srgbRed: 23/255, green: 24/255, blue: 27/255, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 240, height: 260).fill()
            IconRenderer.image(snapshot, animate: true, size: 160, phase: time / 1.2,
                               transition: transition.frame(at: time))
                .draw(in: NSRect(x: 40, y: 65, width: 160, height: 160))
            let label = NSAttributedString(string: clip.to.rawValue, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white
            ])
            label.draw(at: NSPoint(x: (240-label.size().width)/2, y: 30))
            canvas.unlockFocus()
            let image = NSBitmapImageRep(data: canvas.tiffRepresentation!)!.cgImage!
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1/fps]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == count else { throw NSError(domain: "GIF", code: 2) }
    }
}
