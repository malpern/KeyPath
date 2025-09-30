# KeyPath Architecture Improvement Plan

**Status:** Draft
**Date:** 2025-09-29
**Goal:** Simplify state management to eliminate validation spam and improve reliability

---

## Executive Summary

KeyPath has struggled with state synchronization issues causing "validation spam" - multiple concurrent validations cancelling each other and showing stale UI state. Despite multiple fixes (removing Combine listeners, Oracle cache invalidation, onChange triggers, duplicate notification handlers), new instances keep appearing.

**Root Cause:** Too many independent state machines trying to stay synchronized through reactive patterns (Combine publishers, SwiftUI onChange, NotificationCenter). This creates cascading updates and race conditions.

**Solution:** Surgical replacement of the validation/state subsystem with a simple pull-based model. Keep the hard-won domain logic (PermissionOracle, LaunchDaemonInstaller, etc.) and replace only the problematic state coordination layer.

**Scope:** ~8-10 focused sessions over 2-3 weeks for a side project pace.

---

## Current Problems

### 1. Validation Spam (Documented in CLAUDE.md)
- Multiple rounds of fixes: Combine listeners → Oracle cache → onChange → duplicate notifications
- Each fix addresses a symptom, not the root cause
- Logs show concurrent validations cancelling each other
- UI shows stale "checking..." state or incorrect status

### 2. Architectural Issues
**Over-engineered wizard subsystem (41 files):**
- WizardNavigationEngine + WizardNavigationCoordinator + WizardStateInterpreter
- IssueGenerator + ServiceStatusEvaluator + PermissionGrantCoordinator
- Multiple overlapping responsibilities

**KanataManager god object (4,401 lines across 6 files):**
- Owns too many responsibilities: process lifecycle, config, UDP, events
- Extensions (Configuration, EventTaps, Engine, Lifecycle, Output) indicate need for extraction

**State synchronization complexity:**
- 6+ managers with overlapping state
- Caching at multiple levels creating staleness bugs
- Reactive patterns creating cascade updates

### 3. Reliability Issues
- Cannot guarantee validation runs exactly once per trigger
- UI state can diverge from system state
- Difficult to reason about when state updates will occur

---

## What to Keep (Hard-Won Domain Knowledge)

### ✅ Keep Unchanged

1. **PermissionOracle (663 lines)**
   - Represents real macOS TCC complexity you've solved
   - Hierarchical permission checking with Apple API → TCC fallback
   - Well-documented with architectural rationale

2. **LaunchDaemonInstaller (2,465 lines)**
   - Domain complexity is genuine (service ordering, privilege escalation, recovery)
   - This is just hard on macOS

3. **VHIDDeviceManager**
   - Karabiner driver interaction logic
   - Component detection and health checking

4. **KanataUDPClient / SharedUDPClientService**
   - Communication protocol implementation
   - Authentication and session management

5. **WizardTypes.swift**
   - Type definitions are useful (enums for requirements, states, etc.)
   - Good domain modeling

6. **Wizard UI Pages**
   - Individual page views are fine
   - WizardDesignSystem is good

---

## What to Replace (State Synchronization Mess)

### ❌ Replace with Simpler Architecture

1. **Validation Orchestration**
   - Delete: StartupValidator (346 lines)
   - Delete: SystemStatusChecker (937 lines)
   - Replace with: **SystemValidator** (~200 lines)

2. **Wizard Coordination**
   - Delete: WizardNavigationEngine
   - Delete: WizardNavigationCoordinator
   - Delete: WizardStateInterpreter
   - Delete: IssueGenerator (separate from detection)
   - Delete: ServiceStatusEvaluator
   - Replace with: **WizardStateMachine** (~150 lines)

3. **State Management Pattern**
   - Current: Push model (Combine, onChange, NotificationCenter auto-triggering)
   - New: **Pull model** (UI explicitly requests state when needed)

---

## New Architecture Design

### Core Principle: Explicit State Updates Only

**No automatic reactivity:**
- No Combine publishers triggering validation
- No SwiftUI onChange triggering validation
- No NotificationCenter auto-triggering validation
- UI explicitly calls refresh when user requests it

