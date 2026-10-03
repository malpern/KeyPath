# macOS permission footprint investigation — 2026-10-03

## Recommendation

Develop a **driverless, user-session Kanata backend as the default installation path**. Retain the DriverKit backend as an optional advanced path. This best fits the requested priority: seamless installation, with password/Secure Input remapping limitations accepted.

The disposable macOS 26.5.2 guest demonstrated actual Kanata processing through a session event tap and CGEvent output, running as UID 501 with Accessibility alone and **zero system extensions**. A native virtual-keyboard q became a in the foreground target; a Kanata tap-hold configuration produced q on tap and Control+a on hold. This establishes feasibility, not production readiness or physical-keyboard coverage.

Also adopt Karabiner's Accessibility-first permission flow in the existing backend. A separate Input Monitoring approval should be requested only when the **same executable identity's effective IOHID access** remains denied after Accessibility approval. Keep this capability requirement; remove the unconditional extra customer step where macOS already covers it.

## Customer installation requirements

| Requirement | Current driver-backed KeyPath/Kanata | Proposed driverless default | Optional driver-backed path |
|---|---|---|---|
| App installation | App plus privileged output infrastructure | Signed app in user-accessible Applications | App plus privileged infrastructure |
| Accessibility | Required for relevant engine identity | One stable remapper app identity | Required |
| Separate Input Monitoring step | Current Kanata requests it first; KeyPath expects explicit AX and IM | No separate step in verified guest; conditional fallback on other systems | AX first, then effective IOHID check and conditional IM |
| Administrator authentication | Helper/driver installation and Settings approval | Settings approval still used administrator authentication in this guest | Still required for privileged installation |
| Driver extension approval | Required for virtual HID output | Removed | Still required |
| Privileged daemon/background service | Driver output requires root infrastructure | Removed from remapping architecture | Still required |
| Start at login | Existing service arrangement | Optional ordinary user-session registration | Existing user and privileged service arrangement |
| Secure Input/password fields | Driver architecture may cover cases event taps cannot; not tested here | Original keys pass through; remapping pauses | Preserve as advanced capability, subject to hardware testing |

The driverless design removes the root installer/helper and driver-extension approval from the normal path. It does **not** remove macOS consent or promise a password-free Accessibility approval.

Karabiner's current installation documentation still lists background services and Driver Extension approval alongside Accessibility/effective Input Monitoring. Its consolidated permission flow is useful independently of its driver architecture. See [Karabiner installation](https://karabiner-elements.pqrs.org/docs/getting-started/installation/) and [security architecture](https://karabiner-elements.pqrs.org/docs/help/advanced-topics/security/).

## Verified permission and behavior matrix

All product probes were signed disposable app bundles launched independently with `open -n`, rather than direct children of the SSH/provider automation process. START records show UID 501 and parent PID 1. `listen=0` means effective IOHID ListenEvent access granted; 1 denied; 2 unknown. Settings grants/revocations used normal UI, never TCC writes.

| State / experiment | Fresh-process evidence | Functional result | Classification / raw evidence |
|---|---|---|---|
| Neither permission | PID 3647, AX 0, listen 1; engine starts; active tap absent | q reaches target unchanged; engine input/output 0 | Verified — `neither-engine-retest-start.log`, `neither-engine-result.log` |
| Accessibility only; no separate IM entry | PID 2576, AX 1, listen 0; active tap created | q → actual Kanata → a; input 2, output 2, tagged 2; target length 1, no q | Verified — `ax-only-engine-start.log`, `ax-only-engine-result.log`; IM pane showed No Items |
| Both explicit approvals | PID 3307, AX 1, listen 0 | Same real-engine q → a result | Verified — `both-engine-start.log`, `both-engine-result.log` |
| IM only after AX revoked | PID 3487, AX 0, listen 0; active modifying tap absent | q unchanged; engine input/output 0 | Verified — `im-only-engine-start.log`, `im-only-engine-result.log` |
| Home-row modifier tap | PID 3365, AX 1, listen 0 | q tap yields q, input/output/tagged 2 each | Verified — `hrm-tap-result.log` |
| Home-row modifier hold | PID 3422, AX 1, listen 0 | q held 350 ms then a produces one Control+a; input/output/tagged 4 each | Verified — `hrm-hold-result.log` |
| Secure Input in separate foreground process | Remapper PID 2784, AX 1, listen 0; target PID 2788 enables Secure Input | Remapper sees no events, engine input/output 0; target receives original q | Verified controlled case — `secure-engine-start.log`, `secure-engine-result.log` |
| Signed update, same ID/team/path | Version 1 → 2, PID 2694, AX 1, listen 0; strict signature check passes | Grant retained across changed executable hash | Verified — `signed-update-result.log` |
| Different bundle identity, same team | Alternate PID 2752, AX 0, listen 2 initially | No inherited grant | Verified — `alternate-identity-result.log` |
| `hidutil` static mapping with neither grant | PID 3741, AX 0, listen 1, no Kanata runtime | q → a in target; mapping explicitly cleared afterward | Verified — `hidutil-set.log`, `hidutil-target-result.log` |
| Raw IOHID capture / seize | IOHIDManagerOpen succeeds but keyboard device count is zero | No raw keyboard callbacks | Inconclusive VM topology, not capture proof |
| Passive IM-only tap | Tap created but test key missed the bounded target interval | No valid capture conclusion | Invalid timing trial — `im-only-passive-result.log`; excluded from conclusions |
| Full Karabiner installer / physical USB, Bluetooth, built-in keyboards | No whole installer or physical device exercised | Unknown | Untested |
| Crash recovery, all modifier/layout/device combinations, login/FileVault | Bounded prototype only | Unknown | Untested |

