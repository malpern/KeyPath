# KeyPath Architecture Refactoring Plan

**Co-authored by:** Claude Code & RepoPrompt  
**Created:** August 26, 2025  
**Status:** Phase 0 - Planning Complete  

## Executive Summary

This plan addresses critical architectural issues in KeyPath while maintaining build stability, code signing integrity, and the working CGEvent tap architecture. The refactoring will reduce KanataManager from 3,777 lines to ~800-1,000 lines through incremental extraction of services, introduce clear contracts via protocols, and eliminate manager class proliferation without breaking runtime behavior.

**Key Approach:** Introduce contracts first, split large files using extensions, then progressively delegate to extracted services while keeping legacy class names as thin facades. Each milestone compiles independently and can be merged safely.

## Critical Constraints

### Must Preserve
- ✅ **Build stability** - zero functional changes during refactoring
- ✅ **Code signing identity** - bundle ID, entitlements, deployment target unchanged
- ✅ **Separate CGEvent taps** - current working architecture uses multiple managers to avoid tap conflicts
- ✅ **Public APIs** - all existing method signatures remain identical
- ✅ **Threading model** - main thread, runloop, and queue behaviors unchanged
- ✅ **TCC-safe deployment** - preserve Input Monitoring permissions

### Non-Goals (Initially)
- ❌ Renaming public types or moving modules
- ❌ Consolidating CGEvent taps (causes conflicts per CLAUDE.md)
- ❌ Adding third-party dependencies
- ❌ Changing functional behavior

## Current Architecture Issues

### Issue 1: Monolithic KanataManager (3,777 lines)
**Location:** `Sources/KeyPath/Managers/KanataManager.swift`
**Problems:**
- Violates single responsibility principle
- Contains configuration, lifecycle, event taps, engine state, and output synthesis
- Extremely difficult to test, debug, and maintain
- Single point of failure for entire application

### Issue 2: Manager Class Proliferation
**Current Count:** 8 manager classes with unclear boundaries
```
KanataManager.swift                 (3,777 lines) - Monolithic orchestrator
SimpleKanataManager.swift           (712 lines)   - Simplified run mode
KanataConfigManager.swift           (533 lines)   - Configuration handling
KanataLifecycleManager.swift        (426 lines)   - Lifecycle management
LifecycleStateMachine.swift         (381 lines)   - State transitions
ProcessLifecycleManager.swift       (341 lines)   - Process management
LaunchAgentManager.swift            (262 lines)   - Launch agent handling
LaunchDaemonPIDCache.swift          (178 lines)   - PID caching
```

**Problems:**
- Responsibility overlap between KanataManager, SimpleKanataManager, and KanataLifecycleManager
- No clear contracts defining boundaries
- Difficult to understand interaction patterns

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

1. **Multiple CGEvent Taps Preserved**
   - TapSupervisor coordinates without consolidating
   - Each manager retains its tap to avoid conflicts
   - Event tagging prevents processing loops

2. **Protocol-Based Contracts**
   - Clear boundaries via protocols
   - Dependency inversion for testability
   - Explicit interfaces for all services

3. **Incremental Delegation**
   - Legacy classes become thin facades
   - Internal composition changes only
   - Public APIs remain unchanged

## Phased Implementation Plan

### Milestone 0: Documentation and Analysis
**Status:** In Progress  
**Duration:** 2 days  

**Tasks:**
- [x] Create PLAN.md (this document)
- [ ] Create MANAGERS.md with detailed responsibility inventory
- [ ] Validate CGEvent tap usage for EventTag compatibility
- [ ] Document current composition root location

**Deliverables:**
- `MANAGERS.md` - Complete inventory of manager responsibilities
- `docs/CURRENT_EVENT_TAPS.md` - CGEvent tap analysis

### Milestone 1: Non-Breaking File Split
**Duration:** 3 days  
**Risk:** Low  

**Objective:** Split KanataManager into logical extensions without changing any logic.

**Files to Create:**
```
Sources/KeyPath/Managers/
├── KanataManager+Lifecycle.swift      (lifecycle methods)
├── KanataManager+EventTaps.swift      (CGEvent tap handling)
├── KanataManager+Configuration.swift  (config load/watch/apply)
├── KanataManager+Engine.swift         (mapping engine logic)
└── KanataManager+Output.swift         (event synthesis/posting)
```

**Implementation:**
- Move only private and fileprivate methods
- Keep public API in primary file
- Mirror existing imports exactly
- Preserve all @available attributes

