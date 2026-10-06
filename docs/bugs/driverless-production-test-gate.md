# Driverless production test gate

The October 6 broad gate exposed three stale integration contracts. An interrupted-write test called normal staging with corrupt sources; the stronger production validator correctly refused before creating a journal. The fixture now constructs the interrupted prior write directly under the operation gate, retaining the recovery refusal and subsequent repair assertions.

Session Caps owner recovery and the experimental timeout admission used direct process probes. They now use the canonical provider: recovery retains EPERM-as-live semantics, while timeout admission still requires a successful zero-signal probe. The standalone experimental harness compiles the canonical probe source. Permission snapshot and raw diagnostic reads also go through the existing provider façade; raw listening/posting facts remain distinct from combined session readiness.

Five reviewed screenshot baselines changed intentionally: three home-row timing views omit Quick Tap for On Press mode; General includes explicit Caps Lock setup; Repair omits privileged-helper controls. Existing tolerances remain unchanged. These baselines do not establish final customer UX approval.

Validation: 21 focused recovery/lint tests passed; the standalone admission harness passed 15 adverse schema cases plus bounded initialization/preparation checks. The full canonical gate passed **5,445 tests** in 193 seconds, with zero Swift/module-cache/app warnings and seven expected error-path app log entries. Logs: `/private/tmp/keypath-production-full-tests-v2/`. The failed first gate is preserved in `...-v1/`. Accessibility checks passed across 380 files. Local integration relay currency was `0 149`; this is not a fresh GitHub master qualification.

Toolchain deviation remains explicit: Xcode 27 and a verified cached Metal library, with the temporary build plugin restored byte-for-byte. This does not prove fresh Metal compilation, notarization, Gatekeeper acceptance, physical compatibility beyond the existing fixture, genuine OS timeout, or live acceptance of these new source changes.


## Final menu and Repair cleanup

The signed 3cd candidate passed clean manual replacement, normal startup with
preserved consent/configuration, and normal Quit in the disposable guest. The
selected receipt is in the permission-footprint worktree at
`docs/testing/evidence/2026-10-06-manual-replacement-live-acceptance.json`.
This trial generated no physical input and does not qualify legacy staged updates.

Repair/Remove still offered Reset Everything and system uninstall, both refused
by the driverless installer backend. The screen now gives manual removal guidance
and keeps Simulator/configuration backups. Overlay commands extend the standard
View menu instead of creating a duplicate. The Repair snapshot was visually
reviewed and updated without changing tolerances; focused screenshot comparison
passed, with zero Swift/module-cache/app warnings or app errors. Logs:
`/private/tmp/keypath-production-menu-cleanup-v3/`; subsequent removal-guidance
snapshot was recorded in v5, visually reviewed, and compared in v6.

The original sandboxed runner failed before compiling; approved runner v2 compiled
and exposed the expected changed screenshot. These failures remain preserved.
The temporary cached-Metal plugin is restored after every run. Xcode 27 is the
current script pin (the repository AGENTS reference to 26.6 is stale); fresh Metal
compilation and distribution trust remain unverified.

Remaining onboarding issue: first activation checks health while the independent
startup task is still starting the runtime. Its delayed wizard path does not
recheck readiness. The narrow source fix retains and awaits the existing startup task before
automatic surface selection and rechecks after the splash delay, preserving
explicit Set Up KeyPath actions and failed-start recovery. Do not introduce a
second lifecycle controller or use a saved completion flag as runtime health.

These new UI/startup changes follow signed 3cd acceptance and still need separate
signed live relaunch/menu acceptance. The redundant File uninstall command and hidden immediate-uninstall shortcut
are removed; File → Repair/Remove opens the retained removal guidance.
Existing launch/reopen unit tests do not
substitute for that concurrency/UI observation.

Final focused runner v7 reports 15 passed (launch gate, termination coordinator,
reopen policy and Repair snapshot), zero skips, warnings and app errors in31seconds.
The recording-only v5 reports its expected recording failure and is not counted
as a passing comparison. Accessibility380 and whitespace checks passed.


Release tooling follow-up: `Scripts/verify-installed-app.sh` currently requires
`system/com.keypath.kanata`; `Scripts/release-doctor.sh` still describes that
launchd registration as an installed-runtime signal. The final driverless release
must verify the exact session parent/worker, its owned report and TCP readiness,
while retaining signature, notarization and staple checks. Do not pass runtime
qualification by setting CHECK_RUNTIME=0; that switch is trust-only. No host
installation is authorized. This is a product distribution gate, not a reason to
change the VM lab.


Post-polish broad run v3 completed: **5,444 passed, one obsolete lint failure**,
197seconds, zero warnings and seven expected error-path app logs. The failed test
required the deleted immediate system-uninstall shortcut. Its replacement forbids
unsupported system-uninstall routes in driverless menus while retaining the
installer transaction/privileged-execution tests. The complete installer lint
class passed **12 tests** in v8, zero warnings/errors. Do not describe v3 as a
zero-failure full run; it remains preserved. A final zero-failure broad gate and
signed live UI acceptance still precede release.
