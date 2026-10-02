# 006 — Reduced motion keeps fades, drops movement

- **Status**: planned
- **Commit**: 74e6963
- **Severity**: MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 2 files, ~20 lines

## Problem

Every animation short-circuits to "no animation at all" under Reduce Motion, so the UI loses
transitions that aid comprehension (AUDIT.md §6: fewer and gentler, not zero — keep opacity, remove
movement). Sites: `Combo/App/main.swift:238` (panel reveal → instant alpha 1), `:221` (detail show →
instant), `:176` (detail hide → instant order out), `:255` (panel close → instant order out),
`Combo/Views/PanelView.swift:91` (page cross-fade → nil), `:131` (card entrance → no animation, whole
40 pt offset applied instantly), `:195` (hover → nil).

## Target

Reduce Motion keeps a short opacity fade and removes every positional change:

```swift
// panel reveal
context.duration = store.reduceMotion ? 0.12 : 0.16      // same strong curve
// cards (PanelView.CardIn): offset 0 when reduced, opacity still animates
.opacity(done ? 1 : 0)
.offset(x: reduced || done ? 0 : PanelView.cardOffset)
.animation(.easeOut(duration: reduced ? 0.12 : PanelView.cardDuration).delay(reduced ? 0 : Double(index) * PanelView.cardStep), value: done)
// panel close (movement) stays instant; detail window show/hide becomes a 0.12 s fade instead of a cut
```

## Repo conventions to follow

- Strong curve is `cubic-bezier(0.23, 1, 0.32, 1)` (see plan 007 for the token).
- `store.reduceMotion` is the single source of truth and is kept live by `Store.swift:123`.

## Steps

1. `main.swift` detail hide + show: use `store.reduceMotion ? 0.12 : 0.15/0.28` instead of early return.
2. `main.swift` panel reveal: `0.12 : 0.16`.
3. `main.swift` panel close: keep the instant `orderOut` (it is pure movement) — no change.
4. `PanelView.CardIn`: drop the offset under Reduce Motion, keep the fade at 0.12 s, no stagger.
5. `PanelView` page cross-fade and hover: `0.12`s instead of `nil`.

## Boundaries

- Do not add movement under Reduce Motion (no slide, no scale).
- Do not touch the icon animations in `main.swift:75-95` (out of scope, already handled by 002/003).

## Verification

- **Mechanical**: `./build.sh` exits 0; `./verify.sh` passes.
- **Feel check**: System Settings → Accessibility → Display → Reduce motion ON, then open/close the
  panel, open the detail window, Esc it, switch sections. Expect soft 0.12 s fades, zero sliding, no
  hard cuts.
- **Done when**: with Reduce Motion on, nothing changes position and every state change still fades.
