# Test Hygiene Plan

Created: 2026-06-08

This plan is about making KeyPath's existing tests faster to run, easier to
trust, and easier to debug on the primary development machine. It does not
replace `docs/TEST-IMPROVEMENT-PLAN.md`, which focuses on coverage gaps. This
document focuses on harness behavior, log quality, lane design, and build graph
cost.

## Why This Comes First

The immediate priority is the MacBook Air local loop. Remote Mac mini
orchestration is intentionally deferred until the local lanes are already clean,
predictable, and measured. Otherwise a faster machine only hides:

- broad SwiftPM builds that compile most of the app graph for routine checks;
- noisy logs that make failures hard to find;
- test harness failures that leave orphaned `xctest` processes behind;
- local path/cache aliasing that can crash the Swift frontend;
- warning noise that drowns out new diagnostics.

## Observed Problems

These observations came from running `Scripts/run-tests-safe.sh` locally in a
CI-like environment.

### Relative Scratch Path Can Poison Module Caches

Running with the default CI scratch path hit a Swift frontend crash where the
same Clang PCM module appeared through two paths:

- `Scripts/../.build/ModuleCache.noindex/...`
- `.build/ModuleCache.noindex/...`

Using an absolute scratch path avoided that specific crash. The runner should
normalize scratch and module-cache paths before invoking SwiftPM.

### The Safe Runner Can Leave Orphaned Test Processes

During measurement, the wrapper process disappeared while the generated
`KeyPathPackageTests.xctest` process continued running. The harness should own
the full process tree and clean it up on normal exit, timeout, signal, or
wrapper failure.

### Full Test Builds Are Too Broad For Routine Feedback

`Scripts/run-tests-safe.sh` runs `swift build --build-tests`, which currently
pulls in a very wide graph: KeyPathAppKit UI, CLI, layout tracer, snapshot test
targets, resources, Sparkle artifacts, and SwiftPM dependencies. That is
appropriate for a full verification lane, but too expensive for many local
development checks.

### Logs Are Too Noisy

A partial run produced thousands of lines and multi-megabyte output before the
suite finished. The most visible sources were repeated Swift warnings and
runtime diagnostics from config generation, rule collection bootstrapping, and
test-mode services. The suite even triggered log rotation during one run.

### Compiler Warnings Reduce Signal

The run repeatedly emitted Swift warnings for concurrency isolation, unused
values, and always-false branches. Some of this overlaps existing issue #750,
but the test runner should still make new warnings easier to spot.

## Milestones

### Milestone 1: Stabilize The Harness

Goal: `Scripts/run-tests-safe.sh` should be predictable, reproducible, and
cleanup-safe.

Work:

- Normalize `SCRATCH_PATH`, `CLANG_MODULECACHE_PATH`, and
  `SWIFT_MODULECACHE_PATH` to absolute paths.
- Remove mixed path forms such as `Scripts/../.build` from the SwiftPM command
  environment.
- Track and clean up the full child process tree, including generated
  `.xctest` processes.
- Add signal traps for `INT`, `TERM`, `HUP`, and wrapper exit.
- Preserve the existing CI behavior of reusing `.build` when explicitly needed,
  but use the normalized absolute version of that path.
- Add a small harness self-test or shellcheck-style validation for cleanup
  behavior where practical.

Acceptance criteria:

- `Scripts/run-tests-safe.sh` prints normalized scratch/module-cache paths.
- If the wrapper is interrupted, no `KeyPathPackageTests.xctest` process remains.
- A default local run does not produce duplicate PCM module path errors.
- CI behavior remains compatible with the existing self-hosted runner.

### Milestone 2: Reduce Test Log Noise

Goal: full test logs should contain failure-relevant information by default.

Work:

- Add a test/CI log level that suppresses routine config-generation diagnostics.
- Keep explicit diagnostics available behind an opt-in variable such as
  `KEYPATH_TEST_VERBOSE_LOGS=1`.
- Suppress repeated "expected in test mode" diagnostics such as missing
  user-local AppKeymaps when tests intentionally isolate `HOME`.
- Audit high-volume debug/info statements in config generation, rule collection
  bootstrapping, runtime coordinator state publication, and event listeners.
- Make `run-tests-safe.sh` print a concise summary with failed tests, timeout
  reason, and the path to full logs.

Acceptance criteria:

