# InstallerEngine Façade Implementation Plan

**Strategy:** Strangler Fig Pattern - Create the façade first, then incrementally rewrite messy bits to make the façade true.

**Goal:** Improve design, understandability, testability, and reliability of the install flow while maintaining backward compatibility.

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

## Pre-Phase 0: Quick Verification

**Before starting Phase 0, verify these basics:**

- [ ] **File locations decided**:
  - [ ] Source files: `Sources/KeyPath/InstallationWizard/Core/InstallerEngine*.swift`
  - [ ] Test files: `Tests/KeyPathTests/InstallationEngine/InstallerEngineTests.swift`
  - [ ] Types file: `Sources/KeyPath/InstallationWizard/Core/InstallerEngineTypes.swift`
- [ ] **Build system works**:
  - [ ] `swift build` succeeds
  - [ ] `swift test` runs (even if some tests fail)
  - [ ] Can import existing modules (`KeyPathCore`, `KeyPathWizardCore`, etc.)
- [ ] **Existing test infrastructure**:
  - [ ] `Tests/KeyPathTests/InstallationEngine/` directory exists
  - [ ] Can run existing installer tests (`LaunchDaemonInstallerTests`, etc.)
  - [ ] Test overrides work (e.g., `LaunchDaemonInstaller.authorizationScriptRunnerOverride`)
- [ ] **Design doc reviewed**:
  - [ ] `docs/InstallerEngine-Design.html` is final
  - [ ] API signatures are frozen
  - [ ] Type contracts understood

**If all checked ✅ → Proceed to Phase 0**

---

## Phase 0: Pre-Implementation Setup

> **📖 Beginner?** See `facade-planning-phase0-explained.md` for detailed explanations of each step with examples.
> 
> **✅ Phase 0 Complete!** See `docs/strangler-fig/PHASE0_SUMMARY.md` for summary and all deliverables.

### Contract Definition
- [x] **Freeze API signatures** - Document exact method signatures from `docs/InstallerEngine-Design.html`:
  - [x] `inspectSystem() -> SystemContext` → See `docs/strangler-fig/API_CONTRACT.md`
  - [x] `makePlan(for intent: InstallIntent, context: SystemContext) -> InstallPlan` → See `docs/strangler-fig/API_CONTRACT.md`
  - [x] `execute(plan: InstallPlan, using broker: PrivilegeBroker) -> InstallerReport` → See `docs/strangler-fig/API_CONTRACT.md`
  - [x] `run(intent: InstallIntent, using broker: PrivilegeBroker) -> InstallerReport` → See `docs/strangler-fig/API_CONTRACT.md`
- [x] **Define type contracts** - Specify required fields/properties for:
  - [x] `SystemContext` (what must be included) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `InstallIntent` enum cases → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `InstallPlan` (status enum, recipe list, requirement tracking) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `ServiceRecipe` (minimal executable unit structure) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `PrivilegeBroker` (interface/protocol shape) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `InstallerReport` (success/failure fields, requirement failures) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] `Requirement` (status enum: met/missing/blocked) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
- [x] **Create contract test checklist** - Document expected semantics:
  - [x] What `SystemContext` must contain for CLI/GUI/tests → See `docs/strangler-fig/CONTRACT_TEST_CHECKLIST.md`
  - [x] When `InstallPlan.status` should be `.blocked` vs `.ready` → See `docs/strangler-fig/CONTRACT_TEST_CHECKLIST.md`
  - [x] What `InstallerReport` must include for logging/debugging → See `docs/strangler-fig/CONTRACT_TEST_CHECKLIST.md`
  - [x] How requirement failures propagate through plan → report → See `docs/strangler-fig/CONTRACT_TEST_CHECKLIST.md`

### Baseline Establishment
- [x] **Capture current test outputs** - Record baseline behavior:
  - [x] `LaunchDaemonInstallerTests` - current service ordering assertions → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] `PrivilegedOperationsCoordinatorTests` - current privilege path behavior → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] `SystemRequirementsTests` - current compatibility checks → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] Any functional tests in `dev-tools/` scripts → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
