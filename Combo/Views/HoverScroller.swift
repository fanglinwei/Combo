import AppKit
import SwiftUI

final class HoverScroller: NSScroller {
    var accent = NSColor.controlAccentColor
    private var hovered = false

    override class var isCompatibleWithOverlayScrollers: Bool { self == HoverScroller.self }

    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsDisplay = true
    }

    override func drawKnob() {
        guard hovered else { super.drawKnob(); return }
        let knob = rect(for: .knob).insetBy(dx: 2, dy: 1)
        accent.setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }
}

struct HoverScrollerBridge: NSViewRepresentable {
    let accent: NSColor

    func makeNSView(context: Context) -> InstallerView { InstallerView() }
    func updateNSView(_ view: InstallerView, context: Context) { view.accent = accent; view.install() }

    final class InstallerView: NSView {
        var accent = NSColor.controlAccentColor
        private weak var scroller: HoverScroller?
        private var monitor: Any?

        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); install() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                scroller?.setHovered(false)
                scroller = nil
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            } else { install() }
        }

        func install() {
            DispatchQueue.main.async { [weak self] in self?.installNow() }
        }

        private func installNow() {
            guard window != nil else { return }
            var parent = superview
            while let view = parent {
                if let scrollView = view as? NSScrollView {
                    if let scroller = scrollView.verticalScroller as? HoverScroller {
                        if !scroller.accent.isEqual(accent) {
                            scroller.accent = accent
                            scroller.needsDisplay = true
                        }
                        self.scroller = scroller
                    } else {
                        let scroller = HoverScroller()
                        scroller.accent = accent
                        scrollView.verticalScroller = scroller
                        self.scroller = scroller
                    }
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in
                            self?.updateHover(event)
                            return event
                        }
                    }
                    return
                }
                parent = view.superview
            }
        }

        private func updateHover(_ event: NSEvent) {
            guard let scroller else { return }
            let inside = event.window === scroller.window && scroller.bounds.contains(scroller.convert(event.locationInWindow, from: nil))
            scroller.setHovered(inside)
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
