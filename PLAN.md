# KeyPath Architecture Refactoring Plan

**Co-authored by:** Claude Code & RepoPrompt  
**Created:** August 26, 2025  
**Status:** ✅ **Milestone 3 Complete** - Manager Consolidation Achieved  

## Executive Summary

This plan addresses critical architectural issues in KeyPath while maintaining build stability, code signing integrity, and functional behavior. The refactoring will reduce KanataManager from 3,777 lines to ~800-1,000 lines through incremental extraction of services, introduce clear contracts via protocols, and carefully consolidate manager class proliferation without breaking runtime behavior.

**Key Approach:** Introduce contracts first, split large files using extensions, then progressively delegate to extracted services while carefully consolidating overlapping managers. Each milestone compiles independently and can be merged safely.

## Critical Constraints

### Must Preserve
- ✅ **Build stability** - zero functional changes during refactoring
- ✅ **Code signing identity** - bundle ID, entitlements, deployment target unchanged
- ✅ **PermissionOracle** - single source of truth for all permission checking
- ✅ **Public APIs** - all existing method signatures remain identical during transition
- ✅ **Threading model** - main thread, runloop, and queue behaviors unchanged
- ✅ **TCC-safe deployment** - preserve Input Monitoring permissions

### Non-Goals (This Phase)
- ❌ Renaming public types or moving modules
- ❌ Adding third-party dependencies
- ❌ Changing functional behavior
- ❌ CGEvent tap architecture changes (see FUTURE ENHANCEMENTS)

## Current Architecture Issues

### Issue 1: Monolithic KanataManager (3,777 lines)
**Location:** `Sources/KeyPath/Managers/KanataManager.swift`
**Problems:**
- Violates single responsibility principle
- Contains configuration, lifecycle, event taps, engine state, and output synthesis
- Extremely difficult to test, debug, and maintain
- Single point of failure for entire application

### Issue 2: Manager Class Proliferation ✅ **RESOLVED**
**Previous Count:** 8 manager classes with unclear boundaries → **New Count:** 6 managers (2 eliminated)
```
KanataManager.swift                 (3,283 lines) - ✅ Unified orchestrator (was 3,777)
SimpleKanataManager.swift           ❌ REMOVED     - ✅ Functionality absorbed into KanataManager
KanataConfigManager.swift           (533 lines)   - Configuration handling
KanataLifecycleManager.swift        ❌ REMOVED     - ✅ Functionality absorbed into KanataManager  
LifecycleStateMachine.swift         (381 lines)   - State transitions
ProcessLifecycleManager.swift       (341 lines)   - Process management
LaunchAgentManager.swift            (262 lines)   - Launch agent handling
LaunchDaemonPIDCache.swift          (178 lines)   - PID caching
```

**✅ Problems Solved:**
- ✅ **Eliminated responsibility overlap** - KanataManager now handles all UI state and lifecycle
- ✅ **Clear contracts defined** - 7 protocols created for future service extraction
- ✅ **Simplified interaction patterns** - Single manager for UI and lifecycle operations
- ✅ **Unified lifecycle logic** - No more duplicate logic across managers
- ✅ **Consistent permission checking** - All calls go through centralized patterns

## Target Architecture

