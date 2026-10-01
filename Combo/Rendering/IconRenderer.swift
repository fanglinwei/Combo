import SwiftUI
import AppKit
import CoreText

enum IconRenderer {
    @MainActor static func image(_ s: Snapshot, animate: Bool, size: CGFloat, phase: Double = 0, dark: Bool = true,
                                 transition: IconTransition.Frame? = nil, bottomProgress: Double? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
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
        func polygon(_ points: [NSPoint]) {
            let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }; p.close(); fg.setFill(); p.fill()
        }
        func fillRound(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(roundedRect: rect(x,y,w,h), xRadius: radius, yRadius: radius).fill()
        }
        func drawPower(connected: Bool) {
            // C design: keep the plug fixed and distinguish cable state with a circled check/X.
            NSGraphicsContext.saveGraphicsState()
            let mask = NSBezierPath(rect: rect(0,0,100,100))
            mask.append(NSBezierPath(ovalIn: rect(51,48,17,17)))
            mask.windingRule = .evenOdd; mask.addClip()
            stroke([point(42,30),point(42,38)],2.8,fg)
            stroke([point(52,30),point(52,38)],2.8,fg)
            stroke([point(36,38),point(58,38)],2.8,fg)
            let body = NSBezierPath()
            body.move(to: point(39,38)); body.line(to: point(39,46))
            body.curve(to: point(47,54), controlPoint1: point(39,51), controlPoint2: point(42,54))
            body.curve(to: point(55,46), controlPoint1: point(52,54), controlPoint2: point(55,51))
            body.line(to: point(55,38))
            body.lineWidth = 2.8; body.lineCapStyle = .round; body.lineJoinStyle = .round
            fg.setStroke(); body.stroke()
            stroke([point(47,54),point(47,62)],2.8,fg)
            NSGraphicsContext.restoreGraphicsState()
            let badge = NSBezierPath(ovalIn: rect(53,50,13,13))
            badge.lineWidth = 2.4; fg.setStroke(); badge.stroke()
            if connected { stroke([point(56.5,56.5),point(59,59),point(62.5,54.5)],2.2,fg) }
            else {
                stroke([point(57.2,54.2),point(61.8,58.8)],2.2,fg)
                stroke([point(61.8,54.2),point(57.2,58.8)],2.2,fg)
            }
        }
        // Two rounded arcs and a rounded downward triangle, following the supplied reference.
        func drawWiFi(_ layer: IconTransition.Layer) {
            let open = min(1, max(0, layer.networkOpen))
            let loading = layer.content.kind == .connecting && !s.reducedMotion && transition?.reduced != true
            let phase = layer.loadingPhase ?? phase * 1.2 / IconTransition.NetworkTiming.cycle
            func color(_ index: Int) -> NSColor {
                guard loading else { return fg }
                let pulse = max(0, cos(2 * .pi * (phase - Double(index)/3)))
                return fg.withAlphaComponent(0.25 + 0.75 * pulse * pulse)
            }
            let slashStart = point(37 + 26*(layer.retracting ? 1-open : 0), 33 + 26*(layer.retracting ? 1-open : 0))
            let slashEnd = point(37 + 26*(layer.retracting ? 1 : open), 33 + 26*(layer.retracting ? 1 : open))
            NSGraphicsContext.saveGraphicsState()
            if layer.content.kind == .wifiOff && open > 0 {
                let mask = NSBezierPath(rect: rect(15,15,70,65))
                let gap = NSBezierPath()
                gap.move(to: NSPoint(x: slashStart.x-2.5, y: slashStart.y-2.5))
                gap.line(to: NSPoint(x: slashStart.x+2.5, y: slashStart.y+2.5))
                gap.line(to: NSPoint(x: slashEnd.x+2.5, y: slashEnd.y+2.5))
                gap.line(to: NSPoint(x: slashEnd.x-2.5, y: slashEnd.y-2.5)); gap.close()
                mask.append(gap); mask.windingRule = .evenOdd; mask.addClip()
            }
            for index in 0..<2 {
                for points in WiFiGlyph.arcs(index, open: open, retracting: layer.retracting) {
                    stroke(points.map { point($0.x, $0.y) }, WiFiGlyph.lineWidth, color(index+1))
                }
            }
            let tipScale = layer.retracting ? open : 1
            if tipScale > 0 {
                color(0).setFill()
                var transform = CGAffineTransform(a: tipScale, b: 0, c: 0, d: -tipScale,
                                                  tx: 50*(1-tipScale), ty: 100-55*(1-tipScale))
                NSBezierPath(cgPath: WiFiGlyph.tip.copy(using: &transform)!).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if layer.content.kind == .wifiOff && open > 0 { stroke([slashStart, slashEnd], 3.1, fg) }
            if layer.content.kind == .warning {
                stroke([point(65,46),point(65,51)],3.1,fg)
                fg.setFill(); NSBezierPath(ovalIn: rect(63.4,54,3.2,3.2)).fill()
            }
        }
        let frame = transition ?? IconTransition.Frame(layers: [.init(content: IconContent(s))])
        func beginLayer(scale: Double, opacity: Double) {
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
        // Shift every transition layer by 0.8pt at menu-bar size, outside its animated scale.
        NSGraphicsContext.current!.cgContext.translateBy(x: 0, y: 0.8 * 100 / (22 * 1.06))
        for layer in frame.layers where layer.opacity > 0 {
            let content = layer.content
            let numeric = content.kind == .battery || content.kind == .volume
            let baseFont = NSFont.systemFont(ofSize: content.text.count == 3 ? 26 : 31, weight: .medium)
            let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: baseFont.pointSize) } ?? baseFont
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: content.text, attributes: [.font: font, .foregroundColor: fg]))
            let bounds = CTLineGetImageBounds(line, NSGraphicsContext.current?.cgContext)
            // Fit actual glyph bounds within the canvas, preserving the content's aspect ratio.
            // Reserve top clearance for the upward shift, including plug stroke caps.
            let expanded = numeric ? min(86 / max(1, bounds.width), 72 / max(1, bounds.height))
                : (content.kind == .plugged || content.kind == .unplugged ? 2.1 : 2.3)
            let resting = content.kind == .headphones ? 1.35 : 1.05
            beginLayer(scale: (resting + (expanded-resting) * layer.emphasis) * layer.scale, opacity: layer.opacity)
            if content.kind == .plugged || content.kind == .unplugged {
                drawPower(connected: content.kind == .plugged)
            } else if content.isWiFiGlyph {
                drawWiFi(layer)
            } else if let symbol = content.symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [fg]))
                let configured = image.withSymbolConfiguration(configuration) ?? image
                let ratio = min(32 / max(1, configured.size.width), 32 / max(1, configured.size.height))
                let width = configured.size.width * ratio, height = configured.size.height * ratio
                configured.draw(in: rect(50-width/2,46-height/2,width,height))
            } else if content.kind == .unavailable { stroke([point(43,46),point(57,46)],3,fg) }
            else {
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
        if s.charging { polygon([(84,8),(74,22),(80,22),(77,32),(88,17),(82,17)].map { point(CGFloat($0.0),CGFloat($0.1)) }) }
        let bottom = bottomState(muted: s.silenced, adjusting: s.adjusting, playing: s.playing, animate: animate)
        if bottom == .muted {
            polygon([(37,78),(42,78),(49,73),(49,86),(42,82),(37,82)].map { point(CGFloat($0.0),CGFloat($0.1)) })
            stroke([point(55,77),point(62,84)],2.7,fg); stroke([point(62,77),point(55,84)],2.7,fg)
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
        return image
    }

}
