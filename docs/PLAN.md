# KanataManager Refactoring Plan

**Date:** September 29, 2025
**Status:** 🟡 Planning
**Goal:** Break up 4,400-line god object into focused, testable components

---

## Problem Statement

**Current State:** `KanataManager.swift` is a 4,400-line god object that violates Single Responsibility Principle and makes the codebase hard to understand, test, and maintain.

**Responsibilities (Too Many):**
1. Service lifecycle management (start/stop/restart)
2. Configuration file management (read/write/validate)
3. UI state management (@Published properties)
4. Process health monitoring
5. UDP client communication
6. Diagnostics and logging
7. Permission checking coordination
8. Emergency stop handling
9. Config hot-reload coordination
10. User interaction handling

**Evidence of Problem:**
- File size: 4,400 lines (recommended max: 400-500 lines)
- Multiple unrelated concerns in one class
- Hard to test (requires mocking 10+ dependencies)
- Hard to understand (where do I look for X?)
- Acknowledged in ADR-004 as "too large"

**Goal:** Extract focused services following Single Responsibility Principle, making each component:
- **Understandable** - Clear, single purpose
- **Testable** - Mockable dependencies, unit testable
- **Maintainable** - Small enough to hold in head
- **Idiomatic Swift** - Follows Apple best practices

**Target Architecture:**
```
KanataManager (coordinator, ~500 lines)
  ├─ ConfigurationService (~400 lines)
  ├─ ProcessLifecycleManager (exists, ~300 lines)
  ├─ ServiceHealthMonitor (~300 lines)
  ├─ DiagnosticsService (~400 lines)
  └─ UIStatePublisher (~200 lines)
```

---

## Success Criteria

**Quantitative:**
- ✅ KanataManager < 600 lines (from 4,400 lines = 86% reduction)
- ✅ Each extracted service < 500 lines
- ✅ Each service has single, clear responsibility
- ✅ All services have protocol-based interfaces (testable)
- ✅ Unit test coverage > 70% for new services

**Qualitative:**
- ✅ New developer can understand each service in < 15 minutes
- ✅ Services can be unit tested without launching app
- ✅ Changes to one concern (e.g., config format) touch one service
- ✅ No god objects remain

**Non-Goals:**
- ❌ Not rewriting functionality - surgical extraction only
- ❌ Not changing external APIs - internal refactoring
- ❌ Not fixing CGEvent taps (separate effort per CGEVENT_TAP_CLEANUP_PLAN.md)

---

## Strategy: Surgical Extraction with Coexistence

**Approach:** Build new services alongside old code, test incrementally, switch consumers one at a time.

**Why This Works:**
1. **Low risk** - Old code keeps working during refactor
2. **Testable** - New services can be tested before integration
3. **Reversible** - Easy rollback if issues found
4. **Proven** - Same strategy used successfully in validation refactor

**Anti-Pattern to Avoid:**
❌ Big-bang refactor - refactor entire KanataManager at once (high risk, hard to debug)

---

## Phase 1: Extract ConfigurationService

**Goal:** Move all configuration file management into dedicated service.

**Scope:**
- Config file reading/writing
- Config validation
- Default config generation
- Config path management
- Config format conversions (special keys, etc.)

**Files to Create:**
1. `Sources/KeyPath/Services/ConfigurationService.swift` (~400 lines)
   - Protocol: `ConfigurationServiceProtocol`
   - Implementation: `ConfigurationService`
   - Pure logic, no UI dependencies

2. `Tests/KeyPathTests/Services/ConfigurationServiceTests.swift` (~200 lines)
   - Test config reading/writing
   - Test validation logic
   - Test format conversions
   - Test error handling

**Files to Modify:**
- `KanataManager.swift` - Add ConfigurationService property, delegate config operations

**Success Criteria:**
- ✅ All config operations go through ConfigurationService
- ✅ ConfigurationService has no @Published properties (UI concern)
- ✅ ConfigurationService is fully unit tested
- ✅ KanataManager delegates to service for all config operations
- ✅ App builds and runs with no regressions