Reboot findings and final lease disposition are recorded in the completion section below. The report intentionally distinguishes API evidence from UI action success and functional input/output evidence.

## What the prototype actually does

`Scripts/experiments/permissions/probe.m` loads the installed KeyPath bridge dylib and calls its real Kanata passthrough runtime ABI. This bypasses Kanata's `KbdIn` and virtual HID driver while keeping Kanata's configuration parser and processing loop:

```text
Native virtual keyboard
  → active session CGEventTap
  → Kanata passthrough input / processing loop
  → Kanata output queue
  → tagged CGEventPost
  → foreground target
```

Only successfully queued selected input is suppressed. Generated events carry a marker to avoid recapture. The adapter deliberately handles only q, a, and left Control. It records counters and expected-result booleans, not arbitrary typed text. Runs stop after 20 seconds and release held output on clean shutdown.

This is not a full backend: it needs bounded nonblocking queues, event-tap timeout re-enablement, crash/engine-failure fail-open behavior, stuck-key recovery, correct physical and synthesized modifier merging, repeat/layout/media-key coverage, session/login ownership, and complete key translation. Clean-exit releases are not a crash watchdog. Device-specific identification and raw HID suppression are not demonstrated by session event taps.

Secure Input was enabled by a separate unapproved target app, so the remapper could not benefit from owning the protected process. It observed nothing while the target received q. This supports pausing remapping in protected fields; it does not establish every password manager, login window, or FileVault behavior.

## Identity, permissions, and upstream changes

### Kanata

The inspected Kanata checkout is `79bd7fabb7bbb42315864dda7e364f5eafee2630`. In `src/oskbd/macos.rs`, `KbdIn::new` currently checks/requests Input Monitoring before Accessibility, then checks the driver. Change the order to Accessibility first and re-read effective IOHID permission before requesting IM. Unknown access should remain a clearly reported state rather than a fabricated healthy result.

Current Karabiner source at `6029cab0192f428c849e1ead527a9e3d6a39f6ba` launches the **same Core-Service app identity through NSWorkspace in the login user's session** for permission checks. It checks AX and effective IOHID access, prompts AX first, and requests IM only if still needed. The change appeared in commit `bae28b2899d7fd8fbb044b664dee7bf9c659ad7e` and v16.0.0. Source comments distinguish macOS 26 coverage from older systems; this investigation independently confirmed the consolidation on 26.5.2. Do not generalize that observation to every macOS release.

Consider an upstream optional event-tap input/CGEvent output backend. Keep it opt-in until physical-device and failure testing passes. The prototype uses a KeyPath bridge feature and is not a patch to upstream Kanata's production macOS backend.

### KeyPath

Keep `PermissionOracle` as the single product owner. Its current Kanata permission path reads explicit TCC rows and requires both AX and IM; an absent separate IM entry can therefore misrepresent effective access. Its current lookup also uses the launcher path despite a bundle-ID-first comment. Replace that inference with a signed, same-engine-identity permission-check mode launched through NSWorkspace, returning structured identity/version/PID/UID and API results. Probe the actual engine identity rather than treating the GUI's permissions as the daemon's permissions.

