# Driverless merge-readiness review — 2026-10-12

Status: **hold merge pending live acceptance on the final candidate**.

## Scope and provenance

Reviewed `design/driverless-caps-ui`, based on `45f09b16307a78db7f19a951af5f72be1ac6f304`, including the existing uncommitted implementation and dirty Kanata submodule. The integration branch is `master`. The fetched comparison reported zero missing upstream commits and 172 branch commits. A commit alone does not identify this candidate: retain the worktree/submodule patches and artifact hashes alongside the results.

## Checked findings and fixes

| Finding | Reproduction and fix |
| --- | --- |
| Safe tests omitted the real session bridge | The full configuration lane failed with a missing bridge. The runner now builds/selects the actual bridge and fails closed on a missing explicit override. Four shell-contract tests cover setup and failures. |
| Native Caps output rejected by driverless admission | A real Rust parser regression failed before allowing usage 57 as output. Physical Caps input remains subject to the managed bridge and keyboard-identity rules. |
| Unsupported consumer outputs offered in UI | Playback, volume, mute and brightness are visibly unavailable across pickers, function-key configuration and the combined Function pack. Actual bridge tests cover every system action and all 22 built-in default configurations; 21 are admitted and Function is explicitly rejected/unavailable. |
| Devices UI offered unsupported exclusions | Devices is now informational, with connected keyboards and a clear limitation. Both rendered tests fail against the previous interactive implementation. |
| Failed Caps preparation stopped a working runtime | The clean VM reproduced a stop followed by “no eligible keyboard.” Restart now prepares/admission-checks before stopping. Three regressions prove preservation, successful ordering and superseding Stop. |
| Generated/imported configuration needed admission coverage | Actual-bridge tests reject syntactically valid unsupported media/device-filter configurations before mutation, preserve config/sidecar bytes, and verify supported staging/reload. |
| Snapshot fixtures dropped launcher cards intermittently | Randomized `hashValue % 10` produced duplicate IDs. Stable IDs replace it; two regressions failed before the fix. All 155 snapshot-selection tests and three independent process repeats passed without loosening comparisons or changing launcher baselines. |
| Pending script confirmation survived disabling scripts/removing the file | Regression tests failed before execution-boundary rechecks. Missing approval UI now reports failure. Tests use an injected runner, never real user scripts. |
| Plugin installation reported success after failed loading or cancellation | Invalid bundle, invalid principal and cancellation tests failed. Success now requires activation; cancellation reports false. Temporary fixtures avoid real plugin locations/network. |
| Failed plugin replacement erased the old bundle | Two regressions failed. Replacement keeps a recoverable sibling backup until activation succeeds and restores it on failure; failed new installations leave no bad bundle. |
| Activity opt-out accepted events during its final flush | A gated encryption regression reproduced events arriving after disable began. Capture is revoked before suspension. |
| Activity enable overwrote events accepted during history loading | Three gated regressions reproduced lost counts and stale enable completion. Counts reconcile event identities, including concurrent flush, and stale generations are ignored. |
| Reset could be undone by a pending history read | A two-gate regression covers reset completing before an older history result; successful reset invalidates that snapshot without overriding a newer enabled state. |

## Automated evidence

Logs reside on the mini in `/tmp/keypath-final-review/` until copied into the retained evidence directory.

- Rust bridge: 30 passed, including native Caps output regression.
- Python script tests: 28 passed, including four bridge-runner tests.
- Broad Swift gate before the final lifecycle additions: 5,553 passed, one launcher-fixture failure subsequently reproduced and fixed.
- Snapshot selection after fixture fix: 155 passed, unchanged launcher references; three independent repeats: nine passed.
- Script/plugin/logging initial red run: seven failures, three passing controls. Expanded green security/lifecycle selection: 87 passed.
- Plugin rollback red run: two failures, four passing controls.
- Logging enable red run: three failures. Combined follow-up green: 15 passed, no compiler warnings.
- Final broad gate and reset regression outcome: see appended verification receipt.

Expected error logs from failure-injection tests are not product-runtime acceptance failures. Recorded screenshot updates are reviewed UI changes; record mode itself does not count as a passing comparison.

## VM and physical evidence

The unmanaged macOS 26.5.2 guest `cbx_1cc45099ba6b` reached Welcome, normal macOS consent, then the tour after the user granted permissions. It exposed the Caps preflight ordering defect. This lease belonged to the background account, so USB attachment could not establish physical input; it has been destroyed. Its app log was retained. Lab artifact collection partially failed and must not be described as complete.

The replacement desktop-owned lease `cbx_2991fc0ffd79` independently enumerated physical fixture serial `2884855553BC` after transient USB attachment. No automatic USB routing was changed. It runs an unmanaged OS with zero profiles. The app reached Welcome and Accessibility after correcting a staging-only debug framework search-path mistake. Normal macOS permission approval is pending for this new clean guest. Later lifecycle fixes require a refreshed signed artifact before final acceptance.

