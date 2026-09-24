import SwiftUI
import AppKit
import CoreText

// Identity is separate from the value: updating a number never restarts a transition.
struct IconContent: Equatable {
    enum Kind { case wifi, wifiOff, connecting, unavailable, warning, battery, volume, headphones, plugged, unplugged }
    let kind: Kind
    var text = ""
    var priority = 2
    var event: CenterEvent?
    var eventSerial = 0
    var symbol: String?
    var networkState: String?

    init(kind: Kind, text: String = "", priority: Int = 2) {
        self.kind = kind; self.text = text; self.priority = priority
        switch kind {
        case .wifi: networkState = "wifi"
        case .wifiOff: networkState = "wifi.slash"
        case .connecting: networkState = "connecting"
        case .warning: networkState = "exclamationmark"
        default: break
        }
    }
    init(_ snapshot: Snapshot) {
        let event = snapshot.centerEvent
        if event == .power {
            self.init(kind: snapshot.plugged ? .plugged : .unplugged, priority: 4)
        } else if event == .volume {
            self.init(kind: .volume, priority: 4)
        } else if snapshot.wifiConnecting && snapshot.symbol != "wifi.slash" { self.init(kind: .connecting, priority: 3) }
        else if snapshot.symbol == "wifi.slash" { self.init(kind: .wifiOff) }
        else if snapshot.symbol == "exclamationmark" { self.init(kind: .warning) }
        else if !snapshot.symbol.isEmpty && snapshot.symbol != "wifi" { self.init(kind: .unavailable) }
        else if snapshot.batteryPreferred || (snapshot.charging && snapshot.battery.map { $0.isFinite && (0...1).contains($0) } == true) {
            self.init(kind: .battery, text: snapshot.batteryText.replacingOccurrences(of: "%", with: ""))
        }
        else if snapshot.outputIsAirPods { self.init(kind: .headphones) }
        else if snapshot.symbol == "wifi" { self.init(kind: .wifi, priority: 1) }
        else {
            self.init(kind: .battery, text: snapshot.battery.map { String(Int(($0*100).rounded())) } ?? "—")
        }
        self.event = event
        networkState = snapshot.wifiConnecting && snapshot.symbol != "wifi.slash" ? "connecting" : snapshot.networkSymbol ?? snapshot.symbol
        eventSerial = event == nil ? 0 : snapshot.eventSerial
        if kind == .headphones { symbol = "airpodspro" }
        else if kind == .volume {
            if snapshot.silenced { text = "0" }
            else if let volume = snapshot.volume, volume.isFinite, (0...1).contains(volume) {
                text = String(Int((volume * 100).rounded()))
            } else { text = "—" }
        }
    }
    func sameState(as other: IconContent) -> Bool {
        kind == other.kind && priority == other.priority && event == other.event && eventSerial == other.eventSerial
    }
    var isWiFiGlyph: Bool { [.wifi, .wifiOff, .connecting, .warning].contains(kind) }
    var networkContent: IconContent {
        switch networkState {
        case "wifi": IconContent(kind: .wifi, priority: 1)
        case "wifi.slash": IconContent(kind: .wifiOff)
        case "connecting": IconContent(kind: .connecting, priority: 3)
        case "exclamationmark": IconContent(kind: .warning)
        default: self
        }
    }
}

struct IconTransition {
    enum Timing {
        static let centerCrossfade = 0.23
        static let hide = 0.30, grow = 0.30, hold = 3.0, settle = 0.60
        static let peripheralDelay = 0.10, ringFill = 0.50, reduced = 0.16
        static let compactHold = 5.0
        static var restore: Double { hide + grow + hold }
        static var duration: Double { restore + settle + ringFill }
        static func eventDuration(event: CenterEvent = .power, reducedMotion: Bool) -> Double {
            event == .volume ? 2 : (reducedMotion ? reduced : restore + settle) + compactHold
        }
    }
    enum NetworkTiming {
        static let grow = 0.30, morph = 0.40, hold = 2.0, cycle = 1.05
    }
    struct Layer {
        var content: IconContent
        var opacity = 1.0
        var emphasis = 0.0
        var scale = 1.0
        var networkOpen = 1.0
        var retracting = false
        var loadingPhase: Double? = nil
    }
    struct Frame {
        var layers: [Layer]
        var peripheral = 1.0
        var ringOpacity = 1.0
        var ringProgress = 1.0
        var reduced = false
    }
    private(set) var target: IconContent?
    private var origin = Frame(layers: [])
    private var started: Double?
    private var reduced = false
    private var networkMode = false
    private var networkGrow = 0.0
    private var centerOnly = false

