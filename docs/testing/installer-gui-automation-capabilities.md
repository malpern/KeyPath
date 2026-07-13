# Installer GUI Automation Capabilities

This is the handoff document for agents running KeyPath installer QA in the
disposable CrabBox lab. Read it with
[`remote-installer-lab.md`](remote-installer-lab.md).

## The important distinction

macOS requires several approvals to occur in a logged-in GUI session. That does
not mean a human must perform every click. The lab may automate the real System
Settings UI, but it must not edit the TCC database, replace approval state, or
claim success from a click alone.

Use this order for GUI work:

1. Peekaboo semantic discovery and interaction.
2. Fresh Accessibility geometry plus CrabBox native RFB input when a protected
   control rejects semantic clicks.
3. A canonical system, CLI, process, or runtime postcondition after every
   interaction.

Never reuse coordinates from an earlier lease or a scaled screenshot preview.
The July 2026 macOS 15 Tart run exposed a deceptive display report: the backing
display reported `2048x1536`, but both Peekaboo Accessibility bounds and the
CrabBox VNC input viewport used `1024x768`. The correct RFB target was therefore
the AX point itself, not that point multiplied by two. An agent must compare
fresh AX bounds with the actual input viewport for every lease; backing-display
dimensions alone are not a coordinate transform.

Treat the coordinate transform itself as test evidence. A July 2026 run showed
that CrabBox can report a successful RFB click even when an unverified transform
lands on a different System Settings control. Every protected click must
therefore record the current framebuffer dimensions and AX window bounds, assert
the expected System Settings page immediately before delivery, and assert the
expected page (or explicitly expected dialog) immediately afterward. A changed
page is a harness failure; never continue to password entry or report the
permission as granted.

Pass Accessibility coordinates to `keypath-lab protected-click` with `--ax-x`
and `--ax-y`. The controller measures the guest's native and logical display
dimensions and applies the scale itself. Reserve raw `--x` and `--y` coordinates
for diagnostics where the native framebuffer point is already known.

## Current capability matrix

| Gate | Human required? | Current automation path | Required proof |
| --- | --- | --- | --- |
| Logged-in GUI session | Depends on base image | Tart desktop leases have produced usable logged-in sessions. If a lane opens at login, configure automatic login in its disposable base or drive that login through RFB. Do not run the GUI installer as headless root. | Desktop snapshot plus a process launched in the console user's session |
| Accessibility | No inherent human requirement | Operate the real Privacy & Security UI with Peekaboo; use RFB if the protected control rejects AX actions. Do not modify TCC directly. | `PermissionOracle`/system inspection reports granted for the correct signed app |
| Input Monitoring | No inherent human requirement | Same real-UI path. Peekaboo can discover controls; RFB can deliver the approval click. | `IOHIDCheckAccess`-backed KeyPath inspection and live keyboard capture |
| Full Disk Access | No inherent human requirement | Same real-UI path, including file selection when the app must be added. | KeyPath's canonical FDA check after relaunch if required |
| Driver/System Extension | No inherent human requirement | Open Login Items & Extensions semantically, locate the current row, then use fresh native RFB coordinates when the switch ignores semantic input. | VirtualHID extension state and functional device readiness |
| Login Items/Background Activity | No inherent human requirement | Operate the actual Login Items UI with Peekaboo or RFB. | Current `SMAppService` status plus launchd, process, and TCP evidence |
| Authentication/keychain sheet | No | `keypath-lab secure-dialog-input` streams `KEYPATH_TART_ADMIN_PASSWORD` through the lease-owned SSH channel into Peekaboo's MCP `type` tool. | Sheet closes and the protected setting changes |
| KeyPath GUI installer | No, once a desktop session exists | Launch and operate KeyPath inside the logged-in console session. Root may install files, but headless root cannot perform the app-owned `SMAppService` registration flow. | Installer state matrix and runtime postconditions |
| Overlay and keyboard behavior | Partly | Capture screenshots, inspect AX state, send test input, and verify runtime events automatically. Human review remains useful for subjective visual quality. | Screenshot/evidence plus observed input and overlay state |
| Reboot, services, trust, logs, artifacts, cleanup | No | Existing lab commands and scenarios | Post-reboot CLI inspection, signature/Gatekeeper results, logs, artifact manifest, and destroyed lease |

