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
  (see Measurements).

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
- **Clock.** Compare HID and tap times in one clock: event timestamps
  (`CGEvent.timestamp` against the HID value's timestamp). With the same window,
  event timestamps and callback arrival times gave identical per-press results
  in the 2026-11-10 rerun; event timestamps do not depend on when a callback got
  to run. `CGEvent.timestamp`'s unit is not documented, so the worker checks it
  once at start.
- **Matching.** For a tap event, the candidates are the unconsumed HID entries
  with the same key and direction whose time is within a window of the tap
  event's: 30 ms behind it to 5 ms ahead of it. In the overlap runs the tap
  trailed HID by up to 29.7 ms and ran ahead by up to 4.7 ms. If every candidate comes from one keyboard,
  the event is credited to that keyboard. If candidates come from more than one
  keyboard, the event falls back (below). Either way the candidate closest in
  time is consumed, which is the rule the spike measured, so a second
  keyboard's entry is left for the next tap event.
- **Keys wait for their keyboard without blocking the tap.** The worker already
  consumes mapped keys in the tap and feeds the engine itself. When a key with
  a per-keyboard rule has no matching HID entry yet, the worker holds it and
  feeds it when the HID callback supplies a match, or when a deadline passes
  (5 ms after the tap event).
- **Order is kept by holding everything behind a held key.** While a key is
  held, every later event the worker's tap receives is also consumed and
  queued: key down and up, modifier changes (`flagsChanged`) and media keys
  (system-defined events), including keys with no rule at all. Mouse clicks do
  not pass through this tap, so a click within 5 ms of a held key can reach an
  app before it. That is accepted as a limitation. When the held key is released to the engine, the queue
  drains in order: keys for the engine go to the engine, and keys KeyPath does
  not map are re-posted unchanged with the output tag. So a key typed within
  5 ms of a held per-keyboard key is delayed by up to the rest of that 5 ms.
  When nothing is held, keys without a per-keyboard rule follow today's path
  unchanged.
- **Re-posting is a new path, with its own risks.** Today an unmapped key passes
  through the tap untouched. A re-posted one is a new event: its timestamp is
  later, its modifier flags must be copied from the original rather than taken
  from the state at re-post time, and other apps' event taps see it as posted
  by KeyPath. The worker already stops when secure input turns on; it must
  drain the queue before it stops, so no key is lost. Tests cover flags carried
  over, order, and draining on stop.
- **Fallback rule:** an event that cannot be credited to exactly one keyboard is
  treated as coming from *no particular keyboard* and gets the default output.
  That covers: no HID match before the deadline, candidates from two keyboards
  within the window, and an autorepeat while the same key is down on more than
  one keyboard. In the scored rerun no press was credited to the wrong
  keyboard; 11 of 413 fell back.
- Releases and repeats follow the press: a release is credited to the keyboard
  that pressed the key, so the engine never sees a press on one device and a
  release on another. macOS ends a merged press on the first release from
  either keyboard, so that release may physically come from the other one.
- **The worker ignores its own output.** KeyPath re-posts keys, and the spike's
  separate tap saw each key twice, 4–6 ms apart. The worker's tap already skips
  events carrying its output tag; attribution runs only on the originals.

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
  the worker with the config.
- **The hash is kanata's, not KeyPath's.** `DeviceSelectionCache` only caches
  `ConnectedDevice.hash` values that `DeviceEnumerationService` parses from
  `kanata --list`. The worker must produce the same hash for an
  `IOHIDDevice`, so the bridge exposes kanata's own device-hash function and the
  worker calls it; KeyPath never reimplements it. A test compares the worker's
  hashes with `kanata --list` for every connected keyboard.
- A keyboard that is not in the table sends no index and gets the default
  output. If a keyboard that has per-keyboard rules is connected but its hash is
  not in the table, Settings shows it as "not recognised" rather than silently
  doing nothing. Plugging in a keyboard that has per-keyboard rules regenerates
  the config.
- **An event with no device index must take the default branch of a
  `(switch ((device N)) ...)`, never match index 0.** The bridge change in
  rollout step 3 includes a test for exactly that.

### 4. UI that uses the same signal

With the feature on, the Connected Keyboard panel can show the keyboard last
typed on, instead of the one last connected. Without the grant, it keeps the
last-connected behaviour from #1391. This is the only other use of the signal.

## Consequences

- One extra permission, asked for only by people who turn the feature on.
  Everyone else's setup is unchanged.
- Added latency for people who use it: a buffer lookup per key with a
  per-keyboard rule (microseconds), plus at most the 5 ms deadline when the tap
  runs ahead of HID. Any key typed while such a key is held waits too, so order
  is kept. With the feature off, nothing changes.
- Per-keyboard rules are best-effort in one narrow case: the same key held on
  two keyboards at once. The fallback makes that case behave as if the feature
  were off for that key press, which is safe.
- The dormant code (`deviceOverrides`, the switch aliases, the mapper's device
  conditions) is kept and gets a working runtime, instead of being deleted.
- A new test seam: attribution logic as a pure function over (tap event, HID
  buffer) so the matching, ordering and fallback rules are unit-tested without
  hardware. The first tests pin down: order across held and unmapped keys,
  candidates from two keyboards, and an event with no device index. The ESP32
  fixture covers the end-to-end check.

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

## Measurements (settled 2026-11-10)

The scored overlap rerun (spike README, "Same-key overlap rerun") settles the
questions this ADR left open:

- **Window:** 30 ms behind, 5 ms ahead, and a 5 ms hold deadline. Every press
  found its HID value inside it except one. The margin is thin (the extremes
  were 29.7 ms and 4.7 ms) and the window was judged on the same run, so the
  log-only rollout step must report the no-match rate; widen the look-behind
  if it is more than rare. A miss falls back, so it is safe but invisible.
- **Two keyboards within the window fall back every time.** All 10 such presses
  had the other keyboard's press under 5 ms away. Presses 5–30 ms apart had
  only one candidate left by then and were all credited correctly (32 of 32).
  No press was credited to the wrong keyboard, so crediting the closest
  candidate would gain little and adds a way to be wrong.
- **Clock:** event timestamps (see Clock above).
- **Modifiers are attributed like any other key.** The fixture's Left Shift,
  seen as `flagsChanged`, was credited correctly every time alone (528 presses
  and releases). With Left Shift tapped on both keyboards at once, 414 of 430
  presses were credited correctly, none wrongly, and 16 fell back (15 with the
  other keyboard's press under 5 ms away). These counts cover the tap events
  that had ground truth; 43 of 473 had none and are not in them. macOS merges a
  modifier held on two keyboards like any other key: the first release ends it.
- **Known limitation, observed from macOS:** hold a key on keyboard B, tap the
  same key on keyboard A, and A's release ends B's press, because the tap stream
  has only one press to end. The evidence is the 50 Shift releases (20 Right
  arrow) where the other keyboard's release ended the press, and the "first
  release" merge rule fitting the tap stream far better than "every keyboard
  released". The release is credited to the press's keyboard on
  purpose (B in this example), so the engine sees a consistent press and
  release. B's rule therefore stops before B lets go, exactly as it would
  without KeyPath. A per-keyboard rule cannot fix this; the guide for the
  feature should say so.

## Rollout

1. ~~Rerun the overlap test and settle the open question.~~ Done 2026-11-10.
2. Attribution in the worker plus its unit tests, behind the Settings switch,
   with no engine change (log-only: count attributed, unattributed and
   fallback events). Built 2026-11-10: `KeyboardAttributionMonitor`
   (worker) and `KeyboardAttributionLog` (counting, unit-tested), switched by
   Settings → Experimental → Developer Feature Flags → "Keyboard Attribution
   (log only)". It logs `⌨️ [Attribution]` totals every ten minutes and when the
   worker stops; no key or timing is logged. Turning it on asks for Input
   Monitoring; the worker reads the switch when it starts.
3. Bridge device index and the `supported` change; turn on the switch aliases.
4. UI: the switch, the optional permission, hiding device conditions while off,
   and the Connected Keyboard panel. A guide in `guides/` for the feature.