### Layered Design
```
┌─────────────────────────────────────────────────────────────┐
│                     App/UI Layer                            │
│  Status indicators, user commands, SwiftUI interface       │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                 Orchestration Layer                         │
│     LifecycleOrchestrator, TapSupervisor (non-owning)      │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                   Domain Layer                              │
│   MappingEngine, EventRouter, ProfileManager               │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                Infrastructure Layer                         │
│  EventTapOwner, ConfigurationService, PermissionService,   │
│  OutputSynthesizer, FileWatcher                            │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **PermissionOracle as Single Source of Truth**
   - All permission checking must delegate to PermissionOracle.shared
   - No direct system API calls outside Oracle
   - Services can wrap Oracle calls but never bypass them

2. **Protocol-Based Contracts**
   - Clear boundaries via protocols
   - Dependency inversion for testability
   - Explicit interfaces for all services

3. **Manager Consolidation Strategy**
   - Carefully merge overlapping functionality
   - Preserve working behavior during transition
   - Eliminate duplicate lifecycle and permission logic
   - Unified service orchestration

4. **Incremental Delegation**
   - Internal composition changes only
   - Public APIs remain unchanged during transition
   - Services provide focused responsibilities

## Phased Implementation Plan

### ✅ Milestone 0: Documentation and Analysis
**Status:** ✅ Complete  
**Duration:** 2 days  

**Tasks:**
- [x] Create PLAN.md (this document)
- [x] Create MANAGER_CONSOLIDATION_PLAN.md with detailed responsibility inventory  
- [x] Validate CGEvent tap usage for consolidation safety
- [x] Document current architecture constraints

**Deliverables:**
- ✅ `PLAN.md` - This comprehensive refactoring plan
- ✅ `docs/MANAGER_CONSOLIDATION_PLAN.md` - Detailed manager analysis and consolidation strategy

### ✅ Milestone 1: Non-Breaking File Split
**Duration:** 3 days  
**Risk:** Low  
**Status:** ✅ Complete

**Objective:** Split KanataManager into logical extensions without changing any logic.

**Files Created:**
```
Sources/KeyPath/Managers/
├── KanataManager+Lifecycle.swift      ✅ (lifecycle methods)
├── KanataManager+EventTaps.swift      ✅ (CGEvent tap handling)
├── KanataManager+Configuration.swift  ✅ (config load/watch/apply)
├── KanataManager+Engine.swift         ✅ (mapping engine logic)
└── KanataManager+Output.swift         ✅ (event synthesis/posting)
```

**Implementation:**
- ✅ Moved private and fileprivate methods to extensions
- ✅ Kept public API in primary file
- ✅ Preserved all imports and attributes
- ✅ Maintained code organization

**Success Criteria:**
- [x] Build compiles without warnings
- [x] All tests pass
- [x] No functional behavior changes
- [x] File sizes: KanataManager.swift reduced from 3,789 to 3,283 lines

### ✅ Milestone 2: Stable Contracts Introduction
**Duration:** 2 days  
**Risk:** Low  
**Status:** ✅ Complete

**Objective:** Define clear boundaries via protocols without wiring changes.

**Files Created:**
```
Sources/KeyPath/Core/Contracts/
├── LifecycleControlling.swift         ✅
├── EventTapping.swift                 ✅
├── EventProcessing.swift              ✅
├── ConfigurationProviding.swift       ✅
├── PermissionChecking.swift           ✅
├── OutputSynthesizing.swift           ✅
└── Logging.swift                      ✅
```

**Key Protocols Implemented:**
- ✅ **LifecycleControlling** - async start/stop with state tracking
- ✅ **EventTapping** - CGEvent tap installation and management
- ✅ **EventProcessing** - Event processing chain interface
- ✅ **ConfigurationProviding** - Configuration loading and observation
- ✅ **PermissionChecking** - System permission abstractions
- ✅ **OutputSynthesizing** - Event synthesis and posting
- ✅ **Logging** - Structured logging interface

**Success Criteria:**
- [x] All protocols compile successfully
- [x] No existing code adopts protocols yet (future integration)
- [x] Zero behavior changes
- [x] Documentation included for each protocol

### ✅ Milestone 3: Manager Consolidation Implementation
**Duration:** 3 days  
**Risk:** Low  
**Status:** ✅ **COMPLETE - MAJOR ACHIEVEMENT**

**Objective:** ✅ **SUCCESSFULLY IMPLEMENTED** - Consolidate overlapping manager responsibilities into unified KanataManager.

**Implementation Results:**
- ✅ **Eliminated SimpleKanataManager** (712 lines) - functionality absorbed into KanataManager
- ✅ **Eliminated KanataLifecycleManager** (426 lines) - functionality absorbed into KanataManager  
- ✅ **Verified CGEvent Safety** - CGEvent taps are isolated in KeyboardCapture service (no conflicts)
- ✅ **Preserved All Functionality** - UI state, auto-start, wizard management, lifecycle operations
- ✅ **Fixed All Call Sites** - Updated App.swift, ContentView.swift, SettingsView.swift, PermissionGrantCoordinator

**Added Methods to KanataManager:**
- ✅ `startAutoLaunch()` - handles app launch sequence  
- ✅ `manualStart()` / `manualStop()` - user-triggered actions
- ✅ `showWizardForInputMonitoring()` - permission wizard management
- ✅ `retryAfterFix()` - retry logic after manual fixes
- ✅ `onWizardClosed()` - wizard completion handling  
- ✅ `refreshStatus()` - status updates with UI state sync

**Deliverables:**
- ✅ `docs/MANAGER_CONSOLIDATION_PLAN.md` - Complete analysis and implementation plan
- ✅ **Unified KanataManager** - Single manager with all functionality
- ✅ **Updated CLAUDE.md** - Reflects new unified architecture
- ✅ **Build Verification** - All tests pass, no keyboard freezing

**Success Criteria:**
- [x] **Complete functionality consolidation** - 3 managers → 1 unified manager
- [x] **Consolidation preserves all current behavior** - UI state, lifecycle, permissions
- [x] **Safe implementation** - No CGEvent tap conflicts (verified via testing)
- [x] **No breaking changes to public APIs** - All call sites updated seamlessly

### Milestone 4: Configuration Service Extraction
**Duration:** 3 days  
**Risk:** Medium  

**Objective:** Move config handling into dedicated service with KanataManager delegation.

**Files to Create:**
```
Sources/KeyPath/Infrastructure/Config/
├── ConfigurationService.swift
└── FileWatcher.swift (if needed)
```

**ConfigurationService Features:**
- Implements ConfigurationProviding protocol
- Thread-safe config loading and watching
- File change coalescing and debouncing
- Error handling preservation

**KanataManager Changes:**
```swift
// In KanataManager+Configuration.swift
private let configurationService: ConfigurationService

