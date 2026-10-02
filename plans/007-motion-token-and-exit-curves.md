# 007 — One motion curve token; exits stop using the built-in ease-out

- **Status**: planned
- **Commit**: 74e6963
- **Severity**: MEDIUM
- **Category**: Easing and duration / Cohesion
- **Estimated scope**: 3 files, ~25 lines

## Problem

The repo's strong exit curve is hand-typed at `Combo/App/main.swift:227` and `:241`, while three
exit-ish animations use the weak built-in `CAMediaTimingFunction(name: .easeOut)` / SwiftUI
`.easeOut`: `main.swift:180` (detail window hide), `main.swift:260` (panel close slide),
`Combo/Views/PanelView.swift:91` (detail page cross-fade). AUDIT.md §2: built-in easings are too weak
for deliberate motion; use `cubic-bezier(0.23, 1, 0.32, 1)`. `PanelView.swift:114`
(`detailEnterAnimation`) is dead code — nothing references it.

## Target

```swift
// Combo/Views/Theme.swift (or next to the existing palette types)
enum Motion {
    static let out = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)     // entrances/exits
    static let drawer = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)  // slide-away dismissals
    static func animation(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}
// Implemented: the panel close uses `drawer` — measured against the reference recording its first
// frame covers ~37% of the travel (the strong curve covered 79% in the same frame).
```

Durations stay as measured: detail show 0.28 s, detail hide 0.15 s, panel close 0.10 s, page
cross-fade 0.20 s, panel reveal 0.16 s, card 0.30 s with 0.02 s steps.

## Steps

1. Add `Motion` with `out` (AppKit) and `outAnimation` (SwiftUI) helpers.
2. Replace the three built-in `.easeOut` uses above; keep the three hand-typed control-point uses.
3. Delete `PanelView.detailEnterAnimation` (lines 113-115) and the now-unused `detailExitAnimation`
   if present.

## Boundaries

- No duration changes (they are measured values from the reference recordings).
- Do not touch `SoundSections.swift:212` — `ease-in-out` is correct for on-screen slider movement.

## Verification

- **Mechanical**: `./build.sh` exits 0; `grep -rn "name: .easeOut" Combo` returns nothing;
  `grep -rn "detailEnterAnimation" Combo` returns nothing; `./verify.sh` passes.
- **Feel check**: open panel → open detail → Esc → close panel. Exit feel should match the entrance
  curve (fast start, soft landing) rather than the built-in slow start.
