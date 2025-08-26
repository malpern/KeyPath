# KeyPath Refactoring Implementation Guide

**Based on:** RepoPrompt Technical Review - August 26, 2025  
**Purpose:** Address critical implementation gaps identified in PLAN.md review  
**Status:** Implementation-Ready Specifications  

## Executive Summary

RepoPrompt's review validated the overall refactoring approach but identified **4 critical architectural gaps** that must be addressed for successful implementation. This guide provides concrete specifications to fill those gaps.

## Critical Architectural Gaps (Must Address)

### 1. Service Boundary Matrix
**Problem:** Unclear domain ownership leads to state duplication and responsibility leaks  
**Solution:** Explicit service boundaries with state ownership rules

### 2. Composition Root/DI Strategy  
**Problem:** No centralized dependency injection strategy defined  
**Solution:** Lightweight DI container introduced in Milestone 0

### 3. Concurrency Model
**Problem:** Threading behavior undefined during service extraction  
**Solution:** Explicit Swift Concurrency actor pattern for stateful services  

### 4. Domain Contracts
**Problem:** PermissionOracle lacks formal Action/Resource/Decision types  
**Solution:** Typed domain primitives for permission system

## Implementation Specifications

### Composition Root Architecture (Milestone 0 Addition)

**Files to Create:**
```
Sources/KeyPath/Application/Composition/
├── AppContainer.swift
├── CompositionRoot.swift
└── ServiceFactory.swift
```

**AppContainer Implementation:**
```swift
struct AppContainer {
    let permissionOracle: PermissionOracle
    let config: AppConfig
    let logger: Logger
    
    // Services (added incrementally)
    let profiles: ProfilesService
    let shortcuts: ShortcutsService  
    let permissions: PermissionsService
    let input: InputEventSource
}

enum CompositionRoot {
    static var container: AppContainer!
    
    static func bootstrap(env: AppEnvironment) {
        container = AppContainer(
            permissionOracle: DefaultPermissionOracle(),
            config: AppConfig.load(),
            logger: DefaultLogger(),
            profiles: DefaultProfilesService(),
            shortcuts: DefaultShortcutsService(),
            permissions: DefaultPermissionsService(oracle: DefaultPermissionOracle()),
            input: DisabledEventSource() // Per ADR-006
        )
    }
}
```

**Integration Point:**
```swift
// In AppDelegate or App.swift
func applicationDidFinishLaunching() {
    CompositionRoot.bootstrap(env: .production)
    // Existing app setup continues...
}
```

### Service Boundary Matrix

| Domain | Service | State Ownership | Dependencies | Concurrency |
|--------|---------|----------------|--------------|-------------|
| **Permissions** | PermissionOracle | Permission cache, OS state | None | Actor |
| **Profiles** | ProfilesService | Profile cache, active profile | PermissionOracle | Actor |
| **Shortcuts** | ShortcutsService | Shortcut registry, mappings | PermissionOracle | Actor |
| **Input** | InputEventSource | Event streams (disabled) | None | Actor |
| **Config** | ConfigurationService | Config cache, file watching | None | Actor |
| **Output** | OutputSynthesizer | Event queues | PermissionOracle | Actor |
| **Lifecycle** | LifecycleOrchestrator | Service states | All services | MainActor |

**Ownership Rules:**
- Each service owns exactly one domain of state
- No cross-service state sharing (use events for coordination)  
- Only PermissionOracle can cache permission decisions
- Only one service per domain (no duplication)

### Concurrency Model Specification

**Stateful Services → Actors:**
```swift
actor DefaultProfilesService: ProfilesService {
    private var profilesCache: [UUID: Profile] = [:]
    private var activeProfileId: UUID?
    
    func loadProfiles() async throws -> [Profile] {
        // Thread-safe by actor isolation
        return Array(profilesCache.values)
    }
    
    func setActive(_ profileId: UUID) async throws {
        // Atomic state change
        activeProfileId = profileId
    }
}

actor DefaultShortcutsService: ShortcutsService {
    private var shortcuts: [Shortcut] = []
    
    func register(_ shortcut: Shortcut) async throws {
        // Thread-safe registration
        shortcuts.append(shortcut)
    }
}
```

**UI Coordination → MainActor:**
```swift
@MainActor
final class LifecycleOrchestrator: LifecycleControlling {
    private let profiles: ProfilesService
    private let shortcuts: ShortcutsService
    
    func start() async {
        // Coordinate services on main actor
        try await profiles.loadProfiles()
        try await shortcuts.loadActiveShortcuts()
    }
}
```

**Threading Guarantees:**
- All service methods are `async` and actor-isolated
- UI updates happen on `MainActor` only
- Event streams preserve ordering within each service
- Cross-service calls use `await` for proper sequencing

### Domain Contracts for PermissionOracle

**Files to Create:**
```
Sources/KeyPath/Core/Permissions/
├── PermissionTypes.swift
├── PermissionActions.swift
├── PermissionResources.swift
└── PermissionDecisions.swift
```

**Formal Permission Types:**
```swift
enum PermissionAction: Sendable, CaseIterable {
    case captureKeyboard
    case modifyProfiles
    case accessConfiguration
    case synthesizeEvents
    case manageServices
    
    var description: String {
        switch self {
        case .captureKeyboard: return "Capture keyboard input"
        case .modifyProfiles: return "Modify keyboard profiles"
        case .accessConfiguration: return "Access configuration files"
        case .synthesizeEvents: return "Generate keyboard events"
        case .manageServices: return "Manage system services"
        }
    }
}

enum PermissionResource: Sendable {
    case systemKeyboard
    case profile(id: UUID)
    case configuration
    case eventStream
    case launchDaemon(name: String)
}

enum PermissionDecision: Sendable {
    case allow
    case deny(reason: String)
    case prompt(message: String)
    
    var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }
}

struct Subject: Sendable {
    let processId: Int32
    let bundleId: String
    let userId: String?
    
    static let current = Subject(
        processId: ProcessInfo.processInfo.processIdentifier,
        bundleId: Bundle.main.bundleIdentifier ?? "unknown",
        userId: NSUserName()
    )
}
```

