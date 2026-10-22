# Synthetic Cmd+V became plain V

On 2026-10-20, Aqua Voice dictation appeared in clipboard history but ChatGPT
received `v`. Aqua Voice Hook only observes the clipboard and posts Return;
the failing paste shortcut was being rewritten by KeyPath's session worker.

A standalone AppKit diagnostic on the Air posted key code 9 with only
`maskCommand`, using a private CGEventSource. Its own focused window received
key code 9 with flags zero and source PID 59379, the running KeyPath worker.
No clipboard changes or Aqua Voice Hook callbacks were involved.

The worker exempted its own tagged output but processed other applications'
synthetic events as physical input. Aggregate Command did not populate the
device-specific modifier bits or Kanata's held modifier state. Re-emitting V
therefore dropped Command. Unmapped input also had its flags rebuilt, so merely
removing V from the mapping would not reliably fix this.

Software keyboard events (positive source PID) now pass through unchanged,
before physical modifier state, Caps translation, input bookkeeping or Kanata
processing. Hardware events (source PID zero) still take the normal path.
Tap-disabled notifications remain on the existing failure/recovery path.

Regression coverage exercises both paste edges with aggregate-only Command,
software modifier and Unicode events, hardware routing and tap-disable handling.
The live diagnostic is separate evidence from unit coverage: rerun it against an
installed candidate before claiming the installed bug is fixed.
