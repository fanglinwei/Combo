# 004 — Give detail entry a fast start

- **Status**: IMPLEMENTED — UI check pending
- **Commit**: 2599f98
- **Severity**: MEDIUM
- **Category**: Easing, purpose and frequency
- **Estimated scope**: 1 source file, 1 line

## Problem

In `Combo/Views.swift:513,680-684`, selecting a summary card inserts the detail panel with a trailing-edge move but wraps the whole change in `easeInOut`, which starts slowly:

```swift
.transition(.move(edge: .trailing).combined(with: .opacity))
// ...
withAnimation(store.reduceMotion ? nil : .easeInOut(duration: 0.25)) {
    selected = selected == section ? nil : section
    resize(selected)
}
```

The AppKit window-frame morph separately specifies `.easeInEaseOut` in `Combo/main.swift:139-145`; that is appropriate for an element already moving onscreen and should stay.

## Target

Change only the SwiftUI transaction to a 250 ms strong ease-out curve: `.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)`. Keep the transition's move and opacity, the AppKit frame morph's 250 ms `.easeInEaseOut`, and the `store.reduceMotion ? nil` branch. The custom curve comes from `AUDIT.md` in the invoked skill.

## Repo conventions to follow

- Keep local SwiftUI animation at the interaction site (`Combo/Views.swift:680-684`), as the project already does.
- Keep motion optional based on `store.reduceMotion`, as in the current `choose(_:)` implementation.

## Steps

1. Replace `.easeInOut(duration: 0.25)` in `PanelView.choose(_:)` with `.timingCurve(0.23, 1, 0.32, 1, duration: 0.25)`.
2. Do not change `.transition(...)` or the AppKit `CAMediaTimingFunction`.

## Boundaries

- Do not alter panel sizing, layout, cards, hit targets, settings navigation, or AirPods' documented 220 ms animation.
- Do not add a global animation abstraction or a dependency.
- If cited code has changed since commit `2599f98`, stop and report the drift before editing.

## Verification

- **Mechanical**: Run `./build.sh`; expect exit code 0.
- **Feel check**: Open and close battery, Wi-Fi, and sound detail 10 times each in both compact and full-width modes. Confirm new detail content responds immediately, the window edge still moves smoothly, and rapid reversals do not jump. Record at high frame rate or slow playback to 10% to inspect the first 50 ms. Enable Reduce Motion and confirm the move is absent.
- **Done when**: Detail entry uses the specified 250 ms curve, panel frame movement retains its prior easing, and reversals remain smooth.

## Execution note

The `feature/0.0.1` working tree changed concurrently during integration: `Combo/main.swift` now updates the panel frame immediately via `updatePanelFrame()` rather than using the 250 ms AppKit frame morph described above. The SwiftUI detail curve was applied; the newer frame behavior was preserved. The detail and frame pairing needs the manual feel check before treating this plan's original visual target as verified.
