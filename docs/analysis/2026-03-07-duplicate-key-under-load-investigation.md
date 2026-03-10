# Duplicate Key Under Load Investigation

Date: 2026-03-07

## Summary

This investigation started from a user-facing symptom: while the machine is under load,
typing sometimes produces repeated characters even though the physical keyboard was only
pressed once.

The earlier MAL-57 work in KeyPath likely fixed at least one duplicate-notification issue in
the TCP/UI observation path. It did not explain the real text corruption seen in editors under
load.

The current investigation reproduced the real bug and narrowed it to Kanata's macOS output
path.

## Scope

Work was done only in the isolated worktree:

- `/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation`

No investigation edits were required in the main checkout.

## What We Added

### KeyPath-side instrumentation

- Session/reconnect markers in `KanataEventListener`
- Reload boundary markers around config hot reload
- Correlation logging in `RecentKeypressesService`
- A passive macOS event tap to observe session-level key down/up/autorepeat events
- `AutorepeatMismatch` markers when macOS session autorepeat appeared without a matching
  Kanata repeat in the TCP stream
- Improved `Scripts/manual-keystroke-test.sh` artifact capture:
  - `actual-output.txt`
  - `diff-report.txt`
  - `log-slice.txt`
  - `session-markers.txt`
  - `unmatched-autorepeat-events.txt`

### Kanata-side instrumentation

In `External/kanata/src/oskbd/macos.rs`, `KbdOut` now tracks output-held keys and logs:

- `fresh-press`
- `press-while-output-held`
- `release-after-output-hold`
- `release-without-output-press`
- `repeat-while-output-held`
- `repeat-without-output-press`
- `tap-output`

These markers are emitted to daemon stderr/stdout so the manual harness can capture them.

## Reproduction Results

### Early reproductions

Several physical-key `compile` load runs produced real repeated characters in editor output,
for example:

- `nsuddennly`
- `dashedddd`
- `offf-by-one`
- `nullll`
- `roommmm`

At that stage:

- Kanata TCP key-input observation looked mostly clean
- reconnect/replay was not required
- KeyPath's duplicate detector did not fire
- the event tap saw macOS session-level autorepeat events

That established that the bug was not just UI/TCP duplication.

### Strongest reproduction

The strongest run is:

- `/var/folders/nj/b7p4n70x5sl6q3x8cz3pn3zm0000gn/T/keypath-manual-test-20260307-120721`

Important artifacts:

- [`actual-output.txt`](/var/folders/nj/b7p4n70x5sl6q3x8cz3pn3zm0000gn/T/keypath-manual-test-20260307-120721/actual-output.txt)
- [`analysis.txt`](/var/folders/nj/b7p4n70x5sl6q3x8cz3pn3zm0000gn/T/keypath-manual-test-20260307-120721/analysis.txt)
- [`kanata-output-markers.txt`](/var/folders/nj/b7p4n70x5sl6q3x8cz3pn3zm0000gn/T/keypath-manual-test-20260307-120721/kanata-output-markers.txt)

Observed text corruption included:

- `stillllllll`
- `aaaaaaaaaand`
- `forgottenn`
- `debugigng`

The critical output marker was:

- `OutputTransition key=KEY_E action=repeat kind=repeat-while-output-held held_ms=65071`

followed by:

- `OutputTransition key=KEY_E action=release kind=release-after-output-hold held_ms=65177`

## Diagnosis

Current diagnosis is split into two parts:

1. The original duplicate-key bug is real output corruption, not only duplicated UI notifications.
2. The bug does not require reconnect/replay to happen.
3. The strongest successful repros point at Kanata's macOS output path, where a key can remain
   logically held long enough for repeat behavior to occur.
4. Separately, this investigation uncovered a health-model bug in KeyPath itself: the app can show
   a green/healthy state when Kanata is running and TCP-responsive but still cannot open the
   built-in laptop keyboard device.

That second issue is important because it invalidates later repro runs on a laptop and violates the
installer/validation invariants.

## Code Inspection Notes

### Relevant files

- [`External/kanata/src/oskbd/macos.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/oskbd/macos.rs)
- [`External/kanata/src/kanata/output_logic.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/kanata/output_logic.rs)
- [`External/kanata/src/kanata/macos.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/kanata/macos.rs)
- [`External/kanata/src/kanata/mod.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/kanata/mod.rs)

### Most likely fault boundary

`KbdOut` now tracks output-held keys in:

