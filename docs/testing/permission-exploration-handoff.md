> Continuation status (2026-10-03): the initial handoff below is historical.
> The current findings and prototype are documented in
> [permission-exploration-results.md](permission-exploration-results.md).
> The real Kanata driverless adapter, four permission states, signed update,
> alternate identity, controlled Secure Input, home-row tap/hold, and static
> hidutil mapping have now been exercised. The original secure-dialog success
> was a false positive; normal Settings approval was independently verified
> after correcting paired native key transport. Approval policy is `never`;
> the original guest-only restrictions remain in force.
> Lease `cbx_bb5740605b15` is now destroyed; cleanup is independently verified
> complete and provider inventory is empty. Artifact and continuity limitations
> are recorded in the results completion section. The experimental controller
> refuses credential entry after a late focus failure; affected diagnostic
> payloads were removed/redacted. Preserve this worktree. A future hardware or
> continuity trial requires a new admitted lease and reliable credential focus.

# Permission footprint exploration handoff — 2026-10-03

Continue the original user-requested bounded research, not production shipping.
User authorizes reversible guest changes, dependency installation, normal Settings
UI permission approval/revocation, privileged guest commands using existing lab
access, and reboots. No host security/permission/KeyPath changes, unrelated VMs,
TCC writes, SIP disabling, credentials in logs/commits, or manual user intervention.
Latest steering: also assess Karabiner driver/service requirements; seamless
installation matters more than password-field coverage. Optional driverless mode
may accept Secure Input limitations. Full original task and deliverable checklist
should be pasted/attached in the new session.

## Isolation and live resource

- Worktree: `/private/tmp/keypath-permission-footprint`
- Branch: `experiment/macos-permission-footprint`, base `d5581754c143914727dca827f96439246138fcef`.
- Integration checkout untouched; existing untracked `info` and
  `docs/planning/catalog-led-consolidation-progress.html` are not ours.
- Experimental VM lease: `cbx_bb5740605b15`, owned by this investigation.
- Controller must use `vm-lab --host mini keypath ...`; default mini.local
  resolution failed. Do not create VMs directly with providers.
- Lease expires epoch 1791049658 (2026-10-03 17:47:38 UTC / 10:47:38 Pacific).
  Provider reports a 30-minute idle timeout; check status before reuse.
- VM: Parallels, macOS **26.5.2 (25F84)**, console/SSH `keypathqa`, UID 501.
  SIP enabled, initially zero system extensions, sudo from SSH requires password.
- Parallels root guest-control channel works, UID 0; no password needed.
  Use the ownership-guarded `lab.py root` helper. Never act on another resource.
- At handoff the VM remains alive for continuation. Collect artifacts and destroy
  this lease when finished, or create a new admitted clone if expired.

## Read first

Read applicable AGENTS.md and `/Users/malpern/.codex/skills/vm-lab/SKILL.md`.
Lab implementation: `/Users/malpern/local-code/vm-lab/{bin/vm-lab,lib/remote.sh}`.
Lab UI guide is stale: **secure-dialog-input_parallels now exists** and successfully
delivered the existing credential through native Parallels key events. No credential
was exposed. `secure-dialog-input ... --app 'System Settings' --field Password
--submit 'Modify Settings'` returned passed. Independently verify actual approval.

Guest Peekaboo is **3.9.4**, at `/opt/homebrew/bin/peekaboo`, not the documented
`/usr/local/bin/peekaboo`. A guest-only symlink was added from /usr/local/bin to
the actual tool so the lab secure-dialog helper works. Bootstrap --install-tools
passed. Peekaboo AX, screen capture, and event synthesis are already granted.
Baseline Accessibility list also contains prltoolsd and sshd-keygen-wrapper!
Direct SSH/provider launches may inherit automation permissions. Independent
`open -n App.app` is essential for uncontaminated identity evidence.

## Artifacts and current prototypes