Prefer running the bridge and driverless backend inside the signed KeyPath user app process, so its existing Accessibility grant covers that process. A separate helper identity may require another grant and must be tested independently. Use a stable signed app bundle and signing requirement across updates. The same-ID/team/path update retained approval here; another ID signed by the same team did not inherit it. This does not prove moved-path, team-change, or arbitrary helper inheritance. The final remapper placement and bundle identity need their own installation tests.

Gate setup on backend capabilities. A driverless engine should not be blocked by root-only virtual-HID readiness checks. `KanataHostBridge.swift` currently rejects nonroot output when the driver's root-only directory is protected; that remains correct for the driver backend.

### Narrow broker

The driver dependency intentionally uses a root-only socket directory at `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/`. A small root output broker could move configuration parsing and Kanata processing to a user process while allowing only validated output messages over authenticated IPC. This narrows privileged code. It does **not** remove driver installation, extension approval, privileged service consent, or administrator authentication. Do not open the socket directory to all users.

For installation simplicity, prioritize the driverless path over a broker. Use the broker if the optional driver backend still needs privilege separation. No broker or permission weakening was implemented in this investigation.

## `hidutil` alternative

The guest accepted a user-scoped, Virtual Keyboard-matched `UserKeyMapping` from HID usage 20 (q) to 4 (a) without AX or IM. A foreground target independently received a. The mapping was reset to an empty array after the trial.

The immediate `--get UserKeyMapping` returned null even while the functional mapping worked. Treat the target result as the verification, rather than assuming the property read alone reports the service's effective mapping. Apple's [TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html) describes static substitutions, no special privileges, and mappings disappearing when the keyboard service is removed/rebooted. That document is dated; the modern guest functional trial is the evidence for this VM.

`hidutil` is suitable for simple static swaps. It does not replace Kanata layers, tap-hold timing, sequences, or stateful rules, and service matching/persistence across device changes requires separate testing. Do not make it a blanket fallback that silently drops the user's configuration semantics.

## Reproduction and provenance

Base worktree commit: `d5581754c143914727dca827f96439246138fcef`. No production source was modified. Integration checkout and host permissions/security were untouched. Approval policy was verified from the active session configuration as **never**, with unrestricted filesystem access; the user-authorized guest-only scope still applied.

Guest: lease `cbx_bb5740605b15`, Parallels, macOS 26.5.2 (25F84), probe UID 501 / `keypathqa`. SIP was enabled and system extension count zero. Peekaboo/provider automation had separate pre-existing grants; independent app launches and the denied alternate identity control guarded against confusing those grants with product access.

The baseline installed KeyPath app is a September 16 binary, not necessarily the base source revision. Installer archive SHA256: `f1f1043caa4ae8135587703c0d08d6304d6471c82ebbbc81cd7eabc9b93054a3`. Actual bridge dylib SHA256: `106db96220dae50a2f983a0b6c9a69c8422124b0967fc9a25a220da9e0c9ac50`.

Probe identity: `com.keypath.experimental.permission-probe`, Developer ID team `X2RKZ5TG99`. Tested executable hashes:

| Version / purpose | SHA256 |
|---|---|
| Version 1, first successful real-engine adapter | `9903469ed5dbac7e49456e5c07e11f4c22d1f40e7c3587552a59cb2888739db8` |
| Version 2, signed update | `4b105bdfcbf25fc61716882084037dea153e3f2ea812f96f0939ee3994512ff7` |
| Version 2, alternate ID | `59543bb60316be5b1b5711ab52b737818de258e849f5efebc04d593eac7c1d0e` |
| Version 3, HRM and later matrix | `ff324e78e6c67d23c4f3f0da52a3bc09ee003e9c1a57bd92fb18affdfc0c0c80` |

Build uses the locally installed Xcode beta clang, arm64, minimum macOS 15. The prototype is intentionally external to Swift product builds. A new admitted VM needs the baseline bridge installed and normal Settings grants; destroyed leases cannot be rerun.

