# KeyPath automation progress log

This is the durable evidence log for the active KeyPath automation-lab work.
The attached Codex heartbeat reviews it every 20 minutes and appends a new
checkpoint while work is active.

## Progress standard

A checkpoint counts as **advanced** only when there is new, verifiable evidence:
a completed milestone, a changed test result, a newly isolated failure, or a
different bounded next step. Commands run, elapsed time, and repeated attempts
do not count by themselves.

A checkpoint is **looping** when the same blocker or materially identical
attempt repeats without new evidence. When that happens, stop repeating the
approach, record why it is exhausted, and choose a materially different safe
next step.

## 2026-07-24 22:09 PDT — baseline

- **Outcome:** advanced
- **Completed milestone:** The lab mini's Screen Sharing disconnect behavior was
  isolated as the cause of the unexpected host relock and disabled. The native
  Peekaboo lab-host launcher is installed in a fresh macOS 27 candidate.
- **Evidence:**
  - `keypath-lab-mini` is reachable over SSH.
  - `/Library/Preferences/com.apple.RemoteManagement RestoreMachineState` reads
    `0`.
  - `/usr/bin/caffeinate -d -i -m -s` is active on the mini.
  - Dashboard branch `codex/lab-state-dashboard` is clean at `a9af69657`.
  - Automation branch `codex/macos-27-desktop-base` is clean at `df51458b3`.
  - Candidate `cbx_adb383f1f5d2` reached a logged-in desktop after keychain reset
    and reboot; its native Peekaboo host launches, but Accessibility and Screen
    Recording remain unapproved.
  - The guest Sharing pane shows Screen Sharing enabled. The RFB automation
    probe reaches the guest but fails authentication, which confirms transport
    without proving control.
- **Current blocker:** Guest Remote Management is not yet enabled/configured, so
  we do not have an authenticated remote-control path for granting and testing
  the two guest permissions.
- **Next action:** Use the supported guest Sharing UI to replace Screen Sharing
  with Remote Management, then repeat the RFB probe. If it authenticates, use
  that path to grant and verify Peekaboo permissions. If it fails differently,
  record the exact new failure before choosing the next route.
- **Loop check:** not looping. The work moved from an unexplained host-lock
  failure to a verified host fix and a narrower guest-control gate.

## 2026-07-24 22:53 PDT — checkpoint 1

- **Outcome:** looping
- **Completed milestone:** Guest Screen Sharing was replaced with Remote
  Management through the supported System Settings UI. Remote Management and
  its VNC-password option are on, so the baseline blocker is cleared.
- **Evidence:**
  - Active lease `cbx_adb383f1f5d2` remains ready on macOS 27 resource
    `9b5c8578-3f31-46c1-bb29-c7b26d2cf691`.
  - The mini is reachable, `RestoreMachineState` remains `0`, and caffeinate is
    active.
  - The live Sharing pane shows Remote Management on.
  - CrabBox source confirms Parallels reads
    `/var/db/crabbox/vnc.password`; a secret-safe comparison proved that file
    exactly matches the current eight-character encrypted lab credential.
  - Three `secure-console-submit` attempts were recorded at 22:25, 22:27, and
    22:47 PDT, but RFB authentication did not change.
  - Parallels 26.4.0 accepts explicit JSON `press` and `release` events. The
    helper now emits one paced event batch and reports delivery separately from
    its unverified credential postcondition.
  - `bash Scripts/lab/tests/keypath-lab-tests.sh` passes, including the
    credential-leak and unsupported-character guards.
- **Current blocker:** The Remote Management UI password is not yet proven to
  equal the lease credential. RFB therefore still lacks an authenticated
  control path for the native Peekaboo host approvals.
- **Next action:** Do not repeat the old per-key helper. Have the user invoke
  the corrected batched helper while the VNC password field is focused, then
  make one RFB probe the postcondition. If that fails, inspect the resulting
  field length and RFB security negotiation rather than typing again.
- **Loop check:** looping was detected and stopped. Repeating the old helper
  produced transport-success messages without a changed RFB result; the
  materially different path is a tested single-batch press/release transport
  plus an independent RFB postcondition.

## 2026-07-24 23:09 PDT — final trial checkpoint