- [`External/kanata/src/oskbd/macos.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/oskbd/macos.rs#L283)

Keys are inserted on successful output press/repeat and removed on successful output release:

- [`External/kanata/src/oskbd/macos.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/oskbd/macos.rs#L554)

The main macOS recovery loop releases input devices and waits for DriverKit output recovery:

- [`External/kanata/src/kanata/macos.rs`](/Users/malpern/local-code/KeyPath/.worktrees/duplicate-key-investigation/External/kanata/src/kanata/macos.rs#L118)

But there is currently no obvious reset or forced flush of output-held key state when recovery
happens.

That makes this a likely suspect:

- input/output recovery may leave stale output-held state behind
- later writes can observe a key as still held even though the physical/input side moved on
- macOS then sees a real held key long enough to autorepeat

### Why this looks plausible

- The observed `held_ms=65071` is much larger than a normal typing hold.
- That duration is more consistent with stale state surviving across time than with a human hold.
- The recovery path in `kanata/macos.rs` focuses on input re-grab and sink readiness, but does not
  obviously flush output state in `KbdOut`.
- `output_pressed_since` is local to `KbdOut`, which persists on the `Kanata` instance across the
  recovery loop.

This is still a hypothesis, not a proven root cause, but it is now the leading one.

## Follow-up Findings

After the Kanata output-path work, a separate problem appeared during reinstall/retest:

- KeyPath reported green
- Kanata was running from `/Library/KeyPath/bin/kanata`
- TCP was responsive
- but Kanata stderr contained:
  - `IOHIDDeviceOpen error: (iokit/common) not permitted Apple Internal Keyboard / Trackpad`

That means the system looked healthy by current service/TCP checks while the only available
keyboard on the laptop was not actually capturable by Kanata.

The resulting repro runs were invalid:

- `analysis.txt` showed `Key events processed by Kanata: 00`
- `session-markers.txt` showed only `SystemKeyEvent ... previous_kanata_action=none`
- `kanata-output-markers.txt` was empty

So the latest investigation state is:

- the duplicate-key root-cause investigation remains narrowed to Kanata output behavior from the
  earlier valid repros
- but before continuing with more repros, KeyPath's health/installer model must stop treating
  `running + TCP responding` as sufficient success on a laptop

## Health Model Fix

The health-model fix is now implemented in the investigation worktree.

What changed:

- `ServiceHealthChecker` now derives a runtime `KanataInputCaptureStatus` from recent Kanata stderr,
  specifically flagging `IOHIDDeviceOpen ... not permitted Apple Internal Keyboard / Trackpad`.
- Kanata runtime snapshots now carry:
  - `inputCaptureReady`
  - `inputCaptureIssue`
- `InstallerEngine` Kanata postcondition verification now uses the full runtime snapshot decision,
  so `running + TCP responding` no longer counts as success if input capture is unavailable.
- `SystemValidator` and `HealthStatus` now carry Kanata input-capture readiness into the system
  snapshot.
- `SystemContextAdapter` now routes this state as a blocking Kanata Input Monitoring issue instead
  of allowing `.active`.

This is intentionally a runtime-readiness fix, not a change to `PermissionOracle`.
That matches the ADRs better: permission declaration remains owned by `PermissionOracle`, while
service usability is enforced in the service-health / installer layers.

## Proposed Fix Direction

With the false-green state addressed, the next code change after verification should return to the
original duplicate-key investigation.

Priority order:

1. Add a shared Kanata input-capture readiness check based on runtime evidence.
2. Fold that signal into:
   - `InstallerEngine` Kanata postcondition verification
   - `SystemValidator` / `SystemContextAdapter`
   - main app health state so green cannot survive when the built-in keyboard cannot be opened
3. Surface the failure as a blocking Kanata/Input Monitoring issue instead of a false healthy
   state.
4. After that, rerun the duplicate-key harness to get valid laptop repros again.

Success criteria for this health-model fix:

- KeyPath does not report green if Kanata logs built-in keyboard `IOHIDDeviceOpen ... not permitted`
- installer/fix flow fails or warns instead of returning optimistic success
- manual harness no longer produces `Key events processed by Kanata: 00` on the built-in keyboard

Success criteria for the original duplicate-key fix remain:

- no `repeat-while-output-held` markers during normal typing
- no suspicious repeated-character windows in the manual harness
- clean editor output under the same compile load

## Open Questions

- Is the stale output-held state caused only by recovery/reinit, or can normal code paths also
  miss a release?
- Are there custom action paths that emit press/release asymmetrically under load?
- Should `KbdOut` track and actively release all currently held output keys during shutdown,
  recovery, and config reload?

## Status

Investigation is complete enough to support two targeted fixes:

1. KeyPath health/installer truthfulness around built-in keyboard access
2. Kanata-side output-path bug under load

The KeyPath health-model fix should land first so subsequent laptop repros are valid.