- A normal full run log is small enough to scan without log rotation.
- Failure summaries are visible in the last 100 lines.
- Verbose diagnostics remain available for targeted debugging.

### Milestone 3: Define Focused Test Lanes

Goal: developers and agents should not need to run the full suite for every
change.

Work:

- Define named lanes for common feedback needs:
  - `smoke`: fastest sanity checks for core compile and critical unit tests.
  - `unit`: fast root-package model/parser/renderer tests.
  - `appkit`: UI-adjacent logic that requires KeyPathAppKit.
  - `snapshot`: visual snapshots, gated by `KEYPATH_SNAPSHOTS=1`.
  - `installer`: mocked installer and service lifecycle tests.
  - `device`: opt-in real-system tests gated by device/system variables.
  - `full`: current broad suite.
- Add stable script entry points under `Scripts/` or root-level wrappers.
- Make `.github/workflows/ci.yml` call those named lanes instead of embedding
  raw command fragments.
- Document which lane to run for common change types.

Acceptance criteria:

- A developer can choose a lane without remembering filters.
- CI summary identifies which lane failed.
- Full suite remains available and is not weakened.

### Milestone 4: Audit SwiftPM Test Target Dependencies

Goal: narrow test lanes should avoid compiling unrelated product graphs.

Work:

- Review `Package.swift` test targets and dependencies.
- Identify tests in `KeyPathTests` that only need `KeyPathCore`,
  `KeyPathPermissions`, or another smaller module.
- Move or split tests where that avoids importing `KeyPathAppKit`.
- Keep snapshot and visual tests in their own target/lane.
- Avoid broad source imports for CLI-only or pure parser tests.

Acceptance criteria:

- At least one narrow lane builds without compiling the full KeyPathAppKit UI
  graph.
- Test targets remain understandable and do not create circular dependency
  pressure.
- `swift test --list-tests` and lane scripts still work locally and in CI.

Status:

- Started with the smoke lane because it is the fastest developer feedback
  path.
- Added a narrow `KeyPathSmokeTests` SwiftPM target that depends only on
  `KeyPathCore` and `KeyPathPermissions`.
- Moved `KeyPathErrorTests` and `PermissionOracleFastModeTests` into that
  target, removing their accidental `KeyPathAppKit` imports.
- Added focused `KanataDefseqParser` coverage to the smoke target so core
  parser regressions are still covered without importing `KeyPathAppKit`.
- Updated `./Scripts/test-lane.sh smoke-root` to run `KeyPathSmokeTests` with
  XCTest disabled, no separate `swift build --build-tests` prebuild, and module
  cache reuse.

Current Milestone 4 local smoke lane measurements:

- command: `CI_ENVIRONMENT=true KP_SIGN_DRY_RUN=1 KEYPATH_BUNDLED_SIMULATOR_OVERRIDE=/opt/homebrew/bin/kanata-simulator ./Scripts/test-lane.sh smoke-root`;
- build: 0s separate prebuild, 6.49s SwiftPM incremental build inside
  `swift test`;
- test: 13s;
- total: 13s;
- test log size: 4,941 bytes;
- test log Swift warnings: 0;
- result: 31 Swift Testing tests in 2 suites passed.
- after adding parser smoke coverage, the same lane passed 36 Swift Testing
  tests in 3 suites, but a later repeat run timed out at 120s while compiling
  `KeyPathAppKit` before reaching test execution.
- `swift test list --disable-xctest` still works and lists the
  `KeyPathSmokeTests.*` entries, but SwiftPM builds the package-wide test runner
  for that command; the local measurement was 231s and should not be used as
  the smoke lane fast-path benchmark.
- `swift test --target KeyPathSmokeTests` is not available in SwiftPM, and
  `swift test --specifier KeyPathSmokeTests --disable-xctest` still compiled
  the broad package graph in local probing.

Conclusion: this slice improves smoke lane selection, removes accidental AppKit
imports from migrated tests, and keeps logs/test execution narrow once the
runner reaches execution. It does not yet satisfy the cold-build isolation goal.
True isolation will likely require a separate minimal package/test harness or a
different runner strategy, not only more `swift test --filter` usage in the
current package.

Milestone 4b isolated smoke harness:

- Added `dev-tools/smoke-harness`, a separate SwiftPM package that depends on
  the root package by path but imports only the `KeyPathCore` and
  `KeyPathPermissions` products.
