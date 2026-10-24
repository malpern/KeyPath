# Caps Lock rules on every keyboard

**Status:** implementation in progress, 2026-10-24. The worker now applies one
crash-recoverable mapping per eligible keyboard and checks for arrivals every two
seconds. Settings reports uncovered keyboards and offers per-keyboard exclusions.
The original spike and open questions below remain the qualification record;
the opt-in `SessionCapsMappingFleetTests/testLiveAttachedKeyboardsAcquireAndRestore`
passed on three attached USB keyboard services, including the physical HID
fixture, with readback and exact restoration on 2026-10-24. This is not a
release-build or hot-plug test. In particular, a press immediately after plugging in a
keyboard can precede the worker's next inventory check. The passive per-press
attribution described in the proposal has not been implemented.
**Question:** can driverless KeyPath apply Caps Lock rules without asking the user to
choose one keyboard?

**Answer:** yes. The spike supports mapping Caps Lock on every compatible keyboard,
each through its own device-scoped mapping, instead of choosing one. Three of the four
assumptions held on real hardware; hot-plug timing is still unmeasured. Four questions
remain open (see [Open questions](#open-questions)).

## Why a keyboard has to be chosen today

macOS applies Caps Lock's toggle in the HID event system, before the session event tap
where the driverless worker reads keys. The tap cannot cancel it. So managed Caps maps
Caps Lock (`0x700000039`) to a spare function key (F18 by default, `0x70000006D`) with
a device-scoped `UserKeyMapping` written by `hidutil`
(`SessionCapsHIDUtilTransport`), and the worker translates that key back into logical
Caps (`SessionCapsInputState`). See
[session-caps-mapping-lease.md](../bugs/session-caps-mapping-lease.md) and
[driverless-caps-lock.md](../../guides/driverless-caps-lock.md).

The prototype tracked exactly one device. Everything downstream inherited that:

- `SessionCapsSelection` stores one `DeviceIdentity` and its intermediate usage.
- `SessionCapsMappingLease` journals one device's applied mapping for crash recovery
  (journal version 1).
- `SessionCapsRuntimeSupport.automaticSelection` succeeds only when the inventory has
  exactly one eligible device and nothing withheld:
  `guard devices.count == 1, withheld == 0 else { throw Refusal.selection }`.

Any other inventory pauses Caps Lock rules until the user picks a keyboard. The guide
frames this as "KeyPath does not guess which one you mean."

### What that costs

- Every other rule applies to every keyboard. A user who writes a Caps Lock rule almost
  always means the same.
- A MacBook with any external keyboard needs the manual choice. That is the most common
  setup.
- Multi-interface boards (QMK, the cl80) are withheld because one interface cannot be
  picked arbitrarily. With "all keyboards" there is nothing to pick: every interface is
  mapped.
- The lab mini (cl80, X2A, fixture) has started every session with
  `Caps keyboard not chosen automatically (selection); starting with Caps Lock rules paused`.
  Its Caps Lock rule has never run there.

## Original proposal and remaining qualification work

Keep the device-scoped mapping. Apply it to every keyboard KeyPath can target.

1. **Every eligible keyboard service gets the mapping** when the session starts, using
   the same write and readback the single-device path uses. A failed write affects only
   that keyboard.
2. **Hot-plug.** An IOHIDManager matching callback (usage page 1, usage 6) maps a
   newly arrived keyboard before its first keypress. A removed keyboard's service, and
   its mapping, disappear with it; there is nothing to restore.
3. **Journal one entry per device.** Crash recovery restores each entry under the
   existing rules: exact owner, same boot, same device, unchanged mapping. A foreign or
   ambiguous entry is retained, as today.
4. **Report only what is actually uncovered.** A passive observer (IOHIDManager opened
   without seizing; KeyPath already holds Input Monitoring) attributes raw Caps Lock to
   its device. When a keyboard KeyPath could not map sends Caps Lock, KeyPath names it
   and the reason, once. No speculative warning for keyboards that are never used.
5. **The single-keyboard choice becomes an advanced option**, not a prerequisite.

Nothing else changes: the same intermediate pool (F13–F20), the same admission checks
that move the intermediate off a key a rule or shortcut uses, the same
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
- The cl80 appeared as two keyboard-usage devices at one LocationID. `hidutil list`
  showed one keyboard service. See open question 2.

### A4. Merging with existing mappings: holds, with one rule

- **Different source key.** With an existing `F14 → Caps` pair, writing
  `[F14 → Caps, Caps → F18]` kept both working: F14 still toggled the latch, Caps still
  reached the worker as F18. Restoring the original array read back identical.
- **Same source key.** For two pairs with Caps as the source, the first pair wins:
  `[Caps → LeftCtrl, Caps → F18]` held Control during a 1.5 s hold;
  `[Caps → F18, Caps → LeftCtrl]` did not. A Caps Lock remap from System Settings →
  Keyboard → Modifier Keys is exactly this case. See open question 1.

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

## Design details

**Inventory.** `SessionCapsHIDUtilTransport.parseInventory` already separates targetable
devices from withheld ones. "All keyboards" maps every device in `devices`, including
every interface of a multi-interface board that the existing grouping rule already
covers as one keyboard. A shared locator that would
also select a different physical keyboard stays withheld.

**Lease and journal (version 2).** One lease owns N entries, each with its device
identity, the full array it replaced, and the array it wrote. Acquisition writes entries
one at a time, each behind the existing mutation marker. Restoration walks every entry;
one failure does not stop the others, and it leaves that entry for exact-owner retry.
Version 1 journals are read and restored as a one-entry version 2.

**Hot-plug.** The worker owns the matching callback, so the lease stays the single
writer. A new device is admitted under the same checks as at startup (eligibility, all
keys up), then written and journaled. A device that is not admitted is reported as
uncovered, not retried in a loop.

**Existing Caps Lock remap on a device.** Open question 1 decides the policy. Whichever
is chosen, the stored array is preserved and restored byte for byte, which A4 showed is
safe.

**Migration.** An existing `SessionCapsSelection` becomes the advanced
"only this keyboard" setting. Users who never chose one get all keyboards.
`automaticSetupDisabledKey` keeps its meaning: no automatic Caps setup at all.

**UI.** The status line reads `On · all keyboards · Uses F18 behind the scenes`. The
keyboard picker moves under an advanced disclosure. The tour no longer needs a keyboard
selection step.

## Open questions

1. **A keyboard that already remaps Caps Lock.** The first pair wins (A4). Options:
   insert KeyPath's pair first and say so; or leave that keyboard alone and report it as
   uncovered with the reason "Caps Lock is remapped in System Settings." The second
   respects an explicit user choice and is the recommendation, but needs a decision.
2. **Multi-interface boards.** The cl80 exposed two keyboard-usage devices to
   IOHIDManager and one keyboard service to `hidutil list`. Confirm that mapping every
   service `parseInventory` returns covers every interface that can send Caps Lock, by
   pressing Caps on a QMK board.
3. **Hot-plug timing (A2).** Replug a keyboard with the watcher running. Also check
   whether macOS re-applies a Modifier Keys preference after arrival and overwrites
   KeyPath's array.
4. **The stuck F18 under load.** Reproduce on an idle machine with a Caps→F18 mapping
   active, and under synthetic load, to separate starvation from a mapping effect. This
   is independent of "one versus all" but affects any managed-Caps rollout.

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

## Acceptance

Before shipping: open questions 1–4 answered; the lease and journal version 2 unit
tests (N entries, partial restore, version 1 read); a lab run that maps several keyboards,
replugs one, crashes the worker and restarts, with every mapping restored; and the
existing single-keyboard regression tests passing under the advanced option.