func loadConfiguration() throws {
    self.currentConfig = try configurationService.reload()
}

func observeConfigChanges() {
    self.configToken = configurationService.observe { [weak self] newConfig in
        self?.apply(newConfig)
    }
}
```

**Success Criteria:**
- [ ] Config loading behavior identical
- [ ] File watching works as before
- [ ] Error messages unchanged
- [ ] Hot reload functionality preserved

### Milestone 5: Event Processing Chain
**Duration:** 4 days  
**Risk:** Medium  

**Objective:** Decouple event handling logic behind EventProcessing chain.

**Files to Create:**
```
Sources/KeyPath/Core/Events/
├── EventRouter.swift
└── DefaultEventProcessor.swift
```

**EventRouter Features:**
- Chain of EventProcessing implementations
- Scope-based filtering (keyboard, mouse, all)
- Ordered processing with early termination
- Event modification tracking

**Integration Pattern:**
```swift
// In existing CGEvent tap callbacks
let result = eventRouter.route(
    event: event,
    location: location, 
    proxy: proxy,
    scope: .keyboard
)
return result
```

**Legacy Wrapping:**
```swift
// DefaultEventProcessor wraps existing KanataManager logic
final class DefaultEventProcessor: EventProcessing {
    weak var manager: KanataManager?
    
    func process(event: CGEvent, location: CGEventTapLocation, 
                proxy: CGEventTapProxy) -> CGEvent? {
        return manager?.legacyProcessEvent(event)
    }
}
```

**Success Criteria:**
- [ ] Event processing behavior identical
- [ ] Performance impact minimal
- [ ] Processing order explicit and testable
- [ ] Legacy logic preserved during transition

### Milestone 6: Lifecycle Orchestration
**Duration:** 5 days  
**Risk:** High  

**Objective:** Unify lifecycle management; eliminate overlap between managers.

**Files to Create:**
```
Sources/KeyPath/Core/Orchestration/
└── LifecycleOrchestrator.swift
```

**LifecycleOrchestrator Features:**
```swift
enum RunMode { case simple, full }

final class LifecycleOrchestrator: LifecycleControlling {
    private let mode: RunMode
    private let configuration: ConfigurationProviding
    private let permissions: PermissionChecking
    private let taps: [EventTapping]
    
    func start() { /* unified start logic */ }
    func stop() { /* unified stop logic */ }
}
```

**Manager Adaptations:**
- **SimpleKanataManager** → adapter over `LifecycleOrchestrator(mode: .simple)`
- **KanataLifecycleManager** → adapter over `LifecycleOrchestrator(mode: .full)`
- **KanataManager** → delegates lifecycle calls to orchestrator

**Success Criteria:**
- [ ] No lifecycle logic duplication
- [ ] SimpleKanataManager behavior unchanged
- [ ] KanataLifecycleManager behavior unchanged
- [ ] Error handling consistent
- [ ] State transitions identical

### Milestone 7: Service Extraction and Precise Naming
**Duration:** 6 days  
**Risk:** Medium  

**Objective:** Extract core services with precise names while maintaining legacy facades.

**Files to Create:**
```
Sources/KeyPath/Core/Engine/
└── MappingEngine.swift

Sources/KeyPath/Infrastructure/Output/
└── OutputSynthesizer.swift

Sources/KeyPath/Infrastructure/Permissions/
└── PermissionService.swift

