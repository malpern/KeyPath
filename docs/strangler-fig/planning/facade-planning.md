# InstallerEngine Façade Implementation Plan

**Strategy:** Strangler Fig Pattern - Create the façade first, then incrementally rewrite messy bits to make the façade true.

**Goal:** Improve design, understandability, testability, and reliability of the install flow while maintaining backward compatibility.

## 📊 Progress Summary

- ✅ **Phase 0:** Pre-Implementation Setup - COMPLETE
- ✅ **Phase 1:** Core Types & Façade Skeleton - COMPLETE
- ✅ **Phase 2:** Implement `inspectSystem()` - COMPLETE
- ✅ **Phase 3:** Implement `makePlan()` - COMPLETE
- ✅ **Phase 4:** Implement `execute()` - COMPLETE
- ✅ **Phase 5:** Implement `run()` Convenience Method - COMPLETE
- 🔄 **Phase 6:** Migrate Callers - NEXT
- ⏳ **Phase 7:** Refactor Internals - Pending
- ⏳ **Phase 8:** Documentation & Cleanup - Pending

**Files Created:** 4 files (1,244 lines total)
- `InstallerEngineTypes.swift` (276 lines) - All core types
- `PrivilegeBroker.swift` (78 lines) - Privilege operations wrapper
- `InstallerEngine.swift` (573 lines) - Main façade class (fully implemented)
- `InstallerEngineTests.swift` (317 lines) - Comprehensive test suite

**API Status:** All 4 public methods fully functional ✅

## 🎯 Simplification Principles

**Keep it boring and simple:**
- ✅ Start with direct calls to existing singletons (no DI initially)
- ✅ Use existing test overrides instead of creating protocols
- ✅ One test file to start, split if > 500 lines
- ✅ One types file to start, split if > 500 lines
- ✅ Simple environment variable flagging (no build flags)
- ✅ Reuse existing `AppLogger` (no custom logging)
- ❌ **Skip**: Factory patterns, adapter interfaces, callbacks, side-by-side execution
- ❌ **Add later if needed**: Protocols, DI, separate test files, complex flagging

**YAGNI:** You Aren't Gonna Need It - add complexity only when we actually need it.

---

## Pre-Phase 0: Quick Verification ✅ COMPLETE

**Before starting Phase 0, verify these basics:**

- [x] **File locations decided**:
  - [x] Source files: `Sources/KeyPath/InstallationWizard/Core/InstallerEngine*.swift` ✅ Created
  - [x] Test files: `Tests/KeyPathTests/InstallationEngine/InstallerEngineTests.swift` ✅ Created
  - [x] Types file: `Sources/KeyPath/InstallationWizard/Core/InstallerEngineTypes.swift` ✅ Created
- [x] **Build system works**:
  - [x] `swift build` succeeds ✅ Verified
  - [x] `swift test` runs (even if some tests fail) ✅ Verified
  - [x] Can import existing modules (`KeyPathCore`, `KeyPathWizardCore`, etc.) ✅ Verified
- [x] **Existing test infrastructure**:
  - [x] `Tests/KeyPathTests/InstallationEngine/` directory exists ✅ Verified
  - [x] Can run existing installer tests (`LaunchDaemonInstallerTests`, etc.) ✅ Verified
  - [x] Test overrides work (e.g., `LaunchDaemonInstaller.authorizationScriptRunnerOverride`) ✅ Ready
- [x] **Design doc reviewed**:
  - [x] `docs/InstallerEngine-Design.html` is final ✅ Verified
  - [x] API signatures are frozen ✅ Verified
  - [x] Type contracts understood ✅ Verified

**✅ All verified - Completed Phase 0 and Phase 1**

---

## Phase 0: Pre-Implementation Setup ✅ COMPLETE

> **📖 Beginner?** See `planning/facade-planning-phase0-explained.md` for detailed explanations of each step with examples.
> 
> **✅ Phase 0 Complete!** See `docs/strangler-fig/phase0/PHASE0_SUMMARY.md` for summary and all deliverables.

