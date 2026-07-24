# P02 VirtualHID output proof

## Current result

P02 is not yet proven. A managed macOS 26.5.2 lease now proves the helper,
DriverKit extension, VirtualHID daemon, exact installer-derived profile
publication, and genuine Input Monitoring approval. The remaining runtime gate
is Kanata Accessibility.

The legacy PPPC payload draws the launcher and engine Accessibility switches as
managed and enabled, but macOS 26.2 and later no longer honor an Accessibility
grant from that payload. KeyPath's independent oracle correctly finds no
Accessibility TCC record and refuses to call the runtime operational.
[Apple documents the replacement](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services-data.dictionary)
as the declarative `com.apple.configuration.app-settings` configuration.

The smaller alternative is a managed macOS 15 lane, where the legacy
Accessibility grant remains supported and the lab already has native VNC input
and `desktop-type`. The controller correctly targets
`keypath-macos-15-managed`, but that base does not exist yet.

This is an approval-lane limitation, not a confirmed KeyPath remapping defect.
Do not turn it into a product bug or bypass it by modifying system-extension or
privacy databases.

## Managed macOS 26 evidence on July 23, 2026

Lease `cbx_30fc557d2c01` used macOS 26.5.2 (`25F84`), KeyPath commit
`03b3858dd200c9645265f6e9bf519359c834d2e4`, and signed installer SHA-256
`8dcbc201ce9333f5afff305fdd0956863613b45542556f81e6382fb772be87f4`.
Final artifacts are retained at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_30fc557d2c01/20260724T003624Z`

The lease proved:

1. Automatic exact-policy publication, acknowledgement, ProfileList inventory,
   and system-level managed admission.
2. A fresh helper at version `1.1.0`.
3. The VirtualHID system extension at `activated enabled`.
4. A healthy VirtualHID daemon and device.
5. Real console clicks enabling the `Kanata Engine` and `kanata-launcher`
   Input Monitoring rows.
6. A system TCC result of `2` (granted) for the launcher's
   `kTCCServiceListenEvent` entry.

The same log showed no user or system TCC entry for
`kTCCServiceAccessibility`, despite the managed-on switch. Repair therefore
failed closed with Kanata not running or TCP responsive. The lab also extended
its Parallels RFB pointer probe to macOS 26; this clone rejected RFB
authentication, so no native input assertion was claimed.

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

Choose one explicit path:

1. Build and admit `keypath-macos-15-managed`, then run the proof shape above
   with the existing Tart `protected-click` and `desktop-type` primitives.
2. Add NanoMDM Declarative Device Management support and publish an
   `com.apple.configuration.app-settings` Accessibility configuration for
   macOS 26.2 and later.

The macOS 15 base is the smaller route to P02. The declarative route is the
durable macOS 26 and 27 investment. Do not continue treating successful
installation of the legacy macOS 26 PPPC payload as an Accessibility grant.

Keep the unmanaged lane for a small number of real approval-flow tests. If its
DriverKit state remains `activated waiting for user`, preserve the command
output and artifacts, mark the test infrastructure-blocked, and continue
functional remap proof in the managed lane. Never infer a KeyPath product
failure from this state alone.
