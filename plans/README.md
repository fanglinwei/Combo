# Combo animation improvement plans

The plans were written against commit `2599f98` and the working-tree source reviewed on 2026-09-29. All five source changes are now in the working tree of `feature/0.0.1`, with an isolated copy at `/Users/fun/.codex/worktrees/animation-improvements/Combo`. Existing and concurrent edits to `Combo/Views.swift` and `Combo/main.swift` were preserved. `./build.sh` and `git diff --check` passed in the target branch; manual UI, VoiceOver, and Instruments checks remain pending. The target branch now resizes the panel immediately, so plan 004's original expectation of a synchronized AppKit frame morph needs a feel check.

| Order | Plan | Severity | Status | Dependency |
| --- | --- | --- | --- | --- |
| 1 | [001 — Update menu bar accessibility only when the state changes](001-update-status-accessibility-on-change.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 2 | [002 — Remove center glyph scaling in reduced motion](002-remove-scale-in-reduced-motion.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 3 | [003 — React to system Reduce Motion changes](003-observe-reduce-motion-setting.md) | MEDIUM | IMPLEMENTED; UI pending | Verify with 002 applied |
| 4 | [004 — Give detail entry a fast start](004-speed-up-detail-entry.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 5 | [005 — Open the routine panel immediately](005-remove-routine-panel-open-fade.md) | LOW | SUPERSEDED — the panel reveal is a measured requirement of the reference recording (2026-10-02) | None |
| 6 | [006 — Reduced motion keeps fades, drops movement](006-gentler-reduced-motion.md) | MEDIUM | IMPLEMENTED; RM feel-check pending | None |
| 7 | [007 — One motion curve token; exits stop using the built-in ease-out](007-motion-token-and-exit-curves.md) | MEDIUM | IMPLEMENTED; close curve tuned to 0.14 s | None |
| 8 | [008 — Hover feedback animates both ways](008-hover-feedback-symmetry.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 9 | [009 — Panel height eases instead of teleporting](009-panel-height-transition.md) | MEDIUM | IMPLEMENTED; UI pending | None |

The optional AirPods section reveal and media-card visibility transition from the audit are outside this execution set.

## 2026-10-02 round (panel reveal / card entrance / detail window)

Audited at commit `74e6963` against the same playbook. Findings 6-9 above were written and executed
in that round; the open items are the feel-checks and one LOW item: dropping `GlassEffectContainer`
(needed so per-card opacity reaches the tiles) gives up shared glass sampling — measure with
Instruments before shipping to older hardware, fallback is keeping the container and using
`.glassEffectTransition(.materialize)`. The missed opportunity recorded here was later **built**: the status item now lights a capsule while
the panel is open (`PanelHighlightTransition` in `Combo/Rendering/IconTransition.swift`, driven from
`drawIcon()`), matching the reference recording, which keeps the system highlight on for as long as
its panel is up. `NSStatusBarButton.isHighlighted` and `.pushOnPushOff + state` were both tried and
paint nothing on macOS 26, so the highlight is drawn on the button's layer.
