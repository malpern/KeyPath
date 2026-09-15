# P02 VirtualHID output proof

## Current result

**P02 is proven.** On September 15, 2026 a disposable Parallels macOS 26.5.2
guest received real USB HID keystrokes from the ESP32 fixture and TextEdit
observed the remapped output. This closes the gap every earlier attempt hit:
Tart's VNC input never appeared as a guest HID device, so Kanata reported
`InputGrab active=true devices=0` and the target received the unmapped key.

Parallels assigns a physical USB device to the guest that owns the session, so
the fixture enumerates inside the guest as a genuine keyboard. The guest's
`IOHIDDevice` tree contains `KeyPath Physical HID Fixture` (`CAFE:4010`) with
`PrimaryUsage 6` and `Transport USB`, and KeyPath's own device monitor logged
`Keyboard connected: KeyPath Physical HID Fixture (CAFE:4010)`.

### The evidence

One TextEdit document accumulated every fire, so the transitions are visible in
a single artifact. The document ended at `Qwwazvwbzqbz`:

| fire | rules live | fixture sent | document gained |
| --- | --- | --- | --- |
| 1 | none | `q` | `q` (TextEdit autocapitalized it to `Q`) |
| 2 | `q -> w` | `q` | `w` |
| 3 | `q -> w` | `qaz` | `waz` |
| 4 | `q -> w`, `a -> b` | `qaz` | `wbz` |
| 5 | `a -> b` only | `qaz` | `qbz` |

The `v` between fires 3 and 4 is a stray character from a host-side
`prlctl send-key-event` probe, not fixture output.

Read the fires as one controlled experiment. Fire 1 against fire 2 isolates the
rule: identical device, key, and application, with only the rule changing.
Fires 3 and 4 add selectivity — unmapped keys pass through untouched, and a
second independent rule takes effect the same way. Fire 5 closes the loop:
removing only the `q` rule restored `q` while the untouched `a -> b` rule kept
working, which rules out a confound in the device, the app, or the runtime.

Kanata logged every physical press and release (`[KeyInput] sent key=q
action=Press`), so the events reached the engine as real input rather than as
synthesized events.

### Extended matrix on the same lease

With the fixture attached, the following ran against the same guest and a
TextEdit oracle. All keystrokes were physical USB HID input.

| test | sent | expected | result |
| --- | --- | --- | --- |
| shift and passthrough | `Q1!q` with `q -> w` | `W1!w` | pass |
| tap-hold, tap | `s` held 40 ms, rule tap `s` / hold `d`, timeout 200 ms | `s` | pass |
| tap-hold, hold | `s` held 400 ms | `d` | pass |
| throughput | 40 characters at 10 ms intervals | all 40, remap applied | pass, `the wuick brown fox jumps over lazy dogs` |
| remap after recovery | `qaz` after a service teardown and repair | `waz` | pass |
| key repeat through a remap | `q` held 1000 ms | repeated `w` | pass, seven `w` |
| key repeat, unmapped control | `z` held 1000 ms | repeated `z` | pass, seven `z` |
| shifted alternate output | rule `e -> r` with shifted `z`, sent `eE` | `rZ` | pass |
| rule disable then enable | `q` after disable, then after enable | `q` then `w` | pass |
| soak | 180 characters at 15 ms | `wz` repeated cleanly | pass, 360 reports, 0 late |
| live reload while typing | rule changed 7 s into a 10 s run | output switches mid-stream | pass, `wy` to `wb`, no loss at the boundary |
| overlapping keys | `q` down, `z` down while held, both released | `wb` | pass |
| home row mod, hold | `f` held 250 ms as Shift, then `a` | `A` | pass |
| home row mod, tap | `f` tapped 40 ms | `f` | pass |
| emergency stop | Ctrl+Space+Esc as a real chord, then `q` | `q`, remapping off | pass |
| layer activation | space leader held 400 ms | enters `nav`, returns to `base` | pass |

The shift case matters: the remap applies to the physical key and the shift
modifier survives it, so `shift`+`q` yields `W`. Tap-hold is the case
simulation cannot settle, because the verdict depends on real hold duration
crossing the 200 ms timeout. The throughput run reported 82 of 82 USB reports
delivered with zero late reports and 41 microseconds maximum lateness, and
every character reached the app.

Key repeat survives the remap and is not perturbed by it: a one-second hold
produced seven characters through the remap and seven through an unmapped key,
the same count either way.

The rule lifecycle works in both directions from the CLI. `rule disable`
restored passthrough and `rule enable` reinstated the mapping, each taking
effect on the next keystroke, which is a different code path from the
add-and-remove cycle above. `--shifted` resolves against the real physical
shift: `e` produced `r` and shift-`e` produced `Z`.

Holding a remapped key with macOS press-and-hold enabled opens the accent
picker for the **remapped** character (`ŵ`), which is further evidence the
remap is a real HID-level key rather than injected text. Disable
`ApplePressAndHoldEnabled` before measuring repeat.

KeyPath's keyboard overlay independently rendered `W` on the physical Q key
while the rule was live.