- **Outcome:** advanced
- **Completed milestone:** The one-hour audit trial caught and stopped a real
  credential-delivery loop, produced a tested transport correction, and
  separated delivery from authentication proof.
- **Evidence:**
  - Automation commit `a58deadc9` replaces separate ambiguous key submissions
    with one paced batch of explicit press/release events.
  - `bash Scripts/lab/tests/keypath-lab-tests.sh` passes, including the
    secret-leak, unsupported-character, and no-event-on-encode-failure checks.
  - Dashboard commit `c516a288b` records Remote Management as enabled, clears
    the stale host-lock blocker, and leaves M11 calmly waiting instead of
    showing unproven activity.
  - The live Remote Management detail sheet is open with the password field
    targeted. No credential was entered by the agent.
- **Current blocker:** Credential entry is a required user handoff. The live
  RFB authentication postcondition has therefore not yet run against the
  corrected transport.
- **Next action:** The user runs the corrected secure helper with the current
  field targeted and completes the dialog; then run exactly one RFB probe. On
  success, continue to the native Peekaboo permission approvals. On failure,
  inspect field length and RFB negotiation without another blind retry.
- **Loop check:** the repeated approach remains stopped. No further credential
  attempt occurred after the course correction.
- **Trial assessment:** The audits were useful: they exposed three materially
  identical attempts that had been mislabeled as success and forced a
  postcondition-driven correction. The audit itself added roughly ten minutes
  of evidence collection and dashboard/log maintenance during this hour.
  Recommendation: pause the recurring 20-minute loop now. Reuse a lighter
  milestone-triggered audit, or a 30-minute cadence only during long,
  failure-prone lab sessions, instead of keeping this heartbeat permanently.

## 2026-07-25 05:28 PDT — M11 completion checkpoint

- **Outcome:** advanced
- **Completed milestone:** M11 now has a reusable macOS 27 Desktop Automation
  Base proven from a brand-new CrabBox lease, rather than only from the VM used
  to prepare the base.
- **Evidence:**
  - Automation commits `a9770d166` and `3662660c6` route macOS 27 desktop
    leases to `keypath-macos-27-desktop` and verify that the inherited
    `/dev/console` user is `keypathqa`.
  - The reusable Parallels source is `KeyPath macOS 27 Desktop Base`, UUID
    `a7beee48-6dae-4809-9f6f-6382c90b3c3f`.
  - Fresh lease `cbx_45cd7ed5cd38` was created from that source on macOS 27
    build `26A5378j`; its manifest records passed inherited-console and desktop
    bootstrap checks.
  - An independent RFB probe moved the fresh guest pointer from `(10,10)` to
    `(640,360)`.
  - The fresh clone passed the fail-closed macOS 27 selector driver for the
    Accessibility surface and the signed `Peekaboo Lab Host`.
  - Final evidence was collected under
    `artifacts/cbx_45cd7ed5cd38/20260725T122639Z`.
  - The full `Scripts/lab/tests/keypath-lab-tests.sh` suite passes.
- **Current blocker:** none for M11. P02 remains separately blocked on the
  onsite physical mWave USB proof.
- **Next action:** Remove only the disposable validation lease, preserve the
  reusable base, and select the next automation issue that can advance
  remotely.
- **Loop check:** not looping. Treating a formal Parallels template as a
  CrabBox source failed once; registering the same backed-up base bundle as a
  normal stopped source was a materially different correction, and the next
  fresh clone passed end to end.

## 2026-07-25 06:39 PDT — R01 managed Accessibility completion checkpoint

- **Outcome:** advanced
- **Completed milestone:** R01 is proven on a fresh randomized macOS 15
  managed-functional clone, and the exact signed KeyPath app is installed.
- **Evidence:**
  - Lease `cbx_a6d8a327390c` enrolled with a unique clone identity and
    acknowledged the PPPC, system-extension, and service-management profiles.
  - Independent lane verification reported three profiles and
    `verification passed`.
  - Installer admission reported `artifact_policy passed`, proving the staged
    build matches the identities encoded in those profiles.
  - The installed CLI reported `keyPathAccessibility: true` and
    `keyPathInputMonitoring: true`.
  - Commit `0c91bf811` replaces synthetic protected-field typing with
    stdin-only native RFB key delivery, clears interrupted values safely, uses
    a real RFB submit click, and requires the SecurityAgent sheet to close.
  - The full `Scripts/lab/tests/keypath-lab-tests.sh` suite passes.
