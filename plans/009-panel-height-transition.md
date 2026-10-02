# 009 — Panel height eases instead of teleporting

- **Status**: planned
- **Commit**: 74e6963
- **Severity**: MEDIUM
- **Category**: Missed opportunity (state teleport)
- **Estimated scope**: 1 file, ~12 lines

## Problem

`Combo/App/main.swift:232-249`: `updatePanelFrame()` calls `panel.setFrame(frame, display: true)`
immediately. Content that appears after opening — the media card when a track is detected, the error
message, the AirPods row — makes the window jump in height mid-view (AUDIT.md §8: a state change that
teleports).

## Target

```swift
private func updatePanelFrame() {
    guard let panel, let screen = panel.screen else { return }
    let visible = screen.visibleFrame
    let height = min(max(1, overviewHeight > 0 ? overviewHeight : panel.frame.height), max(1, visible.height - 16))
    let frame = NSRect(x: visible.maxX - PanelView.width - 12, y: visible.maxY - height - 8, width: PanelView.width, height: height)
    guard abs(panel.frame.height - frame.height) > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5 else { return }
    // first measurement after opening (nothing measured yet) snaps; later content changes ease
    guard firstLayoutDone, !store.reduceMotion else { panel.setFrame(frame, display: true); firstLayoutDone = true; return }
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        context.timingFunction = Motion.out
        panel.animator().setFrame(frame, display: true)
    }
}
```
`firstLayoutDone` is an `AppDelegate` flag reset to `false` in `togglePanel()`.

## Boundaries

- Do not animate the initial open height (the panel is still invisible/fading).
- Do not animate while a card stagger or the reveal is mid-flight: skip if
  `abs(panel.frame.height - frame.height) > 120` (a first-measure-sized jump) to stay safe.

## Verification

- **Mechanical**: `./build.sh`; `./verify.sh`.
- **Feel check**: start a track mid-session with the panel open, and trigger the error message; the
  panel should grow smoothly (≈0.18 s) instead of jumping. Open the panel fresh: no growth animation.
