# Keyboard attribution spike (paused 2026-11-09)

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

## To finish

Run it where a person can grant Input Monitoring: either the Air with two real
keyboards, or a VM where someone enters the guest password. Report:
- attribution rate
- ambiguous matches
- repeat handling
- tap-minus-HID latency
