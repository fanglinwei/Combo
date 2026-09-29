# 005 — Open the routine panel immediately

- **Status**: IMPLEMENTED — UI check pending
- **Commit**: 2599f98
- **Severity**: LOW
- **Category**: Purpose and frequency
- **Estimated scope**: 1 source file, about 8 deleted lines

## Problem

`Combo/main.swift:106-114` starts every panel open at zero alpha and fades in for 200 ms, although the panel is the menu bar's primary, frequently repeated action. The panel closes immediately at `Combo/main.swift:148`. The fade conveys no spatial relationship with the menu bar item:

```swift
window.alphaValue = store.reduceMotion ? 1 : 0
window.makeKeyAndOrderFront(nil)
store.panelVisible = true
if !store.reduceMotion {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        window.animator().alphaValue = 1
    }
}
```

This is a code-based responsiveness recommendation; perceived delay has not yet been measured with users.

## Target

Show the panel at full opacity on every open, including after a previous fade was interrupted:

```swift
window.alphaValue = 1
window.makeKeyAndOrderFront(nil)
store.panelVisible = true
```

No new animation duration or curve is needed. Native visual feedback on the menu bar button remains.

## Repo conventions to follow

- Keep `Combo/main.swift:79-115` as the only panel-opening path.
- Keep the existing immediate `closePanel()` at line 148 and the reduced-motion handling for panel resizing at lines 139-145.

## Steps

1. Set `window.alphaValue = 1` before `makeKeyAndOrderFront(nil)`.
2. Delete the conditional 200 ms alpha animation block. Leave the rest of opening and closing logic unchanged.

## Boundaries

- Do not change panel location, geometry, size animation, focus behavior, or view content.
- Do not add replacement scale or slide effects.
- If cited code has changed since commit `2599f98`, stop and report the drift before editing.

## Verification

- **Mechanical**: Run `./build.sh`; expect exit code 0. Confirm no alpha animation remains in `togglePanel()`.
- **Feel check**: Rapidly open/close the menu bar panel at least 20 times using mouse and keyboard, including while media is playing. Confirm each open shows a complete, focused panel in the first visible frame, with no blank frame, flash, or stale 0-alpha window. Repeat with Reduce Motion on.
- **Done when**: Every panel open has alpha 1 immediately, focus still works, and rapid toggles reveal no visual glitch.