- Replaced `./Scripts/test-lane.sh smoke` with the isolated harness. The old
  root-package smoke target remains available as `./Scripts/test-lane.sh
  smoke-root` for diagnostics.
- The isolated smoke lane runs the harness with its own build directory and
  fails if `KeyPathAppKit` appears in the build log, unless explicitly
  overridden.
- Seeded the harness with public-API smoke coverage for `KeyPathError`,
  `KanataDefseqParser`, and `PermissionOracle` fast/test mode.

Current isolated smoke measurements:

- clean command: `KEYPATH_ISOLATED_SMOKE_CLEAN=1 ./Scripts/test-lane.sh smoke`;
- clean total: 10-14s;
- warm command: `./Scripts/test-lane.sh smoke`;
- warm total: 1-3s;
- result: 12 Swift Testing tests in 3 suites passed;
- `appkit_in_log=0` for both runs.

Conclusion: the separate harness satisfies the cold-build isolation goal for
core/product-level smoke coverage. The next dependency-audit work should use
this lane as the fast proof point and only extract additional non-UI targets
from `KeyPathAppKit` when important smoke coverage cannot be expressed through
existing public products.

CI now runs `smoke` as an early fail-fast lane before building the kanata fork
or running the full test lane. The full lane remains the broad verification
gate.

### Milestone 5: Warning And Failure Signal Cleanup

Goal: warnings and failure output should support triage instead of burying it.

Work:

- Coordinate with existing issue #750 for Swift 6 concurrency/compiler warnings.
- Prioritize warnings that repeat across many files or indicate actor-isolation
  mistakes in tests.
- Fix low-risk unused-value warnings in tests.
- Keep a warning baseline or summary so new warnings are visible.
- Avoid making all warnings fatal until the baseline is meaningfully reduced.

Acceptance criteria:

- Repeated warnings are reduced enough that new diagnostics stand out.
- The runner reports warning counts or a stable summary.
- Existing warning cleanup remains linked to #750 instead of duplicating scope.

Status:

- Started with two repeated AppKit warning families observed during root-package
  smoke builds:
  - removed the dead `shouldUseKindaVimLearningStyle = false` branch from
    `ContextHUDController.showForLayer`;
  - made the `WindowManager` frontmost-app observer's main-actor mutation
    explicit.
- Local `swift build` recompiled both touched AppKit files and completed without
  re-emitting those warnings.
- A root-package `smoke-root` diagnostic then passed in 115s with
  `test_log_swift_warnings=2498`, surfacing the next repeated production warning
  families.
- Cleaned the next two repeated production warning families:
  - routed `DragToAuthorizeController` animation-completion state transitions
    through an explicit main-actor helper;
  - routed `DistributedNotificationBridge` layer-change observer work through
    an explicit main-actor helper.
- After those fixes, `./Scripts/test-lane.sh smoke-root` passed in 28s with a
  6,647-byte log and `test_log_swift_warnings=0`.
- Removed redundant `await` annotations from `PackDetailView+LiveState` live
  rule-collection reads; local `swift build` recompiled the file without
  re-emitting the warning.
- Cleaned two repeated test warning families:
  - made `UnmappedLayerKeyStyleTests` use the existing main-actor async XCTest
    lifecycle pattern for shared preferences and `OverlayKeycapView` access;
  - made `VallackOverlayZoneTests` main-actor aware, removed an unused keycap
    construction, and removed a redundant nil-coalescing expression.
- Focused appkit lane validation passed for
  `UnmappedLayerKeyStyleTests|VallackOverlayZoneTests` with 58 XCTest tests and
  `test_log_swift_warnings=0`.
- Updated `run-tests-safe.sh` to capture the prebuild phase in a separate build
  log and report `build_log_swift_warnings` alongside test-log warning counts;
  the same focused appkit lane reported both warning counts as zero.
- Refined the warning summary so missing Clang PCM/module-cache rebuild
  messages are reported as `*_module_cache_warnings` instead of inflating the
  Swift source-warning counts.
- Isolated service/privileged tests from the local runner's sudo auto-detection
  by forcing `KEYPATH_USE_SUDO=0` inside those test classes and restoring the
  prior environment afterward.