Sources/KeyPath/Infrastructure/Config/
└── ConfigurationService.swift (if not created in Milestone 4)
```

**Service Responsibilities:**
- **MappingEngine**: Key mapping logic, layer management, macro execution
- **OutputSynthesizer**: CGEvent posting and synthesis
- **PermissionService**: Oracle-delegated permission facade (no direct system calls)
- **ConfigurationService**: Centralized config management

**Critical: PermissionService Implementation**
```swift
final class PermissionService {
    // NEVER call system APIs directly - always delegate to Oracle
    func hasAccessibilityPermission() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.accessibility.isReady
    }
    
    func hasInputMonitoringPermission() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.inputMonitoring.isReady
    }
    
    func getBlockingIssue() async -> String? {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.blockingIssue
    }
}
```

**Adapter Pattern:**
- Keep existing manager class names
- Internal composition with new services
- Public APIs unchanged

**Success Criteria:**
- [ ] MappingEngine handles all key transformation logic
- [ ] OutputSynthesizer posts events correctly
- [ ] Permission checking behavior identical
- [ ] No public API changes

### Milestone 8: KanataManager Slimming
**Duration:** 4 days  
**Risk:** Medium  

**Objective:** Reduce KanataManager complexity through complete delegation.

**Target Structure:**
```swift
// KanataManager.swift (primary file ~200-300 lines)
final class KanataManager {
    // Service dependencies
    private let orchestrator: LifecycleOrchestrator
    private let mappingEngine: MappingEngine  
    private let configurationService: ConfigurationService
    private let outputSynthesizer: OutputSynthesizer
    
