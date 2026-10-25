# Caps Lock rules on every keyboard

**Status:** deployed on the mini and Air, 2026-10-24. The worker applies one
crash-recoverable mapping per eligible keyboard. Since 2026-10-25 it reacts to a
keyboard arriving (an IOKit notification) instead of waiting for its two-second check. Settings reports uncovered keyboards and offers per-keyboard exclusions.
The original spike and remaining questions below remain the qualification record;
the opt-in `SessionCapsMappingFleetTests/testLiveAttachedKeyboardsAcquireAndRestore`
passed on three attached USB keyboard services, including the physical HID
fixture, with readback and exact restoration on 2026-10-24. The release build
passed notarization and runtime verification, but this is not a hot-plug test.
The arrival-to-mapped time is logged but has not yet been measured on a physical replug. The passive per-press
attribution described in the proposal has not been implemented.

**Question:** can driverless KeyPath apply Caps Lock rules without asking the user to
choose one keyboard?

**Answer:** yes. The spike supports mapping Caps Lock on every compatible keyboard,
each through its own device-scoped mapping, instead of choosing one. Three of the four
assumptions held on real hardware; hot-plug timing is still unmeasured. Of the four
follow-up questions, the existing-remap policy is decided and multi-interface coverage
is confirmed structurally (2026-10-22), and the stuck F18 did not reproduce in a lab VM (2026-10-24); see [Follow-up questions and results](#follow-up-questions-and-results).

## Why the original prototype chose one keyboard

macOS applies Caps Lock's toggle in the HID event system, before the session event tap
where the driverless worker reads keys. The tap cannot cancel it. So managed Caps maps
Caps Lock (`0x700000039`) to a spare function key (F18 by default, `0x70000006D`) with
a device-scoped `UserKeyMapping` written by `hidutil`
(`SessionCapsHIDUtilTransport`), and the worker translates that key back into logical
Caps (`SessionCapsInputState`). See
[session-caps-mapping-lease.md](../bugs/session-caps-mapping-lease.md) and
[driverless-caps-lock.md](../../guides/driverless-caps-lock.md).

The original prototype tracked exactly one device. Everything downstream inherited that:

- `SessionCapsSelection` stores one `DeviceIdentity` and its intermediate usage.
- `SessionCapsMappingLease` journals one device's applied mapping for crash recovery
  (journal version 1).
- Automatic selection required exactly one eligible device and nothing withheld.

Any other inventory paused Caps Lock rules until the user picked a keyboard.
The fleet implementation replaced that default while retaining a selected-only mode
for users who already made a choice.

### What that costs

- Every other rule applied to every keyboard while Caps Lock rules could be paused.
- A MacBook with an external keyboard needed a manual choice.
- Multi-interface boards (QMK, the cl80) could be withheld because one interface
  could not be picked arbitrarily. The fleet now maps every verified keyboard-capable
  interface.
- The lab mini's cl80, X2A and fixture previously caused Caps Lock rules to start
  paused until a keyboard was chosen.

## Original proposal and shipped scope

The proposal kept device-scoped mappings and applied them to every keyboard KeyPath
can target. The shipped implementation differs in one way: it reports coverage in Settings
instead of using passive per-press attribution. (It first polled inventory every two
seconds; arrivals now trigger a check, see Hot-plug below.)

1. **Every eligible keyboard service gets the mapping** when the session starts, using
   the same write and readback the single-device path uses. A failed write affects only
   that keyboard.
2. **Hot-plug.** A keyboard arriving triggers an immediate reconcile, with a
   two-second backstop. It admits a newly arrived keyboard when all keys are up and
   retires a removed one.
3. **Journal one lease per device.** Crash recovery restores each device under the
   existing exact-owner, same-boot, same-device and unchanged-mapping checks. A failed
   restoration retains its own record without discarding other keyboards' records.
4. **Report coverage.** Settings reports keyboards that are excluded, withheld or
   could not be mapped. Passive per-press attribution was proven in the spike but is
   not part of the shipped runtime.
5. **The single-keyboard choice becomes an advanced option**, not a prerequisite.

The implementation retains the F13–F20 intermediate pool, admission checks and
"all keys up before activation" check.

## Spike evidence

Run on the lab mini (mini/malpern, macOS 27.2) with KeyPath master `112c0b1fc`
installed, its session running and Caps Lock rules paused. Keyboards: cl80
(`0x5449:0x911c`), X2A (`0x3554:0xf507`) and the ESP32 HID fixture
(`0xcafe:0x4010`), all USB. No keyboard had a mapping beforehand. Only the fixture can
be pressed remotely; the other two were checked by reading back their mappings.

Observables:

- **Caps Lock latch** from `NSEvent.modifierFlags`. A 250 ms raw Caps Lock hold turns
  it on. A 40 ms tap does not (macOS's Caps Lock delay), so short taps cannot show
  whether a mapping prevented the toggle.
- **Worker counters** from the session report (`inputCount`, `outputCount`,
  `heldOutputUsages`). The config sets `process-unmapped-keys yes`, so an unmapped key
  such as F18 is counted in and out; raw Caps with Caps rules paused is not counted.

Writes used the same selector KeyPath's transport builds (VendorID, ProductID,
LocationID), narrowed with `PrimaryUsagePage 1` / `PrimaryUsage 6`. Every script
restored each mapping on exit.

### A1. Several keyboards at once, restored independently: holds

| Step | Result |
|---|---|
| Map Caps→F18 on all three | 48 ms total; each readback shows the pair |
| Fixture Caps, 250 ms hold, unmapped | latch **on** (then toggled back) |
| Fixture Caps, 250 ms hold, mapped | latch off; counters +2/+2 (F18 reached the worker) |
| Fixture F13 while mapped | counters +2/+2; other keys unaffected |
| Restore the fixture only | fixture empty; cl80 and X2A still mapped |
| Fixture Caps after its restore | counters +0, as before mapping |
| Restore cl80 and X2A | all three empty |

### A3. Per-device attribution without seizing: holds

A listen-only IOHIDManager reported each Caps press with its device name, for example
`KEY KeyPath Physical HID Fixture usage=0x39 value=1`, both while the fixture was
unmapped and while it was mapped. Element values are read before `UserKeyMapping`
applies, so attribution does not depend on the mapping state. With the observer
attached, raw Caps still toggled the latch: it did not take the device over.

- It needs Input Monitoring. From an ssh session (which holds it on the mini) the
  manager opened with `0x0`; from Terminal, which lacks it, `IOHIDManagerOpen` returned
  `0xe00002e2` (`kIOReturnNotPermitted`) and no values arrived. Device arrival and
  removal callbacks worked in both cases.
- The first press right after opening was not reported. The machine was heavily loaded
  at the time; this needs a repeat on an idle machine.
- The cl80 appeared as two keyboard-usage devices at one LocationID. The second is its
  shared interface; see [Multi-interface coverage](#multi-interface-coverage-2026-10-22).

### A4. Merging with existing mappings: holds, with one rule

- **Different source key.** With an existing `F14 → Caps` pair, writing
  `[F14 → Caps, Caps → F18]` kept both working: F14 still toggled the latch, Caps still
  reached the worker as F18. Restoring the original array read back identical.
- **Same source key.** For two pairs with Caps as the source, the first pair wins:
  `[Caps → LeftCtrl, Caps → F18]` held Control during a 1.5 s hold;
  `[Caps → F18, Caps → LeftCtrl]` did not. A Caps Lock remap from System Settings →
  Keyboard → Modifier Keys is exactly this case. See follow-up question 1.

### A2. Hot-plug timing: not measured

The fixture has no software reconnect (its only restart path is a firmware update), so
arrival needs a physical replug. What is known: arrival callbacks work without Input
Monitoring, and one device write plus readback takes about 16 ms. What is not: whether
the mapping lands before the first keypress on a real replug, and whether macOS
re-applies a Modifier Keys preference to the new service after KeyPath writes. A
watcher that maps and times any arriving keyboard was prepared on the mini
(`~/caps-spike/arrive`, not committed).

### Incident during the spike

At 21:06 `StuckKeyRecoveryService` reported `keycode-79 repeating with kanata
unresponsive for 17958ms` (F18). The incident snapshot showed the worker holding F18
(`held_output_usages: 109`, input 12 / output 11), with the autorepeat sourced from the
worker. It cleared without intervention. The load average was 240 on 14 cores
(Spotlight indexing, a Time Machine backup, Home Assistant at 100%), so worker
starvation is the likely cause. It was not shown to be unrelated to the mapping. See
open question 4.

It is the only snapshot of its kind. The mini's stuck-key monitor wrote 19 other
snapshots between 2026-10-03 and 2026-10-19, on Escape, Delete, Left, Return and Tab.
The six that recorded worker counters show input equal to output and nothing held,
which fits long real key holds. Only the F18 snapshot shows the worker itself holding output.

### Multi-interface coverage (2026-10-22)

The cl80 exposes three HID interfaces at LocationID `0x2111300`: a keyboard (`1/6`), a
shared interface whose primary usage is mouse (`1/2`), and a VIA vendor channel
(`0xFF60`). The shared interface's event service (`0x100004b67`) lists
`DeviceUsagePairs` of mouse, pointer, system control, consumer control and keyboard
(`1/6`). This is where QMK sends N-key-rollover keyboard reports, so Caps Lock can
arrive on it.

`hidutil list --matching keyboard` returns only the `1/6` service, but KeyPath does not
rely on that alone. `SessionCapsHIDUtilTransport.serviceGroup` adds every sibling
service at the same location for which `serviceEmitsKeyboardUsages` is true (a `1/6`
usage pair, or keyboard input in the report descriptor). The shared interface qualifies.
Writing Caps→F18 with its pair selector (`PrimaryUsagePage 1`, `PrimaryUsage 2`) changed
that service alone, read back correctly, and restored to empty.

Not yet shown: a physical Caps press on the cl80 arriving through the shared interface
and being remapped. That needs someone at the keyboard.

## Design details

**Inventory.** `SessionCapsHIDUtilTransport.parseInventory` separates targetable
keyboards from withheld ones. The fleet maps every eligible service, including
verified keyboard-capable interfaces on a multi-interface board. A selector that
could also affect another physical keyboard stays withheld.

**Lease and journal.** `SessionCapsMappingFleet` keeps one existing
`SessionCapsMappingLease` record per keyboard beneath a common termination guard.
Acquisition, recovery and restoration use the existing exact-owner checks; one
keyboard's failure does not discard other keyboards' recovery records. The old
single-keyboard record remains readable for recovery.

**Hot-plug.** `SessionCapsKeyboardArrivalMonitor` listens for `IOHIDEventService`
registrations (first-match notifications; services present at startup are ignored)
and classifies each with the lease's own `serviceEmitsKeyboardUsages`, so a board's
shared NKRO interface counts. An unreadable capability still counts as an arrival:
an extra inventory read is cheap, a missed arrival is not. An arrival makes the next
fleet check due at once; for three seconds after it, checks then run 0.25 s after the
previous one finishes, because hidutil can list a new service a moment after IOKit
reports it (`SessionCapsCheckSchedule`). The two-second check remains as a backstop,
and covers everything if the notification cannot be registered. The worker logs
`[SessionCaps] Keyboard covered` for every newly covered keyboard, and
`[SessionCaps] Keyboard arrival mapped in N ms` when the newly covered keyboard
follows an arrival within 30 s (a keyboard recovering from its failure backoff is not
counted as the arrival). It admits a new keyboard under the same eligibility and all-keys-up checks as at
startup, and retires records for a removed service. A failed device is left
uncovered and retried with backoff; an unavailable inventory leaves existing
coverage intact and reports that it cannot be verified.

**Existing Caps Lock remap on a device (decided 2026-10-22).** If a keyboard's current
`UserKeyMapping` already has a pair whose source is Caps Lock, KeyPath leaves that
keyboard unmapped and reports it as uncovered: "Caps Lock is remapped in System
Settings on <keyboard>." It applies the rule to every other keyboard. This respects an
explicit user choice, and nothing stops working without saying so. KeyPath never inserts
its pair ahead of the user's. Mappings on other source keys are kept and restored byte
for byte, which A4 showed is safe.

**Migration.** An existing `SessionCapsSelection` keeps the advanced
"only this keyboard" scope. Users who never chose one get all keyboards.
`automaticSetupDisabledKey` keeps its meaning: no automatic Caps setup at all.

**UI.** Settings shows keyboard coverage, per-keyboard exceptions, and the
selected-only option under Caps Lock options. The tour no longer requires a keyboard
selection step.

## Follow-up questions and results

1. **A keyboard that already remaps Caps Lock.** *Decided 2026-10-22:* leave that
   keyboard alone and report it as uncovered (see
   [Design details](#design-details)).
2. **Multi-interface boards.** *Confirmed structurally 2026-10-22:* the existing
   service grouping covers the cl80's shared NKRO interface, and the mapping writes and
   restores there (see
   [Multi-interface coverage](#multi-interface-coverage-2026-10-22)). Remaining: one
   physical Caps press on a QMK board in NKRO mode.
3. **Hot-plug timing (A2).** Replug a keyboard with the watcher running. Also check
   whether macOS re-applies a Modifier Keys preference after arrival and overwrites
   KeyPath's array.
4. **The stuck F18 under load.** *Not reproduced (2026-10-24); a mapping effect is
   unlikely, and host starvation is still unconfirmed.* The test ran in a lab VM
   (macOS 26.5.2, desktop-owned Parallels lane) with the fixture attached to the guest,
   KeyPath master `112c0b1f`, and the mini host's Caps config. The setup was a device-scoped
   Caps→F18 `hidutil` mapping on the fixture inside the guest.
   - **Round A, idle:** 5 holds of 1.5 s and 10 taps of 40 ms.
   - **Round B, no mapping:** 5 raw F18 holds of 1.5 s.
   - **Round C2, mapping on, full guest CPU load:** 4 × `yes` at ~97% each, guest load
     up to 7; 5 holds of 1.5 s.

   After every press the worker's input and output counts matched (final 299/299),
   `heldOutputUsages` was empty, no stuck-key incident was written, and Caps Lock stayed
   off. Raw F18 behaved the same as mapped Caps.

   Limits:
   - The original incident was at load ~240 on the bare-metal host with real devices.
     Guest load 7 on 4 vCPUs only partly simulates that starvation.
   - 30 presses is a small sample.
   - The guest's macOS build and the keyboard (the fixture) differ from the original.

   The finding is that the mapping alone does not deterministically hold F18. Host
   starvation remains the leading explanation but is not proven. Evidence:
   `~/vm-lab-evidence/stuck-f18-20261022T1259Z/run3/` on the mini.

   Getting there took two lab fixes:
   - **A dropped keystroke** in Parallels' synthetic typing broke consent. The fix was
     to qualify the fixture's current firmware for the physical-USB consent route
     (malpern/vm-lab#5, live-accepted 37/37).
   - **An unretried `PRL_ERR_IO_STOPPED`** on the guest exec channel ended earlier
     attempts. The fix is malpern/vm-lab#6, which retries it on reads; that path was not
     exercised in the passing run.

## Alternatives considered

- **One global mapping** (`hidutil property --set` without `--matching`). It covers
  hot-plugged keyboards for free, but it also maps virtual keyboards (VMs, remote
  desktop, Karabiner), it shares a slot other tools write, and a crash leaves Caps Lock
  broken on every keyboard. How it combines with device-scoped mappings was not
  measured. Rejected.
- **Learn the keyboard on its first Caps press**, using the passive observer. Avoids a
  picker but the first press toggles Caps Lock, and it still covers one keyboard.
  Rejected.
- **Seizing keyboards** (exclusive IOHIDManager open) and re-posting everything. Removes
  the toggle problem entirely, but it is a driver-like design that the driverless runtime
  exists to avoid. Rejected.

## Remaining qualification

The shipped fleet passed unit tests and an opt-in live test that acquired and
restored mappings on three attached USB keyboard services. A physical unplug/replug
test is still needed to measure the first-press window (read the `arrival mapped in N
ms` log line) and check whether macOS
reapplies Modifier Keys preferences after arrival. A physical Caps press on the
cl80 in NKRO mode would close the multi-interface question. The stuck-F18 VM
result above narrows the investigation but does not reproduce the host incident.