- [x] **Create system state fixtures** - Capture real outputs for test fixtures:
  - [x] Healthy system snapshot (all services running, permissions granted) → Planned in `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Broken system snapshot (missing services, unhealthy state) → Planned in `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Conflict scenario (root-owned Kanata process detected) → Planned in `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Missing prerequisites (no admin rights, unwritable directories) → Planned in `docs/strangler-fig/TEST_STRATEGY.md`
- [x] **Document current behavior** - Write down what existing code does:
  - [x] `SystemSnapshotAdapter` output format → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] `WizardAutoFixer` auto-fix action mapping → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] `LaunchDaemonInstaller` service dependency order → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] `PrivilegedOperationsCoordinator` fallback chain → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`

### Dependency Injection & Seams
- [x] **Identify collaborators** - List all dependencies the façade will need:
  - [x] `SystemSnapshotAdapter` / `SystemRequirements` / `ServiceStatusEvaluator` → See `docs/strangler-fig/COLLABORATORS.md`
  - [x] `WizardAutoFixer` / `LaunchDaemonInstaller` → See `docs/strangler-fig/COLLABORATORS.md`
  - [x] `PrivilegedOperationsCoordinator` / `HelperManager` → See `docs/strangler-fig/COLLABORATORS.md`
  - [x] `VHIDDeviceManager` / `KanataManager` → See `docs/strangler-fig/COLLABORATORS.md`
  - [x] `PackageManager` / `BundledKanataManager` → See `docs/strangler-fig/COLLABORATORS.md`
- [x] **Keep it simple** - Start with direct dependencies, add DI later if needed:
  - [x] Façade can call existing singletons directly (e.g., `PrivilegedOperationsCoordinator.shared`) → See `docs/strangler-fig/COLLABORATORS.md`
  - [x] Use existing test overrides (e.g., `LaunchDaemonInstaller.authorizationScriptRunnerOverride`) → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Only create `PrivilegeBroker` protocol if we need test doubles (start with concrete type) → See `docs/strangler-fig/TYPE_CONTRACTS.md`
  - [x] **Skip**: Factory patterns, adapter interfaces, system detection abstractions (YAGNI - add if needed) → Documented

### Test Strategy
- [x] **Start with one test file** - `InstallerEngineTests.swift`:
  - [x] Core façade behavior (inspect, plan, execute, run) → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Type validation (SystemContext, InstallPlan, InstallerReport) → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Requirement checking and plan blocking → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Error propagation → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] **Split later if file gets > 500 lines** (YAGNI - start simple) → Documented
- [x] **Integration tests** - Verify façade delegates correctly:
  - [x] `inspectSystem()` calls correct detection modules → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] `makePlan()` generates correct recipes from existing logic → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] `execute()` routes to correct privilege coordinator → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] `run()` chains steps correctly → See `docs/strangler-fig/TEST_STRATEGY.md`
- [x] **Identify test gaps** - Find missing coverage:
  - [x] Conflict detection (`dev-tools/test-updated-conflict.swift` → unit test) → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Requirement validation (currently scattered, needs centralized tests) → See `docs/strangler-fig/TEST_STRATEGY.md`
  - [x] Plan blocking logic (when should plan be `.blocked`?) → See `docs/strangler-fig/CONTRACT_TEST_CHECKLIST.md`