- **Current blocker:** R01 has none. The broader managed-capabilities scenario
  is red because the fresh clone does not yet have the privileged helper,
  DriverKit extension, Kanata daemon, or VirtualHID runtime installed and
  running.
- **Next action:** exercise the supported KeyPath system install/repair path on
  this admitted clone, then rerun the independent managed-capabilities and TCP
  probes.
- **Loop check:** not looping. The failed display-scale probe exposed an
  undeclared Peekaboo path dependency; it was replaced with an AppKit-only
  scale measurement, and the next protected-sheet attempt passed.

## 2026-07-25 07:08 PDT — R03/R04 runtime completion and M01 defect checkpoint

- **Outcome:** advanced
- **Completed milestone:** R03 runtime convergence and R04 TCP readiness pass
  independently on fresh lease `cbx_a6d8a327390c`.
- **Evidence:**
  - KeyPath CLI reports the helper as installed, version `1.1.0`, fresh, and
    working.
  - KeyPath and Kanata both report Accessibility and Input Monitoring granted.
  - `systemextensionsctl` reports
    `org.pqrs.Karabiner-DriverKit-VirtualHIDDevice` activated and enabled.
  - The second state-aware installer pass completed
    `start-karabiner-daemon` and `install-required-runtime-services`, with all
    recipe postconditions satisfied.
  - `Scripts/lab/scenarios/installer-scenario managed-capabilities
    managed-functional` reports `managed_capabilities passed`, including the
    independent `127.0.0.1:37001` TCP probe.
  - Commit `2da2f8d80` adds fail-closed stdin-only protected input for System
    Settings authorization sheets; the full lab shell test suite passes.
- **Current blocker:** M01 exposed a product defect in clean-install ordering.
  The first installer pass successfully installs components and activates the
  DriverKit extension, then `activate-vhid-manager` fails because
  `/Library/LaunchDaemons/com.keypath.karabiner-vhiddaemon.plist` is not
  installed until the later `install-required-runtime-services` recipe.
- **Next action:** fix the recipe ordering or narrow the premature
  postcondition, then create a fresh managed clone and require one installer
  pass plus the independent managed-capabilities scenario.
- **Loop check:** not looping. The second installer invocation was based on a
  materially changed state and dry-run plan; it proved convergence, while the
  preserved first-pass failure identifies the exact single-pass defect.

## 2026-07-25 08:49 PDT — M01 one-pass clean install proven

- **Outcome:** advanced
- **Completed milestone:** M01 passes on fresh randomized macOS 15 managed
  lease `cbx_ce33c403f2f2` with exactly one installer invocation.
- **Evidence:**
  - Product fix `ef09ad7b7` passed 41 focused regression tests and was packaged
    as the exact admitted signed candidate.
  - The fresh clone completed managed admission before KeyPath was allowed to
    mutate installer state.
  - The wizard established the privileged helper and independently showed
    KeyPath plus `kanata-launcher` Accessibility and Input Monitoring green.
  - The single **Fix** invocation completed with `ready=true` and zero blocking
    issues; there was no installer retry.
  - `managed-capabilities` reports `managed_capabilities passed`.
  - `helper-daemon-health` reports `isOperational=true`, no issues, no planned
    recipes, state `Running and TCP responding`, and a valid Kanata TCP
    response.
- **Current blocker:** none for M01.
- **Next action:** preserve the evidence, remove the disposable lease after
  capture, then admit up to two independent tracks: lifecycle scenarios
  (M02/M04/M05) and version transition (M03). Keep M06 after M05 and the matrix
  consumers after their scenario prerequisites.
- **Loop check:** not looping. A stuck splash was traced to the reusable base's
  orphan-cleanup alert intercepting first activation; relaunching after cleanup
  exposed the supported wizard. The installer itself was invoked only once.

## 2026-07-25 09:13 PDT — M02 and M03 parallel admission started

- **Outcome:** advanced
- **Completed milestone:** the repair and upgrade proofs now have committed,
  independently verified, resumable scenario contracts.
