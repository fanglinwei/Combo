# 001 — Update menu bar accessibility only when the state changes

- **Status**: IMPLEMENTED — UI check pending
- **Commit**: 2599f98
- **Severity**: MEDIUM
- **Category**: Performance, accessibility
- **Estimated scope**: 1 source file, about 5 lines; one manual performance check

## Problem

`Combo/main.swift:55-77` redraws the menu bar image on a timer (20 fps while playing or connecting, 60 fps during a transition) and rewrites the same tooltip and accessibility label on every frame:

```swift
let interval = transitioning ? 1.0 / 60 : 0.05
// ...
status.button?.image = image
let description = "\(store.scene == .live ? "" : "演示 · ")\(s.powerHintText)电量 \(s.batteryText) · \(s.network) · 音量 \(s.volumeText)"
status.button?.toolTip = description
status.button?.setAccessibilityLabel(description)
```

`docs/combo-implementation.md:175` explicitly says the screen-reader description should change with semantic state, not animation frames. `Combo/Icon.swift:306-310` also creates and draws a fresh `NSImage` each tick. No profile proves image rendering is too expensive, so this plan does not add a cache or change frame cadence.

## Target

Keep frame rendering and the existing 20/60 fps timing. Only write the tooltip and accessibility label when the description changes:

```swift
if status.button?.toolTip != description {
    status.button?.toolTip = description
    status.button?.setAccessibilityLabel(description)
}
```

On first render, `toolTip` is nil, so both properties are populated. This same comparison covers value and scene changes without another stored state.

## Repo conventions to follow

- Keep the existing single `drawIcon()` path in `Combo/main.swift:55-78` for both timer frames and state changes.
- Reuse the existing `description` string; do not create another formatter or cache.

## Steps

1. In `Combo/main.swift:75-77`, wrap the two metadata assignments in the exact comparison shown above.
2. Leave `IconRenderer.image`, frame cadence, and the description format unchanged.

## Boundaries

- Do not edit `Combo/Icon.swift`, `Combo/Store.swift`, or design documents.
- Do not add dependencies or a new model object.
- If the cited code has changed since commit `2599f98`, stop and report the drift before editing.

## Verification

- **Mechanical**: Run `./build.sh`; expect exit code 0. Search `Combo/main.swift` to confirm both metadata setters are behind one changed-description condition.
- **Feel check**: With VoiceOver enabled, play media for at least 10 seconds and listen for repeated status announcements; then change volume/network status and confirm the current description is available. Inspect the menu bar animation at normal speed and in a slow-motion recording to confirm its frames are unchanged.
- **Performance check**: Use Instruments Time Profiler or Energy Log during 30 seconds of playback before/after if a baseline is available. Record results; do not infer a rendering improvement solely from the metadata guard.
- **Done when**: The metadata setters run only when description text changes, while the existing image animation and state descriptions still work.