```sh
env PROBE_VERSION=3 \
  PROBE_SIGN_IDENTITY='Developer ID Application: Micah Alpern (X2RKZ5TG99)' \
  bash Scripts/experiments/permissions/build-probe.sh '/private/tmp/Permission Probe.app'
ditto -c -k --keepParent '/private/tmp/Permission Probe.app' /private/tmp/permission-probe.zip
# After obtaining a new keypath VM through vm-lab and recording its lease:
python3 Scripts/experiments/permissions/lab.py "$LEASE" upload \
  /private/tmp/permission-probe.zip /Users/keypathqa/Applications --log evidence/upload.log
python3 Scripts/experiments/permissions/lab.py "$LEASE" run \
  'open -n "$HOME/Applications/Permission Probe.app" --args --engine --target; sleep 1; tail -5 "$HOME/permission-probe.log"' \
  --log evidence/start.log
# Send immediately, while the bounded target is alive:
python3 Scripts/experiments/permissions/lab.py "$LEASE" key 24 --log evidence/key.log
python3 Scripts/experiments/permissions/lab.py "$LEASE" run \
  'sleep 20; tail -3 "$HOME/permission-probe.log"' --log evidence/result.log
```

Use `--hrm --target` plus `hrm-hold` for the hold test, and the alternate bundle with `--target --secure-target` for the protected foreground target. Consult the handoff and VM lab UI guide before grant manipulation. The controller is specific to this lab/account layout, ownership-checks the lease, and never creates provider VMs directly.

The controller works around two observed lab transport problems in memory: a missing guest-SSH-user default after provisioning the test administrator, and native JSON key events holding keys instead of paired presses/releases. Installed host lab code was not edited. The original handoff's secure-dialog "passed" result was a false positive; actual API/functional verification established approval only after paired-event credential entry. Credentials came through the existing encrypted lab loader. A late retry lost field focus and placed the disposable guest credential in a username field; newly generated diagnostic images were removed and affected local log content redacted. No credential is included in the commit. The controller now refuses its `secure` action before loading credentials; that transport is not safe to reuse until focus and authorization postconditions are reliable. Enrollment account metadata says `keypathmdm`; actual console/probe user remained `keypathqa`, independently checked.

Raw logs remain local under `evidence/` and the VM lab artifact directory. Upload logs include encoded binaries and are intentionally excluded from the prototype commit. The committed sanitized evidence summary contains only probe counters/identity and selected inventory, with source-log hashes for correlation.

## Implementation effort and release gates

Planning estimates, not measured delivery commitments: 2–4 engineering days for AX-first/effective-permission reporting with canonical oracle ownership and signed identity tests; roughly 1–3 weeks for a complete driverless backend, failure handling, setup integration, and focused device testing. A narrow broker is a separate security-sensitive project and does not buy the same reduction in installation steps.

Before defaulting driverless in a release, test built-in, USB and Bluetooth keyboards on physical supported Macs; all modifier combinations/repeats/layouts; tap timeout and engine crash; fast user switching, logout, sleep/wake and reboot; signed updates at the final app path; Secure Input in representative password apps; and fallback setup without silent semantic loss. Real hardware raw HID/seize behavior cannot be inferred from this VM's zero IOHID keyboard devices.

## Completion record

Two guest reboots were observed by changed boot times (10:04:57 and 10:08:13 Pacific). The UID-501 console session returned, SIP remained enabled, and the first reboot inventory still listed zero system extensions. With AX revoked and effective IOHID access still granted, PID 588 created no active tap and q passed through unchanged. This verifies fail-open behavior after reboot in that permission state, **not Accessibility grant continuity or remapping continuity**.

A later Settings authorization succeeded once (PID 1057, AX 1 / listen 0), but subsequent attempts to isolate IM/reapprove AX did not produce a verified restored grant. UI caches and field focus made those trials unreliable. They are excluded from the successful matrix. Sleep/wake and crash recovery remain untested. The screenshot/property action alone is not an approval postcondition.

Final narrow checks: the Objective-C prototype built and signed successfully; shell syntax and Python compilation passed. The final rebuild hash is `eb5730e20a12c8f8d0bc7b2b0c8b0f73a65b5f0e28d9faa3e0102741aeb23543`; it includes only a clarified clean-exit comment after the tested version-3 build and was not substituted into the guest.

Artifacts were collected at `/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_bb5740605b15/20261003T171212Z` on mini. The newly collected screenshot and late UI/command payloads were removed from local/controller artifact records after the credential-focus failure; earlier evidence and sanitized counters were preserved. Potentially sensitive late capture archives were removed from this owned investigation's artifact and capture directories. No other lease or host security state was modified.

Teardown independently verified: lease status `destroyed`, `cleanup_status=complete`, `cleanup_result=0`, and empty provider inventory. The destroy command warned that its optional GitHub Actions hydration stop marker could not reach the guest; resource deletion and final inventory verification succeeded. The experimental worktree remains in place; no PR, push, production deployment, or product-code change was made.