- **Evidence:**
  - Product/lab commit `d96bb464b` adds strict ready and degraded runtime
    assertions, a real Kanata LaunchDaemon damage fixture, and a one-attempt
    repair plan.
  - The repair fixture requires a proven-ready runtime before damage, a
    proven-degraded runtime before repair, and independent runtime plus TCP
    readiness afterward.
  - The official signed `v1.0.0-beta3` release fixture has checksum
    `c03dabdb5bcab044d334d8d883d36a5676b9ca9d9974a2a20c2c72b91be1107c`;
    it reports version `1.0.0-beta3`, build `3`, and the expected KeyPath team
    and bundle identity.
  - The exact candidate reports version `1.0.0`, build `4`, checksum
    `4ac130b8dee382ae6f14532f4f5d137071619fa68a4b7a23ad9f63785d3882d7`,
    and the same expected identity.
  - The lab harness, scenario-runner, result contract, and new runtime-state
    tests pass.
  - Separate managed macOS 15 and macOS 26 lease creations are active; both
    are still transferring their admitted archives before clone mutation.
- **Current blocker:** none. Archive transfer and managed clone admission are
  still in progress and have not yet produced lease IDs.
- **Next action:** wait for both admissions, install their staged artifacts,
  then execute M02's red-to-green repair proof and M03's beta3-to-current
  transition independently.
- **Loop check:** not looping. The work replaced two false-positive harness
  gaps (healthy-state “repair” and no real upgrade fixture) with materially
  stronger proofs before consuming VM capacity.

## 2026-07-25 10:34 PDT — M03 upgrade proven

- **Outcome:** advanced
- **Completed milestone:** M03 proves the signed `1.0.0-beta3` to exact
  `1.0.0` transition on protected managed macOS 26 lease
  `cbx_f0e00e78cdd7`.
- **Evidence:**
  - The archive identity includes the fixture checksum, preventing a stale or
    substituted upgrade artifact from sharing an admitted archive key.
  - Host-controlled fixture installation passed the managed lane and exact
    artifact-policy checks without placing guest credentials in the scenario.
  - Independent version reads reported `1.0.0-beta3` before upgrade and
    `1.0.0` afterward.
  - Strict deep code-signature verification passed on the resulting
    `/Applications/KeyPath.app`.
  - Evidence was collected under
    `artifacts/cbx_f0e00e78cdd7/20260725T172501Z`, then the disposable lease
    was destroyed.
- **Current blocker:** none for M03.
- **Next action:** keep M03 complete and use its result as a version-transition
  prerequisite for the later pairwise scenario matrix.
- **Loop check:** not looping. The initial guest-only install exposed the
  expected privilege boundary; the replacement host-controlled fixture path
  was a materially different, policy-checked route and completed the proof.

## 2026-07-25 10:34 PDT — M02 product defect fixed; fresh proof human-gated

- **Outcome:** advanced
- **Completed milestone:** M02 reproduced a real repair failure, isolated its
  cause, and produced a tested fix in commit `ce7441fd`.
- **Evidence:**
  - The original clone reached a proven managed runtime, was deliberately
    degraded by booting out `system/com.keypath.kanata`, and failed its one
    allowed repair attempt.
  - Logs showed `SMAppService.unregister()` succeeded, but an optional legacy
    `launchctl bootout` failed through the authorization boundary and aborted
    the flow before re-registration.
  - The fix treats that stale-job cleanup as best effort after successful
    SMAppService unregister, while leaving registration and health checks
    fail-closed.
  - The complete lab shell suite, focused scenario suites, 21
    `ServiceBootstrapperTests`, the production build, signing, and identity
    contract pass.
  - Fresh exact-build lease `cbx_a9262dab5a98` is live with commit
    `ce7441fd` and candidate checksum
    `f81587e5c8b15007c9b1a5f1e7dac13bfc087262b7631fa0e7c9a9b3c9b832d7`.
- **Current blocker:** Apple's protected Device Management password sheet
  requires a human-entered guest password. Tart VNC did not deliver input to
  the SecurityAgent secure field.
- **Next action:** have the remote operator type the guest password into the
  already-open enrollment sheet and click **Enroll**; then finish managed
  admission, install the exact fixed candidate, and require
  ready → damaged → one repair → independently ready.
- **Loop check:** not looping. Automated protected-field input has already
  failed with direct visual evidence and will not be retried. Human entry is
  the materially different next step.
