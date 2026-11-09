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

| Run | Tap events | Matched to a keyboard | Ambiguous | Repeats credited | Tap minus HID (p50 / p95 / max) |
|---|---|---|---|---|---|
| Fixture only | 41 | 41 (100%) | 0 | 29 of 29 | 1.1 / 6.1 / 10.2 ms |
| Fixture and a person typing on the cl80 | 923 | 923 (100%) | 0 | 152 of 152 | 1.1 / 5.4 / 9.2 ms |

**Ground truth.** The fixture sends only arrow keys, and all 606 events credited to it
were arrows. All 317 events credited to the cl80 came from typing: 292 other keys and 25
arrows.

**Event timestamps and callback arrival times give the same answer**, so either clock
works. The tap stream trails the HID stream by about 1 ms, and by at most about 10 ms.

**Not exercised: the same key pressed on two keyboards within a few milliseconds.** The
person's arrow presses were at least 9.3 s from the fixture's. That case is physically
rare, but the matcher would have to choose between the two candidates by timestamp, so it
should be tested deliberately before any feature ships.

**Open question, separate from attribution.** In the fixture-only run, 202 USB reports
produced only 41 key presses, and both streams agreed on that count. In the two-keyboard
run, 3×202 reports produced all 606 events.

## To finish

Test the same-key overlap case on purpose: hold an arrow key on a real keyboard while the
fixture taps the same arrow. Then decide on the opt-in per-keyboard feature. Report:
- attribution rate
- ambiguous matches
- repeat handling
- tap-minus-HID latency