- Baseline signed installed app copied READ-ONLY from host into
  `/private/tmp/KeyPath-permission-baseline.zip` and installed only in guest.
  Archive SHA256 `f1f1043caa4ae8135587703c0d08d6304d6471c82ebbbc81cd7eabc9b93054a3`.
  This app is Sep 16 build, **not** necessarily current source d5581754;
  manifest source commit describes harness source, not binary provenance.
- Engine identifier `com.keypath.kanata-engine`, Developer ID team X2RKZ5TG99;
  binary SHA256 `098740b77a35077cc1b1560b4a7d1d4ca721bb6ef3d43bf7ff03368ce8a145a3`.
- Experimental source files (uncommitted):
  `Scripts/experiments/permissions/probe.m`, `build-probe.sh`, `lab.py`.
- Signed probe: `/private/tmp/Permission Probe.app`, zip
  `/private/tmp/permission-probe.zip`; guest
  `/Users/keypathqa/Applications/Permission Probe.app`.
  Identifier `com.keypath.experimental.permission-probe`, same Developer ID,
  SHA256 `f897c59c9df85457ea08af0111ac83647365202d76d8a78274d9ff8b93722dc3`.
- Probe logs counters only, no arbitrary keycodes/text. 20-second lifetime limits
  capture. Active tap optionally q→a; raw IOHID callback counter; modes
  --remap, --seize, --check-only, --request-ax, --request-im.
- Evidence logs in worktree `evidence/`; do not blindly commit these (upload log
  contains a base64 binary but no secrets). All lab logs remain under
  `/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab` on mini.
- Probe build uses installed Xcode beta clang (stable pin unavailable locally).
  No Swift builds or host deployments performed.

## Evidence so far (do not overclaim)

1. Independent probe with neither permission: START uid=501 ax=0 listen=2;
   HID open=0x0 **devices=0**; active TAP created=0. Later listen=1.
   This VM exposes Virtual Keyboard as an **IOHID event service**, but hidutil
   Devices has only Virtual USB Digitizer. It may not support raw HID capture.
   A successful IOHIDManagerOpen with zero devices is NOT capture proof.
2. Normal Settings UI registered Permission Probe under Accessibility.
   `perform-action --on 'Permission Probe_Toggle'` reported success but did
   not establish approval. A fresh numeric element ID elem_110 worked and
   exposed real Password / Modify Settings authorization sheet.
3. Last completed call: `vm-lab ... secure-dialog-input ...` returned
   `secure_dialog_input passed`, `credential_transport parallels-key-events`.
   **NEXT: independently reopen probe and check ax/listen, confirm toggle state;
   verify IM list still has no explicit product grant.**
4. No real Kanata remapping, driver activation, event injection/output test,
   signed update, reboot, sleep/wake, Secure Input experiment or HRM test yet.
   No architecture permission reduction verified yet.

## Upstream findings

Upstream checkout `/private/tmp/karabiner-permission-research`, HEAD
`6029cab01` (current cloned snapshot). Historical fetches may require network.
Release v16.0.0 May 3, 2026 confirms Accessibility-first conditional IM request.
Relevant commit **bae28b2899d7fd8fbb044b664dee7bf9c659ad7e**, April 18, 2026.
Source paths at v16:
- src/core/CoreService/include/core_service/agent/components_manager.hpp
- src/core/CoreService/include/core_service/core_service_utility.hpp
- src/share/types/core_service_permission_check_result.hpp
Current equivalent agent/permission_checker.hpp under src/apps/CoreService.
Algorithm: launch the SAME Core-Service .app through NSWorkspace with permission-check,
read AXIsProcessTrusted and IOHIDCheckAccess(ListenEvent), prompt AX first,
request IM only if effective IOHID access still denied; required result remains
AX AND effective HID access. Comment says macOS 26 may cover IM through AX,
macOS 14 still requires separate IM. This is not a TCC bypass or a new driver.
Same app executable selects root daemon vs user agent by geteuid().

## Local architecture findings