- After that isolation fix, the broad `appkit` lane reached the existing
  pass condition: 1,338 XCTest tests passed, 18 skipped, no test failures,
  `build_log_swift_warnings=0`, and `test_log_swift_warnings=0`. Remaining
  signal issues are app-log noise (`test_log_app_errors=30`,
  `test_log_app_warnings=2`) and SwiftPM's post-suite signal-5 helper exit,
  which the runner already treats as pass when tests succeeded.
- Added `AppLogger.errorUnlessQuietTest` for expected negative-path diagnostics
  that should remain errors in normal app use but should not pollute quiet test
  logs. Applied it to config write guards, duplicate alias fallback logging, hot
  reload failure branches, and simple-mods invalid-config guards. The broad
  `appkit` lane then passed with `test_log_app_errors=0`,
  `test_log_app_warnings=2`, and `test_log_swift_warnings=0`. The remaining
  reported `build_log_swift_warnings=35` were stale Clang PCM/module-cache
  warnings during the reset/rebuild path, not Swift source diagnostics.
- Quieted the last expected fallback warnings in `SaveCoordinator`; a focused
  `SaveCoordinatorTests` run passed with zero app warnings/errors, and a broad
  warm `appkit` lane passed its existing condition with 1,338 XCTest tests
  passed, 18 skipped, `test_log_app_warnings=0`, `test_log_app_errors=0`,
  `test_log_swift_warnings=0`, and `build_log_swift_warnings=0`.
- Fixed the unfiltered `full` lane invocation path in `run-tests-safe.sh` so
  lanes with no filter/skip arguments do not trip `set -u` on an empty
  `SWIFT_TEST_ARGS` array.
- Quieted expected full-lane negative-path diagnostics from state publishing,
  stuck-key recovery, TCP server probes, and subprocess launch failures while
  preserving warning/error severity in normal app usage.
- Made `PIDFileManager.removePID()` idempotent when another parallel test
  removes the PID file between the existence check and `removeItem`.
- Made the `OverlayHealthIndicatorObserverTests` async gate cancellation-aware
  so the dismiss-cancellation test no longer leaks a checked continuation.
- Current `./Scripts/measure-local-loop.sh full` baseline: build 4s, test 40s,
  total 45s, test log 896,341 bytes, zero Swift warnings, zero module-cache
  warnings, zero app warnings, and zero app errors. SwiftPM still emits the
  known post-suite `swiftpm-testing-helper` signal 5 after tests pass; the safe
  runner classifies that as a harness exit when the suite reports passing tests
  and no failures.

### Milestone 6: Measurement And Regression Guardrails

Goal: we should know whether hygiene changes actually improve the MacBook Air
local loop.

Work:

- Add a lightweight timing wrapper for build time, test execution time, log size,
  and exit status.
- Capture MacBook Air local and CI baseline numbers before major lane changes.
- Track cold versus warm build behavior separately.
- Document recommended MacBook Air commands for common development loops.
- Keep existing lane names stable unless a measured usability problem justifies
  a change.
- Treat regex-based `swift test --filter` lanes as transitional; prefer smaller
  test targets/packages and Swift Testing suites/tags where they reduce build
  graph cost or improve clarity.
- Keep Mac mini orchestration out of scope for this milestone except for
  preserving measurements that will help evaluate it later.

Acceptance criteria:

- Each lane reports elapsed time.
- Full-suite log size and runtime are tracked before and after changes.
- The recommended local workflow prioritizes the fastest reliable MacBook Air
  command for each common change type.
- Future lane refinements remain aligned with Apple's test-pyramid guidance:
  many fast isolated tests, fewer integration checks, and heavier UI/device
  validation only where it provides distinct signal.
- Later Mac mini orchestration decisions can use measured data instead of
  guesses, but do not drive the current milestone.

### Milestone 7: Bounded Core Harness Isolation

Goal: stop treating root-package test-target splits as a speed strategy and
prove whether a small isolated Core harness can provide a genuinely faster
local confidence path.

Context:

- `KeyPathTests` is still one broad target. Even a narrow
  `swift test --filter` against that target can force SwiftPM to compile the
  broad app graph because the target depends on `KeyPathAppKit`, `KeyPathCLI`,
  installer modules, and supporting packages.
- Local measurement and SwiftPM research confirmed this is a tooling
  limitation, not just a KeyPath package-shape problem: `swift test --filter`
  filters test execution, but it does not reliably isolate the build graph
  inside one root package.
