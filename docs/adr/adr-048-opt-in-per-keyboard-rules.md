# ADR-048: Opt-In Per-Keyboard Rules

**Status:** Proposed
**Date:** 2026-11-09
**Builds on:** [ADR-047](adr-047-pre-release-cleanup.md) (one permission set, no
Input Monitoring)
**Evidence:** [keyboard attribution spike](../../dev-tools/spikes/keyboard-attribution/README.md)

## Context

The session runtime reads keys through one modifying CGEventTap
(`SessionRuntimeWorker.createModifyingTap`). On macOS 27 that needs only
Accessibility. The tap merges every keyboard into one stream, so KeyPath cannot
tell which keyboard sent a key. Per-keyboard rules have therefore been dead since
the session runtime became the only one:

- rules still carry `deviceOverrides`, and the config generator still wraps them
  in `(switch ((device N)) ...)` aliases
  (`KanataConfiguration+BlockBuilders.swift`);
- the mapper and the rules list still show device conditions and per-device
  sections;
- the session engine refuses any config with `input_devices` or
  `macos-dev-names-*` (`session_config.rs::supported`), so those rules never run.

Users with a laptop keyboard and an external keyboard (or two external ones) do
want different rules per keyboard. It is the kind of advanced feature a
remapper is chosen for.

**The spike** watched every keyboard through IOHIDManager next to a listen-only
tap. IOHIDManager names the device but needs Input Monitoring. Each tap event
was matched to the HID event for the same key and direction by timestamp. On
the mini:

- **Separate keys, two keyboards:** 923 of 923 tap events credited to a
  keyboard, consistent with ground truth: the fixture sends only arrows and no
  other key was credited to it, and the person's arrows were at least 9.3 s from
  the fixture's. The tap trails HID by about 1 ms (p95 about 5 ms, max about
  10 ms).
- **The same key on two keyboards at once:** macOS merges the presses. While one
  keyboard holds a key, the other keyboard's press of that key produces no tap
  event, and autorepeats appear that neither keyboard caused. 13% of matches
  had two candidates. Per-press correctness in this case is not yet scored
  (see Open question).

## Decision

Bring per-keyboard rules back as an **opt-in feature**. It is the only thing in
KeyPath that asks for Input Monitoring. Everyone else keeps the single
Accessibility permission from ADR-047.

### 1. Turning it on

- Settings gets one switch: **"Different rules for each keyboard"**. Off by
  default.
- Turning it on explains why (KeyPath needs to see which keyboard each key comes
  from) and asks for Input Monitoring through `PermissionOracle`, which gains an
  `inputMonitoring` field again, but only as an *optional* capability: a missing
  grant never makes the system "not ready" and never appears in the setup
  wizard.
- Until the grant arrives, the switch shows "Waiting for Input Monitoring" with
  a button that opens the right System Settings pane. If the grant is later
  removed, per-keyboard rules stop applying (every keyboard gets the default
  rule) and Settings says so. Nothing else breaks.
- Device conditions in the mapper and the per-device sections in the rules list
  are hidden while the feature is off, instead of showing rules that cannot run.

### 2. Attribution, in the worker

- When the feature is on and the grant is present, the session worker opens an
  IOHIDManager on keyboard devices (usage page 1, usage 6) and keeps a small
  buffer of recent input values: device, key (HID usage), direction, HID
  timestamp. Nothing else is stored, and nothing is logged per key.
