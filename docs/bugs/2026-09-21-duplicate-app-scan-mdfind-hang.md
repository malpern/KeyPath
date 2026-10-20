# Settings/Wizard Spinner: Unbounded Spotlight Scan on the Main Actor

**Date:** 2026-09-21
**Severity:** User-visible hang (window stuck on a spinner indefinitely)
**Status:** Fixed

## Problem

Opening Settings → Advanced froze KeyPath behind a spinner for over a minute. The
debug log stopped mid-validation, and `ps` showed a single child process that never
exited:

```
/usr/bin/mdfind kMDItemFSName == 'KeyPath.app'c     (parent: KeyPath, 70s+)
```

Killing that `mdfind` unblocked the app instantly. Run by hand a moment later, the
same query returned in 0.18s.

## Root Cause

Two defects compounded:

1. **No timeout.** `HelperMaintenance.detectDuplicateAppCopies()` launched `mdfind`
   with `Process` and called `waitUntilExit()`, bypassing `SubprocessRunner`, which
   every other subprocess call uses for its timeout. Spotlight can stall for a long
   time — here the index included `KeyPath.app` copies on an external drive
   (Sparkle `generate_appcast` staging directories), plausibly waiting on a sleeping
   volume — and the call simply never returned.
2. **Called on the main actor.** The function was `nonisolated` but synchronous, and
   every caller invoked it from main-actor UI code (`AdvancedSettingsTabView`'s
   `.task`, `SettingsView.copyPublishedStatus()`, and the wizard pages' `.onAppear`).
   A slow scan therefore froze the entire UI rather than one status row.

A third, smaller issue: the build-artifact filter did not know Sparkle's
`Sparkle_generate_appcast/` staging directories, so those copies would have been
reported as duplicate installs.

## Fix

- `detectDuplicateAppCopies()` is now `async` and runs `mdfind` through
  `SubprocessRunner` with a 2-second timeout (`duplicateScanTimeout`). A timeout,
  launch failure, non-zero exit, or empty result falls back to the canonical install
  locations.
- All callers `await` it off the synchronous path. `SettingsView.copyPublishedStatus()`
  stays synchronous (its validation-date observer must only copy published state, see
  `SettingsStatusValidationLintTests`) and folds the scan result in from a follow-up task.
- `/Sparkle_generate_appcast/` joins the excluded path fragments.
- Tests: `testDetectDuplicateAppCopiesUsesBoundedSpotlightScan`,
  `testDetectDuplicateAppCopiesFallsBackWhenSpotlightTimesOut`.

## Lesson

Any subprocess reachable from UI code must go through `SubprocessRunner` with a
timeout. "Fast in practice" (the old comment on this function) is not a bound.
