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

## 2026-07-25 12:00 PDT — M04 trusted-input boundary isolated

- **Outcome:** advanced
- **Completed milestone:** M04 admitted an exact-build managed macOS 26
  Parallels clone and isolated the remaining precondition failure to trusted
  Input Monitoring consent rather than installer, helper, driver, or virtual
  HID setup.
- **Evidence:**
  - Lease `cbx_cd38fd327f7c` is live on macOS 26.5.2 with commit `ce7441fd`
    and the expected installer checksum.
  - The helper is installed, fresh, and working; the Karabiner driver and
    virtual HID device are healthy; KeyPath's Accessibility and Input
    Monitoring checks are true.
  - System Settings visually showed Kanata Engine and `kanata-launcher`
    enabled after synthetic clicks, including after a guest reboot.
  - Canonical runtime status still reports both Kanata permission checks
    false, Kanata not running, and the TCP probe fails with connection
    refused. The visual switch state is therefore not accepted as proof.
  - RFB pointer delivery did not move the guest cursor, and combining a
    synthetic focus click with a native Parallels Space key did not change
    the canonical result.
- **Current blocker:** the current Parallels automation path lacks a trusted
  pointer or focus transport that commits macOS Input Monitoring consent.
  M04 cannot validly test persistence until it begins from an independently
  ready runtime.
- **Next action:** preserve the evidence, stop repeating UI toggles and
  reboots, and implement or prove a trusted Parallels consent-input adapter.
  In parallel-safe work, author the remaining M04 assertion contract and the
  M05/M06 lifecycle harness without claiming their final runtime proofs.
- **Loop check:** not looping. Repeated visual-toggle approaches are now
  explicitly retired because the canonical permission and TCP evidence did
  not change. The next attempt must use a materially different trusted input
  transport or a human console action.

## 2026-07-25 12:05 PDT — M04 proof contract hardened

- **Outcome:** advanced
- **Completed milestone:** commit `26d1c11c4` closes the reboot scenario's
  false-green paths while the trusted-consent transport remains gated.
- **Evidence:**
  - The pre-reboot leg now requires independent runtime readiness and captures
    service status, system inspection, boot marker, and signed app identity.
  - The post-reboot leg refuses to run without same-lease pre-reboot evidence,
    requires the boot marker to change, compares app identity across reboot,
    and requires independent runtime plus TCP readiness.
  - Failures are recorded as a precondition block or KeyPath product failure
    at the exact failed postcondition instead of becoming an ambiguous shell
    exit.
  - The full lab controller test, scenario-result tests, scenario-runner tests,
    and runtime-state tests pass.
- **Current blocker:** no change to the live M04 gate: current remote Parallels
  input cannot commit trusted Kanata Input Monitoring consent.
- **Next action:** prepare the M05 uninstall and M06 reinstall assertion
  contracts remotely, while keeping their final live proof dependent on an
  independently ready managed runtime.
- **Loop check:** not looping. This was new durable harness work and did not
  repeat the failed consent UI approach.

## 2026-07-25 13:53 PDT — M02 one-pass Kanata repair proven

- **Outcome:** advanced
- **Completed milestone:** M02 passed its complete damaged-service repair proof
  on a fresh randomized managed macOS 15 clone using the exact fixed candidate
  from commit `ce7441fd`.
- **Evidence:**
  - Lease `cbx_a9262dab5a98` completed unique-identity enrollment, acknowledged
    all three exact-build profiles, passed managed-functional admission, and
    installed the checksum-bound candidate.
  - KeyPath independently reported the helper, DriverKit components,
    VirtualHID device, Kanata permissions, Kanata process, and TCP channel
    healthy before damage.
  - The scenario booted out `system/com.keypath.kanata` and independently
    recorded `runtime_state\tdegraded`.
  - The checkpointed runner made exactly one repair attempt, recorded the step
    as verified, and independently recorded `runtime_state\tready` afterward.
  - Post-repair service status reports `isOperational=true`, a fresh running
    Kanata service, healthy VirtualHID, no conflicts, and a valid response from
    `127.0.0.1:37001`.
  - Evidence is preserved under
    `artifacts/cbx_a9262dab5a98/20260725T205235Z`, including the pre-damage,
    damaged, runner-state, and post-repair files.
- **Current blocker:** none for M02. M04's trusted Parallels consent boundary is
  separate and unchanged.
- **Next action:** retire the M02 disposable lease and begin M05's uninstall
  contract from a separately admitted, independently ready runtime.
