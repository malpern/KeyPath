# Pending telemetry could restore settings after uninstall

## Cause

KindaVim telemetry keeps counters in memory and flushes them through a debounced
task and `applicationWillTerminate`. Its writer creates the parent Application
Support directory. Successful driverless uninstall could therefore delete that
directory, then have a pending flush recreate it during exit. The backup also
could omit counters that had not reached disk. The configuration operation gate
did not cover this independent telemetry writer.

## Fix

`RuntimeCoordinator.uninstall` suspends telemetry before invoking the uninstall
coordinator. Suspension first flushes pending counters so the backup can include
them, cancels the scheduled flush, and blocks further recording and writes.
Successful uninstall keeps telemetry suspended through termination; the app's
termination callback also skips its telemetry flush after completed uninstall.
Failed uninstall resumes recording without changing the user's opt-in preference.

This uses the existing telemetry store and uninstall lifecycle, with no new timer
or persistence framework.

## Verification boundary

The focused lifecycle suite passed 36 tests: 19 telemetry, 8 uninstall, 5 login,
and 4 termination tests. The telemetry regressions verify that pending counters
reach disk before backup, later recording/flush attempts do not recreate a
removed file, and failure recovery resumes recording without changing opt-in.

These are automated code-level checks. Live backup-first uninstall, app exit,
absence of recreated settings, and fresh onboarding after reinstall remain
pending on the final signed candidate. Do not treat this fix or the passing suite
as completed production acceptance.