**Testing:**
```bash
# Unit tests
swift test --filter ConfigurationServiceTests

# Integration test
# 1. Launch app
# 2. Record a new key mapping
# 3. Verify config file written correctly
# 4. Edit config manually
# 5. Verify hot reload works
```

**Estimated Reduction:** ~800 lines from KanataManager (18% reduction)

---

## Phase 2: Extract ServiceHealthMonitor

**Goal:** Move service health checking and restart logic into dedicated monitor.

**Scope:**
- Service health checks (is process running? responsive?)
- Restart cooldown tracking (prevent restart loops)
- Health state publishing
- Recovery strategies (when to restart vs. give up)

**Files to Create:**
1. `Sources/KeyPath/Services/ServiceHealthMonitor.swift` (~300 lines)
   - Protocol: `ServiceHealthMonitorProtocol`
   - Implementation: `ServiceHealthMonitor`
   - Uses ProcessLifecycleManager (existing)

2. `Tests/KeyPathTests/Services/ServiceHealthMonitorTests.swift` (~150 lines)
   - Test health detection logic
   - Test restart cooldown
   - Test recovery strategies
   - Mock ProcessLifecycleManager

**Files to Modify:**
- `KanataManager.swift` - Add ServiceHealthMonitor property, delegate health checks

**Success Criteria:**
- ✅ All health checking goes through ServiceHealthMonitor
- ✅ Restart loop prevention logic is testable
- ✅ ServiceHealthMonitor is fully unit tested
- ✅ KanataManager delegates to monitor for all health operations
- ✅ Service recovery works as before

**Testing:**
```bash
# Unit tests
swift test --filter ServiceHealthMonitorTests

# Integration test
# 1. Launch app with kanata running
# 2. Verify status shows "healthy"
# 3. Kill kanata process: sudo pkill -f kanata
# 4. Verify monitor detects failure and triggers restart
# 5. Verify restart succeeds
```

**Estimated Reduction:** ~600 lines from KanataManager (14% reduction)

---

## Phase 3: Extract DiagnosticsService

**Goal:** Move diagnostic capabilities into dedicated service.

**Scope:**
- Log collection
- System state snapshots
- Permission status reporting
- Service status reporting
- Diagnostic report generation

**Files to Create:**
1. `Sources/KeyPath/Services/DiagnosticsService.swift` (~400 lines)
   - Protocol: `DiagnosticsServiceProtocol`
   - Implementation: `DiagnosticsService`
   - Aggregates data from other services

2. `Tests/KeyPathTests/Services/DiagnosticsServiceTests.swift` (~150 lines)
   - Test log collection
   - Test report generation
   - Test error handling
   - Mock dependencies

**Files to Modify:**
- `KanataManager.swift` - Add DiagnosticsService property
- `DiagnosticsView.swift` - Use DiagnosticsService instead of KanataManager

**Success Criteria:**
- ✅ All diagnostic operations go through DiagnosticsService
- ✅ DiagnosticsService can be tested without running app
- ✅ DiagnosticsView uses service, not manager
- ✅ Diagnostics screen works as before

**Testing:**
```bash
# Unit tests
swift test --filter DiagnosticsServiceTests

# Integration test
# 1. Launch app
# 2. Open Diagnostics tab
# 3. Verify all sections show correct data
# 4. Copy diagnostics report
# 5. Verify report contains expected information
```

**Estimated Reduction:** ~700 lines from KanataManager (16% reduction)

---

## Phase 4: Extract UIStatePublisher

**Goal:** Separate UI state publishing from business logic.

**Scope:**
- All @Published properties
- UI state derivation (e.g., computed properties for UI)
- State change notifications
- UI coordination logic

**Rationale:**
- ObservableObject mixing with business logic violates separation of concerns
- Makes testing harder (UI framework dependencies)
- Following MVVM pattern - ViewModels should be thin

**Files to Create:**
1. `Sources/KeyPath/UI/ViewModels/KanataViewModel.swift` (~200 lines)
   - Contains all @Published properties
   - Observes services and publishes UI state
   - Thin adapter between services and SwiftUI