**Success Criteria:**
- [ ] Build compiles without warnings
- [ ] All tests pass
- [ ] No functional behavior changes
- [ ] File sizes: KanataManager.swift < 1,000 lines

### Milestone 2: Stable Contracts Introduction
**Duration:** 2 days  
**Risk:** Low  

**Objective:** Define clear boundaries via protocols without wiring changes.

**Files to Create:**
```
Sources/KeyPath/Core/Contracts/
├── LifecycleControlling.swift
├── EventTapping.swift
├── EventProcessing.swift
├── ConfigurationProviding.swift
├── PermissionChecking.swift
├── OutputSynthesizing.swift
└── Logging.swift
```

**Key Protocols:**
```swift
protocol LifecycleControlling {
    func start()
    func stop() 
    var isRunning: Bool { get }
}

protocol EventTapping {
    func install() throws -> TapHandle
    func uninstall()
    var isInstalled: Bool { get }
}

protocol EventProcessing {
    func process(event: CGEvent, location: CGEventTapLocation, 
                proxy: CGEventTapProxy) -> CGEvent?
}

protocol ConfigurationProviding {
    associatedtype Config
    func current() -> Config
    func reload() throws -> Config
    func observe(_ onChange: @escaping (Config) -> Void) -> AnyCancelable
}
```

**Success Criteria:**
- [ ] All protocols compile
- [ ] No existing code adopts protocols yet
- [ ] Zero behavior changes
- [ ] Documentation for each protocol

### Milestone 3: Event Tap Coordination System
**Duration:** 4 days  
**Risk:** Medium  

**Objective:** Implement TapSupervisor and EventTag system for conflict prevention.

**Files to Create:**
```
Sources/KeyPath/Infrastructure/Input/
├── EventTag.swift
├── TapSupervisor.swift
└── TapHandle.swift
```

**EventTag Implementation:**
```swift
struct EventTag {
    static let namespace: Int32 = 0x4B50 // 'KP' for KeyPath
    
    static func tag(event: CGEvent, processorId: Int32, phase: Int32) {
        // Uses CGEventField.eventSourceUserData for 32-bit tagged value
        // Format: 0xNNPPPP (namespace, processorId, phase)
    }
    
    static func readTag(from event: CGEvent) -> (namespace: Int32, processorId: Int32, phase: Int32)?
}
```

**TapSupervisor Features:**
- Non-owning registry of active taps
- Event processor registration with scope filtering
- Loop prevention via event tagging
- No tap consolidation (preserves working architecture)

**Integration Strategy:**
- Feature flag: `let useTapSupervisor = false` (default)
- Optional integration guarded by flag
- Wire only when ready to avoid behavior changes

**Success Criteria:**
- [ ] TapSupervisor correctly registers/unregisters taps
- [ ] Event tagging works without conflicts
- [ ] Feature flag allows safe rollback
- [ ] No existing CGEventField usage conflicts

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
└── AccessibilityPermissionService.swift

Sources/KeyPath/Infrastructure/Input/
└── EventTapOwner.swift
```

**Service Responsibilities:**
- **MappingEngine**: Key mapping logic, layer management, macro execution
- **OutputSynthesizer**: CGEvent posting and synthesis
- **AccessibilityPermissionService**: Permission checks and requests
- **EventTapOwner**: Generic tap ownership and lifecycle

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
- [ ] Preserved CGEvent tap architecture
- [ ] Documentation for all new services

## Implementation Timeline

**Total Duration:** ~30 days  
**Parallel Work Possible:** Milestones 1-2 can overlap  

```
Week 1: Milestones 0-1 (Documentation + File Split)
Week 2: Milestones 2-3 (Protocols + Tap Coordination)  
Week 3: Milestones 4-5 (Config Service + Event Processing)
Week 4: Milestone 6 (Lifecycle Orchestration) 
Week 5: Milestones 7-8 (Service Extraction + Slimming)
Week 6: Milestone 9 + Testing (Composition + Validation)
```

## Next Actions

1. **Complete Milestone 0:**
   - Finish MANAGERS.md inventory
   - Validate CGEvent tap compatibility
   - Identify composition root location

2. **Begin Milestone 1:**
   - Create extension files
   - Move private methods systematically
   - Validate build stability

3. **Establish Testing Pipeline:**
   - Set up performance benchmarks
   - Create integration test suite
   - Define rollback procedures

---

**This plan maintains KeyPath's stability while addressing architectural debt systematically. Each milestone can be implemented, tested, and merged independently, ensuring continuous delivery capability throughout the refactoring process.**