- Creating a root-package `KeyPathCoreTests` target improves organization and
  log scope, but it does not meet the cold-build isolation goal because SwiftPM
  still builds the generated package-wide test product.
- The hidden `--test-product` workaround can target the generated
  `KeyPathPackageTests` product in this toolchain, but that product is
  package-wide. It does not create a per-target `KeyPathCoreTests` product.
- `KeyPathInstallationWizard` is already a separate target that does not depend
  on `KeyPathAppKit`, which is useful. Further installer/wizard splitting
  should be measurement-driven.
- `KeyPathCLI` is a separate target, but it currently depends on
  `KeyPathAppKit`. Splitting CLI tests only helps if the CLI dependency graph is
  narrowed or inverted so CLI-only tests no longer pull the app target.
- The isolated `smoke` harness has already proven the pattern: true speed comes
  from a smaller dependency graph, not just a smaller test filter.

Work:

- Treat the root-package `KeyPathCoreTests` experiment as a finding, not as the
  milestone path. Do not check it in as a build-isolation success unless a later
  toolchain proves it actually avoids the app graph.
- Create a small `dev-tools/core-harness` SwiftPM package, modeled after the
  isolated smoke harness, that depends only on `KeyPathCore`.
- Copy or port only the highest-signal Core checks into the harness first:
  `KanataRuntimeHostTests`, `KanataHostBridgeTests`,
  `KanataDefseqParserTests`, and `TestEnvironmentDetectionTests`.
  Add `SubprocessRunnerTests` only if the harness remains fast and stable.
- Add a `core-isolated` lane only if the harness proves a real speed win. Keep
  existing root lane names stable; do not replace `unit` with a harness command
  until measurements justify it.
- Measure cold and warm harness runs against the current `smoke` and `unit`
  lanes, including whether `KeyPathAppKit` appears in the log.
- Audit the remaining root-package `unit` lane before changing its filter. If
  duplicated smoke/Core coverage does not materially affect elapsed time, keep
  the coverage and document that `unit` is a fast root-package lane rather than
  true Core isolation.
- Stop the harness effort if it does not materially outperform the root
  filtered lane or if the copied-test maintenance burden starts to outweigh the
  local-loop gain.
- Audit `KeyPathCLI`'s dependency on `KeyPathAppKit`. If CLI tests remain a
  meaningful local-loop cost, identify the smallest extraction that moves
  CLI-facing models/facades/protocols into a non-AppKit target.
- Revisit installer/wizard boundaries only after Core and CLI measurements. If
  installer tests still dominate a lane we care about, split pure installer or
  service lifecycle logic from SwiftUI wizard view code.
- Keep the Mac mini/MacBook split deferred until local build graph isolation is
  measured and no longer the main bottleneck.

Acceptance criteria:

- A cold isolated Core harness builds and runs without compiling
  `KeyPathAppKit`.
- The plan records before/after measurements for the current filtered unit lane,
  the isolated smoke lane, and the isolated Core harness.
- The harness either earns a permanent lane with clear speed evidence or is
  explicitly retired so root-package organization work does not masquerade as
  build-speed work.
- The unit-lane audit records whether trimming duplicated smoke/Core suites
  improves elapsed time before any coverage is removed.
- The CLI/AppKit dependency audit produces either a scoped extraction plan or a
  measured decision to defer it.
- Installer/wizard follow-up is based on lane timing and dependency evidence,
  not on target-count preferences.
- Existing lane names remain stable unless a measured workflow problem justifies
  a new name.

Status:

- Implemented `dev-tools/core-harness`, a separate SwiftPM package that depends
  only on the root `KeyPathCore` product.
- Added the `core-isolated` lane in `Scripts/test-lane.sh`; the lane fails if
  `KeyPathAppKit` appears in its build/test log unless explicitly overridden.
- Seeded the harness with the bounded high-signal Core checks from
  `KanataRuntimeHost`, `KanataHostBridge`, `KanataDefseqParser`, and
  `TestEnvironment`.