    mutating func update(_ content: IconContent, at now: Double, reducedMotion: Bool, active: Bool = true) {
        guard active, let previous = target else {
            target = content; started = nil; reduced = reducedMotion; centerOnly = false
            networkMode = active && content.kind == .connecting
            if networkMode { started = now - NetworkTiming.morph - 0.000001; networkGrow = 0 }
            return
        }
        if centerOnly, let started, now - started >= Timing.centerCrossfade {
            centerOnly = false
            self.started = nil
        }
        let changed = !previous.sameState(as: content)
        let downgrade = content.priority < previous.priority
        let centerTransition = changed && (content.priority == previous.priority || downgrade)
        if centerTransition {
            origin = frame(at: now)
            centerOnly = true
            networkMode = false
            started = now
            target = content
            reduced = reducedMotion
            return
        }
        if changed { centerOnly = false }
        let networkChanged = previous.networkState != nil && content.networkState != nil && previous.networkState != content.networkState
        if downgrade && previous.priority == 4 {
            started = nil
            networkMode = content.kind == .connecting
            if networkMode { started = now - NetworkTiming.morph - 0.000001; networkGrow = 0 }
        } else if previous.priority < 4 && content.priority < 4 &&
                    (networkChanged || (changed && (previous.kind == .connecting || content.kind == .connecting)) ||
                     (content.kind == .connecting && (!networkMode || reduced != reducedMotion))) {
            origin = frame(at: now)
            networkGrow = NetworkTiming.grow * (1 - (origin.layers.map(\.emphasis).max() ?? 0))
            networkMode = true; started = now
        } else if content.priority < previous.priority {
            networkMode = false; started = nil
        } else if changed || (reduced != reducedMotion && isAnimating(at: now)) {
            origin = frame(at: now)
            networkMode = false
            started = now
        }
        target = content
        reduced = reducedMotion
    }
    func isAnimating(at now: Double) -> Bool {
        guard let started else { return false }
        if centerOnly { return now - started < Timing.centerCrossfade }
        if networkMode && reduced && target?.kind != .connecting {
            return now - started < Timing.eventDuration(reducedMotion: true)
        }
        if networkMode && !reduced {
            return target?.kind == .connecting || now - started < networkGrow + NetworkTiming.morph + NetworkTiming.hold + Timing.settle + Timing.compactHold
        }
        return now - started < (reduced || target?.kind == .volume ? Timing.reduced : Timing.duration)
    }
    func frame(at now: Double) -> Frame {
        guard let target else { return Frame(layers: []) }
        if centerOnly {
            let elapsed = max(0, now - (started ?? now))
            let t = min(1, max(0, elapsed / Timing.centerCrossfade))
            let eased = t * t * (3 - 2 * t)
            var layers = origin.layers.map { Layer(content: $0.content, opacity: $0.opacity * (1-eased), emphasis: 0, scale: 1 - 0.3 * eased) }
            layers.append(Layer(content: target, opacity: eased, emphasis: 0, scale: 0.7 + 0.3 * eased))
            return Frame(layers: layers.filter { $0.opacity > 0 }, peripheral: origin.peripheral,
                         ringOpacity: origin.ringOpacity, ringProgress: origin.ringProgress, reduced: reduced)
        }
        if networkMode && !reduced, let started { return networkFrame(target, elapsed: max(0, now - started)) }
        guard let started, isAnimating(at: now) else { return Frame(layers: [Layer(content: target)], reduced: reduced) }
        let elapsed = max(0, now - started)
        func ease(_ time: Double, _ duration: Double) -> Double {
            let t = min(1, max(0, time / duration))
            return t * t * (3 - 2 * t)
        }
        if reduced || target.kind == .volume {
            let t = ease(elapsed, Timing.reduced)
            var layers = origin.layers.map { Layer(content: $0.content, opacity: $0.opacity * (1-t)) }
            layers.append(Layer(content: networkMode ? target.networkContent : target, opacity: t))
            return Frame(layers: layers, peripheral: origin.peripheral + (1-origin.peripheral)*t,
                         ringOpacity: origin.ringOpacity + (1-origin.ringOpacity)*t,
                         ringProgress: origin.ringProgress + (1-origin.ringProgress)*t, reduced: reduced)
        }
        let hide = ease(elapsed, Timing.hide)
        var layers = origin.layers.map { Layer(content: $0.content, opacity: $0.opacity * (1-hide), emphasis: $0.emphasis) }
        let grow = ease(elapsed - Timing.hide, Timing.grow)
        let settle = ease(elapsed - Timing.restore, Timing.settle)
        layers.append(Layer(content: target, opacity: grow, emphasis: grow * (1-settle)))
        let peripheral = elapsed < Timing.hide ? origin.peripheral * (1-hide)
            : ease(elapsed - Timing.restore - Timing.peripheralDelay, Timing.settle - Timing.peripheralDelay)
        let ring = ease(elapsed - Timing.restore - Timing.settle, Timing.ringFill)
        return Frame(layers: layers.filter { $0.opacity > 0 }, peripheral: peripheral,
                     ringOpacity: elapsed < Timing.hide ? origin.ringOpacity * (1-hide) : ring,
                     ringProgress: elapsed < Timing.hide ? origin.ringProgress : ring)
    }
    private func networkFrame(_ target: IconContent, elapsed: Double) -> Frame {
        func ease(_ value: Double) -> Double {
            let t = min(1, max(0, value)); return t * t * (3 - 2*t)
        }
        if elapsed < networkGrow {
            let t = ease(elapsed / networkGrow)
            let layers = origin.layers.map { layer -> Layer in
                var result = layer; result.emphasis += (1-result.emphasis)*t; return result
            }
            return Frame(layers: layers, peripheral: origin.peripheral*(1-t),
                         ringOpacity: origin.ringOpacity*(1-t), ringProgress: origin.ringProgress)
        }
        let time = elapsed - networkGrow
        let destination = target.networkContent
        if time < NetworkTiming.morph {
            let p = time / NetworkTiming.morph
            if p < 0.5 && !origin.layers.isEmpty {
                let layers = origin.layers.map { layer -> Layer in
                    var result = layer
                    result.emphasis = 1; result.networkOpen *= 1-ease(p*2); result.retracting = true
                    result.opacity *= 1-ease((p-0.38)/0.12)
                    return result
                }
                return Frame(layers: layers, peripheral: 0, ringOpacity: 0, ringProgress: 0)
            }
            return Frame(layers: [Layer(content: destination, opacity: ease((p-0.5)*4), emphasis: 1,
                                       networkOpen: ease((p-0.5)*2))], peripheral: 0, ringOpacity: 0, ringProgress: 0)
        }
        if target.kind == .connecting {
            return Frame(layers: [Layer(content: destination, emphasis: 1,
                                       loadingPhase: (time-NetworkTiming.morph) / NetworkTiming.cycle)],
                         peripheral: 0, ringOpacity: 0, ringProgress: 0)
        }
        let restore = time - NetworkTiming.morph - NetworkTiming.hold
        if restore <= 0 {
            return Frame(layers: [Layer(content: destination, emphasis: 1)],
                         peripheral: 0, ringOpacity: 0, ringProgress: 0)
        }
        guard restore < Timing.settle + Timing.compactHold else { return Frame(layers: [Layer(content: target)]) }
        let shrink = ease(restore / Timing.settle)
        let ring = ease((restore-Timing.settle) / Timing.ringFill)
        return Frame(layers: [Layer(content: destination, emphasis: 1-shrink)],
                     peripheral: ease((restore-Timing.peripheralDelay) / (Timing.settle-Timing.peripheralDelay)),
                     ringOpacity: ring, ringProgress: ring)
    }
}

