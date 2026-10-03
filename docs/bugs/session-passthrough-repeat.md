# Session passthrough repeat must survive both ABI directions

The physical held-q acceptance trial on 2026-10-03 delivered ten session input
callbacks but only two output events and one remapped `a`. The fixed ESP32 trace,
focused independent target, live worker and clean shutdown all passed; the repeat
outcome failed. Evidence: `evidence/session-runtime/cbx_92ff62339803-ax-final-repeat-corrected-session-9f95f6699ec04e5f.json`.

The session ABI uses 0=release, 1=press, 2=repeat. The macOS physical DriverKit
`InputEvent` conversion recognizes only 1 as press and interprets every other
value as release. Its reverse conversion collapses press and repeat to 1. Those
conversions are appropriate to physical down/up reports, but lose information
when reused by the session passthrough adapter.

Decode and validate the session ABI directly into Kanata `KeyEvent`, preserving
repeat. The simulated passthrough output queue preserves repeat as 2 on macOS;
the physical DriverKit representation remains unchanged. A regression sends
press, repeat and release through the real engine and checks all three returned
values, then rejects unsupported value 3. A signed physical held-key retest is
required before accepting the fix.