2. `Tests/KeyPathTests/UI/KanataViewModelTests.swift` (~100 lines)
   - Test state derivation
   - Test service observation
   - Mock service dependencies

**Files to Modify:**
- `KanataManager.swift` - Remove @Published properties, no longer ObservableObject
- `ContentView.swift` - Use KanataViewModel instead of KanataManager
- Other views using KanataManager

**Success Criteria:**
- ✅ KanataManager has no @Published properties
- ✅ KanataManager is no longer ObservableObject
- ✅ All UI uses KanataViewModel
- ✅ ViewModel is fully unit tested
- ✅ UI updates work as before

**Testing:**
```bash
# Unit tests
swift test --filter KanataViewModelTests

# Integration test
# 1. Launch app
# 2. Verify all UI elements show correct state
# 3. Start/stop service
# 4. Verify UI updates correctly
# 5. Update config
# 6. Verify UI reflects changes
```

**Estimated Reduction:** ~400 lines from KanataManager (9% reduction)

---

## Phase 5: KanataManager as Coordinator

**Goal:** Reduce KanataManager to pure coordinator with no business logic.

**Final Responsibilities (Only):**
1. Own service instances (ConfigurationService, ServiceHealthMonitor, etc.)
2. Coordinate between services when needed
3. Handle app lifecycle events
4. Expose high-level operations to app

**Target Size:** ~500 lines

**Files to Modify:**
- `KanataManager.swift` - Final cleanup, remove remaining complexity

**Success Criteria:**
- ✅ KanataManager < 600 lines
- ✅ No business logic in KanataManager (all delegated to services)
- ✅ Clear, single responsibility (coordination)
- ✅ Easy to understand and test

**Final Architecture:**
```swift
@MainActor
class KanataManager {
    // Service dependencies (injected or created)
    private let configService: ConfigurationServiceProtocol
    private let healthMonitor: ServiceHealthMonitorProtocol
    private let diagnostics: DiagnosticsServiceProtocol
    private let processManager: ProcessLifecycleManager

    // High-level coordination methods
    func start() async throws { ... }
    func stop() async throws { ... }
    func updateConfiguration(_ config: String) async throws { ... }
    func emergencyStop() { ... }

    // No @Published properties (moved to ViewModel)
    // No config logic (moved to ConfigurationService)
    // No health logic (moved to ServiceHealthMonitor)
    // No diagnostic logic (moved to DiagnosticsService)
}
```

**Testing:**
```bash
# Full integration test suite
./run-tests.sh

# Manual testing
# 1. Launch app - verify everything works
# 2. Record keys - verify config updates
# 3. Stop/start service - verify reliability
# 4. Test all wizard flows
# 5. Test all settings changes
# 6. Test diagnostics
# 7. Test emergency stop
```

**Estimated Reduction:** ~400 lines final cleanup

---

## Phase 6: Documentation & Cleanup

**Goal:** Update documentation and remove temporary code.

**Tasks:**
1. Update CLAUDE.md with new architecture
2. Add ADR-009 documenting refactor decision and results
3. Update ARCHITECTURE.md (or consolidate into CLAUDE.md)
4. Remove any temporary/deprecated code
5. Update component diagrams

**Files to Update:**
- `CLAUDE.md` - Add new service architecture section
- `ARCHITECTURE.md` - Update or consolidate
- Add ADR-009 to Architecture Decision Records

**Success Criteria:**
- ✅ Documentation reflects new architecture
- ✅ No outdated references to old structure
- ✅ Clear guide for working with each service
- ✅ ADR documents decision and results

---

## Testing Strategy

### Unit Testing (New Services)
- Mock all dependencies using protocols
- Test business logic in isolation
- Fast feedback (< 1 second per test)
- High coverage (> 70%)

