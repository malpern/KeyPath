# P02 VirtualHID output proof

## Current result

P02 is not yet proven. The unmanaged macOS 15 lane reaches the genuine
VirtualHID Driver Extension control, but the operating system still reports the
extension as `activated waiting for user` after the current supported UI-driven
attempt. Until that becomes `activated enabled`, a `q` to `w` remapping result
in a focused app would not be attributable to KeyPath's normal VirtualHID
output path.

This is an approval-lane limitation, not a confirmed KeyPath remapping defect.
Do not turn it into a product bug or bypass it by modifying system-extension or
privacy databases.

## Evidence captured on July 12, 2026

The disposable unmanaged proof used lease `cbx_1b376f03fbb6`, macOS 15.7.7
(`24G720`), KeyPath commit
`ccbb4d2c1ef3ecbff02a96a8ae517258e5555cb2`, and signed installer SHA-256
`8dcbc201ce9333f5afff305fdd0956863613b45542556f81e6382fb772be87f4`.
Artifacts are retained on the lab host at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_1b376f03fbb6/20260713T042245Z`

Before the DriverKit attempt, this same lease had completed the installer-side
preconditions required for P02:

1. KeyPath Input Monitoring was approved through its real macOS UI.
2. The KeyPath helper and background item were enabled through the real macOS
   UI with secret-safe password entry.
3. KeyPath Accessibility was enabled through the real macOS UI.
4. The P01 `desktop-type` primitive had already proven that a CrabBox VNC/RFB
   key reaches KeyPath's user-session input host.

The KeyPath wizard opened the real Login Items & Extensions surface. The
VirtualHID detail sheet exposed `.Karabiner-VirtualHIDDevice-Manager` and
`org.pqrs.Karabiner-DriverKit-VirtualHIDDevice`, including its approval toggle.
The harness drove that toggle with the current lease-owned UI state, then
checked the OS rather than treating the click as a pass. The authoritative
postcondition remained:

```text
org.pqrs.Karabiner-DriverKit-VirtualHIDDevice [activated waiting for user]
```

## Follow-up confirmation

A second clean unmanaged macOS 15.7.7 lease, `cbx_1a98a85674e7`, repeated the
result with the signed KeyPath candidate from commit `7ca790ab`. Its artifacts
are retained at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_1a98a85674e7/20260713T054117Z`

This run separately proved the preceding approval path: KeyPath Accessibility
and Input Monitoring were true, and the real Login Items password sheet was
completed through the secure dialog helper. The product then reported its
helper installed, working, and fresh. Repair installed the DriverKit component,
but the operating-system postcondition still was:

```text
org.pqrs.Karabiner-DriverKit-VirtualHIDDevice [activated waiting for user]
```

The direct Driver Extensions settings surface showed the extension row but no
supported enable control or authorization sheet. Semantic focus, row/detail
activation, and scrolling did not change that state. This separates the
working KeyPath-helper approval flow from the unresolved DriverKit activation:
do not retry helper/background-item approval when the extension is already in
this state.

## Required proof shape

P02 passes only when all of the following are true in one disposable lease:

1. The approved, normal KeyPath runtime is healthy: Driver Extension enabled,
   VirtualHID daemon running, Kanata running, and TCP readiness responding.
2. A deterministic configuration maps physical `q` to virtual `w`.
3. The harness focuses an independent target app with an observable text value.
4. `keypath-lab desktop-type LEASE --text q` reports the native `vnc-key`
   delivery method.
5. The target app's accessibility value changes to `w`, not `q`.

Step 5 is the functional assertion. Driver metadata, a successful click, and a
KeyPath-local input monitor are useful preparation evidence but are not output
proof.

## Resume path

Prefer the managed-functional lane once lab MDM/APNs enrollment is available.
It can pre-approve the signed KeyPath PPPC, DriverKit, and service-management
requirements without asking the test to exercise Apple's approval UI. Verify
the lane admission contract before installation, then run the proof shape
above.

Keep the unmanaged lane for a small number of real approval-flow tests. If its
DriverKit state remains `activated waiting for user`, preserve the command
output and artifacts, mark the test infrastructure-blocked, and continue
functional remap proof in the managed lane. Never infer a KeyPath product
failure from this state alone.