### Contract Definition
- [x] **Freeze API signatures** - Document exact method signatures from `docs/InstallerEngine-Design.html`:
  - [x] `inspectSystem() -> SystemContext` → See `docs/strangler-fig/phase0/API_CONTRACT.md`
  - [x] `makePlan(for intent: InstallIntent, context: SystemContext) -> InstallPlan` → See `docs/strangler-fig/phase0/API_CONTRACT.md`
  - [x] `execute(plan: InstallPlan, using broker: PrivilegeBroker) -> InstallerReport` → See `docs/strangler-fig/phase0/API_CONTRACT.md`
  - [x] `run(intent: InstallIntent, using broker: PrivilegeBroker) -> InstallerReport` → See `docs/strangler-fig/phase0/API_CONTRACT.md`
- [x] **Define type contracts** - Specify required fields/properties for:
  - [x] `SystemContext` (what must be included) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `InstallIntent` enum cases → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `InstallPlan` (status enum, recipe list, requirement tracking) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `ServiceRecipe` (minimal executable unit structure) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `PrivilegeBroker` (interface/protocol shape) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `InstallerReport` (success/failure fields, requirement failures) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] `Requirement` (status enum: met/missing/blocked) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
- [x] **Create contract test checklist** - Document expected semantics:
  - [x] What `SystemContext` must contain for CLI/GUI/tests → See `docs/strangler-fig/phase0/CONTRACT_TEST_CHECKLIST.md`
  - [x] When `InstallPlan.status` should be `.blocked` vs `.ready` → See `docs/strangler-fig/phase0/CONTRACT_TEST_CHECKLIST.md`
  - [x] What `InstallerReport` must include for logging/debugging → See `docs/strangler-fig/phase0/CONTRACT_TEST_CHECKLIST.md`
  - [x] How requirement failures propagate through plan → report → See `docs/strangler-fig/phase0/CONTRACT_TEST_CHECKLIST.md`

### Baseline Establishment
- [x] **Capture current test outputs** - Record baseline behavior:
  - [x] `LaunchDaemonInstallerTests` - current service ordering assertions → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] `PrivilegedOperationsCoordinatorTests` - current privilege path behavior → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] `SystemRequirementsTests` - current compatibility checks → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] Any functional tests in `dev-tools/` scripts → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
- [x] **Create system state fixtures** - Capture real outputs for test fixtures:
  - [x] Healthy system snapshot (all services running, permissions granted) → Planned in `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Broken system snapshot (missing services, unhealthy state) → Planned in `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Conflict scenario (root-owned Kanata process detected) → Planned in `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Missing prerequisites (no admin rights, unwritable directories) → Planned in `docs/strangler-fig/phase0/TEST_STRATEGY.md`
- [x] **Document current behavior** - Write down what existing code does:
  - [x] `SystemSnapshotAdapter` output format → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] `WizardAutoFixer` auto-fix action mapping → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] `LaunchDaemonInstaller` service dependency order → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] `PrivilegedOperationsCoordinator` fallback chain → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`

### Dependency Injection & Seams
- [x] **Identify collaborators** - List all dependencies the façade will need:
  - [x] `SystemSnapshotAdapter` / `SystemRequirements` / `ServiceStatusEvaluator` → See `docs/strangler-fig/phase0/COLLABORATORS.md`
  - [x] `WizardAutoFixer` / `LaunchDaemonInstaller` → See `docs/strangler-fig/phase0/COLLABORATORS.md`
  - [x] `PrivilegedOperationsCoordinator` / `HelperManager` → See `docs/strangler-fig/phase0/COLLABORATORS.md`
  - [x] `VHIDDeviceManager` / `KanataManager` → See `docs/strangler-fig/phase0/COLLABORATORS.md`
  - [x] `PackageManager` / `BundledKanataManager` → See `docs/strangler-fig/phase0/COLLABORATORS.md`
- [x] **Keep it simple** - Start with direct dependencies, add DI later if needed:
  - [x] Façade can call existing singletons directly (e.g., `PrivilegedOperationsCoordinator.shared`) → See `docs/strangler-fig/phase0/COLLABORATORS.md`
  - [x] Use existing test overrides (e.g., `LaunchDaemonInstaller.authorizationScriptRunnerOverride`) → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Only create `PrivilegeBroker` protocol if we need test doubles (start with concrete type) → See `docs/strangler-fig/phase0/TYPE_CONTRACTS.md`
  - [x] **Skip**: Factory patterns, adapter interfaces, system detection abstractions (YAGNI - add if needed) → Documented