Earlier physical Caps/replug/reboot evidence is recorded in `docs/bugs/caps-replug-recovery.md`. It belongs to an older artifact and is not evidence that every current change passed physically.

## Remaining acceptance matrix

| Area | Automated evidence | Still required on the final signed artifact |
| --- | --- | --- |
| First run and permissions | Permission/state/recovery tests; clean consent reached on earlier candidate | Fresh worker capability after normal grants, deny/revoke/regrant behavior |
| Caps and ordinary remaps | Real parser, output state, lifecycle, generated-config suites | Fixture input/output, held-modifier worker death, reconnect, app restart, guest reboot |
| App shortcuts | Save/rollback and generated-config tests | Create/change/delete, preview synchronization and real app launch after restart |
| App-specific rules | Source-routing, app-context and persistence tests | TextEdit/Terminal foreground switching, fallback and reload without app switch |
| Navigation/window snapping | Catalog/default admission, action/rule tests | Physical trigger through worker, visible target window movement and retained settings |
| Scripts | Security and pending-confirmation lifecycle regressions | Physical trigger to harmless marker, deny/cancel/approve once, restart |
| Plugins/Insights | Isolated install/load/cancel/rollback and encrypted storage/lifecycle tests | Real supported plugin activation, event delivery, opt-out, quit flush and reopen |
| Generated/imported config | Actual parser admission, canonical save preservation | Import then physical output; unsupported import preserves active worker; provider UI error/cancel separately |
| General/advanced settings | Preference durability, driverless status, screenshots | Control-to-effect checks for triggers/timing, login/reboot, backup/restore |
| Tour | All-page geometry tests and rendered previews | All four pages on final app at intended window sizes; app-picker interaction and contrast |

## Media/brightness decision

Keep remapping unavailable in this release, as requested. See `docs/adr/driverless-consumer-output-spike.md` for the source/SDK investigation. A bounded public-API output-only experiment is worth considering later: volume/mute/playback first, brightness separately. Consumer input capture and external-display control are separate projects. A VM cannot qualify real audio/display behavior.

## Merge gate

Do not call the branch merge-ready until the outstanding live matrix has evidence, the final source and submodule revisions are frozen, the full gate passes on that exact source, and repository review/CI gates pass. No merge or guide publication was performed by this review.

## Final automated receipt

The final safe full gate passed **5,572 tests**, exit 0, with zero compiler warnings (build 30 seconds, tests 192 seconds). Log: `final-full.log`; runner: `final-full-runner.log`. The reset regression failed before its four-line fix and passed in this final gate. Accessibility identifier checks passed all 381 files. `git diff --check` is clean except preserved trailing spaces in the historical catalog golden fixture; those are not newly introduced by this review.

The final signed app was installed and independently verified in the replacement guest. Package SHA-256: `99dfefefbbd982d0fdcdb05fd85fb9bcb0d5f266a0af5e024a15ec8f770edb90`; guest executable SHA-256: `ea60ed4806cbd92cf7ec579ee3054ca0147ca78be4a17b3d134d4e39ce9d75c1`. It reaches the normal Accessibility setup; permission approval remains pending. This final candidate supersedes the installer recorded at lease creation. Source evidence is preserved under `source-final/` (tracked binary diff, untracked-source archive and Kanata diff/revision); do not substitute HEAD alone for that source identity.


## Frozen-artifact blockers from the clean run3 VM

The retained ZIP with SHA-256
`99dfefefbbd982d0fdcdb05fd85fb9bcb0d5f266a0af5e024a15ec8f770edb90`
is **not merge-acceptance evidence**. These findings describe that packaged
artifact; they do not establish that the current source has the same defects.

On macOS 26.5.2 lease `cbx_074f3d987cca`, the installed CLI saved the canonical
q → a rule but could not apply it. Library validation rejected
`libkeypath_kanata_host_bridge.dylib`: the CLI has Developer ID team
`X2RKZ5TG99`, while the bridge is ad-hoc/linker-signed with no Team ID.
A normal KeyPath Quit/reopen replaced parent PID1916 with PID13713 but still
left `keypath.kbd` absent and no session worker. Physical input was never
armed or sent, so neither remapping nor restart recovery passed this run.

An independent run of the existing packaged identity contract against the
retained unpacked candidate also failed (exit1): legacy driver/helper assets
remain, including the Karabiner DriverKit package, uninstall scripts and the
Kanata daemon plist. This is separate from the bridge loading failure.

Evidence on the mini:
`~/vm-lab-evidence/automation-20261012-run3/` —
`remap-config-apply.log`, `remap-signatures.log`,
`remap-first-quit.log`, `remap-runtime-failure.log`,
`runtime-integration-blocked.json`, and
`candidate-identity-contract.log/json`.

**Before admitting another acceptance VM**, freeze a fresh candidate from the
intended source and run the packaged identity contract on the exact extracted
ZIP. Require a passing forbidden-asset check, compatible signing identities for
the CLI and bridge, and an installed-CLI driverless validation/apply smoke check
against an isolated disposable configuration. Retain the ZIP hash and those
results. Then repeat clean permission onboarding, actual worker readiness,
physical q → a output and normal Quit/reopen on those same bytes; host test
counts or an app-level signature check do not replace these gates.

