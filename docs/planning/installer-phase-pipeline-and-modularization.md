# Installer Pipeline Consolidation Plan

**Status:** Complete — Milestones 1–4 accepted on 2026-07-10
**Date:** 2026-07-09
**Priority:** Next major installer reliability initiative
**Predecessor:** [Installer Reliability Phase 1](installer-reliability-phase1.md)
**Related:**
[ADR-015](../adr/adr-015-installer-engine.md),
[ADR-031](../adr/adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md),
[ADR-042](../adr/adr-042-executable-installer-state-classification.md), and
[Installer Repair State Matrix](../process/installer-repair-state-matrix.md)

## Purpose

Complete the transition to one installer pipeline:

```text
intent
  -> probe
  -> immutable snapshot
  -> classify
  -> plan
  -> execute
  -> fresh verification snapshot
  -> verified result or planned recovery
```

The wizard, CLI, settings, menu bar, and URL actions should become thin clients
of this pipeline. They should not independently read system state, select
repair operations, or infer success.

This is an incremental consolidation plan, not a rewrite. It has four
milestones with a decision gate after each. Later module extraction remains a
measured option rather than a predetermined outcome.

## Why This Work Is Needed

Phase 1 centralized much of the low-level evidence behind
`SystemStateProvider` and made the repair state matrix executable. That work
improved detection consistency, but compatibility architecture and distributed
ownership remain:

- `SystemValidator` produces `SystemSnapshot`.
- `InstallerEngine` converts it to `SystemContext`.
- `InstallerStateMatrixSnapshot` is derived through adapters.
- `SystemContextAdapter` converts installer context back into wizard state.
- SwiftUI pages still select and sequence some repair actions.
- `ServiceBootstrapper` can call `InstallerEngine.runSingleAction()` while an
  outer installer operation is executing.
- detached post-fix refreshes can probe while another mutation is in flight.

The system can therefore share state vocabulary while still disagreeing about
timing, ownership, and which evidence belongs to a decision.

## Incidents Behind The Plan

### Driver Approval Transition Deadlock

After the user enabled the Karabiner DriverKit extension, the wizard still
reported setup as incomplete. The page used aggregate Karabiner health to
decide whether it could install missing daemon services. Aggregate health
already required those services, creating a circular prerequisite.

The UI was classifying and planning from a partial local view.

### Health Probe Invalidated An Active Mutation

During VirtualHID repair on 2026-07-09:

1. The helper began `repairVHIDDaemonServices` over XPC.
2. A detached post-fix refresh started another inspection.
3. The inspection called `getVersion` on the same serialized helper.
4. The health ping timed out while the helper was still working.
5. The ping invalidated the XPC connection carrying the mutation.
6. The helper completed, but its reply was lost.
7. The router treated the timeout as failure and requested an administrator
   password through AppleScript.
8. A later helper retry, not the fallback, produced the final successful state.

This was not only an XPC bug. Probe, execute, and verify were allowed to overlap,
and a probe had authority to disrupt execution.

### Repeated Repair Work

The Karabiner flow could request daemon repair, then request a restart action
that mapped to the same recipe, then enter `installAllServices`, which requested
repair again. Repeated work increased latency and made timeouts and fallback
more likely.

### Uninstall Ambiguity

The uninstall path historically treated helper failure as permission to run an
administrator script. Current work is moving it toward helper-first execution,
explicit emergency cleanup, and verified component-level postconditions.

## Required Invariants

These invariants define the destination regardless of the final type or module
names:

1. One captured snapshot supplies the facts for one classification and plan.
2. Classification and planning are pure and perform no I/O.
3. Only one installer run executes at a time.
4. Execution performs only operations declared by its plan.
5. Execution does not recursively invoke the installer or create another plan.
6. Passive probes cannot invalidate or interfere with active mutations.
7. Helper timeout or lost reply is ambiguous, not proof of failure.
8. Administrator fallback requires an unsatisfied postcondition and an allowed
   recovery policy.
9. Success requires a fresh snapshot satisfying declared postconditions.
10. Manual approval is a terminal result for the current run, not a retry loop.
11. UI and CLI render shared assessment and result values instead of inventing
    local state rules.

## Canonical Snapshot Direction

Use the existing `SystemSnapshot` as the migration seed. It is already the
direct immutable output of `SystemValidator` and lives below presentation code.

During migration:

- add missing raw installer evidence and capture metadata to `SystemSnapshot`;
- make `SystemContext` and `InstallerStateMatrixSnapshot` compatibility
  projections only;