- **Loop check:** not looping. Direct lease-owned RFB and the existing
  secret-safe secure-dialog path replaced the failed Screen Sharing approach;
  each step changed a canonical postcondition, and the final scenario passed.

## 2026-07-25 14:45 PDT — M05 independent assertion catches live-process defect

- **Outcome:** advanced
- **Completed milestone:** M05 reached a fully healthy managed macOS 15
  baseline, executed the supported uninstall once, and converted a previously
  invisible uninstall gap into a committed product fix.
- **Evidence:**
  - Lease `cbx_cc3e5c6f5813` completed randomized managed enrollment and exact
    installer-policy admission.
  - Before uninstall, service status reported the helper, Kanata runtime,
    shared DriverKit extension, VirtualHID device, permissions, and TCP channel
    healthy and operational.
  - The uninstall report said every supported removal step passed; independent
    inspection confirmed the app bundle, helper, and KeyPath launchd state
    were absent and the configuration plus shared driver were preserved.
  - The independent assertion nevertheless found PID 3920 still executing
    `/Applications/KeyPath.app/Contents/MacOS/KeyPath` from the deleted bundle,
    so it correctly refused to record M05 as passed.
  - Commit `bd3e81e08` changes CLI uninstall to close a running KeyPath app,
    wait, force-terminate only if graceful termination does not complete, and
    refuse to uninstall if the app still cannot be closed. The focused CLI
    test and release build passed.
- **Current blocker:** the corrected signed archive is in Apple notarization;
  managed exact-build admission and the M05 rerun wait on its acceptance.
- **Next action:** staple and verify the accepted candidate, create an exact
  managed lease, rerun M05, then execute M06 on that same lease only after the
  uninstall result is independently passed.
- **Loop check:** not looping. The first live uninstall produced new canonical
  evidence, the failing path was identified precisely, and the next attempt
  uses changed product behavior rather than repeating the rejected action.

## 2026-07-25 14:59 PDT — corrected M05 lease ready at external notarization gate

- **Outcome:** unchanged with reason
- **Completed milestone:** replacement lease `cbx_9e1c128d616f` completed
  randomized macOS 15 enrollment and exact-policy admission for commit
  `bd3e81e083dae89797aaa9f4184fc94524907b79` and archive SHA-256
  `579db98e2fe103600fe3f70c25cd6c45e43460db67be6e517790c1a7264a9c88`.
- **Evidence:** all three PPPC, system-extension, and service-management
  profiles were acknowledged; managed-functional verification passed; the
  clone is live at `192.168.64.29` with installation not yet started. The full
  25-test CLI smoke suite, uninstall-state tests, runtime-state tests, six
  scenario-runner tests, and three scenario-result tests pass for the fix.
- **Current blocker:** Apple submission
  `74c86813-2c51-42cd-9383-c53d5c1b3301` is still `In Progress` after the
  bounded 15-minute wait. Installing the unnotarized archive would weaken the
  release-realistic installer gate and is intentionally not accepted.
- **Next action:** query that exact submission. Once accepted, staple and
  verify the candidate, install it on `cbx_9e1c128d616f`, establish independent
  readiness, rerun M05, and execute M06 only after the same-lease M05 result
  passes.
- **Loop check:** not looping. The replacement clone and test evidence are new
  progress; repeated notarization polling stopped at the time boundary, and no
  additional submission will be stacked.

## 2026-07-25 15:41 PDT — M04–M07 lifecycle chain proven

- **Outcome:** advanced
- **Completed milestone:** randomized managed macOS 15 lease
  `cbx_9e1c128d616f` passed reboot persistence, corrected uninstall,
  same-lease reinstall, real cancellation, deliberate degradation, and
  one-pass recovery. M04, M05, M06, and M07 are now proven.
- **Evidence:**
  - M04 captured an independently ready baseline, changed the guest boot
    marker through an owned Tart reboot, retained the exact signed app
    identity, and passed post-reboot runtime, system-inspection, and TCP
    assertions.
  - M05 reran the supported uninstall with commit `bd3e81e08`; the app bundle,
    helper, services, transient user state, and running GUI were absent while
    the configuration sentinel and shared VirtualHID driver remained.
  - M06 installed the exact candidate on the same lease only after the passed
    M05 result, preserved the configuration sentinel, executed one resumable
    convergence step, and returned to independent readiness.
  - M07 commit `4b42b7a71` adds explicit before/after checkpoints. The live
    run captured the genuine uninstall confirmation, delivered Cancel through
    the lease-owned RFB path, verified unchanged app identity, running GUI,
    configuration, and ready runtime, then booted out Kanata, observed the
    degraded state, repaired once, and received a valid TCP response.
  - The complete lab harness test suite passed after the M07 implementation.
