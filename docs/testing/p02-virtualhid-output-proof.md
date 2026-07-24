# P02 VirtualHID output proof

## Current result

P02 is not yet proven. A disposable managed macOS 15.7.7 clone now proves the
complete healthy runtime, exact q-to-w configuration, and independently
observed target-app output. The target received `q`, not `w`, because Tart's
VNC input did not appear as a guest HID device: Kanata reported
`InputGrab active=true devices=0`. This is an input-source limitation in the
lab, not a confirmed KeyPath remapping defect.

The next proof should inject `q` through a guest-visible test HID device (for
example an isolated IOHIDUserDevice helper) and retain TextEdit as the
independent output oracle. Do not weaken the proof to accept KeyPath's
simulation result; simulation correctly reported q-to-w in this run, while the
real VNC event bypassed Kanata and produced `q`.

The legacy PPPC payload draws the launcher and engine Accessibility switches as
managed and enabled, but macOS 26.2 and later no longer honor an Accessibility
grant from that payload. KeyPath's independent oracle correctly finds no
Accessibility TCC record and refuses to call the runtime operational.
[Apple documents the replacement](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services-data.dictionary)
as the declarative `com.apple.configuration.app-settings` configuration.

The smaller alternative is now available: `keypath-macos-15-managed` is a
stopped Tart base running macOS 15.7.7. It is user-approved MDM enrolled and
has the exact three installer-derived device profiles installed. System-level
lane admission passed before the staging image was renamed to the final base.
Disposable-clone admission and exact policy rehydration are now proven.

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

## Managed macOS 15 base evidence on July 23, 2026

The `keypath-macos-15-managed` Tart base was built from the clean
`ghcr.io/cirruslabs/macos-sequoia-base:latest` source with a new virtual serial
number and MAC address. It runs macOS 15.7.7 (`24G720`) and contains no KeyPath
installation.

The base completed user-approved enrollment in the private lab NanoMDM
instance. NanoMDM acknowledged the exact PPPC, system-extension, and
service-management profiles generated from the signed installer with SHA-256
`8dcbc201ce9333f5afff305fdd0956863613b45542556f81e6382fb772be87f4`.
ProfileList and the in-guest root-level system inventory both contained all
three identifiers, and immutable policy inputs were retained under
`/Library/KeyPathLab/managed-policy/`.

Controller evidence is retained at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/base-keypath-macos-15-managed/20260724T013334Z/managed-policy`

## Disposable macOS 15 proof attempt on July 23, 2026

Lease `cbx_629d00243876` used KeyPath commit
`e13836bae9b0f1a15c7b47cfc8783abad1f9d8a0` and the signed installer with
SHA-256 `8dcbc201ce9333f5afff305fdd0956863613b45542556f81e6382fb772be87f4`.
Artifacts are retained at:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_629d00243876/20260724T015650Z`

The controller rehydrated all three profiles against the macOS 15 base's
explicit enrollment identity, and root-level lane admission passed. Repair
then produced an activated-enabled DriverKit extension, healthy helper,
running Kanata and VirtualHID daemons, a healthy VirtualHID device, and TCP
readiness. The CLI reported `isOperational: true`.

The exact rule was installed with `keypath-cli rule ensure q w --apply`.
`keypath-cli simulate q` reported `w`. With an empty TextEdit document focused,
`desktop-type --text q` reported `method=vnc-key`, but TextEdit contained `q`.
The same run's runtime log reported no captured input device. This cleanly
separates the working output runtime from the unsuitable Tart VNC input source.

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

Continue with one explicit path:

1. Add a lease-scoped, guest-visible test HID input helper and repeat the
   q-to-w TextEdit proof in a disposable `keypath-macos-15-managed` clone.
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