- do not add new facts exclusively to compatibility types;
- keep UI copy and repair decisions out of the snapshot;
- postpone any rename to `InstallerSnapshot` until consumers have migrated.

This is a direction, not a commitment to introduce a new parallel snapshot
type.

## Milestone 1: Execution Safety

**Goal:** Remove the current concurrency, repetition, and fallback hazards
without moving model or module boundaries.

**Status (2026-07-09): Complete.** The race is regression-tested and a real
post-uninstall repair held the helper mutation boundary for 14.1 seconds,
deferred health probing until completion, avoided administrator fallback, and
finished with verified Kanata process and TCP readiness.

### Work

- Add a single-flight installer transaction gate.
- Serialize privileged helper mutations.
- Defer helper health pings while a helper mutation is active.
- Prevent health timeouts from invalidating an active mutation connection.
- Treat lost helper replies and operation timeouts as ambiguous outcomes.
- Verify operation-specific postconditions before administrator fallback.
- Remove duplicate VHID repair/restart/install actions.
- Make already-satisfied operations fast no-ops.
- Document the XPC race in `docs/bugs/`.

### Acceptance Criteria

- A simulated lost helper reply followed by a satisfied postcondition returns
  success without invoking administrator fallback.
- A helper failure with an unsatisfied postcondition invokes only recovery
  explicitly allowed by the operation.
- Concurrent refresh requests do not issue disruptive XPC health pings during
  mutation.
- The Karabiner clean-install flow performs no redundant VHID repairs.
- Install, repair, and uninstall postcondition tests remain green.
- A real clean-install run does not show an unnecessary password prompt.

### Decision Gate

Proceed when the race is reproduced in a test, fixed, and verified on a clean
installed app. If the transaction gate requires broad UI changes, split those
changes into a second PR but do not begin snapshot consolidation first.

## Milestone 2: One Source Of Installer Truth

**Goal:** One immutable snapshot and one pure decision path determine installer
state and the next plan.

**Status (2026-07-10): Complete.** One `SystemSnapshot` capture supplies the
facts projected into `SystemContext`, and `InstallerDecisionPipeline` is the
single pure classification/planning path used by the engine and clients.

### Progress

- Core snapshot and decision convergence completed on 2026-07-09 after
  Milestone 1 acceptance. Final client-owned action sequencing migrates with
  Milestone 3 so it can target the owned run API rather than another temporary
  bridge.
- The first convergence slice adds helper approval as a raw `SystemSnapshot`
  fact, projects it through the existing compatibility result, and migrates
  wizard routing to consume the captured helper facts without another helper or
  `SMAppService` read.
- The canonical validator probe now exposes explicit cached/fresh capture
  policies. Initial wizard detection may reuse a snapshot captured within 1.5
  seconds; normal refresh, install, and repair inspection remains fresh.
- `InstallerDecisionPipeline` now produces the matrix assessment, diagnostic
  matrix actions, and executable auto-fix actions together from one context and
  intent. `InstallerEngine` and wizard projection both consume that result. The
  temporary `ActionDeterminer` migration façade was deleted after the client
  migration completed.
- `SystemSnapshot` now carries explicit complete/cancelled/timed-out capture
  status alongside its timestamp. Compatibility projections and wizard timeout
  results preserve that fact, and incomplete captures are excluded from the
  canonical validator cache.
- macOS version and DriverKit compatibility are now captured in
  `SystemSnapshot`; `InstallerEngine` and main-app projections no longer perform
  a second `SystemRequirements` read.
- A lint ratchet now protects the migrated wizard routing paths. The remaining
  pre-snapshot welcome check now consumes the same canonical result as initial
  routing, so wizard navigation performs no separate helper or `SMAppService`
  evidence read.
- Core acceptance is complete: value fixtures exercise classification and
  planning without system I/O, table-driven cases pin snapshot-to-plan
  behavior, and all compatibility projections derive from the captured
  snapshot.
- A purity lint prevents the planner from regrowing direct system reads. The
  obsolete `/Library/LaunchDaemons` existence check was removed from planning;
  actual filesystem failures remain executor results instead of hidden planning
  probes.

### Work

- Ensure `SystemSnapshot` contains every fact used by current classification or
  planning, including capture completeness and stale/timeout evidence.
