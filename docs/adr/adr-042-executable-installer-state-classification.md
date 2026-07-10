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

2. **Live OS evidence belongs in the canonical snapshot capture**
   - SMAppService status, launchctl read-only evidence, process discovery,
     process liveness, TCP readiness, and permission snapshots are centralized
     behind `SystemValidator`, `SystemStateProvider`, or their owned low-level
     helpers and is recorded in one `SystemSnapshot`.
   - Consumers must not call direct SMAppService status, `pgrep`, `launchctl
     print`, `kill(pid, 0)`, or permission snapshot sources once migrated.
   - Lint tests ratchet each migrated consumer.

3. **Consumers report the same row/action vocabulary**
   - CLI `system inspect` reports the shared state-matrix row and plan.
   - Menu-bar health treats `runningAndTCPResponding` as the only healthy
     classified row once validation has produced a classification.
   - Wizard detection results publish the shared state-matrix row and plan from
     the same canonical context used by the engine.

4. **Package boundaries stay honest**
   - `SystemValidator` captures OS evidence and projects it into the canonical
     context consumed by `InstallerDecisionPipeline`.
   - The former live-provider and `SystemContextAdapter` compatibility paths
     were deleted in PRs #1091 and #1092 after clients migrated.
   - Package boundaries must not recreate a second live evidence path.

5. **Deletion follows migration**
   - The compatibility bridge was retained during migration, then deleted once
     production consumers used the shared snapshot/row/action vocabulary.
   - Lint ratchets now prevent those deleted paths from regrowing.

## Enforcement

- `InstallerStateMatrixGoldenTests.testEveryDocumentedStateMatrixRowHasAGoldenFixture`
  ensures every documented row is represented by a golden fixture.
- `InstallerStateMatrixGoldenTests.testClassifySnapshotAndPlanMatchStateMatrixGoldenFixtures`
  pins row and plan classification for every fixture.
- `WizardPureLogicTests.test_systemStateProjectionPublishesStateMatrixMetadata`
  pins canonical context-to-presentation projection.
- `CLIOutputContractTests.testInspectResultRepairMetadataJSONShape` pins CLI
  row/plan output.
- `MainAppStateControllerTests.menuBarHealthPrefersStateMatrixRow` pins the
  menu-bar healthy predicate.
- `WizardPureLogicTests.test_systemContextStateMatrixSnapshot_classifiesStoppedRuntimeWithStaleInputCapture`
  pins pure classification of canonical context evidence.
- `SnapshotConsumerLintTests` and `InstallerDecisionPipelineLintTests` prevent
  duplicate capture, adapter, and decision paths.
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

- `SystemSnapshot`, its canonical `SystemContext` projection, and the narrower
  pure matrix input remain distinct value shapes, but no longer trigger
  independent live captures.
- Maintaining the single-capture boundary requires explicit lint ratchets as
  new consumers are added.

## Related

- [ADR-031: Kanata Service Lifecycle Invariants and Postcondition Enforcement](adr-031-kanata-service-lifecycle-invariants-and-postcondition-enforcement.md)
- [ADR-040: Process Liveness and Signaling Across the Privilege Boundary](adr-040-process-liveness-across-privilege-boundary.md)
- [Installer repair state matrix](../process/installer-repair-state-matrix.md)
- [Installer reliability Phase 1 plan](../planning/installer-reliability-phase1.md)