The live-reload case is the most demanding one here and the most
representative: a rule was applied while the fixture was still typing at about
33 characters per second. The emitted text switched from `wy` to `wb` partway
through with no garbled, dropped, or duplicated characters at the boundary, so
a config reload does not disturb input already in flight.

Overlapping presses are handled correctly. The fixture's `run-text` emits one
key at a time, but its script format is a raw HID report stream
(`<microseconds> <modifiers> <up to six usages>`), so a hand-built script can
hold one key while pressing another. With `q` still down when `z` went down,
the output was `w` then `b` — each key remapped, in the right order.

That route then proved a home row mod, the feature this lab could never reach
before. With `f` bound to tap `f` / hold `lsft`, holding it 250 milliseconds and
pressing `a` produced `A`, while a 40 millisecond tap produced `f`. Both the
timing threshold and the modifier chord behaved correctly against real hardware.

**A custom rule can be silently outranked by an enabled collection.** The first
home row mod attempt produced lowercase `a`. `rule add f --tap f --hold lsft
--on-conflict replace` reported `applied: true`, but the generated config still
bound `f` to `layer_home-arrows_f` from the enabled Home Row Arrows collection,
so the custom rule never took effect. Disabling that collection made the rule
active on the next reload and the test passed. Worth checking whether
`--on-conflict replace` should detect a collection-owned key rather than
reporting success. **Always confirm the generated config binds the key you
expect before concluding a rule does not work.**

The emergency stop was exercised the same way and behaves as documented. A real
Ctrl+Space+Esc chord from the fixture stopped Kanata: `q` produced `w`
immediately before the chord and `q` immediately after, with the process gone
and port 37001 closed. That is the safety guarantee working against physical
hardware rather than a synthesized event.

**Recovering from the emergency stop took two attempts.** With KeyPath's window
focused, the first activation produced "KeyPath Runtime, powered by Kanata
Engine, failed to start. Click Fix to retry."; the second restored a running
Kanata, an open port 37001, and a launchd service reporting `running`. Worth
understanding why the first attempt fails, since a user hitting the emergency
stop will meet this. Note also that the body text says "Click Fix" while the
button reads "Restart", the same copy mismatch seen on the earlier repair step.

Layer activation works from physical input too. Holding the space leader key
for 400 milliseconds made Kanata log `Entered layer: (deflayer nav` and then
`(deflayer base` on release, so the leader-key layer resolves on real hold
timing rather than only in simulation.

Still unproven with physical input: the hyper key and tap-dance. The chord
script is the route to both.

**Trap: TextEdit autocorrect silently rewrites remapped output.** The first
throughput run appeared to show the remap failing at speed — the document read
`quick`, not `wuick`. Autocorrect had repaired the "misspelling" the remap
produced. Any future text-oracle test must disable
`NSAutomaticSpellingCorrectionEnabled` and `NSAutomaticCapitalizationEnabled`
first, or it will report false results in both directions.

### Finding: a failed service restart leaves the daemon unregistered

`keypath-cli service restart`, invoked as the console user from outside a GUI
session, stopped Kanata and then failed with "Could not restart Kanata
service". It did not merely fail to start: `com.keypath.kanata` was gone from
the launchd system domain entirely, so `launchctl kickstart` could not find it.
`keypath-cli system repair` then failed at
`install-required-runtime-services` with `userActionRequired: true`.

The reporting was correct — the command failed closed and said so — but the
system was left worse off than before the call, and no command-line path
recovered it.

Recovery came from the app. KeyPath's own UI had already detected the state and
offered a repair step reading "KeyPath runtime is not running. Click Fix to
start it." Activating it restored a running Kanata and TCP readiness, and the
`q -> w` rule was still in force afterwards.

Two caveats before treating this as a product bug. The invocation was
`sudo -u keypathmdm` from a root guest-control context, which is not how a user
runs the CLI, and re-registering a service legitimately needs user approval.
The part worth investigating is the unregistration side effect on a failed
restart, not the authorization requirement.

Minor: that repair step's body text says "Click Fix" while its button is
labelled "Start".

### Lease and artifacts

