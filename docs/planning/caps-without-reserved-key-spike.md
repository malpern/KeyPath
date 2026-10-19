# Spike: managed Caps Lock without a reserved intermediate key

Date: 2026-10-19. Branch `spike/caps-untranslatable-usage` (off
`design/caps-device-picker`). Throwaway prototype in
`Scripts/spikes/caps-hid-usage-probe/`. No product code changed.

## Question

Today driverless KeyPath leases `Caps → F18` (hidutil `UserKeyMapping`) on one
chosen keyboard instance, and reserves F18 on every keyboard because the
CGEvent tap cannot tell which keyboard sent it. Could Caps instead be mapped to
a HID usage that macOS never turns into a CGEvent keycode, and be read only from
the chosen event service, so that nothing needs reserving?

## Answer

**No-go as specified. A variant works, at a cost we should not pay now.**

1. The per-service reader the question assumes, `IOHIDEventSystemClient`, is
   closed to us. Every client type (admin, monitor, passive, rate-controlled,
   simple) creates, schedules and activates without error, and then delivers
   **no events at all**, not even for the translatable control key. The
   monitor-type entitlements (`com.apple.private.hid.client.event-monitor`,
   `.admin`, `.event-filter`, ...) are private Apple entitlements, so a
   Developer ID app cannot get them. That is private SPI behind a private
   entitlement: dead end.
2. Untranslatable targets do exist, and they fully neuter Caps. The CGEvent tap
   sees nothing, and the Caps lock state does not change.