- Current MacBook Air measurements:
  - clean `KEYPATH_ISOLATED_CORE_CLEAN=1 ./Scripts/test-lane.sh core-isolated`:
    15s total, 13 Swift Testing tests in 4 suites, `appkit_in_log=0`, 5,283-byte
    log;
  - warm `./Scripts/test-lane.sh core-isolated`: 2s total, 13 tests,
    `appkit_in_log=0`, 2,990-byte log;
  - warm `./Scripts/test-lane.sh smoke`: 2s total, 12 tests,
    `appkit_in_log=0`, 2,548-byte log;
  - warm root-package `./Scripts/test-lane.sh unit`: 8s total, 329 tests,
    zero Swift/module/app warnings or errors.
- Decision: keep `core-isolated` as a permanent fast Core confidence lane. It
  is not a replacement for `unit`; `unit` remains the broader root-package
  parser/model/renderer lane. The harness earns its place because it proves
  cold and warm build-graph isolation without compiling AppKit.
- CLI/AppKit audit:
  - clean command:
    `rm -rf /tmp/keypath-cli-audit-build && /usr/bin/time -p swift build --product keypath-cli --scratch-path /tmp/keypath-cli-audit-build`;
  - result: passed in 127.95s real time, 537.64s user time, 38.64s sys time;
  - scratch size: 1.1GB;
  - build log signal: 638 `Compiling KeyPathAppKit` lines versus 79
    `Compiling KeyPathCLI` lines.
- Decision: splitting the CLI product name or lane will not help while
  `KeyPathCLI` depends on `KeyPathAppKit`. A real speed win requires extracting
  CLI-facing models, schema/version utilities, and facade logic out of
  `Sources/KeyPathAppKit/CLI` into a non-AppKit target. Start with pure value
  types and command-parse/output-contract tests; then move storage/config/packs
  facades only when their dependencies can move with them. Keep installer and
  simulator facades AppKit-backed until a measured lane shows they dominate.
- Do not split installer/wizard targets further unless a lane timing run shows
  they dominate a workflow we care about.

## Relationship To Existing Issues

- #604 covers the broad long-term test improvement plan.
- #698 covers real `pgrep`/process-spawn deadlocks and tests bypassing the safe
  base class.
- #750 covers Swift 6 concurrency and compiler warning cleanup.

The issues created from this plan should focus on harness stability, log
quality, lane design, dependency narrowing, and measurement.

## Recommended Order

1. Stabilize `run-tests-safe.sh` path handling and cleanup.
2. Reduce test log noise enough that failures are readable.
3. Add named lane scripts around the current suite.
4. Audit and split test dependencies where the payoff is clear.
5. Clean warning hotspots.
6. Add MacBook Air local-loop measurement guardrails and workflow docs.
7. Isolate the build graph for routine local checks with a bounded isolated
   Core harness, then audit CLI/AppKit decoupling, then revisit
   installer/wizard boundaries only if measurements justify it.

## Current Status

As of 2026-06-08, Milestone 1 is implemented in `Scripts/run-tests-safe.sh`:

- scratch, `HOME`, and module-cache paths are normalized to absolute paths;
- generated module caches live under the normalized scratch path and are reused
  by default for warm local/CI lanes; set `KEYPATH_TEST_RESET_MODULE_CACHE=1`
  for an intentional cache-reset diagnostic run.
- the runner traps interruption/exit and cleans the SwiftPM test process tree;
- full-run timing and log-size summaries are printed locally and in GitHub step
  summaries.

Latest local full safe-runner baseline:

- build: 86s;
- test: 48s;
- total: 135s;
- log size: 3,087,438 bytes;
- result: 3,476 executed, 100 skipped, 0 failures.

SwiftPM still reports a post-suite `swiftpm-testing-helper` signal 5 exit after
the test suite has passed. The runner currently treats that as a harness exit,
not a test failure, when there are passing tests and no failed tests in the log.

Milestone 2 is partially implemented. The runner now defaults expected fixture
diagnostics to debug level in quiet test runs while preserving warning-level
output in normal app usage and under `KEYPATH_TEST_VERBOSE_LOGS=1`. The latest
local full safe-runner measurement after this change:

- build: 139s;
- test: 53s;
- total: 193s;
- test log size: 919,538 bytes;
- test log app warnings: 28;
- test log app errors: 63;
- result: 3,477 executed, 100 skipped, 0 failures.

The remaining high-volume noise is mostly build-time Swift compiler warnings,
not app diagnostics in the test log. The next cleanup pass should focus on the
largest repeated warning families before changing runner behavior further.