### Test Strategy
- [x] **Start with one test file** - `InstallerEngineTests.swift`:
  - [x] Core façade behavior (inspect, plan, execute, run) → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Type validation (SystemContext, InstallPlan, InstallerReport) → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Requirement checking and plan blocking → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Error propagation → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] **Split later if file gets > 500 lines** (YAGNI - start simple) → Documented
- [x] **Integration tests** - Verify façade delegates correctly:
  - [x] `inspectSystem()` calls correct detection modules → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] `makePlan()` generates correct recipes from existing logic → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] `execute()` routes to correct privilege coordinator → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] `run()` chains steps correctly → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
- [x] **Identify test gaps** - Find missing coverage:
  - [x] Conflict detection (`dev-tools/test-updated-conflict.swift` → unit test) → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Requirement validation (currently scattered, needs centralized tests) → See `docs/strangler-fig/phase0/TEST_STRATEGY.md`
  - [x] Plan blocking logic (when should plan be `.blocked`?) → See `docs/strangler-fig/phase0/CONTRACT_TEST_CHECKLIST.md`
- [x] **Regression tests** - Ensure existing behavior preserved:
  - [x] Service dependency order still respected → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] Privilege escalation paths still work → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`
  - [x] SMAppService vs LaunchDaemon logic still correct → See `docs/strangler-fig/phase0/BASELINE_BEHAVIOR.md`

### Operational Considerations
- [x] **Feature flagging** - Keep it simple:
  - [x] Use environment variable (`KEYPATH_USE_INSTALLER_ENGINE=1`) for testing → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Build flags, runtime flags (add later if needed) → Documented
- [x] **Logging** - Reuse existing:
  - [x] Use `AppLogger.shared` (already exists) → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Log at key points: inspect start/end, plan generation, execution start/end → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Complex tracing, custom log levels (add if needed) → Documented
- [x] **Migration path** - Incremental adoption:
  - [x] Start with tests (safest) → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Then CLI (easier to debug) → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Then GUI (most visible) → See `docs/strangler-fig/phase0/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Side-by-side execution (just switch when ready) → Documented
- [x] **Documentation** - Minimal updates:
  - [x] Add façade section to `ARCHITECTURE.md` → Planned
  - [x] Inline comments for complex logic → Planned
  - [x] **Skip**: Migration guide, extensive examples (add if needed) → Documented

---

## Phase 1: Core Types & Façade Skeleton ✅ COMPLETE

> **✅ Phase 1 Complete!** See `docs/strangler-fig/phase1/PHASE1_SUMMARY.md` for summary and deliverables.

### Type Definitions
- [x] **Create `InstallerEngineTypes.swift`** - Start with one file, split later if > 500 lines:
  - [x] `SystemContext` struct (permissions, services, conflicts, etc.) ✅ Created
  - [x] `InstallIntent` enum (`.install`, `.repair`, `.uninstall`, `.inspectOnly`) ✅ Created
  - [x] `Requirement` enum/struct (named prerequisites with `.met`/`.missing`/`.blocked` status) ✅ Created
  - [x] `ServiceRecipe` struct (executable operation unit) ✅ Created
  - [x] `InstallPlan` struct (ordered recipes, status: `.ready`/`.blocked(requirement:)`) ✅ Created
  - [x] `InstallerReport` struct (extend existing `LaunchDaemonInstaller.InstallerReport`) ✅ Created
- [x] **Create `PrivilegeBroker.swift`** - Start simple:
  - [x] Start with concrete struct wrapping `PrivilegedOperationsCoordinator.shared` ✅ Created
  - [x] **Skip protocol initially** - add if we need test doubles ✅ No protocol
  - [x] Use existing test overrides if needed ✅ Ready for test overrides

### Façade Skeleton
- [x] **Create `InstallerEngine.swift`**:
  - [x] Define class (no DI initially - call singletons directly) ✅ Created
  - [x] Implement `inspectSystem()` - delegate to existing detection code ✅ Stubbed (Phase 2)
  - [x] Implement `makePlan()` - delegate to existing planning logic (stub initially) ✅ Stubbed (Phase 3)
  - [x] Implement `execute()` - delegate to existing execution code (stub initially) ✅ Stubbed (Phase 4)
  - [x] Implement `run()` - chain inspect → plan → execute ✅ Implemented
  - [x] Add basic error handling ✅ Blocked plan handling added