3. The public `IOHIDManager` sees the **raw** Caps press and release from the
   chosen device whatever the mapping is (it reads device reports before the
   service's key-mapping filter). So "neuter with an untranslatable mapping,
   read raw Caps from one device" removes the reservation entirely, but it
   costs three things:
   - **Input Monitoring.** `IOHIDManager` on keyboards needs ListenEvent
     access. Today's driverless flow needs only Accessibility.
   - **A cross-stream sequencer.** HID reports reach `IOHIDManager` before the
     same reports reach the CGEvent tap, by 0.8 ms at the median and up to
     15 ms. A naive merge puts 2–3% of transitions out of order at 4–16 ms key
     spacing, which is exactly what tap-hold decides on.
   - **A second input path into kanata**, next to the event tap.

Recommendation: take plan (a), a configurable intermediate chosen by evidence
that names the current Caps owner (Raycast and others). Keep the variant in
item 3 on file in case Input Monitoring becomes acceptable for other reasons. If
it does, the sequencer below is the part to prototype in the product.

## Setup

- **Input:** the ESP32 USB HID fixture (VID 0xcafe / PID 0x4010, "KeyPath
  Physical HID Fixture"), plugged into the **mini**. Real USB reports, scripted
  at 4 ms resolution through its HTTP API, which the probe reached through an
  ssh tunnel via linux because agent shells on the mini cannot reach LAN hosts.
  Event service `0x1004a62dc`, device `0x1004a62d4`.
- **Why the mini and not the Air:** the Air's built-in keyboard needs a person
  pressing keys, and KeyPath holds a live `Caps → F18` lease on it. Only the
  fixture's own service was remapped. KeyPath was not installed on the mini.
- **Host:** macOS 27.2 (26B5112a). The mini was **heavily loaded** (load
  average 33–54, a Parallels VM and CI running), so read the latencies as
  pessimistic.
- **Probe** (`main.swift`): a listen-only session CGEventTap, a public
  `IOHIDManager` input-value callback, and an `IOHIDEventSystemClient` via
  dlsym. Everything is printed as NDJSON on one nanosecond clock. Note:
  `CGEventGetTimestamp` is already in nanoseconds on this OS. Converting it from
  mach ticks a second time inflates it 41.7×.
- **Driver:** `drive.py` snapshots the fixture's mapping, maps
  `Caps → <candidate>` on the fixture service only, fires the script, and
  restores the snapshot in `finally`. The fixture's original Raycast mapping
  (`Caps → F20`, 0x70000006F) was read back after every run. The Air's lease
  was never touched (checked at the end with `hidutil property --get`).

## 1. Delivery and attribution

Three Caps taps per candidate (120 ms hold, 300 ms gap):

| Caps mapped to | hidutil accepts and reads back | CGEvent tap | IOHIDManager | event-system client |
|---|---|---|---|---|
| 0x07/0x6E F19 (control) | yes | keyDown/keyUp, keycode 80, ×3 | raw 0x39 ↓/↑ ×3, device 0x1004a62d4 | nothing |
| 0x07/0x73 F24 | yes | **nothing** | same | nothing |
| 0x07/0xA5 reserved | yes | **nothing** | same | nothing |
| 0x07/0xE8 reserved | yes | **nothing** | same | nothing |
| 0x07/0xFF reserved | yes | **nothing** | same | nothing |
| 0x07/0x03 ErrorUndefined | yes | **nothing** | same | nothing |
| 0xFF00/0x01 vendor | yes | **nothing** | same | nothing |
| 0x0C/0x2FF unassigned consumer | yes | **nothing** | same | nothing |

"Nothing" means no keyDown, keyUp, flagsChanged or NSSystemDefined event. The
HID system lock state (`CGEventSource.flagsState(.hidSystemState)`,
`maskAlphaShift`) was false before and after a tap and a 1 s hold. A held Caps
produced exactly one down and one up on `IOHIDManager`, with no repeats.

Attribution: `IOHIDManager` reports the **device** (`IOHIDDevice`, the
service's provider), not the event service the lease is keyed on. Resolving
that is an ancestor lookup and was not prototyped. On the Air, `IOHIDManager`
enumerates the built-in keyboard as device `0x1000693ee` (FIFO transport, one
Caps element); its event service is `0x100069400`. Delivery from the built-in
was **not** observed, because that needs key presses.

Side finding: **F21–F24 are untranslatable too.** F24 behaves like a reserved
usage, so under plan (a) the F21–F24 range cannot serve as a tap-visible
intermediate.

## 2. Timing and ordering

`timing.py` interleaves Caps with a tap-visible key on the same fixture. The
other key alternates between F19 and Left Shift, in both nestings (C↓ O↓ C↑ O↑
and O↓ C↓ O↑ C↑), with gaps cycling through 4/8/12/16 ms. A product would merge
two streams: Caps from `IOHIDManager`, everything else from the tap.

| | run 1 (→0xA5, 300 cycles) | run 2 (→0x03, 400 cycles) |
|---|---|---|
| Transitions | 1200 | 1600 |
| Caps leaked to tap | 0 | 0 |
| Merge by arrival: positions out of order | **24** | **48** |
| Merge by event timestamp: out of order | 26 | 30 |
| Same report, tap.t − HID.t (F19) | p50 0.82 / p95 7.4 / max 10.3 ms | p50 0.78 / p95 5.1 / max 7.9 ms |
| Same report, tap.t − HID.t (Shift) | p50 0.83 / p95 8.3 / max 9.8 ms | p50 0.79 / p95 5.2 / max 15.5 ms |
| IOHIDManager delivery (recv − t) | p50 0.12 / p99 1.0 / max 4.2 ms | p50 0.13 / p99 9.5 / max 20 ms |
| Tap delivery (recv − t) | p50 0.06 / p99 1.0 / max 2.2 ms | p50 0.06 / p99 9.3 / max 21 ms |
| HID copies sorted by HID timestamp = truth | yes | yes |
| Sequenced merge = truth | **yes** | **yes** |
| Sequencer Caps hold-back | p99 2.5 / max 5.1 ms | p99 1.0 / max 7.4 ms |

Reading it:

- **CGEvent timestamps are not HID timestamps.** WindowServer stamps the event
  when it creates it, 0.8–15 ms after the report, so neither arrival order nor
  timestamps can merge the two streams.
- **Caps runs ahead.** It came in before the next later tap event in all but 1
  of 1398 cases (the exception by 0.1 ms). The danger is a key pressed physically *before* Caps reaching
  kanata *after* it. That is a tap-hold misfire ("a" then Caps, decided as
  Hyper+a).
- **A sequencer fixes it in this data.** `timing.py sequence` uses the
  `IOHIDManager` copy of every key as the clock: a Caps event is held until
  every tap-visible key with an earlier HID timestamp has arrived through the
  tap. That reproduces the true order exactly, and holds Caps back by
  ≤ 7.4 ms. The offline model is optimistic, though. It pairs tap events with
  HID copies per key in FIFO order and knows every pair arrives. A real
  sequencer also has to:
  - watch every keyboard, not just the chosen one;
  - ignore synthetic events (the mini's own KeyPath re-posts each key; the
    analysis filtered on `eventSourceStateID == 1`);
  - time out on HID reports that never reach the tap (Secure Input, other taps
    consuming them).

## 3. Secure Input, sleep/wake, replug

- **Secure Input** (`EnableSecureEventInput` held by a helper process):
  `IOHIDManager` receives **nothing**, neither Caps nor F19, for the whole
  window. The tap still receives modifier `flagsChanged`. Delivery resumes on
  release without reopening the manager. Caps stays neutered, so it is a dead
  key in password fields, which matches today's F18 behaviour. A press that
  begins before Secure Input and is released during it would leave Caps stuck
  down. The product would need the same release-on-Secure-Input rule it needs
  today.
- **Sleep/wake:** not measured. The mini cannot be slept, and the Air would
  need a root-scheduled wake and someone at its keyboard.
- **Replug:** not measured. The fixture only re-enumerates through an OTA
  reflash, which is out of proportion for this spike. Expectation, not
  evidence: `UserKeyMapping` is per service and is lost on re-enumeration
  (which the lease already handles), and `IOHIDManager` needs re-scoping to
  the new device. That is the same identity problem the picker already solves.

## What was not shown

- Built-in keyboard delivery on the Air: `air-manual-check.sh` does it in about
  a minute with someone at the Air (quit KeyPath first).
- That `IOHIDManager` actually fails without Input Monitoring. Both shells used
  here already had ListenEvent granted. The requirement rests on Apple's
  `IOHIDRequestAccess` contract, not on a denial observed here.
- Sleep/wake and replug, above.