### New Components

#### 1. SystemValidator (replaces StartupValidator + SystemStatusChecker)

```swift
@MainActor
class SystemValidator {
    // Dependencies (existing services)
    private let oracle = PermissionOracle.shared
    private let daemonInstaller = LaunchDaemonInstaller()
    private let vhidManager = VHIDDeviceManager()
    private let processManager: ProcessLifecycleManager

    // Single public method - no caching, no state
    func checkSystem() async -> SystemSnapshot {
        // 1. Get permissions from Oracle (has its own cache)
        let permissions = await oracle.currentSnapshot()

        // 2. Check components
        let components = checkComponents()

        // 3. Check conflicts
        let conflicts = await processManager.detectConflicts()

        // 4. Check health
        let health = checkHealth()

        // 5. Return complete snapshot
        return SystemSnapshot(
            permissions: permissions,
            components: components,
            conflicts: conflicts,
            health: health,
            timestamp: Date()
        )
    }

    // Helper methods call existing services
    private func checkComponents() -> ComponentStatus { ... }
    private func checkHealth() -> HealthStatus { ... }
}

// Simple data structure - no logic
struct SystemSnapshot {
    let permissions: PermissionOracle.Snapshot
    let components: ComponentStatus
    let conflicts: ConflictStatus
    let health: HealthStatus
    let timestamp: Date

    // Computed properties for UI
    var isReady: Bool { ... }
    var blockingIssues: [Issue] { ... }
    var allIssues: [Issue] { ... }
}
```

**Key characteristics:**
- Stateless (no @Published, no cached results)
- Synchronous helpers for components/health
- Async only for network/process operations
- Pure function: same inputs → same outputs
- Oracle manages its own cache (1.5s TTL)

#### 2. WizardStateMachine (replaces Navigation Engine/Coordinator/Interpreter)

```swift
@MainActor
class WizardStateMachine: ObservableObject {
    @Published var currentPage: WizardPage = .summary
    @Published var systemState: SystemSnapshot?
    @Published var isRefreshing = false

    private let validator = SystemValidator()
    private let fixer = SystemFixer() // Renamed WizardAutoFixer

    // UI calls this explicitly
    func refresh() async {
        isRefreshing = true
        systemState = await validator.checkSystem()
        isRefreshing = false
    }

    // Simple navigation - no complex state interpretation
    func nextPage() {
        guard let state = systemState else { return }
        currentPage = determineNextPage(from: currentPage, state: state)
    }

    func previousPage() {
        currentPage = determinePreviousPage(from: currentPage)
    }

    // Simple state-based logic
    private func determineNextPage(from current: WizardPage, state: SystemSnapshot) -> WizardPage {
        // Linear flow with skip logic for completed steps
        switch current {
        case .summary:
            if !state.conflicts.isEmpty { return .conflicts }
            if state.permissions.hasMissingKeyPathPermissions { return .inputMonitoring }
            // ... etc
        case .conflicts:
            if state.permissions.hasMissingKeyPathPermissions { return .inputMonitoring }
            // ... etc
        }
    }
}
```

**Key characteristics:**
- Single @Published state property
- Explicit refresh (no automatic)
- Simple page navigation logic
- No separate coordinator/engine/interpreter

#### 3. MainAppStateController (replaces StartupValidator in ContentView)

```swift
@MainActor
class MainAppStateController: ObservableObject {
    @Published var systemState: SystemSnapshot?
    @Published var showWizard = false

    private let validator = SystemValidator()
    private var hasRunInitialValidation = false

    // Called once on app launch
    func performInitialValidation() async {
        guard !hasRunInitialValidation else { return }
        hasRunInitialValidation = true

        // Wait for services to be ready (existing logic)
        await kanataManager.waitForServiceReady(timeout: 10.0)

        // Single validation
        systemState = await validator.checkSystem()

        // Auto-open wizard if issues
        if let state = systemState, state.hasBlockingIssues {
            showWizard = true
        }
    }

    // Manual refresh only (button in UI)
    func refreshStatus() async {
        systemState = await validator.checkSystem()
    }
}
```