Milestone 3 is now started with named lane entry points in
`Scripts/test-lane.sh`. Most lanes are SwiftPM filters over the existing safe
runner; `smoke` now uses the isolated harness from Milestone 4b:

- `smoke` for fast isolated product-level sanity coverage;
- `smoke-root` for the root-package `KeyPathSmokeTests` target, retained as a
  diagnostic lane rather than the fast path;
- `unit` for fast root-package model/parser/renderer logic;
- `cli` for focused command, facade, output contract, and import/export tests;
- `runtime` for focused TCP, runtime coordinator, process lifecycle,
  permission, keyboard capture, VHID, and system-support tests;
- `appkit-ui` for focused UI/state, mapper, preference, and recommendation
  tests;
- `appkit-config` for focused config, pack, catalog, and rule collection tests;
- `appkit` for the broad AppKit-adjacent catch-all lane;
- `installer` for InstallerEngine, wizard, daemon/service lifecycle, and
  health-check tests;
- `snapshot` for visual snapshot tests with `KEYPATH_SNAPSHOTS=1`;
- `device` for opt-in real-system installer smoke under `KEYPATH_E2E_DEVICE=1`;
- `full` for the existing full safe SwiftPM suite.

CI now calls the named `smoke` lane before the named `full` lane. This gives
developers and CI a shared vocabulary for the fast product-level smoke check
and the broad verification gate.

Latest local root-package smoke lane measurement:

- command: `CI_ENVIRONMENT=true ./Scripts/test-lane.sh smoke-root`;
- build: 213s;
- test: 3s;
- total: 216s;
- test log size: 18,939 bytes;
- result: 102 passed, 0 failures.

This confirms that filters make execution and logs small, but the root-package
test runner can still force a broad build. The isolated `smoke` harness is now
the fast path; `smoke-root` remains useful when validating root SwiftPM target
behavior.

Milestone 4 started by moving the first smoke tests into `KeyPathSmokeTests`;
see the Milestone 4 status section above for the current measurement.

Milestone 6 is implemented with the MacBook Air local loop as the target:

- `unit`, `appkit`, `installer`, `snapshot`, and `full` lanes reuse the
  normalized module cache by default for faster warm local feedback.
- `Scripts/measure-local-loop.sh` records lane summaries into
  `.build/local-loop-measurements/` as Markdown and TSV so local timing changes
  can be compared without copying terminal output.
- `docs/MACBOOK_AIR_LOCAL_LOOP.md` documents the recommended lane by change
  type, warm-cache policy, measurement presets, and when to use verbose logs.

Milestone 7 now has enough evidence to keep the bounded isolated Core lane:

- `core-isolated` runs a separate `dev-tools/core-harness` package that depends
  only on `KeyPathCore`.
- Latest direct lane measurements: clean `core-isolated` passed in 15s, warm
  `core-isolated` passed in 2s, and warm `smoke` passed in 2s; all reported
  `appkit_in_log=0`.
- `unit` remains useful and fast when warm at 8s, but it is a broader
  root-package lane rather than a build-isolated Core lane.
- Follow-up measurements refined that baseline: `./Scripts/measure-local-loop.sh
  --clean-core core-isolated` passed in 12s with `appkit_in_log=0`, and
  `./Scripts/measure-local-loop.sh core-isolated` passed in 3s with
  `appkit_in_log=0`.
- `run-tests-safe.sh` now supports `KEYPATH_TEST_ENFORCE_CLEAN_SUMMARY=1` to
  fail an otherwise passing lane when summary warning/error counts regress.
  CI enables this guardrail for the full lane; elapsed time remains
  informational rather than enforced.
- Future milestone work should keep lane names stable, avoid treating filter
  strings as the final architecture, and move toward Apple-aligned test
  organization when target/package boundaries or Swift Testing suites/tags give
  measurable clarity or speed benefits.
- Current warm MacBook Air baseline from
  `./Scripts/measure-local-loop.sh --preset baseline`: `smoke` 2s,
  `core-isolated` 3s, `unit` 16s, and `appkit` 22s. The isolated lanes both
  reported `appkit_in_log=0`; the root-package lanes reported zero Swift
  warnings, module-cache warnings, app warnings, and app errors in their final
  summaries.