- **Current blocker:** none for M04–M07. Apple notarization remains a separate
  release-distribution gate and is not evidence for or against the already
  proven managed functional lifecycle behavior. P02 remains an onsite physical
  keypress case.
- **Next action:** preserve final lease artifacts, then implement M12's
  capacity- and TTL-aware nightly diagonal and M13's deterministic weekly
  pairwise expansion without treating physical-only P02 as an unattended
  pass requirement.
- **Loop check:** not looping. The work crossed six distinct canonical
  postconditions and replaced the obsolete Parallels trusted-input blocker
  with a fully ready randomized Tart lane; no failed action was repeated
  without changed evidence.

## 2026-07-25 16:16 PDT — M12 and M13 matrix contracts proven

- **Outcome:** advanced
- **Completed milestone:** M12 now produces the bounded unattended nightly
  diagonal, and M13 produces the deterministic operator-supervised weekly
  pairwise expansion. The macOS 27 job is packaged as a single unattended
  semantic-selector scenario rather than depending on prearranged UI state.
- **Evidence:**
  - Commit `2f0979739` gives every guest scenario command the pinned user-local
    tool path. A live direct probe returned Python 3.12.13 and Peekaboo 3.9.8.
  - Commits `3b13beacf` and `9c4487ba3` add the macOS 27 Accessibility-pane
    preparation, bounded launch retry, semantic readiness check, and
    fail-closed selector driver invocation.
  - Disposable lease `cbx_b31f2d95334f` passed the packaged scenario on macOS
    27.0 build `26A5378j`. Artifact set `20260725T231532Z` retains the readiness
    snapshot, fresh AX snapshot, permission preflight, OS version, and selector
    contract. The lease was then destroyed and cleanup is complete.
  - The nightly plan contains two unattended jobs in one provider-safe wave:
    local contracts and macOS 27 selectors. Every VM job has a bounded TTL and
    `destroy-owned-lease` finalizer.
  - The operator-supervised weekly plan contains ten jobs in six waves and
    covers all 81 eligible factor pairs. Shared macOS 26 identity work is
    serialized. The physical mWave case remains explicitly excluded.
  - Seven planner tests, the selector-driver tests, the new packaged-scenario
    test, and the complete lab harness suite pass.
- **Current blocker:** none for M12 or M13. P02 remains the sole upstream
  physical boundary; P03 and P04 now correctly show that their managed runtime
  prerequisites are proven and only the onsite mWave output is missing.
- **Next action:** execute the onsite P02 q-to-w proof when physical access is
  available, then capture P03 overlay evidence and P04 launch-to-remap timing
  in the same prepared session.
- **Loop check:** not looping. The work moved from missing Python resolution,
  through a newly exposed System Settings launch race and incorrect private
  token expectation, to a packaged live-passing scenario with retained
  evidence and owned cleanup.

## 2026-07-25 16:30 PDT — final P02-P04 onsite event packaged

- **Outcome:** advanced
- **Completed milestone:** commit `2e7caa66f` converts the three remaining
  physical blocks into one resumable onsite session with separate P02, P03,
  and P04 machine-readable outcomes.
- **Evidence:** the prepare stage refuses to arm unless the explicitly named
  physical keyboard appears in the guest HID inventory, retains only selected
  non-serial device fields, requires independently ready managed runtime, and
  establishes the exact q-to-w rule plus an AX-visible overlay and clean
  TextEdit oracle. The observe stage relaunches KeyPath, focuses TextEdit,
  waits for one held physical q, verifies independent output w, captures
  `keycap-code-12` as pressed or held, and records launch-to-output timing.
  Contract tests prove the all-pass path, missing-HID block, and literal-q
  product-failure path. The complete lab suite passes. A final read-only host
  inventory check found `Product = mWave` and `Manufacturer = Kinesis
  Corporation`; commit `d3e640ea9` uses that exact non-secret match in the
  documented onsite command.
- **Current blocker:** actual completion still requires onsite access to make
  the mWave guest-visible and hold physical q once. No remote or synthesized
  event can satisfy this proof.
- **Next action:** create the owned managed USB lease onsite, run the prepare
  stage, start observe, and hold mWave q until it completes. Retain artifacts,
  destroy the lease, then mark P02-P04 proven only if their result files pass.