- [x] **Add initial tests**:
  - [x] Test façade can be instantiated ✅ Created
  - [x] Test `inspectSystem()` returns `SystemContext` ✅ Created
  - [x] Test `makePlan()` returns `InstallPlan` ✅ Created
  - [x] Test `execute()` returns `InstallerReport` ✅ Created
  - [x] Test `run()` chains steps correctly ✅ Created

---

## Phase 2: Implement `inspectSystem()` ✅ COMPLETE

> **✅ Phase 2 Complete!** See `docs/strangler-fig/phase2/PHASE2_SUMMARY.md` for summary and deliverables.

**Status:** ✅ Complete - Real detection logic implemented

### Detection Integration
- [x] **Wire up `SystemValidator`**:
  - [x] Create `SystemValidator` instance in `init()` ✅
  - [x] Call `systemValidator.checkSystem()` in `inspectSystem()` ✅
  - [x] Convert `SystemSnapshot` to `SystemContext` format ✅
  - [x] Add tests verifying context contains real data ✅
- [x] **Wire up `SystemRequirements`**:
  - [x] Create `SystemRequirements` instance in `init()` ✅
  - [x] Call `systemRequirements.getSystemInfo()` ✅
  - [x] Include compatibility info in `SystemContext` ✅
  - [x] Convert `SystemInfo` to `EngineSystemInfo` ✅
- [x] **Conflict detection**:
  - [x] Conflicts included via `SystemSnapshot.conflicts` ✅
  - [x] Conflicts mapped to `SystemContext.conflicts` ✅
- [x] **Service status**:
  - [x] Service health included via `SystemSnapshot.health` ✅
  - [x] Service health mapped to `SystemContext.services` ✅
- [x] **Integration**:
  - [x] `inspectSystem()` returns real system data ✅
  - [x] All detection consolidated through `SystemValidator` ✅
  - [x] Tests verify real data (not stubs) ✅

---

## Phase 3: Implement `makePlan()` ✅ COMPLETE

> **✅ Phase 3 Complete!** See `docs/strangler-fig/phase3/PHASE3_SUMMARY.md` for summary and deliverables.

**Status:** ✅ Complete - Real planning logic implemented

### Planning Logic Integration
- [x] **Wire up requirement checking**:
  - [x] Check writable directories ✅
  - [x] Check helper registration (soft check) ✅
  - [x] Mark plan as `.blocked` if requirements unmet ✅
  - [x] Add tests for requirement validation ✅
- [x] **Wire up action determination logic**:
  - [x] Map `InstallIntent` to auto-fix actions ✅
  - [x] Duplicate `SystemSnapshotAdapter.determineAutoFixActions()` logic ✅
  - [x] Generate `ServiceRecipe`s from auto-fix actions ✅
  - [x] Add tests for intent → action mapping ✅
- [x] **Wire up service recipe generation**:
  - [x] Generate recipes for common actions ✅
  - [x] Map actions to `ServiceRecipe` types ✅
  - [x] Include health check criteria ✅
  - [x] Add tests for recipe generation ✅
- [x] **Recipe ordering**:
  - [x] Basic ordering implemented ✅
  - [x] TODO: Enhanced dependency resolution (future enhancement)
- [x] **Integration tests**:
  - [x] Test plan generation for `.install` intent ✅
  - [x] Test plan generation for `.repair` intent ✅
  - [x] Test plan generation for `.inspectOnly` intent ✅
  - [x] Test plan blocking when requirements unmet ✅
  - [x] Test recipe structure validation ✅

---

## Phase 4: Implement `execute()` ✅ COMPLETE

### Execution Logic Integration
- [x] **Wire up `PrivilegeBroker`**:
  - [x] Create concrete struct wrapping `PrivilegedOperationsCoordinator.shared`
  - [x] Delegate privileged operations to coordinator
  - [x] Add missing methods (installBundledKanata, activateVirtualHIDManager, etc.)
  - [x] Add tests for broker delegation
