import SwiftUI
import AppKit
import CoreText

enum IconRenderer {
    @MainActor static func image(_ s: Snapshot, animate: Bool, size: CGFloat, phase: Double = 0, dark: Bool = true,
                                 transition: IconTransition.Frame? = nil, bottomProgress: Double? = nil) -> NSImage {
        // Draw at the destination's pixel density instead of rescaling a lockFocus bitmap.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(s, animate: animate, size: size, phase: phase, dark: dark,
                 transition: transition, bottomProgress: bottomProgress)
            return true
        }
    }

    @MainActor private static func draw(_ s: Snapshot, animate: Bool, size: CGFloat, phase: Double, dark: Bool,
                                       transition: IconTransition.Frame?, bottomProgress: Double?) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform(); transform.scale(by: size / 100); transform.concat()
        // Keep the menu bar and every preview on the same centered canvas.
        let placement = NSAffineTransform()
        placement.translateX(by: 50, yBy: 50)
        placement.scale(by: 1.06)
        placement.translateX(by: -50, yBy: -54.5)
        placement.concat()
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
        func fillRound(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect: rect(x,y,w,h), xRadius: radius, yRadius: radius).fill()
        }
        var symbolOpacity = 1.0
        func symbol(_ icon: AppIcon, in box: NSRect, opacity: Double = 1) {
            guard let image = AppIcons.image(icon, color: fg) else { return }
            let fit = min(box.width / image.size.width, box.height / image.size.height)
            image.draw(in: NSRect(x: box.midX - image.size.width * fit / 2,
                                    y: box.midY - image.size.height * fit / 2,
                                    width: image.size.width * fit, height: image.size.height * fit),
                         from: .zero, operation: .sourceOver, fraction: opacity * symbolOpacity)
        }
        func drawPower(connected: Bool) {
            NSGraphicsContext.saveGraphicsState()
            let mask = NSBezierPath(rect: rect(0, 0, 100, 100))
            mask.append(NSBezierPath(ovalIn: rect(51, 45, 20, 20)))
            mask.windingRule = .evenOdd
            mask.addClip()
            symbol(.power(.plug), in: rect(30, 26.5, 40, 39))
            NSGraphicsContext.restoreGraphicsState()
            symbol(.power(connected ? .connected : .disconnected), in: rect(54, 48, 14, 14))
        }
        func drawWiFi(_ layer: IconTransition.Layer) {
            let icon: AppIcon.NetworkIcon
            switch layer.content.kind {
            case .wifiOff: icon = .off
            case .warning: icon = .warning
            default: icon = .wifi
            }
            let loading = layer.content.kind == .connecting && !s.reducedMotion && transition?.reduced != true
            let loadingPhase = layer.loadingPhase ?? phase * 1.2 / IconTransition.NetworkTiming.cycle
            let opacity = loading ? 0.25 + 0.75 * pow(max(0, cos(2 * .pi * loadingPhase)), 2) : 1
            symbol(.network(icon), in: rect(29.5, 29.5, 41, 33), opacity: opacity)
        }
        let frame = transition ?? IconTransition.Frame(layers: [.init(content: IconContent(s))])
        func beginLayer(scale: Double, opacity: Double) {
            // NSImage's fraction replaces CGContext alpha for symbol drawing.
            symbolOpacity = opacity
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext.current!.cgContext
            context.setAlpha(opacity)
            context.translateBy(x: 50, y: 54)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -50, y: -54)
        }
        let peripheralScale = frame.reduced ? 1 : 0.05 + 0.95 * frame.peripheral
        beginLayer(scale: 1, opacity: frame.ringOpacity)
        func ring(_ end: Double, _ color: NSColor) {
            // Leave space for the bolt and round caps without clipping their ends.
            if s.charging {
                arc(50,44,36,150,min(end,300),5.7,color)
                if end > 346 { arc(50,44,36,346,end,5.7,color) }
            } else { arc(50,44,36,150,end,5.7,color) }
        }
        ring(390,s.charging ? rgb(15,58,35) : track)
        if let battery = s.battery, battery > 0, frame.ringProgress > 0 { ring(150+240*min(1,battery)*frame.ringProgress,s.charging ? rgb(40,205,80) : battery < 0.2 ? rgb(255,59,65) : fg) }
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        for layer in frame.layers where layer.opacity > 0 {
            let content = layer.content
            let numeric = content.kind == .battery || content.kind == .volume
            let baseFont = NSFont.systemFont(ofSize: content.text.count == 3 ? 26 : 31, weight: .medium)
            let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: content.text, attributes: [.font: font, .foregroundColor: fg]))
            let bounds = CTLineGetImageBounds(line, NSGraphicsContext.current?.cgContext)
            // Fit actual glyph bounds within the canvas, preserving the content's aspect ratio.
            // Reserve top clearance for the upward shift, including plug stroke caps.
            let expanded: Double
            if numeric {
                expanded = min(86 / max(1, bounds.width), 72 / max(1, bounds.height))
            } else {
                switch content.kind {
                case .plugged, .unplugged: expanded = 1.8
                case .headphones: expanded = 2.24
                case .unavailable: expanded = 2.24
                default: expanded = 2.0
                }
            }
            let resting = content.kind == .headphones ? 1.1 : numeric ? 1.05 : 1.0
            beginLayer(scale: (resting + (expanded-resting) * layer.emphasis) * layer.scale, opacity: layer.opacity)
            if content.kind == .plugged || content.kind == .unplugged {
                drawPower(connected: content.kind == .plugged)
            } else if content.isWiFiGlyph {
                drawWiFi(layer)
            } else if let glyph = content.glyph {
                symbol(glyph, in: rect(30, 26.5, 40, 39))
            } else if content.kind == .unavailable {
                symbol(.status(.unavailable), in: rect(30, 26.5, 40, 39))
            } else {
                if let context = NSGraphicsContext.current?.cgContext {
                    let bounds = CTLineGetImageBounds(line, context)
                    context.textPosition = CGPoint(x: 50-bounds.midX, y: 100-46-bounds.midY)
                    CTLineDraw(line, context)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        beginLayer(scale: peripheralScale, opacity: frame.peripheral)
        // Match the former 24-unit bolt height after SF Symbol padding.
        if s.charging { symbol(.power(.charging), in: rect(70.5, 4, 21, 32)) }
        let bottom = bottomState(muted: s.silenced, adjusting: s.adjusting, playing: s.playing, animate: animate)
        if bottom == .muted {
            symbol(.sound(.muted), in: rect(36, 70, 28, 17))
        } else if bottom == .volume && s.volume == nil { fillRound(43,79,14,3,1.5,track) }
        else {
            let offsets = [0.0, 0.35, 0.65, 0.15]
            let progress = bottomProgress ?? (bottom == .playing ? 1 : 0)
            for (i, coordinate) in [(31.0,77.0),(43.0,82.0),(57.0,82.0),(69.0,77.0)].enumerated() {
                let (x,y) = coordinate
                let p = s.reducedMotion ? 0.3 : phase
                let barHeight = 7 + 5.5*(1+sin(2 * .pi * (p+offsets[i])))
                let height = 6.8 + (barHeight - 6.8) * progress
                let dotColor = i < (volumeDots(s.volume) ?? 0) ? fg : track
                let color = dotColor.blended(withFraction: progress, of: fg) ?? fg
                fillRound(x-3.4,y+3.4-height,6.8,height,3.4,color)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

}
