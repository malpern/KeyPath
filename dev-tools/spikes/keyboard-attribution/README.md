# Keyboard attribution spike (2026-11-09)

**Question:** can KeyPath tell which physical keyboard each key came from,
so per-keyboard remapping could return as an opt-in feature?

The session runtime reads keys through a CGEventTap, which merges all
keyboards into one stream. Per-device rules have been unsupported since the
driverless runtime became the only one: the session engine refuses
`macos-dev-names-*` (`Rust/KeyPathKanataHostBridge/src/session_config.rs`).

**Approach under test:** also watch every keyboard through IOHIDManager. That
stream names the device but needs Input Monitoring. Then match each tap event
to the HID event for the same key and direction by timestamp.

`main.swift` records both streams and matches them offline when it stops. It
stores key codes only, never text. Build and run:

```bash
swiftc -O -target arm64-apple-macos27.0 -o kb-attribution main.swift
./kb-attribution --seconds 120 [--csv out.csv]
```

It needs Input Monitoring for whatever launches it (Terminal, or a wrapper
`.app` with `NSInputMonitoringUsageDescription`).

Limits of the tool:
- Its HID-to-keycode table covers letters, digits, punctuation, Return, Escape,
  Delete, Tab, Space and the arrows. Other keys (F-keys, Home/End, the keypad,
  the ISO `#` key) are skipped on the HID side, so their tap events always come
  out unattributed. The recorded runs used only covered keys.
- If macOS disables the tap (timeout or secure input), the tool re-enables it and
  prints a warning, because tap counts are then incomplete. The 2026-11-09 runs
  used a build without this check; their HID and tap totals agreed except where
  same-key merging explains the gap.

## What happened

1. **First run, on the mini:** inconclusive.
   - The ESP32 HID fixture delivered 202 reports, but neither stream saw any of
     its arrow keys.
   - Someone was typing on the cl80 keyboard at the time. The HID stream caught
     only 10 of about 60 tap events.
   - The agent shell (under the Claude app) likely had only partial Input
     Monitoring, so the results are not trustworthy.
   - The raw CSV was deleted.
2. **A clean macOS 27 VM** (lease `cbx_687d083c91c3`):
   - The fixture was attached through the Parallels Devices menu, and the guest
     saw it as a HID keyboard.
   - The run stopped at the guest's Input Monitoring password prompt. The lab's
     credential helper is disabled on Parallels, and the agent does not enter
     passwords.
   - The lease was destroyed, and the fixture is back on the host with
     autoconnect left at "ask".

## Lessons

- **Lab VM bundles:** four lab VM bundles were owned by the disabled
  `restore-helper` account, so no desktop VM could clone. They were chowned to
  malpern through a sudo lease on 2026-11-09.
- **Fixture attachment:** Parallels refuses a persistent USB binding for this
  fixture ("does not support bypassing the host OS"). Attach it transiently from
  the VM window's Devices > USB menu. The window belongs to the separate
  "macOS VM" app, not Parallels Desktop.
- **Opening Parallels Desktop restarted its service and stopped the running
  lab VM.** Expect that, and restart the VM with `prlctl start`.
- **Deployment target:** build for the guest's macOS version. A binary built on
  27.3 fails to launch on 27.0 with LaunchServices error -10825.

## Results on the mini (2026-11-09, KBAttribution.app with Input Monitoring)

| Run | Tap events | Matched to a keyboard | Ambiguous | Repeats given a device* | Tap minus HID (p50 / p95 / max) |
|---|---|---|---|---|---|
| Fixture only | 41 | 41 (100%) | 0 | 29 of 29 | 1.1 / 6.1 / 10.2 ms |
| Fixture and a person typing on the cl80 | 923 | 923 (100%) | 0 | 152 of 152 | 1.1 / 5.4 / 9.2 ms |

\* A repeat inherits the device of the last matched press. The tool does not
check that device again, so this column counts repeats that got a device, not
repeats proven correct.

**Ground truth.** The fixture sends only arrow keys, and all 606 events credited to it
were arrows. All 317 events credited to the cl80 came from typing: 292 other keys and 25
arrows.

**Event timestamps and callback arrival times give the same answer**, so either clock
works. The tap stream trails the HID stream by about 1 ms, and by at most about 10 ms.

**Not exercised in these two runs: the same key pressed on two keyboards within a few
milliseconds.** The person's arrow presses were at least 9.3 s from the fixture's. The
overlap run below tests that case on purpose.

## Same-key overlap run (2026-11-09, first attempt)

The fixture tapped Right arrow 400 times (20 ms down, every 50 ms) while a person
tapped Right arrow on the cl80 for about 25 seconds.

| | Count |
|---|---|
| HID events (both keyboards, down + up) | 1093 |
| Tap events: fresh presses and releases | 933 |
| Tap events: autorepeat | 80 |
| Ambiguous, by event timestamp | 122 (13%) |
| Ambiguous, by callback arrival | 316 |
| Credited to the fixture / the cl80 | 730 / 203 |
| Tap minus HID (p50 / max / min) | about 1.3 / 27 / −3.9 ms |

**macOS merges overlapping presses of the same key.** While one keyboard holds Right
arrow, a press of Right arrow on the other produces no new tap event. A release on
either keyboard probably ends the press (not yet confirmed from raw rows). That is why HID shows 160 more events than the tap
stream, and why 80 autorepeats appear when neither keyboard held the key that long. So
in this case, the merged stream does not record which keyboard is holding the key.

Every tap event was credited to some keyboard, but per-press correctness was not
scored: the raw CSV was deleted before that analysis ran. A rerun is planned. It will
score each credited press against the fixture's known schedule and measure how close
two presses must be before the choice is wrong.

**Consequence for a feature:** a per-keyboard rule cannot be exact when the same key is
down on two keyboards at once. It needs a defined fallback for that window (see the
per-keyboard rules ADR).

**Open question, separate from attribution.** In the fixture-only run, 202 USB reports
produced only 41 key presses, and both streams agreed on that count. In the two-keyboard
run, 3×202 reports produced all 606 events.

## To finish

Rerun the overlap test and keep the CSV until the per-press scoring has run. Report:
- per-press correctness against the fixture's schedule
- the cross-device gap below which attribution goes wrong
- merged and phantom-repeat counts
- both clocks matched with the same window (the first overlap run let arrival times
  look 50 ms ahead but event timestamps only 5 ms, so its 122 against 316 is
  not a fair comparison)

Before the rerun, extend the tool to record `flagsChanged` events and the
modifier usages (0xE0–0xE7), so modifier keys are measured too. That needs a
rebuild of `KBAttribution.app` and a fresh Input Monitoring grant.

Then fill in the open section of the per-keyboard rules ADR.