- Follow-up unit-lane audit: sequential measurements passed at 9s warm and 7s
  with `KEYPATH_TEST_RESET_MODULE_CACHE=1`. A candidate filter that removed the
  smoke/Core-duplicated `KeyPathErrorTests` and `KanataDefseqParserTests`
  reduced coverage from 329 passed tests to 288 passed tests but still took 9s.
- CLI/AppKit audit confirmed the next likely speed win is architectural, not a
  lane-filter change. A clean `swift build --product keypath-cli` with an
  isolated scratch path took 127.95s, generated a 1.1GB scratch build, and
  compiled the AppKit UI/resource graph before compiling the CLI target. The
  next extraction should create a non-AppKit CLI support target for pure result
  models, schema/version helpers, and low-level facade logic; command parsing
  tests can move there first. AppKit-backed installer/simulator/system facades
  should move later, only with dependency evidence.
  Because the root-package build dominates this lane, keep the current filter
  and treat `unit` as fast model/parser/renderer coverage, not true Core
  isolation. The `core-isolated` lane remains the true Core-only fast path.
- Follow-up appkit-lane audit: the broad `appkit` lane passed in 26s with 1,429
  tests, with 6s spent building and 20s in test execution. A focused
  `appkit-ui` lane passed in 11s with 442 tests. After removing CLI facade
  spillover, the focused `appkit-config` lane passed in 14s with 835 tests and
  zero Swift warnings, module-cache warnings, app warnings, or app errors. Keep
  the broad `appkit` lane as a catch-all, but use the focused lanes for ordinary
  UI/state and config/pack edits.
- Follow-up CLI-lane audit: `KeyPathCLI` still depends on `KeyPathAppKit`, so
  a focused root-package CLI lane improves test selection and log scope but is
  not build isolation. Ambiguous `OutputTests` and `OutputContractTests` were
  renamed to `CLIOutputTests` and `CLIOutputContractTests` so the lane can
  select CLI output coverage without pulling unrelated output suites. The
  `cli` lane passed warm in 8s with 333 tests and zero Swift warnings,
  module-cache warnings, app warnings, or app errors. The `appkit-config` lane
  now excludes CLI facade tests.
- Follow-up runtime-lane audit: older full-suite logs showed the remaining
  broad-lane spillover was concentrated in TCP/client robustness, runtime
  coordinator, process lifecycle, permission/system checks, keyboard capture,
  VHID, helper, and low-level utility suites. A focused `runtime` lane was added
  for that surface. A quiet-machine run of `./Scripts/measure-local-loop.sh
  runtime` passed in 18s total, with 5s build time, 12s test execution, 346
  passed tests, and zero Swift warnings, module-cache warnings, app warnings, or
  app errors. This lane also surfaces verbose XCTest performance metric output
  from runtime/utility tests; treat that as a future hygiene question if runs
  show log noise or instability.
- Current warm installer audit from `./Scripts/measure-local-loop.sh
  installer`: 15s total, 266 passed, and zero Swift warnings,
  module-cache warnings, app warnings, or app errors. The measured cost is
  mostly shared build time plus `InstallerEngineTests`, `PackageManagerTests`,
  and `MockPackageManagerTests`; wizard-specific coverage is not the dominant
  cost. Do not split installer/wizard lanes yet. Keep the existing installer
  lane as the right local check unless future edits show a repeated need for
  narrower package-manager or wizard feedback.
- Installer-lane hygiene required keeping `run-tests-safe.sh` hermetic by
  default (`KEYPATH_USE_SUDO=0` unless explicitly overridden) and downgrading
  expected installer failure-path diagnostics to debug in quiet test runs.
- Current quiet warm full baseline from `./Scripts/measure-local-loop.sh full`:
  33s total, 4s build, 29s test execution, 4,227 passed tests, and zero Swift
  warnings, zero module-cache warnings, zero app warnings, and zero app errors.
  This is now suitable as the broad local confidence check when the narrower
  lane for a change passes first.

The Mac mini workflow is deferred. Revisit it only after the MacBook Air loop is
fast and boring enough that remote execution would solve a measured capacity
problem instead of compensating for harness noise.

Next planned milestone: treat the current lane set as the stable local loop and
watch for regressions. CLI/AppKit extraction is worth revisiting only if a
measured workflow needs true build isolation; the current `cli` lane already
gives a fast, stable selection path. Installer/wizard splits should follow only
after the remaining lane timings justify the extra dependency work.