- [x] **Wire up service installation**:
  - [x] Execute `ServiceRecipe`s in order
  - [x] Call `PrivilegeBroker` methods for service operations
  - [x] Respect dependency ordering (basic - returns in order)
  - [x] Add tests for service installation execution
- [x] **Wire up component installation**:
  - [x] Execute component recipes
  - [x] Map recipe IDs to `PrivilegeBroker` methods
  - [x] Add tests for component installation
- [x] **Wire up health checks**:
  - [x] Verify services after installation using `LaunchDaemonInstaller.isServiceHealthy()`
  - [x] Perform health checks after recipe execution
  - [x] Add tests for health verification
- [x] **Error handling**:
  - [x] Stop on first failure
  - [x] Capture error context
  - [x] Generate `InstallerReport` with failure details
  - [x] Add tests for error scenarios
- [x] **Integration tests**:
  - [x] Test execution with real broker (may require admin in some environments)
  - [x] Test error handling and reporting
  - [x] Test recipe execution order
  - [x] Test empty plan handling

---

## Phase 5: Implement `run()` Convenience Method ✅ COMPLETE

### Convenience Wrapper
- [x] **Implement chaining**:
  - [x] Call `inspectSystem()` → `makePlan()` → `execute()` internally ✅ (Already implemented)
  - [x] Handle errors at each step ✅ (Errors handled via return types)
  - [x] Return `InstallerReport` with full context ✅
- [x] **Add basic logging**:
  - [x] Log at start/end of each step using `AppLogger.shared` ✅ (Already implemented)
- [x] **Add tests**:
  - [x] Test `run()` chains steps correctly ✅
  - [x] Test error propagation ✅
  - [x] Test all intents ✅
  - [x] Test complete report structure ✅
- [x] **Code verification**:
  - [x] Code compiles successfully ✅
  - [x] API structure verified ✅
  - [x] All methods functional ✅
- [x] **Documentation**:
  - [x] Updated README.md ✅
  - [x] Updated planning doc ✅
  - [x] Created Phase 5 summary ✅

**Note:** Full `swift test` run completed successfully on 2025-11-18 after fixing the unrelated test compilation errors called out earlier.

---

## Phase 6: Migrate Callers

#### Pre-Kickoff Status — 2025-11-19
- [x] `install-system.sh` restored as the canonical CLI wrapper (`install-system.sh install`)
- [x] `Scripts/install-via-cli.sh` delegated to the new wrapper; CLI entry is now wired through the Swift target
- [x] `Scripts/test-installer.sh` auto-detects the Kanata binary (override via `KANATA_BINARY_OVERRIDE`)
- [x] Full `swift test` run + docs updated; ready to start caller migration work

### CLI Migration
- [ ] **Identify CLI entry points**:
  - [ ] Find all CLI scripts that call installer code
  - [ ] Document current behavior
- [ ] **Migrate CLI to façade**:
  - [ ] Replace direct calls with façade methods
  - [ ] Update error handling
  - [ ] Update output formatting
  - [ ] Test CLI commands still work
- [ ] **Add CLI tests**:
  - [ ] Test CLI commands with façade
  - [ ] Verify output format
  - [ ] Verify error messages

### GUI Migration
- [ ] **Identify GUI entry points**:
  - [ ] Find wizard auto-fix button
  - [ ] Find installation wizard flows
  - [ ] Document current behavior
- [ ] **Migrate GUI to façade**:
  - [ ] Replace `WizardAutoFixer` calls with façade
  - [ ] Update UI state management
  - [ ] Update error display
  - [ ] Test GUI flows still work
- [ ] **Add GUI tests**:
  - [ ] Test wizard flows with façade
  - [ ] Verify UI updates correctly
  - [ ] Verify error handling

### Test Migration
- [ ] **Migrate functional tests**:
  - [ ] Update tests to use façade
  - [ ] Replace mocks with fake brokers
  - [ ] Verify test coverage maintained
- [ ] **Add façade-specific tests**:
  - [ ] Test façade contract compliance
  - [ ] Test requirement checking
  - [ ] Test plan generation
  - [ ] Test execution paths

---

## Phase 7: Refactor Internals

### Clean Up Existing Code
- [ ] **Refactor detection code**:
  - [ ] Extract reusable detection functions
  - [ ] Remove duplication between `SystemSnapshotAdapter` and related code
  - [ ] Improve testability
