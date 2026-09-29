# 003 — React to system Reduce Motion changes

- **Status**: IMPLEMENTED — UI check pending
- **Commit**: 2599f98
- **Severity**: MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 1 source file, about 5 lines

## Problem

`Combo/Store.swift:73,149-163` reads the system setting at initialization and during `refresh()`, but its workspace observers cover sleep and session state only:

```swift
@Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
// ...
let nc = NSWorkspace.shared.notificationCenter
for (name, active) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true), (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true)] {
    observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
            self?.screenActive = active
            self?.mediaPlayback.setEnabled(active)
            if active { self?.refresh() } else { self?.foldExperiment.release() }
        }
    })
}
// ...
func refresh() {
    reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
```

If the user changes Reduce Motion while Combo stays open, the menu bar icon and panel can continue using the old value until `refresh()` next runs.

## Target

Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter`, then assign the current `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` to `reduceMotion` on the main actor. Apple's API specifies this notification center and states that the notification carries no useful `userInfo`: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification . Keep the existing `refresh()` read as a fallback.

## Repo conventions to follow

- Use `observers: [NSObjectProtocol]` in `Combo/Store.swift:91` and the existing `nc.addObserver` pattern at lines 150-159.
- `Combo/Store.swift:413` already removes every token in `observers` during `stop()`; append the new token there rather than creating another cleanup path.

## Steps

1. Immediately after `let nc = NSWorkspace.shared.notificationCenter`, append one observer for `.accessibilityDisplayOptionsDidChangeNotification` with `object: NSWorkspace.shared`, `queue: .main`, and a weak `self` capture.
2. In its callback, update `reduceMotion` on `@MainActor` from `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
3. Leave `refresh()`, existing observers, and `stop()` intact.

## Boundaries

- Do not poll the setting or introduce a timer.
- Do not modify system accessibility preferences.
- Do not add dependencies or alter unrelated Store refresh behavior.
- If cited code has changed since commit `2599f98`, stop and report the drift before editing.

## Verification

- **Mechanical**: Run `./build.sh`; expect exit code 0. Confirm the new observer token enters `observers`, so existing cleanup removes it.
- **Feel check**: While media is playing and Combo remains open, toggle macOS System Settings → Accessibility → Display → Reduce Motion. Without reopening the panel or app, confirm the menu bar bars stop/start and the settings label changes. Toggle back. In a screen recording slowed to 10%, confirm active spatial transitions stop when the setting is enabled.
- **Done when**: Runtime changes to the system setting update `Store.reduceMotion` immediately, and no observer survives `Store.stop()`.
