import SwiftUI
import AppKit
import CoreText

// Coordinates and palette follow docs/assets/render_design.py, on a 100 × 100 canvas.
enum IconRenderer {
    @MainActor static func image(_ s: Snapshot, center: String, animate: Bool, size: CGFloat, phase: Double = 0, dark: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        let transform = NSAffineTransform(); transform.scale(by: size / 100); transform.concat()
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
        let fg = dark ? rgb(244,244,246) : rgb(36,37,42)
        let track = dark ? rgb(86,89,97) : rgb(167,170,179)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 100-y) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: 100-y-h, width: w, height: h) }
        func stroke(_ points: [NSPoint], _ width: CGFloat, _ color: NSColor) {
            guard let first = points.first else { return }
            let p = NSBezierPath(); p.move(to: first); points.dropFirst().forEach { p.line(to: $0) }
            p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
            color.setStroke(); p.stroke()
        }
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ start: Double, _ end: Double, _ width: CGFloat, _ color: NSColor) {
            let count = max(2, Int(abs(end-start)*2))
            let points = (0...count).map { i -> NSPoint in
                let angle = (start + (end-start)*Double(i)/Double(count)) * .pi / 180
                return point(cx + r*cos(angle), cy + r*sin(angle))
            }
            stroke(points, width, color)
        }
        func polygon(_ points: [NSPoint]) {
            let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }; p.close(); fg.setFill(); p.fill()
        }
        func fillRound(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect: rect(x,y,w,h), xRadius: radius, yRadius: radius).fill()
        }
        // Punch out the charging badge instead of painting an opaque background patch.
        NSGraphicsContext.saveGraphicsState()
        if s.charging {
            let clip = NSBezierPath(rect: rect(0,0,100,100))
            clip.append(NSBezierPath(roundedRect: rect(70,8,20,24), xRadius: 4, yRadius: 4))
            clip.windingRule = .evenOdd; clip.addClip()
        }
        arc(50,44,36,150,390,5.7,track)
        if let battery = s.battery, battery > 0 { arc(50,44,36,150,150+240*min(1,battery),5.7,battery <= 0.2 ? rgb(241,108,112) : fg) }
        NSGraphicsContext.restoreGraphicsState()
        let selected = s.centerOverride ?? center
        if s.symbol == "wifi" {
            arc(50,57,23,228,312,4.7,fg); arc(50,57,13,231,309,4.7,fg)
            let points = [point(50,57)] + (0...50).map { i -> NSPoint in
                let angle = (220 + Double(i)*2) * .pi/180
                return point(50 + 6*cos(angle),57 + 6*sin(angle))
            }
            polygon(points)
        } else if s.symbol == "exclamationmark" {
            stroke([point(50,32),point(50,47)],5,fg)
            fg.setFill(); NSBezierPath(ovalIn: rect(47.2,54,5.6,5.6)).fill()
        } else if !s.symbol.isEmpty { stroke([point(43,46),point(57,46)],3,fg) }
        else if selected == "音频输出设备" {
            if s.headphones {
                arc(50,44,13,180,360,4,fg)
                for x: CGFloat in [35,59] { fillRound(x,43,6,15,3,fg) }
            } else {
                // Generic speaker fallback; never infer an Apple headphone model from its name.
                let box = NSBezierPath(roundedRect: rect(41,30,18,30), xRadius: 3, yRadius: 3)
                box.lineWidth = 2.5; fg.setStroke(); box.stroke()
                fg.setFill(); NSBezierPath(ovalIn: rect(47.5,35,5,5)).fill()
                let cone = NSBezierPath(ovalIn: rect(45,45,10,10)); cone.lineWidth = 2; cone.stroke()
            }
        } else {
            let value = selected == "当天日期" ? s.day ?? String(format: "%02d", Calendar.current.component(.day, from: Date())) : s.battery.map { String(Int(($0*100).rounded())) } ?? "—"
            let font = NSFont(name: "Arial", size: value.count == 3 ? 26 : 31) ?? .systemFont(ofSize: 31, weight: .regular)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: fg]))
            if let context = NSGraphicsContext.current?.cgContext {
                let bounds = CTLineGetImageBounds(line, context)
                context.textPosition = CGPoint(x: 50-bounds.midX, y: 100-46-bounds.midY)
                CTLineDraw(line, context)
            }
        }
        if s.charging { polygon([(84,8),(74,22),(80,22),(77,32),(88,17),(82,17)].map { point(CGFloat($0.0),CGFloat($0.1)) }) }
        let bottom = bottomState(muted: s.muted, adjusting: s.adjusting, playing: s.playing, animate: animate)
        if bottom == .muted {
            polygon([(37,78),(42,78),(49,73),(49,86),(42,82),(37,82)].map { point(CGFloat($0.0),CGFloat($0.1)) })
            stroke([point(55,77),point(62,84)],2.7,fg); stroke([point(62,77),point(55,84)],2.7,fg)
        } else if bottom == .volume && s.volume == nil { fillRound(43,79,14,3,1.5,track) }
        else {
            let offsets = [0.0, 0.35, 0.65, 0.15]
            for (i, coordinate) in [(31.0,77.0),(43.0,82.0),(57.0,82.0),(69.0,77.0)].enumerated() {
                let (x,y) = coordinate
                if bottom == .playing {
                    let p = s.reducedMotion ? 0.3 : phase
                    let height = 7 + 3.5*(1+sin(2 * .pi * (p+offsets[i])))
                    fillRound(x-3.4,y+3.4-height,6.8,height,3.4,fg)
                } else {
                    (i < (volumeDots(s.volume) ?? 0) ? fg : track).setFill()
                    NSBezierPath(ovalIn: rect(x-3.4,y-3.4,6.8,6.8)).fill()
                }
            }
        }
        return image
    }
}
struct ComboIcon: View {
    let snapshot: Snapshot
    let center: String
    let animate: Bool
    var size: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) var reduced
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let moving = bottomState(muted: snapshot.muted, adjusting: snapshot.adjusting, playing: snapshot.playing, animate: animate) == .playing && !reduced && !snapshot.reducedMotion
        TimelineView(.animation(minimumInterval: 0.05, paused: !moving)) { context in
            Image(nsImage: IconRenderer.image(snapshot, center: center, animate: animate, size: size, phase: reduced ? 0.3 : context.date.timeIntervalSinceReferenceDate / 1.2, dark: scheme == .dark))
                .frame(width: size, height: size)
        }.accessibilityLabel("电量 \(snapshot.batteryText)，\(snapshot.network)，音量 \(snapshot.volumeText)")
    }
}