Lease `cbx_f4fdf8bd64de`, KeyPath commit
`5fce69baa1c967e05379f7ee8a9a5507aeeca67b`, signed installer SHA-256
`88fbb04fd987e05dc9d5dfbc9d2967469d7f27cefc63fe67e54c8c12214fe130`, macOS
26.5.2 (`25F84`). Helper `1.3.2` fresh and working, Kanata running, the
VirtualHID driver installed with a healthy daemon and device. Artifacts:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_f4fdf8bd64de/20260915T135147Z`

### Deviations to keep in mind

The artifact was Developer ID signed but **not notarized**, so Gatekeeper
assessed it as rejected. A notarized build has not yet been proven on this path.

Three steps needed a human at the console and are not yet automated: macOS
Setup Assistant, the KeyPath permission grants (each raises an authenticated
password prompt that this lane cannot drive), and confirming the Parallels USB
attach dialogs. The remap itself, rule application, reload, and evidence
collection were all automated.

The console session ran as `keypathmdm`, the lab's fallback administrator,
because `keypathqa` in this base carries a SecureToken whose authentication
fails under Parallels guest control. That detail matters when reading results:
`keypath-cli` run through the lab's SSH channel acts as `keypathqa` and reads a
**different** config file from the one Kanata loads for the console user. The
first fire produced `q` precisely because the rule had been written to
`keypathqa`'s config while Kanata was running the console user's. Apply rules
as the console user when validating runtime behavior.

## Managed-policy limitation, still open

This is separate from the output proof above and remains true. The legacy PPPC
payload draws the launcher and engine Accessibility switches as managed and
enabled, but macOS 26.2 and later no longer honor an Accessibility grant from
that payload. KeyPath's independent oracle correctly finds no Accessibility TCC
record and refuses to call the runtime operational.
[Apple documents the replacement](https://developer.apple.com/documentation/devicemanagement/privacypreferencespolicycontrol/services-data.dictionary)
as the declarative `com.apple.configuration.app-settings` configuration.

`keypath-macos-15-managed` is a stopped Tart base running macOS 15.7.7. It is
user-approved MDM enrolled and has the exact three installer-derived device
profiles installed. System-level lane admission passed before the staging image
was renamed to the final base. Disposable-clone admission and exact policy
rehydration are proven.

This is an approval-lane limitation, not a KeyPath remapping defect. Do not
turn it into a product bug or bypass it by modifying system-extension or
privacy databases.

## Earlier attempts

The runs below predate the proof above and are retained for their lane and
policy findings.

### Managed macOS 26 evidence on July 23, 2026

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

### Managed macOS 15 base evidence on July 23, 2026

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

### Disposable macOS 15 proof attempt on July 23, 2026

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

### Tart keyboard-path follow-up on July 23, 2026

Lease `cbx_f7009ff1b833` used KeyPath commit
`229ec8014fd708fa4931b63d1c915879bd830f6d` and the same signed installer
SHA-256. Managed admission passed, the real background-item and Input
Monitoring approvals were completed, repair reported `isOperational: true`,
and the exact q-to-w rule was applied. Kanata reported a successful live
reload and `InputGrab active=true`.

Two additional input routes still produced literal `q` in an independently
observed empty TextEdit document:

1. A key sent to Tart's focused graphical VM window.
2. A guest-side synthesized key event delivered by Peekaboo.

The graphical Tart run exposed a guest `Virtual USB Keyboard`, but Tart 2.32.1
also configures `VZMacKeyboardConfiguration`. The focused-window key continued
to bypass Kanata, so the mere presence of the USB keyboard device is not proof
that Tart delivered the event through it.

A locally built Tart 2.32.1 experiment removed the Mac keyboard configuration
and retained only `VZUSBKeyboardConfiguration`. After the host's removable
volume access prompt was approved, the guest did not reach SSH or a responsive
desktop within three minutes. The experiment was stopped, the stock Tart
runtime was restored, and KeyPath again reported `isOperational: true`.
USB-only Tart is therefore not an admitted lab route.

An ad-hoc-signed `IOHIDUserDevice` prototype was also rejected before launch.
AMFI reported that its restricted entitlements were not validated. The dead
prototype was removed rather than retained as a misleading resume path.

### Evidence captured on July 12, 2026

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

### Follow-up confirmation

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

### Required proof shape

P02 passes only when all of the following are true in one disposable lease.
The September 15, 2026 run above satisfied every point.

1. The KeyPath runtime is healthy: the VirtualHID driver installed with a
   healthy daemon and device, Kanata running, and TCP readiness responding.
2. A deterministic configuration maps physical `q` to virtual `w`, applied to
   the config the running Kanata actually loaded.
3. The harness focuses an independent target app with an observable text value.
4. The keystroke originates from a device the guest enumerates as a real USB
   HID keyboard, confirmed in the guest's `IOHIDDevice` tree.
5. The target app's value changes to `w`, not `q`.

Step 5 is the functional assertion. Driver metadata, a successful click, and a
KeyPath-local input monitor are useful preparation evidence but are not output
proof. Simulation output is never a substitute: it reported q-to-w correctly in
runs where the real key still produced `q`.

### What remains

1. Prove the same path with a **notarized** artifact; the September 15 run used
   a Developer ID build that Gatekeeper rejects.
2. Automate the three human steps: Setup Assistant, the permission grants that
   raise an authenticated password prompt, and the Parallels USB attach
   confirmation. Until then this proof needs someone at the console.
3. Add NanoMDM Declarative Device Management support and publish a
   `com.apple.configuration.app-settings` Accessibility configuration for
   macOS 26.2 and later. This is the durable route for the managed lane and is
   independent of the output proof.

Do not retry Tart VNC, guest synthesized events, an ad-hoc restricted
entitlement, or the USB-only Tart configuration. Do not continue treating
successful installation of the legacy macOS 26 PPPC payload as an
Accessibility grant.

Keep the unmanaged lane for a small number of real approval-flow tests. If its
DriverKit state remains `activated waiting for user`, preserve the command
output and artifacts, mark the test infrastructure-blocked, and continue
functional remap proof in the managed lane. Never infer a KeyPath product
failure from this state alone.