```swift
// Example: ConfigurationService unit test
func testValidateConfig_ValidConfig_ReturnsTrue() {
    let service = ConfigurationService()
    let validConfig = "(defsrc caps)\n(deflayer base esc)"

    XCTAssertNoThrow(try service.validate(validConfig))
}

func testValidateConfig_InvalidConfig_ThrowsError() {
    let service = ConfigurationService()
    let invalidConfig = "(invalid syntax)"

    XCTAssertThrowsError(try service.validate(invalidConfig))
}
```

### Integration Testing (After Each Phase)
- Test with real system
- Verify no regressions
- Manual testing checklist per phase

### Regression Testing (Final)
- Full test suite: `./run-tests.sh`
- Manual testing of all features
- Extended runtime testing (leave app running overnight)

---

## Risk Mitigation

### Risk 1: Breaking Existing Functionality
**Mitigation:**
- Coexistence strategy - new services alongside old code
- Test after each phase before proceeding
- Easy rollback (git revert)

### Risk 2: Protocol Explosion
**Problem:** Too many protocols makes code hard to navigate
**Mitigation:**
- One protocol per service (max 6 protocols total)
- Clear naming: `ConfigurationServiceProtocol`, `ServiceHealthMonitorProtocol`
- Keep protocols focused and small

### Risk 3: Over-Abstraction
**Problem:** Making services too generic or complicated
**Mitigation:**
- Keep services concrete and focused
- Extract only what exists, don't add new abstractions
- Prefer composition over inheritance

### Risk 4: Hidden Dependencies
**Problem:** Services depend on each other in unexpected ways
**Mitigation:**
- Make dependencies explicit (constructor injection)
- Document dependencies in service headers
- Use dependency injection for testing

---

## Timeline Estimate

**Phase 1: ConfigurationService** - 1-2 days
- Extract config logic
- Write unit tests
- Integration test

**Phase 2: ServiceHealthMonitor** - 1-2 days
- Extract health logic
- Write unit tests
- Integration test

**Phase 3: DiagnosticsService** - 1-2 days
- Extract diagnostics
- Write unit tests
- Integration test

**Phase 4: UIStatePublisher** - 1-2 days
- Extract UI state
- Create ViewModel
- Update views
- Integration test

**Phase 5: Final Coordinator** - 1 day
- Final cleanup
- Full testing

**Phase 6: Documentation** - 1 day
- Update docs
- Add ADR

**Total: 6-11 days** (depending on complexity discovered)

---

## Architectural Principles

### 1. Single Responsibility Principle
Each service has one reason to change:
- ConfigurationService: config format changes
- ServiceHealthMonitor: health detection logic changes
- DiagnosticsService: diagnostic requirements change

### 2. Dependency Injection
Services receive dependencies through constructor:
```swift
class ServiceHealthMonitor {
    init(processManager: ProcessLifecycleManagerProtocol) {
        self.processManager = processManager
    }
}
```

### 3. Protocol-Based Interfaces
Every service has a protocol for testing:
```swift
protocol ConfigurationServiceProtocol {
    func loadConfiguration() async throws -> String
    func saveConfiguration(_ config: String) async throws
    func validate(_ config: String) throws
}
```

### 4. Composition Over Inheritance
KanataManager composes services, doesn't inherit:
```swift
class KanataManager {
    private let configService: ConfigurationServiceProtocol
    private let healthMonitor: ServiceHealthMonitorProtocol

    func start() async throws {
        let config = try await configService.loadConfiguration()
        // ... coordinate services ...
    }
}
```

### 5. Testability First
Every service is designed to be unit tested:
- Pure functions where possible
- Mockable dependencies
- No hidden global state
- No UI framework dependencies in services

---

## Success Metrics

**Before Refactor:**
- KanataManager: 4,400 lines
- Responsibilities: 10+ concerns in one class
- Testability: Integration tests only (slow, brittle)
- Understanding: Takes hours to understand
- Maintenance: Changes touch many unrelated concerns

**After Refactor (Target):**
- KanataManager: < 600 lines (86% reduction)
- Services: 5 focused services, each < 500 lines
- Testability: Unit tests for all services (fast, reliable)
- Understanding: Each service understandable in < 15 minutes
- Maintenance: Changes touch one service, clear where to look