- **Threading.** The HID manager and the tap are scheduled on the same run loop
  (the worker's main run loop), so their callbacks never run concurrently and
  the buffer needs no lock. Nothing ever blocks waiting for the other callback;
  that would deadlock on a shared run loop.
- **Matching.** For a tap event, take the oldest unconsumed HID entry with the
  same key and direction whose timestamp is within a window of the tap event's
  timestamp. Consume it, so a second keyboard's matching event is left for the
  next tap event. The window must cover both directions: the tap trailed HID by
  up to 27 ms and ran ahead of it by up to 3.9 ms in the overlap run. Start at
  30 ms behind and 5 ms ahead; the rerun sets the final numbers.
- **Keys without a per-keyboard rule are not affected.** They follow today's
  path unchanged and need no attribution.
- **Keys with a per-keyboard rule wait for their keyboard, without blocking the
  tap.** The worker already consumes mapped keys in the tap and feeds the engine
  itself. For such a key it consumes the event, and if no HID entry has matched
  yet it holds the event in order and feeds it when the HID callback supplies a
  match, or when a deadline passes (5 ms after the tap event). Later events are
  queued behind a held one so key order never changes. The added latency is at
  most the deadline, and only for those keys.
- **Fallback rule:** an event that cannot be credited to exactly one keyboard is
  treated as coming from *no particular keyboard* and gets the default output.
  That covers: no HID match before the deadline, two candidates within the
  window, and an autorepeat while the same key is down on more than one
  keyboard. The fallback is meant to make a wrong-keyboard rule rare; whether
  it is rare enough is what the rerun measures. In the common case it is exact.
- Releases and repeats follow the press: a release is credited to the keyboard
  that pressed the key, so the engine never sees a press on one device and a
  release on another.

### 3. Engine

- `runtime.sendInput(value:usagePage:usage:)` gains an optional device index.
  The bridge forwards it to kanata's per-event device, so the existing
  `(switch ((device N)) ...)` aliases work unchanged.
- `session_config.rs::supported` accepts `input_devices` for per-device switch
  conditions only. `macos-dev-names-include/exclude` stay refused: the tap
  cannot drop a keyboard's events before macOS processes them, so "ignore this
  keyboard entirely" is not something the session runtime can honour.
- Today `renderDeviceSwitchExpression` sets `N` to the device's position in the
  generator's `connectedDevices` list, keyed by `ConnectedDevice.hash`. A
  position changes when a keyboard is plugged in or removed, so the worker must
  not guess it. The generated config ships its device table (hash → index) to
  the worker with the config, and the worker maps each HID device to a hash the
  same way `DeviceSelectionCache` does. A keyboard that is not in the table
  sends no index and gets the default output. Plugging in a keyboard that has
  per-keyboard rules regenerates the config.

### 4. UI that uses the same signal

With the feature on, the Connected Keyboard panel can show the keyboard last
typed on, instead of the one last connected. Without the grant, it keeps the
last-connected behaviour from #1391. This is the only other use of the signal.

## Consequences

- One extra permission, asked for only by people who turn the feature on.
  Everyone else's setup is unchanged.
- Added latency for people who use it: a buffer lookup per key with a
  per-keyboard rule (microseconds), plus at most the 5 ms deadline when the tap
  runs ahead of HID. Keys without such a rule are unaffected.
- Per-keyboard rules are best-effort in one narrow case: the same key held on
  two keyboards at once. The fallback makes that case behave as if the feature
  were off for that key press, which is safe.
- The dormant code (`deviceOverrides`, the switch aliases, the mapper's device
  conditions) is kept and gets a working runtime, instead of being deleted.
- A new test seam: attribution logic as a pure function over (tap event, HID
  ring buffer) so the matching and fallback rules are unit-tested without
  hardware. The ESP32 fixture covers the end-to-end check.

## Alternatives considered

- **Always ask for Input Monitoring.** Rejected: ADR-047 removed it because most
  users do not need it, and a second privacy prompt during setup costs everyone.
- **Delete the per-keyboard code.** Rejected: the spike shows the feature is
  achievable and the UI and config generation already exist.
- **Read keys only through IOHIDManager and seize the device.** Rejected:
  seizing keyboards and posting output from them is the privileged path ADR-045
  retired.
- **Feed the engine at once and correct it when the match arrives.** Rejected:
  the engine cannot take back output it has already sent.
- **Block the tap callback until the HID event arrives.** Rejected: both
  callbacks share a run loop, so the HID callback could never run while the tap
  waits.

## Open question

**How close must two same-key presses be before attribution is wrong?** The
first overlap run shows merging and 13% two-candidate matches, but its per-press
scoring was lost. The rerun (spike README, "To finish") decides two numbers here:

- the matching window (15 ms proposed above);
- whether two-candidate matches should take the earlier candidate or fall back
  every time. This ADR assumes fall back every time until the data says
  otherwise.

## Rollout

1. Rerun the overlap test and settle the open question.
2. Attribution in the worker plus its unit tests, behind the Settings switch,
   with no engine change (log-only: count attributed, unattributed and
   fallback events).
3. Bridge device index and the `supported` change; turn on the switch aliases.
4. UI: the switch, the optional permission, hiding device conditions while off,
   and the Connected Keyboard panel. A guide in `guides/` for the feature.
