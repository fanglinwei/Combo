# Combo animation improvement plans

The plans were written against commit `2599f98` and the working-tree source reviewed on 2026-09-29. All five source changes are now in the working tree of `feature/0.0.1`, with an isolated copy at `/Users/fun/.codex/worktrees/animation-improvements/Combo`. Existing and concurrent edits to `Combo/Views.swift` and `Combo/main.swift` were preserved. `./build.sh` and `git diff --check` passed in the target branch; manual UI, VoiceOver, and Instruments checks remain pending. The target branch now resizes the panel immediately, so plan 004's original expectation of a synchronized AppKit frame morph needs a feel check.

| Order | Plan | Severity | Status | Dependency |
| --- | --- | --- | --- | --- |
| 1 | [001 — Update menu bar accessibility only when the state changes](001-update-status-accessibility-on-change.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 2 | [002 — Remove center glyph scaling in reduced motion](002-remove-scale-in-reduced-motion.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 3 | [003 — React to system Reduce Motion changes](003-observe-reduce-motion-setting.md) | MEDIUM | IMPLEMENTED; UI pending | Verify with 002 applied |
| 4 | [004 — Give detail entry a fast start](004-speed-up-detail-entry.md) | MEDIUM | IMPLEMENTED; UI pending | None |
| 5 | [005 — Open the routine panel immediately](005-remove-routine-panel-open-fade.md) | LOW | IMPLEMENTED; UI pending | Execute after 001 because both touch `Combo/main.swift` |

The optional AirPods section reveal and media-card visibility transition from the audit are outside this execution set.