- [x] **Regression tests** - Ensure existing behavior preserved:
  - [x] Service dependency order still respected → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] Privilege escalation paths still work → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`
  - [x] SMAppService vs LaunchDaemon logic still correct → See `docs/strangler-fig/BASELINE_BEHAVIOR.md`

### Operational Considerations
- [x] **Feature flagging** - Keep it simple:
  - [x] Use environment variable (`KEYPATH_USE_INSTALLER_ENGINE=1`) for testing → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Build flags, runtime flags (add later if needed) → Documented
- [x] **Logging** - Reuse existing:
  - [x] Use `AppLogger.shared` (already exists) → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Log at key points: inspect start/end, plan generation, execution start/end → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Complex tracing, custom log levels (add if needed) → Documented
- [x] **Migration path** - Incremental adoption:
  - [x] Start with tests (safest) → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Then CLI (easier to debug) → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] Then GUI (most visible) → See `docs/strangler-fig/OPERATIONAL_CONSIDERATIONS.md`
  - [x] **Skip**: Side-by-side execution (just switch when ready) → Documented
- [x] **Documentation** - Minimal updates:
  - [x] Add façade section to `ARCHITECTURE.md` → Planned
  - [x] Inline comments for complex logic → Planned
  - [x] **Skip**: Migration guide, extensive examples (add if needed) → Documented

---

## Phase 1: Core Types & Façade Skeleton

### Type Definitions
- [ ] **Create `InstallerEngineTypes.swift`** - Start with one file, split later if > 500 lines:
  - [ ] `SystemContext` struct (permissions, services, conflicts, etc.)
  - [ ] `InstallIntent` enum (`.install`, `.repair`, `.uninstall`, `.inspectOnly`)
  - [ ] `Requirement` enum/struct (named prerequisites with `.met`/`.missing`/`.blocked` status)
  - [ ] `ServiceRecipe` struct (executable operation unit)
  - [ ] `InstallPlan` struct (ordered recipes, status: `.ready`/`.blocked(requirement:)`)
  - [ ] `InstallerReport` struct (extend existing `LaunchDaemonInstaller.InstallerReport`)
- [ ] **Create `PrivilegeBroker.swift`** - Start simple:
  - [ ] Start with concrete struct wrapping `PrivilegedOperationsCoordinator.shared`
  - [ ] **Skip protocol initially** - add if we need test doubles
  - [ ] Use existing test overrides if needed

### Façade Skeleton
- [ ] **Create `InstallerEngine.swift`**:
  - [ ] Define class (no DI initially - call singletons directly)
  - [ ] Implement `inspectSystem()` - delegate to existing detection code
  - [ ] Implement `makePlan()` - delegate to existing planning logic (stub initially)
  - [ ] Implement `execute()` - delegate to existing execution code (stub initially)
  - [ ] Implement `run()` - chain inspect → plan → execute
  - [ ] Add basic error handling
- [ ] **Add initial tests**:
  - [ ] Test façade can be instantiated
  - [ ] Test `inspectSystem()` returns `SystemContext`
  - [ ] Test `makePlan()` returns `InstallPlan`
  - [ ] Test `execute()` returns `InstallerReport`
  - [ ] Test `run()` chains steps correctly

---

## Phase 2: Implement `inspectSystem()`

### Detection Integration
- [ ] **Wire up `SystemSnapshotAdapter`**:
  - [ ] Call `SystemSnapshotAdapter.adapt()` in `inspectSystem()`
  - [ ] Convert output to `SystemContext` format
  - [ ] Add tests verifying context contains expected data
- [ ] **Wire up `SystemRequirements`**:
  - [ ] Call `SystemRequirements.validateSystemCompatibility()`
  - [ ] Include compatibility info in `SystemContext`
  - [ ] Add tests for compatibility detection
- [ ] **Wire up conflict detection**:
  - [ ] Integrate conflict detection logic (`dev-tools/test-updated-conflict.swift`)
  - [ ] Include conflicts in `SystemContext`
  - [ ] Add tests for conflict scenarios
- [ ] **Wire up service status**:
  - [ ] Call `ServiceStatusEvaluator` checks
  - [ ] Include service health in `SystemContext`
  - [ ] Add tests for service status detection
- [ ] **Integration tests**:
  - [ ] Test `inspectSystem()` on healthy system
  - [ ] Test `inspectSystem()` on broken system
  - [ ] Test `inspectSystem()` with conflicts
  - [ ] Verify output matches existing detection behavior

---

## Phase 3: Implement `makePlan()`

### Planning Logic Integration
- [ ] **Wire up requirement checking**:
  - [ ] Check admin rights availability
  - [ ] Check writable directories
  - [ ] Check SMAppService approval
  - [ ] Check helper registration
  - [ ] Mark plan as `.blocked` if requirements unmet
  - [ ] Add tests for requirement validation
- [ ] **Wire up `WizardAutoFixer` logic**:
  - [ ] Map `InstallIntent` to auto-fix actions
  - [ ] Generate `ServiceRecipe`s from auto-fix actions
  - [ ] Add tests for intent → action mapping
- [ ] **Wire up service recipe generation**:
  - [ ] Call `LaunchDaemonInstaller` service creation logic
  - [ ] Generate recipes for Kanata, VHID daemon, VHID manager
  - [ ] Respect service dependency order
  - [ ] Add tests for recipe generation and ordering
- [ ] **Wire up component installation**:
  - [ ] Integrate `PackageManager` logic
  - [ ] Integrate `BundledKanataManager` logic
  - [ ] Generate recipes for component installation
  - [ ] Add tests for component recipes
- [ ] **Wire up version checks**:
  - [ ] Integrate `shouldUpgradeKanata()` logic
  - [ ] Generate upgrade recipes if needed
  - [ ] Add tests for version upgrade planning
- [ ] **Integration tests**:
  - [ ] Test plan generation for `.install` intent
  - [ ] Test plan generation for `.repair` intent
  - [ ] Test plan blocking when requirements unmet
  - [ ] Verify plan matches existing behavior

---

## Phase 4: Implement `execute()`

### Execution Logic Integration
- [ ] **Wire up `PrivilegeBroker`**:
  - [ ] Create concrete struct wrapping `PrivilegedOperationsCoordinator.shared`
  - [ ] Delegate privileged operations to coordinator
  - [ ] Use existing test overrides if needed (no protocol initially)
  - [ ] Add tests for broker delegation
- [ ] **Wire up service installation**:
  - [ ] Execute `ServiceRecipe`s in order
  - [ ] Call `LaunchDaemonInstaller` methods
  - [ ] Respect dependency ordering
  - [ ] Add tests for service installation execution
- [ ] **Wire up component installation**:
  - [ ] Execute component recipes
  - [ ] Call `PackageManager` / `BundledKanataManager`
  - [ ] Add tests for component installation
- [ ] **Wire up health checks**:
  - [ ] Verify services after installation
  - [ ] Restart unhealthy services
  - [ ] Add tests for health verification
- [ ] **Error handling**:
  - [ ] Stop on first failure
  - [ ] Capture error context
  - [ ] Generate `InstallerReport` with failure details
  - [ ] Add tests for error scenarios
- [ ] **Integration tests**:
  - [ ] Test execution with fake broker (no side effects)
  - [ ] Test execution with real broker (requires admin)
  - [ ] Test error handling and reporting
  - [ ] Verify execution matches existing behavior

---

## Phase 5: Implement `run()` Convenience Method

### Convenience Wrapper
- [ ] **Implement chaining**:
  - [ ] Call `inspectSystem()` → `makePlan()` → `execute()` internally
  - [ ] Handle errors at each step
  - [ ] Return `InstallerReport` with full context
- [ ] **Add basic logging**:
  - [ ] Log at start/end of each step using `AppLogger.shared`
  - [ ] **Skip**: Callbacks, intermediate artifact emission (add if needed)
- [ ] **Add tests**:
  - [ ] Test `run()` chains steps correctly
  - [ ] Test error propagation

---

## Phase 6: Migrate Callers

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
- [ ] Dependency injection approach: _______________
- [ ] Feature flagging mechanism: _______________
- [ ] Logging strategy: _______________
- [ ] Migration order: _______________

### Open Questions
- [ ] Question: _______________
- [ ] Question: _______________
- [ ] Question: _______________

### Risks & Mitigations
- [ ] Risk: _______________ → Mitigation: _______________
- [ ] Risk: _______________ → Mitigation: _______________

---

**Last Updated:** [Date]
**Status:** Planning Phase

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

