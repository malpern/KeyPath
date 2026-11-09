# Stuck-key detector fires when no runtime is running

**Date:** 2026-11-08
**Status:** Fixed

## Symptom

The mini wrote 20 stuck-key incident reports between 07:37 and 09:44 Pacific
(`~/Library/Logs/KeyPath/stuck-key-incidents/`). That made it look like keys were
getting stuck in hardware, since some reports came while KeyPath's runtime was
not running at all.

## Cause

None of the keys were stuck. `StuckKeyRecoveryService` reports an incident when
macOS autorepeats a key and Kanata has seen no event for 3 seconds. The rule
assumes every key passes through Kanata. Every one of the 20 reports says
`the session runtime was never started by this app`. With no runtime running,
Kanata is always quiet, so holding any key long enough to autorepeat counts as
"stuck". The keys were the ones people hold: arrows, delete, space and escape.
The six escape reports exactly 30 seconds apart are the detector's 30-second
cooldown re-firing while escape was held. There are exactly 20 because the
folder keeps only the newest 20, so these false reports also pushed out older,
real evidence.

Nothing observes `stuckKeyIncidentDetected`, so no alert reached the user. The
cost was error-level log lines, false incident files and lost real reports.

## Fix

`StuckKeyRecoveryService.runtimeIsRemapping`, wired by `RuntimeCoordinator`, is
true only while the session runtime reports `running` with its tap active. The
detector ignores autorepeat otherwise. The legacy daemon backend keeps the old
behaviour. Tests: `StuckKeyRecoveryServiceTests`
(`testIgnoresHeldKeysWhileTheRuntimeIsNotRemapping`,
`testStillSurfacesIncidentWhileTheRuntimeIsRemapping`).
