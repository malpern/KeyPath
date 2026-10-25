# Standalone session worker shutdown and function flags

Observed in the isolated driverless prototype on macOS 26.5.2, 2026-10-03.

The worker directly drives CFRunLoop rather than NSApplication's event loop.
A DispatchSourceSignal on the main dispatch queue did not deliver shutdown.
Moving it to a global queue exposed a second problem: Swift inferred main-actor
isolation for the handler created inside the actor-isolated worker. SIGTERM
then trapped in the executor check. The handler must explicitly be Sendable,
enqueue termination onto the main CFRunLoop, and wake that loop. PID disappearance
alone is insufficient acceptance: require the final stopped report and released
output ledger. Physical trials now verify both.

Function-key events such as F18 carry the Function flag even without a held
physical Fn key. Copying that flag to a remapped letter can invoke a macOS
Fn shortcut; Caps→F18→a repeatedly lost target focus. Track physical Fn from
its own keycode-63 flagsChanged events instead. A regression test covers F18
without Fn, real Fn press/hold/release, and Caps flag preservation. With this
correction, real ESP32 Caps→F18→Kanata basic mapping and both tap/hold branches
passed while maintaining target focus. The OS substitution is experimental and
fixture-scoped; automatic product mapping lifecycle is still pending.
