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
    /// 设备字形。中央只画 `Snapshot.deviceGlyph` 给出的这一个，来源可能是 SF Symbol，
    /// 也可能是资源目录里的矢量图（第三方厂商 SVG，见 OutputDevice.swift）。
    var glyph: DeviceGlyph?
    var networkState: String?

    init(kind: Kind, text: String = "", priority: Int = 2) {
        self.kind = kind; self.text = text; self.priority = priority
        switch kind {
        case .wifi: networkState = "wifi"
        case .wifiOff: networkState = "wifi.slash"
        case .connecting: networkState = "connecting"
        case .warning: networkState = "exclamationmark"
        case .headphones: glyph = .symbol("headphones")
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
        else if let deviceGlyph = snapshot.deviceGlyph { self.init(kind: .headphones); self.glyph = deviceGlyph }
        else if snapshot.symbol == "wifi" { self.init(kind: .wifi, priority: 1) }
        else {
            self.init(kind: .battery, text: snapshot.battery.map { String(Int(($0*100).rounded())) } ?? "—")
        }
        self.event = event
        networkState = snapshot.wifiConnecting && snapshot.symbol != "wifi.slash" ? "connecting" : snapshot.networkSymbol ?? snapshot.symbol
        eventSerial = event == nil ? 0 : snapshot.eventSerial
        if kind == .volume {
            if snapshot.silenced { text = "0" }
            else if let volume = snapshot.volume, volume.isFinite, (0...1).contains(volume) {
                text = String(Int((volume * 100).rounded()))
            } else { text = "—" }
        }
    }
    func sameState(as other: IconContent) -> Bool {
        kind == other.kind && priority == other.priority && event == other.event && eventSerial == other.eventSerial && glyph == other.glyph
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
        if centerOnly, let started, now - started >= (reduced ? Timing.reduced : Timing.centerCrossfade) {
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
        if centerOnly { return now - started < (reduced ? Timing.reduced : Timing.centerCrossfade) }
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
            let t = min(1, max(0, elapsed / (reduced ? Timing.reduced : Timing.centerCrossfade)))
            let eased = t * t * (3 - 2 * t)
            var layers = origin.layers.map { Layer(content: $0.content, opacity: $0.opacity * (1-eased), emphasis: 0, scale: reduced ? 1 : 1 - 0.3 * eased) }
            layers.append(Layer(content: target, opacity: eased, emphasis: 0, scale: reduced ? 1 : 0.7 + 0.3 * eased))
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

struct BottomTransition {
    static let duration = 0.2
    private var startValue = 0.0
    private var endValue: Double?
    private var started: Double?

    mutating func update(_ snapshot: Snapshot, animate: Bool, at now: Double, reducedMotion: Bool, active: Bool = true) {
        let bottom = bottomState(muted: snapshot.silenced, adjusting: snapshot.adjusting, playing: snapshot.playing, animate: animate)
        let end = bottom == .playing ? 1.0 : 0.0
        let eligible = bottom == .playing || (bottom == .volume && !snapshot.adjusting && volumeDots(snapshot.volume) != nil)
        guard active && animate && !reducedMotion && eligible else {
            startValue = end; endValue = eligible ? end : nil; started = nil
            return
        }
        guard let previous = endValue else {
            startValue = end; endValue = end
            return
        }
        guard previous != end else { return }
        startValue = value(at: now)
        endValue = end
        started = now
    }

    func value(at now: Double) -> Double {
        guard let started, let end = endValue else { return startValue }
        let t = min(1, max(0, (now - started) / Self.duration))
        let eased = t * t * (3 - 2 * t)
        return startValue + (end - startValue) * eased
    }

    func isAnimating(at now: Double) -> Bool {
        guard let started, let end = endValue else { return false }
        return startValue != end && now - started < Self.duration
    }
}

/// Lights the status item while the panel is open — the reference recording keeps that highlight on
/// for as long as the panel is up. Same shape as `BottomTransition`: a value we ease over time and
/// redraw from the animator timer.
/// 菜单栏图标的高亮底色补间（0↔1）。
/// 手写而不是用 NSAnimationContext：图标的底色是 layer 属性，走不了窗口的 animator 代理，
/// 所以复用本文件既有的做法——由 60fps 的 drawIcon 时钟每帧取值绘制。
struct PanelHighlightTransition {
    static let duration = 0.14
    private var startValue = 0.0
    private var endValue: Double?
    private var started: Double?

    mutating func update(active: Bool, animate: Bool, at now: Double, reducedMotion: Bool) {
        let end = active ? 1.0 : 0.0
        guard animate, !reducedMotion else {
            startValue = end; endValue = end; started = nil
            return
        }
        guard let previous = endValue else {
            startValue = end; endValue = end
            return
        }
        guard previous != end else { return }
        startValue = value(at: now)
        endValue = end
        started = now
    }

    func value(at now: Double) -> Double {
        guard let started, let end = endValue else { return startValue }
        let t = min(1, max(0, (now - started) / Self.duration))
        let eased = t * t * (3 - 2 * t)
        return startValue + (end - startValue) * eased
    }

    func isAnimating(at now: Double) -> Bool {
        guard let started, let end = endValue else { return false }
        return startValue != end && now - started < Self.duration
    }
}

// Pixel-measured from Tests/WiFiReference.png, in the menu-bar renderer's 100 × 100 coordinates.