## Rebuilt candidate after packaging blockers

The maintained build-and-sign path completed with deployment, notarization,
Sparkle publication and website publication disabled. The exact ZIP was
extracted and passed the full identity contract and strict deep signature
verification. ZIP SHA-256:
c3eefa5a88c96cfe64adca09b13b58c6967502fc22a9b17dd06316203f85eefb.
App executable SHA-256:
ce1d64d96a9c3d566548e65a6eadb96f65e53b6623ac567187d94e068c3e1d7a.
The bridge now has the expected Developer ID team and stable identifier, and
the forbidden legacy resources are absent.

A separately identified verification gap was fixed: signature metadata display
is no substitute for signature integrity verification. Three regressions passed,
including a real signed app with a modified Info.plist that must be rejected.
The identity gate explicitly verifies the bridge and simulator as well as the
app. See signature-inspection-is-not-verification.md.

Before VM admission, the extracted packaged CLI reported its config path inside
a temporary HOME/CFFIXED_USER_HOME and validated a minimal q-to-a configuration
there with isValid:true. This is parser/signing evidence, not live input evidence.
No apply or reload was issued against the host runtime. The release build had
two deprecation warnings (each repeated in diagnostic context) for existing
Keychain authentication-UI constants in ActivityLogEncryption.

Evidence on mini: ~/keypath-review-evidence/20261012-rebuild/.
acceptance-candidate.json binds dirty source snapshots and artifact hashes.
Clean macOS26/27 live qualification is in progress and remains a separate gate.

An additional CLI dry-run defect was proved after the candidate was frozen:
pending recovery could restore configuration/defaults, delete the journal, and
reload the runtime despite preview semantics. Two new regression tests failed
before the fix; all 18 ConfigFacade/admission tests passed after it in an isolated
worktree. The fix is integrated into source and refuses previews while any
recovery journal exists. It is not included in ZIP c3eefa5a…eefb currently used
by the VM runs. A later final candidate must incorporate it; do not label this
VM artifact as the final source revision.


## Corrected candidate: macOS 26 physical evidence

On admitted lease cbx_040b75b6f2d6 (public UID 502), normal Accessibility
consent was independently confirmed through the enabled Settings toggle and
fresh signed KeyPath capabilities (Accessibility and effective input access true).
The original approval command returned an unverified result after foreground
handoff; its failed receipt is preserved alongside separate reconciliation proof.
No permission/password action was replayed.

The exact frozen ZIP c3eefa5a…eefb successfully saved and applied q-to-a through
its bundled CLI. The physical fixture then submitted one q down/up pair; the
independent native capture app received exactly a down/up, no repeat or stuck
key, and the active worker's input/output counters each increased by two.
Evidence: ~/vm-lab-evidence/automation-20261012-run4/remap-before-ready.json.
Normal Quit/reopen subsequently passed. Both original parent and worker were
independently absent before reopening. The new parent/worker and session nonce
differed, the configuration hash was unchanged, and a second physical q pair
again produced exactly a down/up with two input and two output events.
Evidence: remap-after-reopen.json and qualification-result.json in the same
run4 directory. The owned VM was destroyed and the fixture independently
verified back on the host with its autoconnect policy unchanged.
This verifies application restart only; OS reboot recovery and the broader
feature matrix remain outstanding.

The capture harness itself had a confirmed blocker: kern.num_taskthreads is a
per-task ceiling, not current thread inventory. Its replacement uses a bounded,
background live inventory query and refuses missing or stale data. All 37 Jig
tests passed and the signed replacement's resource admission passed in this VM.
That harness fix is committed to the separate physical-fixture PR #1238 at
4ab0f731f; this driverless branch does not contain the Jig package. The corrected
Jig ZIP is d51c41ff8837c45329114816e0ce29f11c2716bc3c8907c727489a304a12276e.

## Independent v2 macOS 26 repeat

A second corrected-candidate clean run, cbx_fcaa9849c5f6, passed normal
Accessibility consent directly using boot-UUID-bound lab source 679459f.
Physical calibration verified all 37 pairs without repeats. Fresh product
capabilities were Accessibility/effective input true. CLI q-to-a and actual
physical output passed before and after normal Quit/reopen; old processes
were absent, new parent/worker/nonce differed, and config SHA remained
c7018ddbd9b55669633ec58da7eec28093f0164a771714488ed23e7e94040e7b.
The VM was destroyed and fixture return independently verified before handoff.

Evidence: ~/vm-lab-evidence/automation-20261012-v2-mac26/qualification-result.json.
This repeats runtime and application-restart coverage on ZIP c3eefa5a…eefb.
It does not cover Settings save UI, OS reboot recovery, macOS27, the complete
feature matrix, or the later source-only CLI dry-run fix.