Kanata submodule currently 79bd7fabb7bbb42315864dda7e364f5eafee2630.
New worktree submodule is not initialized; preserve original submodule checkout.
`External/kanata/src/oskbd/macos.rs`: KbdIn::new calls ensure_input_monitoring_permission
BEFORE ensure_accessibility_permission, before driver_activated. It requests IM on
unknown and rejects denied. Mouse capture already uses active CGEventTap; mouse
output uses CGEvent post (HID tap location).
KeyPath `PermissionOracle` Kanata status reads explicit TCC AX/IM (read-only) and
requires both. KeyPath own IM is soft, its AX remains hard. An AX-derived effective
HID grant may be missed by explicit-row logic: inferred, needs runtime verification.
PermissionOracle is canonical owner; do not add unrelated direct permission checks
to product code.

Karabiner-DriverKit-VirtualHIDDevice deliberately accepts root clients; socket is
`/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock`.
KeyPath KanataHostBridge.swift explicitly rejects nonroot output if directory root-only.
DriverKit dependency source cached at
`~/.cargo/git/checkouts/driverkit-8a31868619f335a0/9fcaf6f/`.
A broker narrows root code but does not remove driver/extension/admin approval.
Do not chmod open the socket as a proposed security solution.

Existing bridge supports passthrough Kanata engine input/output via C ABI:
`Rust/KeyPathKanataHostBridge/include/keypath_kanata_host_bridge.h`.
`passthru-output-spike` feature builds simulated input/output and starts real
Kanata processing loop, intentionally bypassing KbdIn. Installed dylib in
`/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib`
may already enable this (default build script feature); verify by calling ABI.
This is likely the smallest driverless prototype: active session CGEventTap →
passthrough engine → CGEvent output, tag generated events to avoid recursion,
translate modifier flags and keycodes correctly, watchdog/release on failure.

## Useful commands

```sh
cd /private/tmp/keypath-permission-footprint
vm-lab --host mini keypath status cbx_bb5740605b15
python3 Scripts/experiments/permissions/lab.py cbx_bb5740605b15 run \
 'open -n "$HOME/Applications/Permission Probe.app" --args --check-only; sleep 1; cat "$HOME/permission-probe.log"' \
 --log evidence/ax-approved-postcondition.log
python3 Scripts/experiments/permissions/lab.py cbx_bb5740605b15 run \
 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"; sleep 1; peekaboo inspect-ui --app "System Settings" --json' \
 --log evidence/im-after-ax.log
python3 Scripts/experiments/permissions/lab.py cbx_bb5740605b15 root 'id' --log evidence/root.log
python3 Scripts/experiments/permissions/lab.py cbx_bb5740605b15 key 24 --log evidence/native-q.log
# key is X11/Parallels native code, 24=q; delivered event is virtual-device input,
# not proof of physical USB/Bluetooth HID support.
env PROBE_SIGN_IDENTITY='Developer ID Application: Micah Alpern (X2RKZ5TG99)' \
 bash Scripts/experiments/permissions/build-probe.sh '/private/tmp/Permission Probe.app'
vm-lab --host mini keypath artifacts cbx_bb5740605b15
vm-lab --host mini keypath destroy cbx_bb5740605b15
```

## Next work / final deliverables

Continue paths in user-specified order: HID consolidation, identity/update ownership,
narrow broker, optional driverless prototype using actual Kanata engine, hidutil.
Test neither/AX-only/IM-only/both with normal UI and independent fresh processes.
Automation grants must remain separate. Add version/hash/UID/launch evidence.
HID baseline may be blocked by absent keyboard IOHIDDevice; record it and continue
event-tap experiments. Do not equate synthetic CGEvent or virtual-device events with
physical hardware proof. Preserve SIP/TCC/system-extension protections.
Deliver recommendation, before/after requirement table, verified/failed/inferred/
untested matrix with reproduction/logs, limitations, customer steps removed,
prototype commit/rerun/effort, separate Kanata upstream and KeyPath recommendations.
Include Karabiner driver/service recommendation per latest steering.