“No inherent human requirement” describes what the supported UI automation can
do. It does not mean every gate is already composed into one unattended
scenario. The remaining engineering task is orchestration and per-OS selector
hardening, not a macOS security bypass.

## Core capability inventory

The lab already has the reusable foundations for immutable signed inputs,
disposable lane-aware leases, provider-capacity admission, logged-in desktop
sessions, semantic AX interaction, guarded RFB clicks and typing, secret-safe
authorization, canonical permission/service checks, screenshots and artifacts,
and owned cleanup. P01 additionally proves that lease-owned RFB input reaches
KeyPath's intended user-session capture host without hardware.

The remaining core capabilities are:

1. P02 functional output proof: attribute an observed remapped VirtualHID event
   to a known captured input.
2. Complete runtime convergence assertions: Accessibility/Input Monitoring for
   the intended runtime, Kanata running, and TCP readiness must agree across
   product and independent evidence.
3. The deterministic managed lane: Apple certificate, NanoMDM enrollment,
   profile publication, managed-base proof, and unique clone identity.
4. A resumable scenario runner with differential assertions, explicit failure
   ownership, sanitized artifacts, and consolidated machine-readable results.
5. Hardened macOS 26 and macOS 27 selectors before those OS versions can claim
   the same unattended UI coverage as macOS 15.

Clean install, repair, upgrade, reboot, uninstall, reinstall, cancellation,
nightly, and pairwise entries are consumers of those foundations. They are
important scenario coverage, but they are not separate low-level physics or
orchestration primitives.

## Supported tools

Create a desktop lease and use the typed guest adapter for evidence-producing
semantic operations:

```bash
Scripts/lab/keypath-lab create \
  --macos 15 --lane unmanaged-ui --commit "$SHA" --installer dist/KeyPath.zip --desktop

Scripts/lab/keypath-lab nameplate "$LEASE" enable

Scripts/lab/keypath-lab run "$LEASE" -- \
  Scripts/lab/peekaboo-ui snapshot \
  --app 'System Settings' \
  --output .keypath-lab/scenario-output/approvals/system-settings.json
```

The optional Nameplate label is click-through operator instrumentation. It is
installed only in the disposable guest, never in a base image. Keep it visible
while choosing or attaching to a lease, then hide it around scenario-owned
screenshots. The controller's `artifacts` command performs that hide/restore
automatically. Nameplate launch-at-login remains disabled so its own
`SMAppService` registration cannot affect KeyPath Background Items evidence.

For a password sheet on the Tart lane:

```bash
Scripts/lab/keypath-lab secure-dialog-input "$LEASE" \
  --app 'System Settings' \
  --field Password \
  --submit 'Modify Settings'
```

Peekaboo's MCP `type` result echoes typed text. The secure command suppresses
that entire response. With `--submit`, the command also waits for both the named
field and submit control to disappear; the protected setting still needs its
canonical postcondition. Never reproduce the MCP call through `keypath-lab run`,
put a password in an argument, or collect its output.

For an AX-resistant control, take a fresh semantic snapshot, read the native
framebuffer size, calculate the current scale, deliver a CrabBox desktop click
in native framebuffer pixels, and verify the resulting state. A click result is
delivery evidence, not approval evidence.

## Orchestrator architecture contracts

### The product owns planning

The orchestrator must not become a second installer planner. Its selector reads
the product's own `keypath-cli system inspect --json` result, including
`plannedRecipes` and `userActionRequired`, and executes only the user-shaped UI
portion of that plan. If the harness needs planner information that the CLI does
not expose, extend the CLI contract rather than reproducing installer decisions
in lab code.

Record the product's `runID`, `planID`, and before/after snapshot IDs in the lab
timeline. These IDs join a failed lab action directly to product telemetry and
must survive artifact collection.

### Harness retries are not product retries

The runner may retry a failed screenshot, stale semantic snapshot, or
undelivered RFB action. Those are harness transport retries and must be recorded
as such. If the product reports that an installer action succeeded but its
postcondition is absent, rerunning the product action is not a transparent
retry; it is a product finding.

Scenarios are strict by default. More than one product convergence iteration is
reported as a warning or failure according to the scenario. A scenario may opt
into forgiving convergence when it is intentionally testing recovery, but the
report must retain every attempt.

### Assertions are differential