- Introduce one probe entry point with cached and fresh capture policies.
- Keep parallel low-level reads internal to that capture.
- Produce one pure assessment from snapshot plus intent.
- Produce one pure plan from assessment plus intent.
- Move DriverKit approval, helper approval, runtime readiness, and stale
  diagnostic rules out of views and adapters.
- Migrate the wizard first while preserving compatibility projections for
  other clients.
- Add lint tests preventing migrated clients from regrowing direct evidence
  reads.

Suggested API shape, subject to a spike:

```swift
probe.capture(freshness: .cached | .fresh) -> SystemSnapshot
classify(snapshot, intent) -> InstallerAssessment
plan(assessment, intent) -> InstallPlan
```

These may be methods, free functions, or small types. Do not create separate
classes merely to match the names above.

### Acceptance Criteria

- Every input used by the wizard's classification and planning exists in the
  captured snapshot.
- Planning and classification tests run with value fixtures and no system I/O.
- A snapshot can derive compatibility `SystemContext` and matrix values without
  additional reads.
- Wizard classification and routing no longer decide whether to repair,
  restart, register, or invoke fallback. User-triggered action sequencing moves
  with Milestone 3 so it can target the owned run API.
- Table-driven fixtures pin important snapshot -> assessment -> plan behavior.

### Decision Gate

Compare complexity and testability with the current path. Continue only if the
canonical path removes local decisions rather than adding a second abstraction
beside them. If a proposed new type duplicates `SystemSnapshot` or
`InstallerStateMatrixSnapshot`, consolidate before proceeding.

## Milestone 3: One Owned Run Pipeline

**Goal:** Execute the complete plan once, then verify it with one fresh
snapshot.

**Status (2026-07-10): Complete.** Real-Mac clean install, repair, upgrade, and
uninstall/reinstall acceptance passed. Healthy repeated install and repair are
verified no-ops; every mutation is correlated to its declared plan and final
snapshot; installed runtime verification confirms process, launchd, and TCP
readiness.

### Progress

- Started on 2026-07-10 after PR #1079 merged Milestones 1 and 2.
- Post-merge installed CLI repair reproduced the recursive-run deadlock: the
  outer transaction executed `install-required-runtime-services`, then
  `ServiceBootstrapper.installAllServices()` called `runSingleAction()` and
  waited forever to reacquire the same transaction gate.
- The first slice removes that nested engine/plan creation while preserving the
  helper-first VHID operation and adds a lint ratchet against recurrence.
- Installed verification after that slice exposed a second-observer race: CLI
  repair and CLI inspect could briefly disagree about TCP readiness. The next
  slice moves the fresh, cache-invalidating final capture into the owned engine
  transaction and makes CLI clients consume that report evidence.
- Recipes now declare operation-specific observable postconditions. The owned
  run verifies only those declarations against its final snapshot, treats a
  lost operation reply as success only when a complete pre-run baseline proves
  the failed recipe's state transitioned from unsatisfied to satisfied, and
  attaches a newly classified repair plan when verification fails.
- Snapshots, plans, runs, reports, and per-step telemetry now carry stable,
  correlated identities. App and CLI report paths expose one structured
  completion state, including approval-pending, verified lost replies,
  verification failure, and explicit recovery-required outcomes.
- VHID activation is now an explicit planned recipe ordered before dependent
  service work. Generic service executors no longer probe activation state or
  inject an undeclared activation operation, and a lint ratchet prevents that
  planner/executor boundary from drifting.
- Wizard fix actions now render the owned run's completion state and project
  its final context directly into wizard state. The prior delayed refresh,
  SMAppService preflight reads, detached VHID probe, and post-fix state-machine
  reinspection have been removed.

### Work

- Give each plan a stable ID, ordered steps, prerequisites, expected
  postconditions, and recovery policy.
- Execute only the declared steps and record structured outcomes.
- Remove `ServiceBootstrapper -> InstallerEngine.runSingleAction()` recursion.
- Remove executor reads that make new planning decisions.
- Capture one fresh post-execution snapshot with relevant caches invalidated.
- Compare that snapshot against declared postconditions.
- Include before/after snapshot IDs in reports and telemetry.
- Reclassify failed verification to produce a new recovery plan.
- Represent manual approval and explicit emergency cleanup as structured run
  results.
- Migrate wizard-owned repair/restart selection and live pre-action reads to
  requests handled by the owned run pipeline; pages may request a user goal but
  may not choose or sequence executor operations.

Suggested conceptual flow:

```swift
let before = probe.capture(.fresh)
let assessment = classify(before, intent)
let plan = plan(assessment, intent)
let execution = execute(plan)
let after = probe.capture(.fresh)
let result = verify(plan, execution, after)
```

Implementation may keep these responsibilities inside `InstallerEngine` until
separate ownership demonstrably simplifies the code.

### Acceptance Criteria

- Every executed operation appears in the original plan.
- No bootstrapper or operation creates another installer plan.
- For recipes with declared postconditions, command or helper success without
  satisfying those postconditions remains failure. Low-risk filesystem recipes
  that intentionally declare no postcondition continue to rely on their reply.
- Lost replies with satisfied postconditions become verified success.
- Failed verification produces a newly planned recovery rather than an
  unplanned executor branch.
- Wizard and CLI expose the same structured completion and recovery states.

### Decision Gate

Run clean install, repair, upgrade, and uninstall on a real Mac. Do not begin
compatibility deletion until the canonical pipeline handles those workflows
and its telemetry can explain every executed step and fallback.

## Milestone 4: Consolidate Clients And Modularize By Evidence

**Goal:** Remove compatibility architecture and encode only proven ownership
boundaries as Swift modules.

**Status (2026-07-10): Complete.** Clients consume shared decision and run
evidence, production compatibility adapters and dead forwarding paths are
removed, helper identity has one shared version contract, and canonical local
workflows select stable Xcode 26.6.

### Outcome

- PR #1088 removed duplicate client matrix recapture and made CLI/app clients
  consume the decision produced from their owned context.
- PR #1089 replaced conflicting helper version literals with one
  `KeyPathHelperContract`; a healthy matching helper now classifies as running
  with an empty repair plan.
- PR #1090 centralized Xcode selection for build, test, deploy, and release
  workflows. Selection is version-based, so different app bundle names do not
  silently route KeyPath onto Xcode beta.
- PR #1091 removed unused RuntimeCoordinator/KanataViewModel install and repair
  bridges, the lossy wizard repair report, an ignored engine dependency, and a
  no-op wizard configuration hook.
- PR #1092 removed `SystemContextAdapter`. Wizard presentation state is now an
  explicit pure projection from the canonical installer context, protected by
  golden tests and an anti-regrowth ratchet.
- PRs #1094-#1097 closed the senior-review correctness findings: every
  helper-first fallback rechecks authoritative state, failed sub-probes cannot
  produce complete snapshots, fresh capture invalidates component facts,
  zero-recipe runs are verified no-ops with preserved correlation IDs, and all
  production mutation routes share the installer transaction.

### Client Consolidation

Migrate the CLI, settings, menu bar, URL actions, and diagnostics to shared
snapshot, assessment, plan, and run-result values. Then remove unused adapters,
duplicate issue/action determination, client-owned repair sequencing, and
obsolete caches.

Potential deletion candidates include:

- `SystemContext`;
- `SystemContextAdapter`;
- `InstallerStateMatrixSnapshot`;
- temporary bridges and equivalence tests;
- detached client refresh orchestration.

Delete each only after production consumers have migrated. Keep
`InstallerStateMatrixRow` if it remains useful as a classification label.

### Module Decision

Measure the warm build graph after ownership stabilizes. Start with the smallest
useful extraction:

```text
KeyPathInstallerCore
  snapshot and evidence values
  assessment, plan, and result values
  pure classifier, planner, and verifier
  no SwiftUI or AppKit
```

Extract additional modules only when measurements justify them:

```text
KeyPathInstallerSystem   # optional macOS probe/execution boundary
KeyPathInstallerUI       # optional SwiftUI wizard/resource boundary
```

One `KeyPathInstallerCore` extraction may provide most of the test and compile
benefit. Do not create one module per page, manager, or installer step.

### Acceptance Criteria

- Clients cannot access low-level installer probes or privileged routers.
- One canonical snapshot-shaped installer value remains.
- Compatibility adapters are removed from production code.
- Core logic tests build without SwiftUI/AppKit when Core extraction is chosen.
- Any module extraction demonstrates a meaningful reduction in measured source
  invalidation or test graph size.
- Installed app behavior remains unchanged by module movement.

### Decision Gate

Compare warm incremental compile, link, deploy, signing, restart, and
first-window times separately. Keep only module boundaries that reduce a
meaningful cost without disproportionate public API or resource-bundle
complexity.

### Module Decision (2026-07-10)

Do not add `KeyPathInstallerCore` now. The ownership cleanup produced a fast
enough warm development graph without another public module boundary:

| Measured lane | Elapsed | Build | Test | Result |
| --- | ---: | ---: | ---: | --- |
| AppKit-free isolated core | 12s | 6s | <1s | 13 tests passed; no AppKit in log |
| Warm unit | 6s | 4s | 2s | passed |
| Warm AppKit | 20s | 3s | 17s | 1,476 tests passed |
| Warm installer-focused | 15s | 5s | 9s | 605 passed; one unrelated shared-state case isolated green |

The same worktrees showed that cold SwiftPM compilation remains the expensive
case (roughly 96–139 seconds), but moving the installer contracts would not
demonstrably reduce that whole-package cold graph. It would instead require a
large public-API migration across `KeyPathWizardCore`,
`KeyPathInstallationWizard`, `KeyPathAppKit`, CLI, and test targets. Existing
boundaries are retained; reconsider extraction only if source-invalidation
traces show installer edits repeatedly rebuilding unrelated UI or if a focused
installer lane cannot remain near the current warm duration.

## Recommended PR Sequence

The exact count is intentionally not fixed. A likely sequence is:

1. Execution transaction and helper XPC safety.
2. Postcondition-before-fallback and duplicate repair removal, if too broad for
   the first PR.
3. Canonical snapshot contract and probe spike.
4. Wizard migration to pure assessment and planning.
5. Plan-only execution and recursive-call removal.
6. Fresh verification and planned recovery.
7. Remaining client migration and compatibility deletion.
8. Measured Core extraction, followed by optional System/UI extraction.

Each PR should start from updated `origin/master` in its own worktree and use
the narrowest relevant test lane before the final broad gate.

## What To Do First

Complete Milestone 1 before snapshot or module movement.

Why:

- it removes the observed password-prompt and XPC invalidation race;
- it protects later migrations from concurrent installer runs;
- it establishes the execution phase boundary needed by the target design;
- it is behaviorally testable without changing public model APIs;
- it prevents a broad architecture migration from obscuring an urgent runtime
  reliability fix.

After Milestone 1 merges, perform a short Milestone 2 spike before committing to
the full model migration. Do not add snapshot convergence or module extraction
to the current uninstall/UI reliability branch.

## Measurement

Track before and after relevant milestones:

- direct installer evidence reads outside the probe owner;
- active snapshot and compatibility types;
- client-owned repair action selectors;
- recursive `InstallerEngine.runSingleAction()` calls;
- administrator fallback count during clean install and repair;
- helper mutation count per clean install;
- healthy repeated-repair duration;
- warm incremental compile time for one installer SwiftUI edit;
- link, deploy, signing, restart, and first-window time;
- focused installer logic test duration.

Module changes are successful when source invalidation and compile/type-check
work shrink without simply moving cost into linking or duplicated resources.

## Risks And Guardrails

### Avoid A Parallel Architecture

New snapshot, assessment, or plan types must replace decisions in the same PR
or establish a clearly temporary compatibility projection. Do not add a second
fully active path and defer migration indefinitely.

### Avoid Premature Modules

Stabilize value contracts and ownership before target extraction. Temporary
adapters should not become public APIs merely to satisfy an early module split.

### Preserve Recovery

Removing immediate fallback must not remove recovery. Fallback remains a
planned step after fresh failed verification, with explicit user authorization
where required.

### Keep UI Responsive Without Independent Probes

Expose transaction phase and snapshot staleness to clients. Render
"executing" or "verifying" from run state rather than starting overlapping
system inspections.

### Do Not Over-Serialize The App

Serialize installer runs and helper mutations, not unrelated application work.
Independent low-level reads may remain parallel inside one snapshot capture.

## Non-Goals

- No autonomous background repair.
- No broad installer UI redesign during ownership migration.
- No one-target-per-page modularization.
- No big-bang replacement of all compatibility types.
- No weakening of postconditions to make the migration appear green.
- No assumption that module extraction alone will produce a five-second deploy
  loop.

## Completion Definition

The plan is complete when:

1. one probe supplies one canonical immutable snapshot;
2. pure classification and planning determine installer behavior;
3. one single-flight run executes only planned operations;
4. a fresh snapshot verifies declared postconditions;
5. recovery is planned from verified state;
6. clients render shared values rather than owning installer decisions;
7. compatibility state models and adapters are removed where no longer needed;
8. only measured, useful Swift module boundaries are retained;
9. real-mac install, repair, upgrade, and uninstall pass without false success,
   repeated repairs, or unnecessary administrator prompts.