// Pixel-measured from Tests/WiFiReference.png, in the menu-bar renderer's 100 × 100 coordinates.
enum WiFiGlyph {
    static let lineWidth: CGFloat = 4.6
    static let tip: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 46.082, y: 52.318))
        path.addQuadCurve(to: CGPoint(x: 53.918, y: 52.318), control: CGPoint(x: 50, y: 49.568))
        path.addQuadCurve(to: CGPoint(x: 54.241, y: 54.705), control: CGPoint(x: 54.788, y: 52.868))
        path.addLine(to: CGPoint(x: 51.6, y: 57.28))
        path.addQuadCurve(to: CGPoint(x: 48.4, y: 57.28), control: CGPoint(x: 50, y: 58.555))
        path.addLine(to: CGPoint(x: 45.759, y: 54.705))
        path.addQuadCurve(to: CGPoint(x: 46.082, y: 52.318), control: CGPoint(x: 45.212, y: 52.868))
        path.closeSubpath()
        return path
    }()
    static let bounds = CGRect(x: 33.685, y: 33.7, width: 32.63, height: 24.218)
    static func arcs(_ index: Int, open: Double = 1, retracting: Bool = false) -> [[CGPoint]] {
        let radius = index == 0 ? 12.434 : 20.624
        let centerY = index == 0 ? 57.072 : 56.624
        let angle = index == 0 ? 40.1 : 42.81
        let segments = retracting
            ? [(270-angle, 270-angle+angle*open), (270+angle-angle*open, 270+angle)]
            : [(270-angle, 270+angle)]
        return segments.map { start, end in
            (0...40).map { step in
                let theta = (start+(end-start)*Double(step)/40) * .pi/180
                let width = retracting ? 1 : open
                return CGPoint(x: 50+radius*cos(theta)*width, y: centerY-radius+(radius+radius*sin(theta))*width)
            }
        }
    }
}