**Enhanced PermissionOracle Protocol:**
```swift
protocol PermissionOracle: Sendable {
    func can(_ subject: Subject, perform action: PermissionAction, on resource: PermissionResource) async -> PermissionDecision
    func require(_ subject: Subject, to action: PermissionAction, on resource: PermissionResource) async throws
}

// Convenience extensions
extension PermissionOracle {
    func allows(_ action: PermissionAction, on resource: PermissionResource) async -> Bool {
        let decision = await can(.current, perform: action, on: resource)
        return decision.isAllowed
    }
    
    func requireCurrent(_ action: PermissionAction, on resource: PermissionResource) async throws {
        try await require(.current, to: action, on: resource)
    }
}
```

### Permission Bypass Prevention (Milestone 1 Addition)

**Compile-time Enforcement:**
```swift
// Sources/KeyPath/Core/Permissions/PermissionGuards.swift

#if STRICT_PERMISSION_ENFORCEMENT
// Make direct OS API calls impossible to use accidentally
@available(*, unavailable, message: "Use PermissionOracle.can() instead")
func AXIsProcessTrusted() -> Bool { fatalError() }

@available(*, unavailable, message: "Use PermissionOracle.can() instead")  
func IOHIDCheckAccess(_ type: IOHIDRequestType) -> IOHIDAccessType { fatalError() }
#endif

// Runtime verification in debug builds
enum PermissionGuard {
    #if DEBUG
    static func verifyNoBypassesOnStartup() {
        // Scan call stack for forbidden patterns
        // Log warnings for any potential bypasses found
    }
    #endif
}
```

**Build Configuration:**
```
// Config.xcconfig
STRICT_PERMISSION_ENFORCEMENT = YES
ENABLE_CGEVENT_TAP = NO
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) STRICT_PERMISSION_ENFORCEMENT
```

### Event Ordering Preservation

**Problem:** Converting synchronous event handling to async actors may change timing

**Solution:** Ordered Event Processing
```swift
actor EventOrderingService {
    private var eventQueue: [InputEvent] = []
    private var isProcessing = false
    
    func process(_ event: InputEvent, via handler: @escaping (InputEvent) async -> Void) async {
        eventQueue.append(event)
        
        guard !isProcessing else { return }
        isProcessing = true
        
        defer { isProcessing = false }
        
        while !eventQueue.isEmpty {
            let nextEvent = eventQueue.removeFirst()
            await handler(nextEvent)
        }
    }
}
```

### Service Extraction Safety Checklist

**For Each Service Extraction (Milestones 4-7):**

1. **State Migration Checklist:**
   - [ ] Identify all state variables being moved
   - [ ] Ensure no state is duplicated across services
   - [ ] Verify state access patterns remain equivalent
   - [ ] Test state persistence/loading behavior

2. **Concurrency Safety Checklist:**
   - [ ] Mark stateful services as `actor`
   - [ ] Add `async` to all service methods
   - [ ] Update all call sites with `await`
   - [ ] Verify no blocking operations in async context

3. **Permission Integration Checklist:**
   - [ ] All permission checks delegate to PermissionOracle
   - [ ] No direct OS API calls remain
   - [ ] Permission decisions use typed Actions/Resources
   - [ ] Error handling preserves user experience

4. **Event Behavior Checklist:**
   - [ ] Event ordering preserved during transition
   - [ ] Event timing behavior unchanged
   - [ ] No event loss during async boundaries
   - [ ] Stream backpressure handled properly

## Updated Milestone 0 Tasks

Add these critical foundation tasks to Milestone 0:

### Additional Milestone 0 Tasks:
- [ ] **Create AppContainer and CompositionRoot**
- [ ] **Define Service Boundary Matrix**
- [ ] **Implement PermissionOracle domain types**
- [ ] **Add permission bypass prevention**
- [ ] **Set up concurrency model documentation**
- [ ] **Create EventOrderingService foundation**

### Updated Milestone 0 Duration: 
**3 days** (was 2 days) - additional complexity justified by risk reduction

## Integration with Existing PLAN.md

This implementation guide **supplements** PLAN.md without replacing it:

- **PLAN.md** remains the overall strategy and milestone sequencing
- **IMPLEMENTATION_GUIDE.md** provides the concrete technical specifications
- **Together** they address both strategic direction and tactical execution

## Success Criteria Enhancement

Add these criteria to PLAN.md success metrics:

### Technical Architecture Criteria:
- [ ] All services follow actor concurrency model
- [ ] Zero permission bypasses (enforced at compile time)
- [ ] Single composition root manages all dependencies
- [ ] Event ordering preserved during async transitions
- [ ] Formal domain types used throughout permission system

### Implementation Safety Criteria:
- [ ] All state migrations verified with existing behavior
- [ ] Cross-service communication uses proper async patterns
- [ ] No shared mutable state between services
- [ ] Permission decisions use typed Action/Resource contracts

---

**This implementation guide addresses the critical architectural gaps identified by RepoPrompt, ensuring the refactoring plan can be executed successfully with minimal risk of regression or architectural drift.**