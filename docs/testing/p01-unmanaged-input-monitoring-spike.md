# P01 unmanaged Input Monitoring spike

## Result

The macOS 15 unmanaged UI lane can automate KeyPath's own Input Monitoring
approval without mutating TCC, deliver a key through CrabBox's native VNC/RFB
path, and observe that key in KeyPath's user-session input host. P01 is proven.

The raw embedded `kanata-launcher` executable still could not be registered
through the supported System Settings paths tested on July 12, 2026. ADR-032
defines that executable as a legacy recovery runtime, so that result is a
separate packaging/managed-lane investigation rather than a prerequisite for
P01.

The disposable proof used lease `cbx_a35298e9ffef`, macOS 15.7.7 (24G720),
KeyPath commit `442f4c5c27c2a3b414486eaaa9c9104e28482d4a`, and signed installer SHA-256
`5a4246cf624683d546cf10cbfb9a05e75943c9c9d98fef85866b1890c4c2a2f7`.
Artifacts are retained on the lab host at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_a35298e9ffef/20260713T023731Z`

The successful capture proof used lease `cbx_8262dcfb476b` with the same OS,
commit, and installer. After `KeyPath_Toggle` reported `AXValue=1`, the harness
opened Input Capture Experiment, started recording, and sent `q` with CrabBox
`desktop type`. CrabBox reported `method=vnc-key`, and the experiment's AX tree
contained the captured `Q` chip. The new lease-owned `desktop-type` wrapper then
repeated delivery with `w`.

Capture-proof artifacts are retained at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_8262dcfb476b/20260713T025018Z`

## Proven behavior

1. Peekaboo 3.9 could discover and invoke KeyPath's wizard controls with
   `perform-action --action AXPress`. Its generic `click` command did not
   reliably invoke the same SwiftUI button.
2. The standard `universalAccessAuthWarn` prompt exposed a semantic
   `Open System Settings` action and opened the correct Input Monitoring page.
3. `KeyPath_Toggle` could be enabled through AXPress. System Settings then
   required `Quit & Reopen`; after that action the running KeyPath process
   reported Input Monitoring granted through `IOHIDCheckAccess`.
4. Password entry for protected System Settings changes remained secret-safe.
   `secure-dialog-input` required the Password and Modify Settings controls to
   disappear before returning success.
5. Finder and System Settings geometry returned to their original values after
   every `permission-drag` attempt.
6. A CrabBox VNC key event reached KeyPath's local `NSEvent` capture monitor and
   appeared as a visible captured-key chip. This is input evidence, not merely
   proof that an injection command returned success.

## Separate legacy-runtime limitation

The actual input consumer is
`/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher`. The
following supported unmanaged paths did not create its Input Monitoring row:

- System Settings Add and the native open panel: the raw executable is filtered
  and Open remains unavailable.
- A fresh Finder-to-permission-list drag through Peekaboo: the first attempt
  produced a legitimate authentication sheet, but no launcher row appeared
  after authentication. A second authenticated attempt produced neither an
  authorization sheet nor the required row postcondition.
- Dropping on the Add control rather than the existing list row: no launcher row
  appeared.

Do not treat an authentication sheet, completed drag, or closed password sheet
as permission success. Any future legacy-runtime test still requires a launcher
row plus canonical permission and live input-capture evidence.

## Decision boundary

Continue in this order:

1. Use the proven KeyPath-owned input event as P02's input and observe the
   remapped VirtualHID output.
2. Prove the managed-functional PPPC profile grants ListenEvent to the exact
   signed launcher requirement. This is the preferred non-hardware functional
   lane once the lab MDM path is available.
3. If PPPC cannot target this raw executable reliably, spike packaging the
   launcher as a properly signed app bundle or service whose designated
   requirement macOS can represent consistently in TCC and MDM.
4. Keep the unmanaged lane for genuine KeyPath approval-prompt and quit/reopen
   behavior even if the managed lane owns deterministic functional testing.

Never write the TCC database to make this spike pass.
