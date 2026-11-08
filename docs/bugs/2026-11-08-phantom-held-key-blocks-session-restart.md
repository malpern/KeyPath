# A phantom held key blocked session restart indefinitely

**Symptom.** After a deploy on the mini (2026-11-08 09:06), the session runtime
refused to start (`managed-caps-activation-refused: physicalKeysHeld`). The wake
recovery loop then waited forever with
`Wake recovery waiting on held key codes [0]`. Nothing was pressed.

**Cause.** `CGEventSource.keyState(.hidSystemState, key: 0)` read A as down for
minutes in both HID and combined state. The worker posts its output at the
session level, so it cannot set HID state, and its orderly exit already releases
the keys it holds. This was a release report lost below KeyPath. The mini's
`~/Library/Logs/KeyPath/stuck-key-incidents/` holds 20 hardware stuck-key
reports from that morning (arrows, Delete, Space, Escape; `source_pid: none`),
including some from times the runtime was not running.

Activation refuses held keys on purpose, because changing the Caps Lock mapping
mid-press can strand a key. The recovery loop named the key after 5 s, but its
only remedy was asking the user to press it.

**Fix.** If the same keys still read as held after
`phantomHeldKeyRelease` (15 s), the loop posts one HID key-up for each
(`SessionCapsRuntimeSupport.postHIDRelease`), once per key, and rechecks. Posting
that key-up by hand is what restored remapping on 2026-11-08. A key that truly is
still held only sees an early release.

**Open.** The hardware stuck-key incidents themselves are not explained. Check
which keyboard sends them before blaming KeyPath.