**Tracking Progress:**
```bash
# Monitor line count after each phase
wc -l Sources/KeyPath/Managers/KanataManager.swift

# Track test coverage
swift test --enable-code-coverage
xcrun llvm-cov report
```

---

## Decision Points

### After Phase 1
**Question:** Is ConfigurationService providing value?
**Metrics:**
- Is config code easier to test?
- Is config logic clearer?
- Did we reduce KanataManager size meaningfully?

**Decision:** Proceed to Phase 2 if yes, adjust approach if no

### After Phase 3
**Question:** Have we achieved sufficient separation?
**Metrics:**
- Is KanataManager < 2,000 lines?
- Are services testable and clear?
- Is code easier to understand?

**Decision:** Proceed to Phase 4 or stop here if diminishing returns

### After Phase 5
**Question:** Should we extract more services?
**Risk:** Over-engineering vs. clarity

**Decision:** Stop here unless clear benefit to further extraction

---

## Follow-Up Work

**After this refactor completes:**

### Priority 1: CGEvent Tap Architecture
See `CGEVENT_TAP_CLEANUP_PLAN.md`
- Move all event taps to daemon
- Eliminate keyboard freezing
- GUI becomes pure UI

### Priority 2: Wizard Simplification
- Complete Phase 5 (remove SystemSnapshotAdapter)
- Evaluate if multiple engines/coordinators needed
- Simplify to single StateManager if possible

### Priority 3: Testing Infrastructure
- Add protocol-based dependency injection throughout
- Increase unit test coverage
- Reduce reliance on integration tests

---

## Related Documents

- **REFACTOR_COMPLETE.md** - Validation refactor (successful example of this strategy)
- **CGEVENT_TAP_CLEANUP_PLAN.md** - Next priority after this refactor
- **CLAUDE.md** - Main architecture documentation
- **ADR-004** - Documents manager consolidation that led to god object

---

## Notes

**Why Now?**
The validation refactor (September 29, 2025) proved the surgical extraction strategy works:
- 54% code reduction
- Zero regressions
- Improved reliability
- Same approach can work for KanataManager

**Why This Matters:**
KanataManager is the heart of the application. Breaking it up will:
- Make the entire codebase easier to understand
- Enable faster feature development
- Improve reliability through better testing
- Follow Apple best practices (SRP, MVVM)
- Set pattern for future refactoring work

---

**Document Version:** 1.0
**Author:** Claude Code
**Date:** September 29, 2025


## Config Apply Pipeline (New Work)
- Introduce `ConfigApplyPipeline` actor as single entry point for edits
- Pre-/post-write validation; transactional writes via `ConfigurationManager`
- Hot reload (TCP) then wait-for-ready (engine response or log `driver_connected 1`) with timeout
- Typed error model (`ConfigError`) and structured `ConfigDiagnostics`
- UI: success toast only on non-rollback; error toast with copyable diagnostics on rollback
- Observability: `os.Logger` categories (`config.apply`, `config.validate`, `config.write`, `config.reload`)
- Migration: `SimpleModsService` becomes thin adapter; writing centralized
- Tests: unit tests for parser/writer/pipeline; integration tests for reload/rollback

### Implementation Steps
1) Create `docs/CONFIG_APPLY_PIPELINE.md` (design doc) ✅
2) Add types: `ConfigEditCommand`, `ConfigError`, `ConfigDiagnostics`, `ApplyResult` (in Core)
3) Implement `ConfigApplyPipeline` (actor) with staged flow
4) Move disk writing into `ConfigurationManager` atomic write API
5) Expose short-lived log watcher utility for `driver_connected 1`
6) Refactor `SimpleModsService` to call pipeline; remove direct writes/health checks
7) Introduce `os.Logger` instrumentation (subsystem/categories)
8) Update UI to use `ApplyResult`; ensure rollback errors produce red toast with details
9) Tests: unit and integration (mock TCP + log watcher)
10) Rollout guarded behind feature flag; default on after validation