- **Loop check:** not looping. This did not retry the rejected Tart VNC,
  synthetic-event, ad-hoc HID entitlement, or USB-only boot routes; it reduced
  the remaining physical work to one admitted event with explicit evidence.

## 2026-07-25 16:47 PDT — final remote USB route audited and closed

- **Outcome:** unchanged with reason
- **Completed milestone:** the remaining post-boot USB-attachment hypothesis
  was resolved from the signed Tart fork and the existing matched live trials.
- **Evidence:**
  - `USBPassthroughManager` attaches a physical accessory only through
    `virtualMachine.usbControllers.first` after the VM reaches the running
    state.
  - Tart can expose that controller only by placing an
    `VZXHCIControllerConfiguration` in the immutable VM configuration before
    startup; there is no supported running-VM controller-add operation.
  - The retained remote A/B work already proved a healthy non-USB macOS 15
    boot and repeated pre-network stalls for every USB-controller variant,
    including removal of Tart's synthetic keyboard.
  - The uncommitted preconfigured-accessory source variant is the already
    rejected pre-start experiment and was left untouched rather than promoted
    or rerun.
- **Current blocker:** P02, P03, and P04 require one onsite session in which
  the mWave is made guest-visible and its physical q key is held once. That
  external physical event cannot be reproduced by remote software without
  invalidating the acceptance test.
- **Next action:** onsite, create the owned managed USB lease, run
  `physical-remap-session prepare`, begin `observe`, hold physical q, retain
  the three result artifacts, and destroy the lease.
- **Loop check:** not looping. The source audit tested a distinct hot-attach
  hypothesis and ruled it out without consuming another VM. Further remote
  USB boot attempts would repeat a proven failure mode and are retired.

## 2026-07-30 08:13 PDT — Sparkle-bundled Kanata update acceptance proven

- **Outcome:** advanced
- **Completed milestone:** notarized KeyPath 1.0.1 build 8 now proves that a
  KeyPath update can replace its bundled Kanata runtime without leaving the
  prior SMAppService registration active or opening a redundant administrator
  authentication prompt.
- **Evidence:**
  - Commits `fcb2cbfd4`, `543fb0a2b`, and `762e9dace` add stale bundled-service
    repair planning, force refresh of an active stale Kanata registration, and
    wait for normal asynchronous SMAppService removal before using the
    privileged bootout fallback.
  - The focused regression set passed 34 tests, and the complete suite passed
    3,997 XCTest cases with zero failures plus all executed Swift Testing
    suites.
  - Apple accepted notarization submission
    `b2f5e259-e792-4b12-b4d8-a0efbf2957af`; stapling and Gatekeeper validation
    passed. The stapled private archive SHA-256 is
    `d689c3e0340a55ccad3231733ac722df2bc98ca9b500e4c6a66ca1f785d2ee33`.
  - Managed macOS 15.7.7 lease `cbx_940aaa3ecba3` first registered a genuine
    build 6 bundled runtime and reported it fresh. After the app bundle changed
    to build 8, independent status reported the active build 6 runtime as
    `Stale runtime` with freshness `stale`.
  - Build 8 executed `install-required-runtime-services` once and its structured
    recipe postcondition succeeded. macOS logged unregister success, management
    state 0, register success, and management state 1. No `osascript` or
    administrator-authentication event appeared in the repair window.
  - Final independent status reports active runtime
    `com.keypath.KeyPath build 8`, freshness `fresh`, Kanata running, helper
    1.3.0 fresh and working, VirtualHID healthy, strict code-sign verification
    passing, Gatekeeper notarization accepted, and bundled Kanata
    1.12.1-prerelease-1.
- **Current blocker:** none for the bundled-runtime update path. The disposable
  clone still lacks Kanata Input Monitoring by construction, so whole-system
  operational status remains false even though the update recipe and its
  postcondition passed. Existing P02-P04 physical-input blockers are unchanged.
- **Next action:** review draft PR #1250, merge it when approved, then repeat
  the release validation from merged master before publishing any public
  Sparkle feed or release. The rebased branch equivalents are `7260ed4eb`,
  `d0adf7eb7`, and `10e9737b1`; its post-rebase full suite passed 3,998 XCTest
  cases with zero failures plus all executed Swift Testing suites.
- **Loop check:** not looping. Each candidate exposed a different boundary:
  stale-runtime detection, forced refresh, then an unnecessary privilege
  fallback. Build 8 changed the behavior and crossed the previously failing
  postcondition in one managed-clone attempt.
