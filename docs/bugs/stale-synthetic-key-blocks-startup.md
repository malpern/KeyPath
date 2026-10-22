# A key nobody was pressing left remapping off with no explanation

## Symptom (mini, 2026-10-20)

KeyPath started without its engine three times in one day (11:01, 14:09,
14:18). Each start logged:

```
Managed Caps activation refused: physicalKeysHeld
Wake recovery gate: held-keys elapsedMs=0
```

and nothing after that. Port 37001 refused connections for hours, and the only
visible message was "Remapping will resume when your keyboard session is ready."

## Cause

`SessionCapsRuntimeSupport.requirePhysicalAllUp()` read
`CGEventSource.keyState(.combinedSessionState, …)`. It reported Space
(keycode 49) held while HID state did not:

```
combined: [49]   hid: []
```

No keyboard was holding Space. Pressing and releasing Space on the cl80 and
unplugging the fixture and the X2A changed nothing. One Space key-up posted at
the session tap (`kCGSessionEventTap`, from a combined-state source) cleared it
immediately.

The wake recovery loop polls the same check every 250 ms and logs only when the
blocker changes, so it waited silently for as long as the stale state lasted.

How the state diverged is not established. Posted events reach both records: a
key-down posted at the session tap from a private source set HID state as well,
and a key-up from a different source cleared both. That experiment did not
reproduce a combined-only press, and which program posted the original press is
unknown.

## Fix

- The check reads `.hidSystemState`, which was clear throughout this incident.
  It exists so a Caps Lock hidutil mapping never changes mid-press, and hidutil
  acts on HID events.
- Because HID state can also be held by a posted press, the wake recovery loop
  no longer waits silently: after 5 seconds on `held-keys` it logs the key codes
  and shows "Remapping is waiting because macOS reports the “space” key as held
  down. Press and release it to resume."

## Clearing it by hand

Post one key-up for the stuck key code at the session tap, for example from
Python with `ctypes`: `CGEventSourceCreate(0)`, then
`CGEventCreateKeyboardEvent(src, 49, False)` and `CGEventPost(1, event)`. A
key-up on its own types nothing. Logging out also clears it.
