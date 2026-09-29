# 002 — Remove center glyph scaling in reduced motion

- **Status**: IMPLEMENTED — UI check pending
- **Commit**: 2599f98
- **Severity**: MEDIUM
- **Category**: Accessibility, physicality
- **Estimated scope**: 2 files, about 15 source/test lines

## Problem

`Combo/Icon.swift:154-174` uses the 230 ms center-only transition even when `reduced` is true. Its incoming glyph grows from 0.7 to 1.0, and the outgoing glyph shrinks from 1.0 to 0.7:

```swift
if centerOnly { return now - started < Timing.centerCrossfade }
// ...
if centerOnly {
    let elapsed = max(0, now - (started ?? now))
    let t = min(1, max(0, elapsed / Timing.centerCrossfade))
    let eased = t * t * (3 - 2 * t)
    var layers = origin.layers.map { Layer(content: $0.content, opacity: $0.opacity * (1-eased), emphasis: 0, scale: 1 - 0.3 * eased) }
    layers.append(Layer(content: target, opacity: eased, emphasis: 0, scale: 0.7 + 0.3 * eased))
```

`docs/combo-settings.md:75,84` specifies a 0.16 s short fade without spatial enlargement under reduced motion. `Tests/IconTransitionCheck.swift:96-102` only checks the final frame.

## Target

Keep the normal 0.23 s crossfade and its tested scale behavior. When `reduced` is true, use `Timing.reduced` (0.16 s), keep both layer scales at exactly 1.0, and fade their opacity only. The center-only `isAnimating(at:)` duration and `frame(at:)` duration must agree.

## Repo conventions to follow

- `Combo/Icon.swift:70-80` already centralizes `centerCrossfade = 0.23` and `reduced = 0.16`; reuse these constants.
- `Combo/Icon.swift:183-189` is the existing reduced-motion opacity-only exemplar.
- Add one assertion to the existing `Tests/IconTransitionCheck.swift` executable rather than introducing a test framework.

## Steps

1. In `IconTransition.isAnimating(at:)`, make the `centerOnly` duration `reduced ? Timing.reduced : Timing.centerCrossfade`.
2. In the `centerOnly` branch of `frame(at:)`, calculate `t` with that same duration. Preserve the existing smoothstep opacity interpolation.
3. For reduced motion, set outgoing and incoming `scale` to `1`; for normal motion, preserve the existing scale formulas exactly.
4. In `Tests/IconTransitionCheck.swift` near the `reducedCompletion` case, assert at 0.08 s after transition start that all visible layers have `scale == 1`, both layers are present with nonzero opacity, and the transition has finished after 0.161 s. Keep existing normal-motion assertions unchanged.

## Boundaries

- Do not change normal-motion scaling, network morphing, power hint holds, volume hint timing, or the 1.2 s playback bars.
- Do not add new animation constants or dependencies.
- If cited code has changed since commit `2599f98`, stop and report the drift before editing.

## Verification

- **Mechanical**: Run `./build.sh`; expect the existing and new `IconTransitionCheck` assertions to pass.
- **Feel check**: Enable macOS Reduce Motion. In settings preview, switch between two normal center states and between Wi-Fi connecting and a result. At 10% playback speed, confirm each glyph stays at fixed size and only opacity changes. Disable Reduce Motion and confirm the original normal scaling is still present.
- **Done when**: Every center-only reduced-motion frame has `scale == 1`, lasts 0.16 s, and normal-motion tests remain unchanged.