struct WiFiIcon: View {
    var level = 3
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / WiFiGlyph.bounds.width, y: size.height / WiFiGlyph.bounds.height)
            context.translateBy(x: -WiFiGlyph.bounds.minX, y: -WiFiGlyph.bounds.minY)
            for index in 0..<2 {
                context.opacity = level >= index + 2 ? 1 : 0.25
                for points in WiFiGlyph.arcs(index) {
                    var path = Path(); path.addLines(points)
                    context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: WiFiGlyph.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
            context.opacity = level > 0 ? 1 : 0.25
            context.fill(Path(WiFiGlyph.tip), with: .foreground)
        }
        .frame(width: 16, height: 16 * WiFiGlyph.bounds.height / WiFiGlyph.bounds.width)
        .accessibilityHidden(true)
    }
}

// Coordinates and palette follow docs/assets/render_design.py, on a 100 × 100 canvas.
enum IconRenderer {
    @MainActor static func image(_ s: Snapshot, animate: Bool, size: CGFloat, phase: Double = 0, dark: Bool = true, transition: IconTransition.Frame? = nil) -> NSImage {
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
            for (i, coordinate) in [(31.0,77.0),(43.0,82.0),(57.0,82.0),(69.0,77.0)].enumerated() {
                let (x,y) = coordinate
                if bottom == .playing {
                    let p = s.reducedMotion ? 0.3 : phase
                    let height = 7 + 5.5*(1+sin(2 * .pi * (p+offsets[i])))
                    fillRound(x-3.4,y+3.4-height,6.8,height,3.4,fg)
                } else {
                    (i < (volumeDots(s.volume) ?? 0) ? fg : track).setFill()
                    NSBezierPath(ovalIn: rect(x-3.4,y-3.4,6.8,6.8)).fill()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return image
    }

}
struct ComboIcon: View {
    let snapshot: Snapshot
    let animate: Bool
    var size: CGFloat = 100
    var previewScene: Scene? = nil
    @State private var transition = IconTransition()
    @State private var eventStarted = Date.timeIntervalSinceReferenceDate
    @State private var frameTime = Date.timeIntervalSinceReferenceDate
    @Environment(\.accessibilityReduceMotion) var reduced
    @Environment(\.colorScheme) var scheme
    private var reducedMotion: Bool { reduced || snapshot.reducedMotion }
    private var eventDuration: Double {
        IconTransition.Timing.eventDuration(event: previewScene?.event ?? .power, reducedMotion: reducedMotion)
    }
    private func display(at time: Double) -> Snapshot {
        var value = snapshot
        value.reducedMotion = reducedMotion
        if previewScene?.event != nil && time - eventStarted >= eventDuration {
            value.centerEvent = nil
            value.adjusting = false
        }
        return value
    }
    var body: some View {
        let current = display(at: frameTime)
        let moving = (bottomState(muted: current.silenced, adjusting: current.adjusting, playing: current.playing, animate: animate) == .playing || current.wifiConnecting) && !reducedMotion
        let pending = previewScene?.event != nil && frameTime - eventStarted < eventDuration
        TimelineView(.animation(minimumInterval: transition.isAnimating(at: frameTime) ? 1.0 / 60 : 0.05,
                                paused: !moving && !pending && !transition.isAnimating(at: frameTime))) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let value = display(at: time)
            Image(nsImage: IconRenderer.image(value, animate: animate, size: size, phase: reducedMotion ? 0.3 : time / 1.2, dark: scheme == .dark,
                                             transition: transition.frame(at: time)))
                .frame(width: size, height: size)
                .onChange(of: context.date) { _, date in
                    frameTime = date.timeIntervalSinceReferenceDate
                    transition.update(IconContent(display(at: frameTime)), at: frameTime, reducedMotion: reducedMotion)
                }
        }.accessibilityLabel("\(current.powerHintText)电量 \(snapshot.batteryText)，\(snapshot.network)，音量 \(snapshot.volumeText)")
            .onChange(of: IconContent(snapshot), initial: true) { old, content in
                let now = Date.timeIntervalSinceReferenceDate
                if !old.sameState(as: content) || transition.target == nil { eventStarted = now }
                frameTime = now
                transition.update(IconContent(display(at: now)), at: now, reducedMotion: reducedMotion)
            }
            .onChange(of: reducedMotion) { _, _ in
                frameTime = Date.timeIntervalSinceReferenceDate
                transition.update(IconContent(display(at: frameTime)), at: frameTime, reducedMotion: reducedMotion)
            }
    }
}
