# 008 — Hover feedback animates both ways

- **Status**: planned
- **Commit**: 74e6963
- **Severity**: MEDIUM
- **Category**: Interruptibility / feedback
- **Estimated scope**: 1 file, ~6 lines

## Problem

`Combo/Views/PanelView.swift:190-197`: the hovered card is inserted into `hoveredCards` with no
animation (`if inside { hoveredCards.insert(hoverID) }`) but removed under
`withAnimation(.easeOut(duration: 0.18))`. The highlight therefore pops on and fades off — asymmetric
feedback on the app's most-repeated interaction.

## Target

```swift
.onHover { inside in
    guard let hoverID else { return }
    if inside { withAnimation(enter) { hoveredCards.insert(hoverID) } }
    else { withAnimation(exit) { hoveredCards.remove(hoverID) } }
}
```
enter = 0.12 s strong ease-out, exit = 0.18 s strong ease-out, both `nil` under Reduce Motion (plan 006).

## Boundaries

- Hover is not movement: change only opacity/colour timing, never offset or scale.
- Leave `.glassEffect(.regular.interactive())` press feedback untouched.

## Verification

- **Mechanical**: `./build.sh`; `./verify.sh`.
- **Feel check**: sweep the cursor across the four cards and out of the panel; the highlight should
  ease in and out with no pop, and no trail behind a fast sweep.
