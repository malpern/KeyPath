# Test Strategy

**Status:** ✅ PLANNED - Test approach defined

**Date:** 2025-11-17

---

## Test File Structure

### Single Test File to Start
**File:** `Tests/KeyPathTests/InstallationEngine/InstallerEngineTests.swift`

**Rationale:** Keep it simple, split later if > 500 lines

**Contains:**
- Core façade behavior tests
- Type validation tests
- Requirement checking tests
- Error propagation tests
- Integration tests

---

## Test Categories

### 1. Contract Tests (Verify Types Work)

**Purpose:** Ensure types have required fields and work correctly

**Tests:**
- [ ] `SystemContext` can be created with all required fields
- [ ] `InstallPlan` can be created with recipes and status
- [ ] `InstallerReport` extends existing report correctly
- [ ] `Requirement` status enum works correctly
- [ ] `ServiceRecipe` can be created with all fields

**Example:**
```swift
func testSystemContextHasRequiredFields() {
    let context = SystemContext(
        permissions: ...,
        services: ...,
        conflicts: ...,
        // ... all required fields
    )
    XCTAssertNotNil(context.permissions)
    XCTAssertNotNil(context.services)
    // ... verify all fields exist
}
```

---

### 2. Façade Behavior Tests (Verify Methods Work)

**Purpose:** Ensure façade methods work as expected

**Tests:**
- [ ] `inspectSystem()` returns `SystemContext`
- [ ] `makePlan()` returns `InstallPlan` with correct status
- [ ] `execute()` returns `InstallerReport`
- [ ] `run()` chains steps correctly
- [ ] Methods handle errors gracefully

**Example:**
```swift
func testInspectSystemReturnsContext() async {
    let engine = InstallerEngine()
    let context = await engine.inspectSystem()
    XCTAssertNotNil(context)
    XCTAssertNotNil(context.permissions)
}
```

---

### 3. Requirement Checking Tests

**Purpose:** Verify requirement validation works correctly

**Tests:**
- [ ] Plan is `.blocked` when admin privileges missing
- [ ] Plan is `.blocked` when SMAppService not approved
- [ ] Plan is `.ready` when all requirements met
- [ ] Multiple missing requirements all captured
- [ ] Requirement failures propagate to report

**Example:**
```swift
func testPlanBlockedWhenAdminMissing() async {
    let engine = InstallerEngine()
    let context = SystemContext(/* ... admin missing ... */)
    let plan = await engine.makePlan(for: .install, context: context)
    XCTAssertEqual(plan.status, .blocked(requirement: .adminPrivileges))
}
```

---

### 4. Integration Tests (Verify Delegation)

**Purpose:** Ensure façade correctly calls existing code

**Tests:**
- [ ] `inspectSystem()` calls `SystemSnapshotAdapter`
- [ ] `makePlan()` calls `WizardAutoFixer` logic
- [ ] `execute()` calls `PrivilegedOperationsCoordinator`
- [ ] Service dependency order preserved
- [ ] Privilege fallback chain preserved

**Example:**
```swift
func testInspectSystemCallsSnapshotAdapter() async {
    // Use test override or spy to verify call
    let engine = InstallerEngine()
    let context = await engine.inspectSystem()
    // Verify context matches what SystemSnapshotAdapter would produce
}
```

---

### 5. Regression Tests (Preserve Existing Behavior)

**Purpose:** Ensure we don't break existing functionality

**Tests:**
- [ ] Service dependency order still respected (VHID Daemon → VHID Manager → Kanata)
- [ ] SMAppService guard still works (skips Kanata plist if active)
- [ ] Privilege escalation fallback chain still works
- [ ] Version checks still work (`shouldUpgradeKanata`)
- [ ] Conflict detection still works

**Example:**
```swift
func testServiceDependencyOrderPreserved() async {
    let engine = InstallerEngine()
    let plan = await engine.makePlan(for: .install, context: healthyContext)
    
    // Verify recipes are in correct order
    let serviceIDs = plan.recipes.compactMap { $0.serviceID }
    XCTAssertEqual(serviceIDs, [
        "com.keypath.karabiner-vhiddaemon",
        "com.keypath.karabiner-vhidmanager",
        "com.keypath.kanata"
    ])
}
```

---

## Test Doubles & Mocks

### Strategy: Use Existing Test Overrides

**Existing Overrides Available:**
- `LaunchDaemonInstaller.authorizationScriptRunnerOverride` - Override privilege execution
- `LaunchDaemonInstaller.isTestModeOverride` - Override test mode
- `PrivilegedOperationsCoordinator.serviceStateOverride` - Override service state (DEBUG)
- `PrivilegedOperationsCoordinator.installAllServicesOverride` - Override install (DEBUG)

**Approach:**
- Use existing overrides instead of creating new mocks
- Create simple test doubles only if existing overrides insufficient
- Start with concrete types, add protocols later if needed

---

## Test Fixtures

### System State Fixtures

**Create fixtures for:**
- [ ] Healthy system (all services running, permissions granted)
- [ ] Broken system (services unhealthy, permissions missing)
- [ ] Conflict scenario (root-owned Kanata process)
- [ ] Missing prerequisites (no admin rights, unwritable directories)

**Format:** JSON files in `Tests/KeyPathTests/InstallationEngine/Fixtures/`

**Usage:**
```swift
let healthyContext = try loadFixture("healthy_system.json")
let plan = await engine.makePlan(for: .repair, context: healthyContext)
```

---

## Test Gaps to Address

### Missing Coverage Currently

**Conflict Detection:**
- Currently: Script in `dev-tools/test-updated-conflict.swift`
- Need: Unit test in test suite
- Action: Extract logic, add to `InstallerEngineTests`

**Requirement Validation:**
- Currently: Scattered across codebase
- Need: Centralized tests
- Action: Test requirement checking in `makePlan()`

**Plan Blocking Logic:**
- Currently: Not explicitly tested
- Need: Tests for when plan should be blocked
- Action: Add tests for each blocking scenario

---

## Test Execution Strategy

### Unit Tests (Fast, No Side Effects)
- Test type creation
- Test requirement checking logic
- Test plan generation logic
- Use test overrides to avoid real system calls

### Integration Tests (Slower, Real System)
- Test façade delegates correctly
- Test with real singletons
- May require admin privileges
- Use environment variable to skip if needed

### Regression Tests (Verify Behavior Preserved)
- Compare façade output to existing code output
- Verify service order preserved
- Verify privilege paths preserved

---

## Test Data Management

### Fixtures Directory
```
Tests/KeyPathTests/InstallationEngine/Fixtures/
├── healthy_system.json
├── broken_system.json
├── conflict_scenario.json
└── missing_prerequisites.json
```

### Test Helpers
- `loadFixture(_:)` - Load JSON fixture
- `createMockContext(_:)` - Create SystemContext for testing
- `createMockPlan(_:)` - Create InstallPlan for testing

---

## Success Criteria

**Phase 0 Complete When:**
- [ ] Test file structure planned
- [ ] Test categories defined
- [ ] Test gaps identified
- [ ] Fixture strategy defined
- [ ] Test execution strategy defined

**Phase 1+ Will:**
- Create actual test file
- Write contract tests
- Write behavior tests
- Add fixtures
- Run tests and verify

---

## Notes

- Start simple: one test file, basic tests
- Use existing test infrastructure (XCTest)
- Leverage existing test overrides
- Add complexity only when needed
- Focus on preserving existing behavior