Promote the capability matrix's Required proof column into an `assert-state`
schema with three values for every gate:

```yaml
input_monitoring:
  claimed: granted
  observed: granted
  agreement: true
```

`claimed` comes from KeyPath's inspection and installer report. `observed`
comes from independent OS, process, launchd, TCP, extension, input-event, or UI
evidence. Disagreement is a first-class product failure even when the final
desired value appears true in one source.

### Failure ownership is explicit

Every failed step must use one of these top-level classifications:

- `keypath-product-failure`
- `harness-selector-failure`
- `harness-transport-failure`
- `provider-failure`
- `unsupported-os-selector`
- `environment-precondition-failure`

A self-test with a deliberately incorrect selector must prove that it produces
`harness-selector-failure`, never a KeyPath failure.

### Fixtures reproduce reality when possible

Create starting states through the path that produces them in real use: install
an older release before an upgrade, interrupt a real operation, disable a real
service, or reboot at the relevant boundary. Direct mutation is permitted only
when a realistic recipe is impractical. Mark such fixtures `synthetic: true`,
record every mutation, and verify the resulting state with the same differential
`assert-state` used by normal scenarios.

## Physics checkpoints

P01 is proven on a Tart macOS 15 guest: a lease-owned CrabBox VNC/RFB key event
reached KeyPath's intended user-session input host and appeared in Input Capture
Experiment. This proves the software-only input transport and KeyPath capture
path. It does not grant or prove the separate raw `kanata-launcher` legacy
recovery runtime.

P02 remains: activate the complete runtime path and prove that the healthy
VirtualHID Driver Extension produces observable remapped output from that
captured input, not merely an installed, enabled, or device-healthy status.
The first unmanaged macOS 15 attempt reached the genuine Driver Extensions
control but remained `activated waiting for user`; its evidence and managed-lane
resume criteria are in [P02 VirtualHID output proof](p02-virtualhid-output-proof.md).

If virtual output cannot be observed in the VM, retain the VM lane for
installer, repair, and state testing and add an explicitly separate
physical-device lane for that functional probe. Do not weaken the functional
assertion to make the VM pass.

## What remains to build

The next lab slice should implement a resumable approval orchestrator that:

1. Confirms a logged-in console user and launches KeyPath in that session.
2. Reads the product's `plannedRecipes` and `userActionRequired` to select the
   next user-shaped action without duplicating product planning.
3. Captures before-state evidence.
4. Tries a semantic Peekaboo action, then a freshly calculated RFB fallback.
5. Uses `secure-dialog-input` only when an authentication sheet is present.
6. Re-inspects claimed and independently observed state. It may retry harness
   delivery, but treats missing product postconditions as findings.
7. Reboots, verifies persistence, collects sanitized artifacts, and destroys
   the owned lease.

Implement selectors separately for macOS 15, 26, and 27. Do not encode one
version's System Settings hierarchy or coordinates as a universal sequence.

Build in this order:

1. Run the two Tart functional-physics checks.
2. Add the console-session bootstrap contract and selector-misclassification
   self-test.
3. Build the strict, product-plan-driven approval orchestrator and macOS 15
   golden path.
4. Add differential `assert-state` and functional usage probes.
5. Add reality-recipe fixtures and self-verifying per-OS drivers.
6. Add resumability, then the pruned matrix scheduler and consolidated report.

## Matrix execution policy

Do not run the full cross-product. Maintain a curated core diagonal that covers
every installer state-matrix row at least once, targeted at roughly twenty
nightly scenarios. Generate pairwise combinations for a slower weekly run.
Keep the matrix off the pull-request path until runtime and flake measurements
justify a smaller smoke subset.

The scheduler must respect provider capacity, support a scenario obtaining a
fresh lease when isolation requires it, and check the two-hour lease TTL against
the predicted reboot-inclusive runtime before starting. Cleanup remains a
mandatory finalizer for every owned lease.

## Hard boundaries

- Never write or copy a TCC database.
- Never treat `SMAppService.status == .enabled` as runtime readiness.
- Never store passwords, decrypted secrets, private keys, or MCP type responses
  in logs or artifacts.
- Never reuse raw screen coordinates across leases.
- Never report an approval from click success alone.
- Never mutate a base image while diagnosing a disposable clone unless the
  explicit task is to build a new versioned base.
