# Kanata Runtime Plan (User-Agent First)

## Goals & Requirements

1. Restore functional keyboard capture.
   Kanata must reliably receive hardware key events so remaps (e.g., 1→2) fire every time.
2. Honor macOS security model.
   Input Monitoring permission is per-user and must apply to the process that reads key events.
3. Preserve a stable binary path for TCC.
   `/Library/KeyPath/bin/kanata` is the canonical target so permissions survive app updates and bundle relocations.
4. Accurate wizard status.
   The installer must reflect real key traffic rather than trusting TCC rows.
   This prevents “all green” when kanata is still blind.
5. Minimal user confusion.
   The wizard should guide users to grant permission to the exact binary path the service execs.

## What We Learned

- System LaunchDaemons can appear “granted” in TCC but still fail to receive real key events.
  This shows up as `IOHIDDeviceOpen … not permitted` in the kanata stderr log.
- macOS 26 (Tahoe) can hide CLI entries added via “+” in the Input Monitoring UI.
  The absence of a UI row is not proof that permission was not granted.
- The wizard must not treat “TCC says granted” as “working”.
  We need runtime evidence that kanata is processing non-keepalive key events.

## Alternatives Considered

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| A. System LaunchDaemon only | Simple packaging | Unreliable IM delivery; easy to show false greens | Rejected |
| B. User-session agent runs stock kanata | Works with macOS IM model; no Kanata fork | Might fail if VirtualHID output requires root-only access | Chosen (first) |
| C. User-session input proxy + root kanata | Keeps root where needed for output | Requires additional IPC and more moving parts | Fallback |

## Current Direction

We run `com.keypath.kanata` as an `SMAppService.agent` (LaunchAgent).
That agent execs `/Library/KeyPath/bin/kanata`.

We still keep Karabiner VirtualHID services as system LaunchDaemons.
Those are installed and repaired via the privileged helper / InstallerEngine.

## Wizard Verification Rules

- “Kanata Input Monitoring granted” is detected via a TCC read for `/Library/KeyPath/bin/kanata`.
  This is used only to know whether the user completed the System Settings step.
- “Kanata Input Monitoring working” requires runtime evidence.
  The wizard stays red until kanata logs real key events (not just WakeUp keepalives).
- Logs are written to:
  - `/var/tmp/com.keypath.kanata.stdout.log`
  - `/var/tmp/com.keypath.kanata.stderr.log`

## Next Step If This Fails

If running stock kanata as a user agent cannot emit remapped events (VirtualHID access),
we move to Option C.
Option C keeps kanata privileged for output, but adds a user-session component for input capture.