**Key characteristics:**
- Explicit once-on-launch validation
- No automatic revalidation
- Manual refresh button for user control
- Simple flag prevents duplicate runs

---

## Implementation Plan

### Phase 1: Build New SystemValidator (2-3 sessions)

**Goal:** Create new validator alongside existing code, prove it works

**Tasks:**
1. Create `Sources/KeyPath/Services/SystemValidator.swift`
2. Create `Sources/KeyPath/Models/SystemSnapshot.swift`
3. Implement SystemValidator by calling existing services:
   - PermissionOracle.shared.currentSnapshot()
   - LaunchDaemonInstaller methods
   - VHIDDeviceManager methods
   - ProcessLifecycleManager.detectConflicts()
4. Add computed properties to SystemSnapshot:
   - `isReady: Bool`
   - `blockingIssues: [Issue]`
   - `allIssues: [Issue]`
5. Write simple test that calls validator and inspects snapshot

**Success Criteria:**
- SystemValidator returns complete state
- No caching (each call is fresh, except Oracle's internal cache)
- No side effects (pure state inspection)

**Files to Create:**
- `Sources/KeyPath/Services/SystemValidator.swift` (~200 lines)
- `Sources/KeyPath/Models/SystemSnapshot.swift` (~100 lines)

**Files to Reference (not modify):**
- PermissionOracle.swift
- LaunchDaemonInstaller.swift
- VHIDDeviceManager.swift
- ProcessLifecycleManager.swift

---

### Phase 2: Rewrite Wizard (3-4 sessions)

**Goal:** New wizard using SystemValidator, simple state machine

**Tasks:**
1. Create `Sources/KeyPath/InstallationWizard/Core/WizardStateMachine.swift`
2. Implement simple page navigation (determineNextPage/previousPage)
3. Create `Sources/KeyPath/UI/NewInstallationWizardView.swift` (temporary name)
4. Connect existing wizard pages to new state machine
5. Test wizard flow manually
6. Add "New Wizard (Beta)" button to test alongside old wizard

**Success Criteria:**
- Wizard shows correct status on each page
- Navigation flows logically based on system state
- Manual refresh button updates state correctly
- No automatic updates (no validation spam)

**Files to Create:**
- `Sources/KeyPath/InstallationWizard/Core/WizardStateMachine.swift` (~150 lines)
- `Sources/KeyPath/UI/NewInstallationWizardView.swift` (scaffold only)

**Files to Modify:**
- Existing wizard pages (connect to new state machine)

**Files to Eventually Delete (mark with TODO comments for now):**
- WizardNavigationEngine.swift
- WizardNavigationCoordinator.swift
- WizardStateInterpreter.swift
- IssueGenerator.swift (logic moves to SystemSnapshot computed properties)
- ServiceStatusEvaluator.swift

---

### Phase 3: Replace Main App Validator (2 sessions)

**Goal:** Replace StartupValidator in ContentView with simple controller

**Tasks:**
1. Create `Sources/KeyPath/Services/MainAppStateController.swift`
2. Replace StartupValidator usage in ContentView
3. Remove all automatic validation triggers:
   - No Combine publishers
   - No onChange handlers
   - No NotificationCenter auto-triggers
4. Add manual "Refresh Status" button
5. Keep single notification handler for wizard close (`.kp_startupRevalidate`)
6. Test app launch → initial validation → no spam

**Success Criteria:**
- App launches, runs ONE validation
- Wizard closes, runs ONE validation
- Manual refresh runs ONE validation
- No concurrent validations in logs
- UI state always reflects latest validation (no staleness)

**Files to Create:**
- `Sources/KeyPath/Services/MainAppStateController.swift` (~100 lines)

**Files to Modify:**
- `Sources/KeyPath/UI/ContentView.swift` (replace StartupValidator)
- `Sources/KeyPath/Services/StartupCoordinator.swift` (simplify notification posting)

**Files to Delete:**
- `Sources/KeyPath/Services/StartupValidator.swift`

---

### Phase 4: Cleanup & Simplify Managers (2-3 sessions)

**Goal:** Extract responsibilities from KanataManager, delete old wizard code

**Tasks:**
1. Extract from KanataManager:
   - Create `KanataProcessController` (lifecycle only)
   - Promote `KanataConfigManager` to main service
   - Use existing SharedUDPClientService
2. Delete old wizard orchestration files:
   - WizardNavigationEngine.swift
   - WizardNavigationCoordinator.swift
   - WizardStateInterpreter.swift
   - IssueGenerator.swift (if logic fully moved)
   - ServiceStatusEvaluator.swift
   - SystemStatusChecker.swift
3. Rename NewInstallationWizardView → InstallationWizardView
4. Update CLAUDE.md with new architecture

**Success Criteria:**
- KanataManager is ~1000 lines (coordination only)
- Old wizard files deleted
- New architecture documented
- All tests passing

**Files to Create:**
- `Sources/KeyPath/Services/KanataProcessController.swift` (~300 lines)

**Files to Modify:**
- `Sources/KeyPath/Managers/KanataManager.swift` (reduce to coordinator)
- CLAUDE.md (document new architecture)

**Files to Delete:**
- InstallationWizard/Core/WizardNavigationEngine.swift
- InstallationWizard/Core/WizardNavigationCoordinator.swift
- InstallationWizard/Core/WizardStateInterpreter.swift
- InstallationWizard/Core/IssueGenerator.swift
- InstallationWizard/Core/ServiceStatusEvaluator.swift
- InstallationWizard/Core/SystemStatusChecker.swift
- Services/StartupValidator.swift

---

## Migration Strategy

### Coexistence During Development

1. **Phase 1-2:** New code lives alongside old
   - SystemValidator doesn't interfere with existing code
   - New wizard can be tested via separate button
   - Zero risk to existing functionality

2. **Phase 3:** Cutover point
   - Replace StartupValidator → MainAppStateController
   - This is the key moment where behavior changes
   - Keep old wizard available as fallback initially

3. **Phase 4:** Cleanup
   - Only delete old code after new code is proven
   - Can be done incrementally

### Rollback Plan

If new architecture has issues:
- Phase 1-2: Just delete new files
- Phase 3: Revert ContentView changes, restore StartupValidator
- Phase 4: N/A (wouldn't reach this if problems exist)

---

## Testing Strategy

### Manual Testing Checklist

**Validation Behavior:**
- [ ] App launches → ONE validation runs
- [ ] Check logs: no concurrent validations
- [ ] UI shows spinner → status (no stuck spinner)
- [ ] Manual refresh button works
- [ ] Wizard opens with correct status
- [ ] Wizard refresh button works
- [ ] Wizard close → ONE validation runs
- [ ] Multiple rapid refreshes don't cause crashes

**Status Accuracy:**
- [ ] Permissions granted → shows green
- [ ] Permissions denied → shows red
- [ ] Service running → shows active
- [ ] Service stopped → shows ready/stopped
- [ ] Main screen matches wizard status (no divergence)

**Wizard Flow:**
- [ ] Summary page shows correct status
- [ ] Navigation skips completed steps
- [ ] Auto-fix buttons work
- [ ] Manual fix instructions clear
- [ ] Final page starts service

### Log Analysis

Compare logs before/after for validation spam:

**Before (problematic):**
```
🔍 [StartupValidator] Starting validation (runID: A)
🔍 [SystemStatusChecker] Starting detection (runID: B)
🚫 [StartupValidator] Cancelled (runID: A)
🔍 [StartupValidator] Starting validation (runID: C)
🚫 [StartupValidator] Cancelled (runID: C)
```

**After (desired):**
```
🔍 [MainAppStateController] Initial validation starting
🔍 [SystemValidator] Checking system state
✅ [MainAppStateController] Validation complete (1.2s)
```

---

## Success Metrics

### Quantitative
- Lines of code: ~38,687 → ~36,000 (7% reduction in complexity)
- Wizard subsystem: 41 files → ~25 files (remove coordinators/engines)
- KanataManager: 4,401 lines → ~1,200 lines (extract services)
- Validation files: 2 files (1,283 lines) → 2 files (~300 lines)

### Qualitative
- Zero validation spam in logs
- UI state never stale/stuck
- Easy to reason about when state updates
- No race conditions or cancellations
- Reliable one-time validation on app launch

### Side Project Sustainability
- New developer can understand state flow in <30 minutes
- Adding new system checks is straightforward
- Debugging state issues is simple (no cascade tracking)

---

## Risk Mitigation

### Risk 1: Recreating Same Problems

**Mitigation:**
- Strict rule: No automatic reactivity in new code
- Code review checkpoint after Phase 1: verify stateless design
- If validation spam reappears, pause and analyze root cause

### Risk 2: Breaking Existing Functionality

**Mitigation:**
- Build new code alongside old (Phases 1-2)
- Comprehensive manual testing before cutover (Phase 3)
- Keep old wizard available as fallback initially

### Risk 3: Underestimating Complexity

**Mitigation:**
- Phase 1 is proof-of-concept (if it's harder than expected, reassess)
- Can abort after any phase without losing work
- Document learnings in CLAUDE.md as you go

### Risk 4: Side Project Burnout

**Mitigation:**
- Each phase is ~2-3 sessions (digestible chunks)
- Concrete deliverables per phase (working code, not refactoring)
- Can pause after Phase 2 and have usable new wizard

---

## Decision Points

### After Phase 1: Continue or Pivot?

**If SystemValidator is simpler and clearer:** → Continue to Phase 2
**If SystemValidator recreates complexity:** → Reassess (maybe complexity is essential)

### After Phase 2: Commit to Cutover?

**If new wizard is more reliable:** → Continue to Phase 3
**If new wizard has same issues:** → Document learnings, keep old code

### After Phase 3: Complete Cleanup?

**If main app is stable:** → Continue to Phase 4
**If issues emerge:** → Stabilize before cleanup

---

## Open Questions

1. **KanataManager extraction:** How much to extract now vs. later?
   - Recommendation: Do minimal extraction in Phase 4, defer deeper refactor

2. **Wizard page flow:** Keep all existing pages or simplify?
   - Recommendation: Keep existing pages, just change coordination

3. **Issue generation:** Inline in SystemSnapshot or separate?
   - Recommendation: Inline as computed properties (simpler)

4. **Testing:** Add unit tests or rely on manual testing?
   - Recommendation: Manual testing for side project, add unit tests if time permits

---

## Timeline Estimate (Side Project Pace)

**Phase 1:** 2-3 sessions × 2-3 hours = 4-9 hours
**Phase 2:** 3-4 sessions × 2-3 hours = 6-12 hours
**Phase 3:** 2 sessions × 2-3 hours = 4-6 hours
**Phase 4:** 2-3 sessions × 2-3 hours = 4-9 hours

**Total:** 18-36 hours over 2-4 weeks

Aggressive: 2 weeks (3-4 sessions/week)
Comfortable: 4 weeks (2 sessions/week)

---

## Next Steps

1. **Review this plan:** Adjust based on your constraints/priorities
2. **Start Phase 1:** Create SystemValidator.swift
3. **Validate approach:** Verify new validator is simpler/clearer
4. **Decide:** Continue to Phase 2 or pivot based on learnings

---

## Appendix: Key Architectural Principles

### Do's ✅
- **Pull model:** UI explicitly requests state
- **Single source of truth:** One @Published property drives UI
- **Stateless services:** Services don't cache (except Oracle's internal 1.5s TTL)
- **Explicit updates:** All state changes initiated by user action
- **Simple data flow:** UI → Controller → Validator → Services → Data

### Don'ts ❌
- **No automatic reactivity:** No Combine publishers triggering validation
- **No cascading updates:** No onChange/NotificationCenter auto-triggers
- **No multi-level caching:** Only Oracle caches (it manages its own TTL)
- **No concurrent validations:** Ensure one validation at a time
- **No complex coordination:** No engine/coordinator/interpreter layers

### When in Doubt
Ask: "Could this trigger an automatic validation?"
If yes → Remove it, make it explicit.

---

**Document Version:** 1.0
**Last Updated:** 2025-09-29
**Status:** Ready for Phase 1 implementation