import SwiftUI

struct ComboIcon: View {
    @ObservedObject private var localization = Localization.shared
    let snapshot: Snapshot
    let animate: Bool
    var size: CGFloat = 100
    var previewScene: Scene? = nil
    @State private var transition = IconTransition()
    @State private var bottomTransition = BottomTransition()
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
        let transitioning = transition.isAnimating(at: frameTime) || bottomTransition.isAnimating(at: frameTime)
        TimelineView(.animation(minimumInterval: transitioning ? 1.0 / 60 : 0.05,
                                paused: !moving && !pending && !transitioning)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let value = display(at: time)
            Image(nsImage: IconRenderer.image(value, animate: animate, size: size, phase: reducedMotion ? 0.3 : time / 1.2, dark: scheme == .dark,
                                             transition: transition.frame(at: time), bottomProgress: bottomTransition.value(at: time)))
                .frame(width: size, height: size)
                .onChange(of: context.date) { _, date in
                    frameTime = date.timeIntervalSinceReferenceDate
                    let value = display(at: frameTime)
                    transition.update(IconContent(value), at: frameTime, reducedMotion: reducedMotion)
                    bottomTransition.update(value, animate: animate, at: frameTime, reducedMotion: reducedMotion)
                }
        }.accessibilityLabel(L("\(current.powerHintText)电量 \(snapshot.batteryText)，\(LKey(snapshot.network))，音量 \(snapshot.volumeText)"))
            .onChange(of: IconContent(snapshot), initial: true) { old, content in
                let now = Date.timeIntervalSinceReferenceDate
                if !old.sameState(as: content) || transition.target == nil { eventStarted = now }
                frameTime = now
                let value = display(at: now)
                transition.update(IconContent(value), at: now, reducedMotion: reducedMotion)
                bottomTransition.update(value, animate: animate, at: now, reducedMotion: reducedMotion)
            }
            .onChange(of: bottomState(muted: current.silenced, adjusting: current.adjusting, playing: current.playing, animate: animate) == .playing) { _, _ in
                let now = Date.timeIntervalSinceReferenceDate
                frameTime = now
                bottomTransition.update(display(at: now), animate: animate, at: now, reducedMotion: reducedMotion)
            }
            .onChange(of: reducedMotion) { _, _ in
                frameTime = Date.timeIntervalSinceReferenceDate
                let value = display(at: frameTime)
                transition.update(IconContent(value), at: frameTime, reducedMotion: reducedMotion)
                bottomTransition.update(value, animate: animate, at: frameTime, reducedMotion: reducedMotion)
            }
    }
}
