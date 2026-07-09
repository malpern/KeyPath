# ADR-042: Executable Installer State Classification

## Status

Accepted

## Date

2026-07-08

## Context

The installer reliability Phase 1 plan converted the installer repair state
matrix from a review checklist into executable code. Before this work, wizard,
CLI, menu-bar, and repair code could each infer "healthy", "stopped",
"registered", "loaded", and "manual approval required" from different evidence.
That allowed false-green states and repair loops to reappear even after
individual bugs were fixed.

ADR-031 established that install/repair success requires verified
postconditions. ADR-040 established that process liveness across the
root/unprivileged boundary must use the real OS semantics. Phase 1 adds the
next layer: consumers must classify the same immutable evidence into the same
state-matrix row before deciding what to report or which repair plan vocabulary
to expose.

## Decision

Treat `InstallerStateMatrixPlanner` as the executable contract for the installer
repair state matrix.

1. **The table is executable**
   - Each row in `docs/process/installer-repair-state-matrix.md` has a golden
     fixture in `InstallerStateMatrixGoldenTests`.
   - Classification is `InstallerStateMatrixSnapshot -> InstallerStateMatrixRow`.
   - Planning vocabulary is `InstallerStateMatrixRow -> [InstallerStateMatrixAction]`.

2. **Live OS evidence belongs behind `SystemStateProvider`**
   - SMAppService status, launchctl read-only evidence, process discovery,
     process liveness, TCP readiness, and permission snapshots are centralized
     behind `SystemStateProvider` or its owned low-level helpers.
   - Consumers must not call direct SMAppService status, `pgrep`, `launchctl
     print`, `kill(pid, 0)`, or permission snapshot sources once migrated.
   - Lint tests ratchet each migrated consumer.

3. **Consumers report the same row/action vocabulary**
   - CLI `system inspect` reports the shared state-matrix row and plan.
   - Menu-bar health treats `runningAndTCPResponding` as the only healthy
     classified row once validation has produced a classification.
   - Wizard detection results publish the shared state-matrix row and plan next
     to legacy wizard state/issues/actions.

4. **Package boundaries stay honest**
   - The live `SystemStateProvider` matrix adapter lives in AppKit because it
     reads SMAppService and runtime evidence.
   - Wizard core cannot import AppKit without a dependency cycle, so it consumes
     the same classifier through a pure `SystemContext ->
     InstallerStateMatrixSnapshot` bridge.
   - This is an intentional Phase 1 boundary, not a second state model.

5. **Repair-model and deletion work stay sequenced later in Phase 1**
   - This ADR records the Workstream 1/2/5 detection contract only.
   - Workstream 3 remains Phase 1 work, but starts after migrated consumers are
     using the shared snapshot/row/action vocabulary and the lint ratchets are
     stable.
   - Workstream 6 remains Phase 1 work, but runs last so it deletes code that
     Workstream 3 has made obsolete instead of polishing code about to be
     removed.
   - Phase 2 remains limited to autonomous/background repair behaviors.

## Enforcement

- `InstallerStateMatrixGoldenTests.testEveryDocumentedStateMatrixRowHasAGoldenFixture`
  ensures every documented row is represented by a golden fixture.
- `InstallerStateMatrixGoldenTests.testClassifySnapshotAndPlanMatchStateMatrixGoldenFixtures`
  pins row and plan classification for every fixture.
- `SystemStateProviderInstallerStateMatrixTests.*` pins live AppKit matrix
  snapshot materialization from provider-owned evidence.
- `CLIOutputContractTests.testInspectResultRepairMetadataJSONShape` pins CLI
  row/plan output.
- `MainAppStateControllerTests.menuBarHealthPrefersStateMatrixRow` pins the
  menu-bar healthy predicate.
- `WizardPureLogicTests.test_systemContextAdapterPublishesStateMatrixMetadata`
  pins wizard row/plan publication.
- `WizardPureLogicTests.test_systemContextStateMatrixSnapshot_classifiesStoppedRuntimeWithStaleInputCapture`
  pins the pure wizard-core snapshot bridge.
- `SMAppServiceStatusLintTests`, `PermissionSnapshotLintTests`,
  `PgrepProcessDiscoveryLintTests`, `LaunchctlEvidenceLintTests`,
  `LivenessPredicateLintTests`, and `TCPReadinessLintTests` prevent migrated
  consumers from regrowing direct OS evidence reads.

## Consequences

### Positive

- Wizard, CLI, and menu-bar surfaces can no longer silently invent incompatible
  health classifications for the same runtime state.
- The state matrix now fails in tests when a row or action contract changes.
- Future installer reliability work can change repair behavior against a stable
  detection vocabulary.

### Negative

- There are temporarily two snapshot-shaped values: the existing
  `SystemSnapshot`/`SystemContext` flow and the narrower
  `InstallerStateMatrixSnapshot`.
- The wizard bridge still exists because of package boundaries, but it preserves
  the matrix-critical registration, approval, runtime payload, runtime
  readiness, input-capture, and helper freshness evidence and is pinned against
  the live provider adapter by focused equivalence tests.
- Full deletion of duplicate caches and snapshot adapters is deferred within
  Phase 1 until Workstream 3 has stabilized the repair model.

## Related

- [ADR-031: Kanata Service Lifecycle Invariants and Postcondition Enforcement](adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md)
- [ADR-040: Process Liveness and Signaling Across the Privilege Boundary](adr-040-process-liveness-across-privilege-boundary.md)
- [Installer repair state matrix](../process/installer-repair-state-matrix.md)
- [Installer reliability Phase 1 plan](../planning/installer-reliability-phase1.md)