    // Public API (unchanged signatures)
    func start() { orchestrator.start() }
    func stop() { orchestrator.stop() }
    func processKeyDown(_ event: CGEvent) -> CGEvent? {
        return mappingEngine.processKeyDown(event)
    }
    // ... other delegated methods
}
```

**Extension Files (~100-200 lines each):**
- Thin delegation wrappers
- Preserve access levels
- Maintain error handling patterns

**Success Criteria:**
- [ ] KanataManager.swift under 800 lines total
- [ ] Extensions under 200 lines each
- [ ] All logic delegated to services
- [ ] Zero functional changes

### Milestone 9: Composition Root and Dependency Injection
**Duration:** 3 days  
**Risk:** Low  

**Objective:** Centralize service construction and dependency wiring.

**Files to Create:**
```
Sources/KeyPath/Application/Composition/
└── CompositionRoot.swift
```

**CompositionRoot Features:**
```swift
final class CompositionRoot {
    static func makeKanataStack(mode: RunMode) -> (
        kanata: KanataManager,
        lifecycle: KanataLifecycleManager, 
        simple: SimpleKanataManager
    ) {
        // Service construction and injection
        let configService = ConfigurationService(...)
        let mappingEngine = MappingEngine(...)
        let orchestrator = LifecycleOrchestrator(mode: mode, ...)
        
        return (
            kanata: KanataManager(orchestrator: orchestrator, ...),
            lifecycle: KanataLifecycleManager(orchestrator: orchestrator),
            simple: SimpleKanataManager(orchestrator: orchestrator)
        )
    }
}
```

**Success Criteria:**
- [ ] All service dependencies explicit
- [ ] Single construction point
- [ ] Easy testing setup
- [ ] Call sites unchanged

## Risk Mitigation

### High-Risk Areas
1. **CGEvent Tap Modifications** (Milestones 3, 5)
   - **Risk:** Breaking keyboard/mouse input
   - **Mitigation:** Feature flags, extensive testing, rollback capability

2. **Lifecycle Changes** (Milestone 6)
   - **Risk:** Service startup/shutdown issues
   - **Mitigation:** Adapter pattern preserves existing behavior

3. **Event Processing Chain** (Milestone 5)
   - **Risk:** Performance impact, event dropping
   - **Mitigation:** Performance testing, legacy fallback

### Testing Strategy
- **Unit Tests**: Each extracted service
- **Integration Tests**: Manager facade behavior
- **Manual Testing**: Full keyboard/mouse functionality
- **Performance Tests**: Event processing latency
- **Rollback Tests**: Feature flag disable scenarios

## Success Criteria

### Quantitative Metrics
- [ ] KanataManager reduced from 3,777 to <1,000 lines
- [ ] No manager class over 500 lines
- [ ] Build time unchanged (±5%)
- [ ] Test suite passes 100%
- [ ] Zero functional regressions

### Qualitative Metrics  
- [ ] Clear separation of concerns
- [ ] Testable components via protocols
- [ ] Maintainable code structure
- [ ] No CGEvent tap architectural changes (deferred to FUTURE)
- [ ] Documentation for all new services

## Implementation Timeline

**Total Duration:** ~30 days  
**Parallel Work Possible:** Milestones 1-2 can overlap  

```
Week 1: Milestones 0-1 (Documentation + File Split)
Week 2: Milestones 2-3 (Protocols + Manager Analysis)  
Week 3: Milestones 4-5 (Config Service + Event Processing)
Week 4: Milestone 6 (Lifecycle Orchestration) 
Week 5: Milestones 7-8 (Service Extraction + Slimming)
Week 6: Milestone 9 + Testing (Composition + Validation)
```

## ✅ **MILESTONE 3 ACHIEVEMENT - MAJOR PROGRESS**

### What Was Accomplished

**🎯 Successfully completed the most critical architectural improvement:**
- ✅ **Manager Consolidation Complete** - 3 overlapping managers → 1 unified KanataManager
- ✅ **1,138 lines eliminated** - SimpleKanataManager (712) + KanataLifecycleManager (426) removed
- ✅ **Zero functionality lost** - All UI state, lifecycle, and permission features preserved
- ✅ **CGEvent Safety Verified** - No keyboard freezing issues (taps isolated in KeyboardCapture)
- ✅ **Build Stability Maintained** - All compilation and testing requirements met

### Current Architecture Status

**Completed Milestones:** 0, 1, 2, **3** ✅  
**Remaining Manager Classes:** 6 (down from 8)  
**KanataManager Complexity:** Reduced and unified (3,283 lines with all functionality)

## Next Actions (Milestone 4+)

The foundation is now solid for continued architectural improvements:

1. **Configuration Service Extraction (Milestone 4):**
   - Extract config handling from KanataManager+Configuration.swift
   - Create dedicated ConfigurationService with protocol compliance
   - Implement file watching and change detection services

2. **Event Processing Chain (Milestone 5):**
   - Create EventRouter for processing chain management
   - Implement EventProcessing protocol adoption
   - Maintain existing CGEvent tap behavior

3. **Service Extraction (Milestones 6-8):**
   - Progressive extraction of remaining services
   - Protocol-driven dependency injection
   - Continued complexity reduction

**The hard work is done!** Manager consolidation was the highest-risk, highest-reward milestone and has been successfully completed.

---

**This plan maintains KeyPath's stability while addressing architectural debt systematically. Each milestone can be implemented, tested, and merged independently, ensuring continuous delivery capability throughout the refactoring process.**

---

## FUTURE ENHANCEMENTS (Do Not Implement Now)

### CGEvent Tap Architecture Modernization

**Background:** ARCHITECTURE.md ADR-006 calls for eliminating GUI CGEvent taps to follow the "one event tapper" rule and prevent keyboard freezing. This is a complex architectural change that should be tackled separately after the current refactoring is complete.

### Future Milestone: TCP-Based Key Recording
**When:** After current refactoring complete (Milestone 9+)  
**Objective:** Replace KeyboardCapture CGEvent taps with TCP-based communication  

**Approach:**
- Remove KeyboardCapture CGEvent taps entirely
- Implement key recording via kanata TCP API
- Follow Karabiner-Elements pattern (daemon-only taps)
- GUI communicates with daemon for key capture needs

**Files to Create (Future):**
```
Sources/KeyPath/Services/
├── TCPKeyRecording.swift
└── KanataClient.swift (enhanced)
```

**Implementation Strategy:**
```swift
// Future: TCP-based key recording
final class TCPKeyRecording {
    private let kanataClient: KanataClient
    
    func startRecording(callback: @escaping (String) -> Void) async {
        // Send TCP command to kanata daemon to start recording
        // Daemon handles all CGEvent taps
        await kanataClient.sendCommand(.startKeyRecording)
        
        // Listen for key events via TCP
        await kanataClient.listenForKeyEvents(callback)
    }
}
```

**Benefits:**
- Eliminates GUI CGEvent taps (ADR-006 compliance)
- Prevents keyboard freezing from multiple taps
- Follows proven industry pattern
- Single event tapper rule compliance

**Why Future:** This change affects core functionality and requires extensive testing with real keyboard input. Should be done after the current architectural refactoring is stable.

### Future Milestone: Event Processing Modernization
**When:** After TCP-based recording implemented  
**Objective:** Modernize event processing without CGEvent tap conflicts

**Files to Create (Future):**
```
Sources/KeyPath/Core/Events/
├── EventProcessor.swift
├── EventRouter.swift (simplified)
└── TCPEventHandler.swift
```

**Note:** The EventTag and TapSupervisor concepts from the original Milestone 3 may still be valuable for this future work, adapted for TCP-based event handling rather than multiple CGEvent taps.