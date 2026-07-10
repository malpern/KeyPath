# ADR-031: Kanata Service Lifecycle Invariants and Postcondition Enforcement

## Status

Accepted

## Date

2026-02-28

## Context

A reliability incident showed a gap between installer completion signaling and actual Kanata runtime state:

1. `installBundledKanata` replaced binaries and could stop/re-register service state.
2. In stale SMAppService conditions (`.enabled` but not loaded), recovery could be skipped by generic install throttle.
3. Restart-window heuristics could briefly treat the system as healthy without process+TCP readiness.
4. The installer action could return success, then quickly degrade to "service stopped" / "no TCP".

This violated user expectations and produced false green states after install/repair flows.

## Decision

Adopt explicit service lifecycle invariants for Kanata install/repair paths:

1. **Strict postcondition for success**
   - Mutating installer actions that affect Kanata runtime must not report success until Kanata is `ready` (`running + TCP responding`) or the system is explicitly in pending Login Items approval.

2. **Stale recovery bypasses generic throttle**
   - If SMAppService is active but launchd cannot load the daemon (stale enabled registration), recovery install/register logic bypasses normal install-attempt throttling.

3. **Registration is metadata, not liveness**
   - `SMAppService.status == .enabled` is treated as registration state only.
   - Runtime health requires process and TCP evidence.

4. **Definitive unhealthy evidence is terminal for the attempt**
   - Repeated `launchctl` not-found (`exit 113`) with `!running && !responding` is not treated as transiently healthy.
   - Installer action fails with diagnostics instead of returning optimistic success.

5. **Shared terminology**
   - `registered`: SMAppService metadata
   - `loaded`: launchd discoverability
   - `running`: process present
   - `responding`: TCP probe success
   - `ready`: `running && responding`

6. **Executable state classification**
   - The installer repair state matrix is not just a checklist. It is encoded by
     `InstallerStateMatrixPlanner` and backed by golden tests.
   - CLI, menu-bar, and wizard surfaces publish or consume the same
     `InstallerStateMatrixRow` / `InstallerStateMatrixAction` vocabulary before
     deciding whether a state is healthy, degraded, or manual-action-required.
   - Live evidence is captured once by `SystemValidator` into the canonical
     snapshot and projected into the context consumed by
     `InstallerDecisionPipeline`. The deleted provider/wizard adapters must not
     be restored.

## Consequences

### Positive

- Installer reports now match runtime reality.
- Stale-registration repair is deterministic even during throttle windows.
- "Green then stopped" transitions are reduced by fail-fast postconditions.
- Health decisions are easier to test and reason about.
- State classification now has table-driven regression coverage for every
  documented matrix row.

### Negative

- Install/repair actions can fail more often in borderline startup conditions instead of masking failures.
- Additional polling and diagnostics add modest complexity.
- The canonical snapshot, context projection, and narrower pure matrix input
  remain separate value shapes and therefore require anti-regrowth ratchets.

### Follow-up

- The owned-run pipeline and compatibility deletion completed in July 2026;
  future changes must preserve the single-capture contract.

## Enforcement

- `InstallerStateMatrixGoldenTests.testEveryDocumentedStateMatrixRowHasAGoldenFixture`
  and
  `InstallerStateMatrixGoldenTests.testClassifySnapshotAndPlanMatchStateMatrixGoldenFixtures`
  pin the documented rows and action plans.
- `WizardPureLogicTests.test_systemStateProjectionPublishesStateMatrixMetadata`
  pins canonical projection into presentation state.
- `CLIOutputContractTests.testInspectResultRepairMetadataJSONShape`,
  `MainAppStateControllerTests.menuBarHealthPrefersStateMatrixRow`, and
  `SnapshotConsumerLintTests` and `InstallerDecisionPipelineLintTests`
  pin consumer adoption.

## Related

- [ADR-040: Process Liveness and Signaling Across the Privilege Boundary](adr-040-process-liveness-across-privilege-boundary.md)
- [ADR-042: Executable Installer State Classification](adr-042-executable-installer-state-classification.md)
- [Installer repair state matrix](../process/installer-repair-state-matrix.md)