- [ ] **Refactor planning code**:
  - [ ] Extract recipe generation logic
  - [ ] Centralize requirement checking
  - [ ] Improve testability
- [ ] **Refactor execution code**:
  - [ ] Extract privileged operation wrappers
  - [ ] Improve error handling
  - [ ] Improve testability
- [ ] **Remove dead code**:
  - [ ] Identify unused code paths
  - [ ] Remove deprecated methods
  - [ ] Clean up old test code

---

## Phase 8: Documentation & Cleanup

### Documentation
- [ ] **Update architecture docs**:
  - [ ] Document façade design in `ARCHITECTURE.md`
  - [ ] Update `NEW_DEVELOPER_GUIDE.md` with façade usage
  - [ ] Add code examples
- [ ] **Add inline documentation**:
  - [ ] Document public API methods
  - [ ] Document type contracts
  - [ ] Add usage examples
- [ ] **Create migration guide**:
  - [ ] Document how to migrate from old API
  - [ ] Provide code examples
  - [ ] List breaking changes (if any)

### Final Validation
- [ ] **Run full test suite**:
  - [ ] All existing tests pass
  - [ ] All new façade tests pass
  - [ ] No regressions introduced
- [ ] **Manual testing**:
  - [ ] Test CLI commands
  - [ ] Test GUI wizard flows
  - [ ] Test edge cases
- [ ] **Performance validation**:
  - [ ] Verify no performance regressions
  - [ ] Profile critical paths
  - [ ] Optimize if needed
- [ ] **Code review**:
  - [ ] Review façade implementation
  - [ ] Review test coverage
  - [ ] Review documentation

---

## Notes & Decisions

### Key Decisions Made
- [x] Dependency injection approach: **Direct singleton calls** (no DI initially, YAGNI)
- [x] Feature flagging mechanism: **Environment variable** (`KEYPATH_USE_INSTALLER_ENGINE=1`)
- [x] Logging strategy: **Reuse `AppLogger.shared`** (no custom logging infrastructure)
- [x] Migration order: **Tests → CLI → GUI** (incremental adoption)
- [x] Type naming: **`EngineSystemInfo`** (renamed from `SystemInfo` to avoid conflict)
- [x] PrivilegeBroker visibility: **Internal init** (can't be public with internal coordinator)

### Open Questions
- ✅ **SystemContext ↔︎ SystemSnapshot bridge:** Documented in Phase 2 summary—`SystemValidator` already returns the data we surface as `SystemContext`.
- ✅ **PrivilegeBroker test doubles:** Deferred per YAGNI; concrete broker plus existing coordinator overrides are sufficient for Phase 6 migrations.
- ✅ **InstallerEngineTypes file size:** Staying below 500 lines (276 today); plan says split only if we cross that threshold.

### Risks & Mitigations
- [x] Risk: **Type naming conflicts** → Mitigation: Renamed `SystemInfo` to `EngineSystemInfo` ✅
- [x] Risk: **Build failures** → Mitigation: Fixed all compilation errors, build succeeds ✅
- [ ] Risk: **Test failures in Phase 2** → Mitigation: Will add integration tests incrementally

---

**Last Updated:** 2025-11-18
**Status:** Phase 5 Complete ✅

---

## 📝 Simplifications Made (vs. Initial Plan)

**Removed over-engineering:**
1. ❌ **Protocol-based abstractions** → ✅ Start with concrete types, add protocols if needed
2. ❌ **Factory patterns** → ✅ Direct instantiation
3. ❌ **Adapter interfaces** → ✅ Direct calls to existing code
4. ❌ **Separate test files per type** → ✅ One test file, split if > 500 lines
5. ❌ **Separate type files** → ✅ One types file, split if > 500 lines
6. ❌ **Complex feature flagging** → ✅ Simple env var
7. ❌ **Custom logging infrastructure** → ✅ Reuse `AppLogger`
8. ❌ **Callback mechanisms** → ✅ Basic logging only
9. ❌ **Side-by-side execution** → ✅ Just switch when ready
10. ❌ **Dependency injection** → ✅ Direct singleton calls initially

**Result:** Plan is ~40% simpler, focuses on getting it working first, adds complexity only when proven necessary.

