# KeyPath does not need Input Monitoring on macOS 27

**Date:** 2026-11-08
**Status:** Fixed

## Symptom

After granting only Device Control and Data Access (the macOS 27 name for
Accessibility), remapping worked, but Settings showed a red Input Monitoring row
and "Keyboard discovery unavailable until Input Monitoring is enabled for
KeyPath."

## Evidence

On the Air (macOS 27.3), with only Device Control and Data Access granted:

- The session runtime ran a modifying session tap and remapped keys. Its report
  showed `effectiveInputAccess: true`.
- The main app's `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` returned
  denied (`IM: denied` in the oracle log).

So the runtime has all the access it needs, and the red row described a
permission nothing in remapping uses.

## What still used Input Monitoring

Only main-app features:

| Feature | Old method | New method |
|---|---|---|
| Connected-keyboard detection (`HIDDeviceMonitor`) | `IOHIDManagerOpen`, gated on IM | I/O Registry matching notifications (`RegistryKeyboards`) |
| First-launch layout pick (`KeyboardTypeDetector`) | `IOHIDManagerOpen`, gated on IM | I/O Registry properties |
| Emergency stop chord | listen-only tap, gated on `CGPreflightListenEventAccess` | `ObservingEventTap`: listen-only, else pass-through modifying tap |
| Key recording while the runtime runs | listen-only tap | `ObservingEventTap` |
| Investigation tap | listen-only tap | `ObservingEventTap`, gated on Accessibility |

Reading a device's registry properties (name, vendor and product ID) needs no
privacy permission; only opening the device does. A listen-only tap needs Input
Monitoring, while a modifying tap needs only Device Control and Data Access.

A modifying tap holds every keystroke until its callback returns, so
`ObservingEventTap` runs on its own thread and hops to the main actor
afterwards: a stalled main thread can never delay typing. It re-enables itself
when macOS disables it for a timeout. It asks for listen-only only when
`CGPreflightListenEventAccess()` already allows it, because requesting one
without access can prompt for Input Monitoring.

The first-launch layout refinement used to run only with Input Monitoring, so
its "done" flag is unset for most existing users. It now replaces the stored
layout only while that is still the default, so a user's choice survives.

The emergency stop chord was silently disabled for anyone without Input
Monitoring, which on macOS 27 is everyone who follows setup.

## Not changed

- Setup already decided from the runtime's own input access (`kanata.inputMonitoring`
  in the session backend), so it never routed to the Input Monitoring page when
  remapping worked. That page remains a fallback if the runtime reports it cannot
  read keys.
- The oracle still records KeyPath's own Input Monitoring as a raw fact for
  diagnostics. Settings no longer lists it in driverless mode.

## Follow-up: Input Monitoring removed (ADR-047 step 3)

The permission model is now one snapshot: KeyPath's own Device Control and Data
Access grant plus the running runtime's key-access report
(`PermissionOracle.Snapshot.accessibility` and `.runtimeKeyAccess`). The Input
Monitoring wizard page, Settings rows, prompts, deep links, notification
action, `NSInputMonitoringUsageDescription`, and the CLI's `*InputMonitoring`
and `kanataAccessibility` status fields are gone; `keypath status --json` now
reports `keyPathAccessibility` and `runtimeKeyAccess`. When the runtime reports
it cannot read keys, setup asks the user to quit and reopen KeyPath. The raw
listen preflight survives only behind `keyPathCanCreateListenOnlyTap()`, and the
worker still records raw listen/post facts in its report for diagnostics.
