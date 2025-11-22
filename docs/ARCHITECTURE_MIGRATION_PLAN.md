# KeyPath Architecture Migration Plan

## Executive Summary

This document outlines the migration from the current conflict-prone, multi-instance architecture to a clean, state-driven architecture that eliminates race conditions and provides predictable behavior.

### InstallerEngine Façade (Status: Complete; Callers Migrated)
- Façade API: `inspectSystem`, `makePlan`, `execute`, `run` (see `InstallerEngine.swift`)
- Feature flag: `KEYPATH_USE_INSTALLER_ENGINE=1` routes wizard/CLI/manager through the façade
- Health pipeline: launchctl PID + TCP probe + freshness guard shared by wizard & main app
- Backward compatibility: output issues and plans remain compatible with legacy config behavior
- Next (Phase 8): finalize docs and retire remaining legacy adapters once stable

**Problem**: Multiple Kanata processes are started due to uncoordinated initialization paths, auto-conflict resolution, and race conditions between UI components.

**Solution**: Centralized state management with explicit user actions, comprehensive logging, and full test coverage.

---

## Current Architecture Issues

### Root Causes Identified

1. **Multiple Startup Paths**: 7 different code paths can call `startKanata()`
2. **Race Conditions**: Wizard auto-kills processes that KanataManager is starting
3. **No Coordination**: Components act independently without shared state
4. **Auto-Actions**: Wizard makes decisions without user consent
5. **Poor Observability**: Limited logging makes debugging difficult

### Impact

- Keyboard becomes unresponsive due to HID device conflicts
- Unpredictable wizard behavior
- Complex debugging when issues occur
- User confusion about system state

---

## Target Architecture

### Core Principles

1. **Single Source of Truth**: `KanataLifecycleManager` owns all process state
2. **Explicit User Intent**: No automatic actions without user approval
3. **State Machine**: Predictable state transitions with validation
4. **Comprehensive Logging**: Full audit trail for debugging
5. **Testable Components**: Each component is independently testable

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interface Layer                     │
│  ┌─────────────────┐  ┌─────────────────┐                 │
│  │   ContentView   │  │InstallationWiz  │                 │
│  │ (Reactive UI)   │  │ (Reactive UI)   │                 │
│  └─────────────────┘  └─────────────────┘                 │
└─────────────┬───────────────────┬───────────────────────────┘
              │                   │
              ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                State Management Layer                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │           KanataLifecycleManager                        │ │
│  │  - Owns all Kanata process state                       │ │
│  │  - Coordinates user actions                            │ │
│  │  - Publishes state changes                             │ │
│  │  - Handles error recovery                              │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────┬───────────────────┬───────────────────────────┘
              │                   │
              ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                  Service Layer                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │LifecycleState   │  │SystemRequire    │  │ConfigMgr    │ │
│  │Machine          │  │mentsChecker     │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────┬───────────────────┬───────────────────────────┘
              │                   │
              ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                  System Layer                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ProcessManager   │  │PermissionMgr    │  │LogManager   │ │
│  │                 │  │                 │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## Migration Plan

## Phase 1: Immediate Stabilization (Days 1-2)

### Objective
Stop multiple instance creation while preserving existing functionality.

### Changes

#### 1.1 Add Process Synchronization Lock
**File**: `Sources/KeyPath/KanataManager.swift`

```swift
class KanataManager: ObservableObject {
    private static let startupLock = NSLock()
    private var lastStartAttempt: Date?
    private let minStartInterval: TimeInterval = 2.0
    
    func startKanata() async {
        KanataManager.startupLock.lock()
        defer { KanataManager.startupLock.unlock() }
        
        // Prevent rapid successive starts
        if let lastAttempt = lastStartAttempt,
           Date().timeIntervalSince(lastAttempt) < minStartInterval {
            AppLogger.shared.log("⚠️ [Start] Ignoring rapid start attempt within \(minStartInterval)s")
            return
        }
        lastStartAttempt = Date()
        
        // Existing startKanata logic...
    }
}
```

#### 1.2 Remove Wizard Auto-Kill Logic
**File**: `Sources/KeyPath/InstallationWizardView.swift`

```swift
// REMOVE lines 361-382 (auto-termination logic)
// REPLACE with user choice dialog

private func handleConflictDetection(_ processes: [ProcessInfo]) {
    // Show conflict dialog instead of auto-killing
    showConflictResolutionDialog(processes: processes)
}
```

#### 1.3 Add ContentView Debouncing
**File**: `Sources/KeyPath/ContentView.swift`

```swift
struct ContentView: View {
    @State private var lastRequirementCheck: Date = .distantPast
    private let checkInterval: TimeInterval = 2.0
    
    private func checkRequirementsAndShowWizard() {
        let now = Date()
        guard now.timeIntervalSince(lastRequirementCheck) > checkInterval else {
            AppLogger.shared.log("🔍 [ContentView] Skipping requirements check - too soon")
            return
        }
        lastRequirementCheck = now
        
        // Existing logic...
    }
}
```

### Testing Strategy

#### Unit Tests
```swift
class Phase1StabilizationTests: XCTestCase {
    
    func testStartupLockPreventsRapidStarts() async {
        let manager = KanataManager()
        let startTime = Date()
        
        // Start two processes rapidly
        async let result1 = manager.startKanata()
        async let result2 = manager.startKanata()
        
        let _ = await [result1, result2]
        
        // Verify only one process was actually started
        XCTAssertEqual(manager.runningProcessCount, 1)
        XCTAssertLessThan(Date().timeIntervalSince(startTime), 0.5)
    }
    
    func testContentViewDebouncing() {
        let contentView = ContentView()
        let initialCheckTime = Date()
        
        // Rapid requirement checks
        contentView.checkRequirementsAndShowWizard()
        contentView.checkRequirementsAndShowWizard()
        contentView.checkRequirementsAndShowWizard()
        
        // Verify only one check was performed
        XCTAssertEqual(contentView.requirementCheckCount, 1)
    }
    
    func testWizardNoAutoKill() async {
        let wizard = InstallationWizardView()
        let mockProcesses = [ProcessInfo(pid: 123, command: "kanata")]
        
        await wizard.checkInitialState(processes: mockProcesses)
        
        // Verify processes were NOT automatically killed
        XCTAssertEqual(getRunningProcessCount("kanata"), 1)
        XCTAssertTrue(wizard.showingConflictDialog)
    }
}
```

#### Integration Tests
```swift
class Phase1IntegrationTests: XCTestCase {
    
    func testNoMultipleInstancesOnAppLaunch() async {
        let app = KeyPathApp()
        
        // Simulate app launch
        await app.launch()
        
        // Wait for initialization to complete
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify only one Kanata process exists
        let processes = await findKanataProcesses()
        XCTAssertLessThanOrEqual(processes.count, 1, "Multiple Kanata processes detected")
    }
    
    func testWizardDoesNotInterfereWithStartup() async {
        let lifecycleManager = KanataLifecycleManager()
        let wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        // Start Kanata
        async let startResult = lifecycleManager.startKanata()
        
        // Show wizard immediately  
        await wizard.appear()
        
        let result = await startResult
        
        // Verify startup succeeded despite wizard
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(await findKanataProcesses().count, 1)
    }
}
```

### Acceptance Criteria
- [ ] No more than 1 Kanata process running at any time
- [ ] App startup does not create multiple instances
- [ ] Wizard does not automatically kill processes
- [ ] ContentView requirements checking is debounced
- [ ] All existing functionality preserved
- [ ] Unit tests pass with >90% coverage
- [ ] Integration tests verify single instance behavior

---

## Phase 2: State Machine Foundation (Days 3-6)

### Objective
Introduce centralized state management without breaking existing UI.

### Changes

#### 2.1 Create Lifecycle State Machine
**File**: `Sources/KeyPath/LifecycleStateMachine.swift`

```swift
import Foundation
import Combine

enum LifecycleState: Equatable, CaseIterable {
    case uninitialized
    case checkingRequirements
    case requirementsNotMet(missing: [RequirementType])
    case conflictDetected(processes: [ConflictingProcess])
    case readyToStart
    case starting
    case running(process: RunningProcess)
    case stopping
    case failed(error: KanataError, recovery: RecoveryOptions)
    
    func canTransitionTo(_ newState: LifecycleState) -> Bool {
        switch (self, newState) {
        case (.uninitialized, .checkingRequirements): return true
        case (.checkingRequirements, .requirementsNotMet): return true
        case (.checkingRequirements, .conflictDetected): return true
        case (.checkingRequirements, .readyToStart): return true
        case (.requirementsNotMet, .checkingRequirements): return true
        case (.conflictDetected, .readyToStart): return true
        case (.readyToStart, .starting): return true
        case (.starting, .running): return true
        case (.starting, .failed): return true
        case (.running, .stopping): return true
        case (.running, .failed): return true
        case (.stopping, .readyToStart): return true
        case (.failed, .checkingRequirements): return true
        default: return false
        }
    }
}

class LifecycleStateMachine: ObservableObject {
    @Published private(set) var currentState: LifecycleState = .uninitialized
    
    private let stateQueue = DispatchQueue(label: "kanata.state", qos: .userInitiated)
    private let logger = StructuredLogger.shared
    
    func transition(to newState: LifecycleState, reason: String, correlationId: String) -> Bool {
        return stateQueue.sync {
            guard currentState.canTransitionTo(newState) else {
                logger.log(
                    level: .warn,
                    category: .stateTransition,
                    message: "Invalid state transition blocked",
                    correlationId: correlationId,
                    context: [
                        "fromState": String(describing: currentState),
                        "toState": String(describing: newState),
                        "reason": reason
                    ],
                    component: "StateMachine"
                )
                return false
            }
            
            let oldState = currentState
            currentState = newState
            
            logger.log(
                level: .info,
                category: .stateTransition,
                message: "State transition completed",
                correlationId: correlationId,
                context: [
                    "fromState": String(describing: oldState),
                    "toState": String(describing: newState),
                    "reason": reason
                ],
                component: "StateMachine"
            )
            
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
            
            return true
        }
    }
}
```

#### 2.2 Create KanataLifecycleManager
**File**: `Sources/KeyPath/KanataLifecycleManager.swift`

```swift
@MainActor
class KanataLifecycleManager: ObservableObject {
    @Published private(set) var lifecycleState: LifecycleState = .uninitialized
    @Published private(set) var systemRequirements = SystemRequirements()
    @Published private(set) var lastError: KanataError?
    
    private let stateMachine = LifecycleStateMachine()
    private let kanataManager: KanataManager
    private let requirementsChecker: SystemRequirementsChecker
    private let logger = StructuredLogger.shared
    
    init(kanataManager: KanataManager = KanataManager()) {
        self.kanataManager = kanataManager
        self.requirementsChecker = SystemRequirementsChecker()
        
        // Observe state machine changes
        stateMachine.$currentState
            .receive(on: DispatchQueue.main)
            .assign(to: &$lifecycleState)
    }
    
    func initialize() async {
        let correlationId = CorrelationContext.current.generateId(for: "INITIALIZE")
        
        logger.log(
            level: .info,
            category: .lifecycle,
            message: "Initializing KanataLifecycleManager",
            correlationId: correlationId,
            context: [:],
            component: "LifecycleManager"
        )
        
        _ = stateMachine.transition(to: .checkingRequirements, reason: "Initialize", correlationId: correlationId)
        
        systemRequirements = await requirementsChecker.checkAllRequirements()
        
        if !systemRequirements.allMet {
            _ = stateMachine.transition(
                to: .requirementsNotMet(missing: systemRequirements.missingRequirements),
                reason: "Requirements not met",
                correlationId: correlationId
            )
        } else {
            let conflicts = await detectConflicts()
            if !conflicts.isEmpty {
                _ = stateMachine.transition(
                    to: .conflictDetected(processes: conflicts),
                    reason: "Conflicts detected",
                    correlationId: correlationId
                )
            } else {
                _ = stateMachine.transition(to: .readyToStart, reason: "All requirements met", correlationId: correlationId)
            }
        }
    }
    
    func requestStart() async -> ActionResult {
        let correlationId = CorrelationContext.current.generateId(for: "USER_START")
        
        guard case .readyToStart = lifecycleState else {
            return .rejected(reason: "Cannot start from state \(lifecycleState)")
        }
        
        _ = stateMachine.transition(to: .starting, reason: "User requested start", correlationId: correlationId)
        
        do {
            let process = try await kanataManager.startKanataProcess()
            _ = stateMachine.transition(to: .running(process: process), reason: "Start succeeded", correlationId: correlationId)
            return .completed
        } catch {
            let kanataError = KanataError.from(error)
            lastError = kanataError
            _ = stateMachine.transition(
                to: .failed(error: kanataError, recovery: kanataError.recoveryOptions),
                reason: "Start failed",
                correlationId: correlationId
            )
            return .failed(error: kanataError)
        }
    }
    
    private func detectConflicts() async -> [ConflictingProcess] {
        // Implementation for conflict detection
        return []
    }
}
```

#### 2.3 Update Existing Components
**File**: `Sources/KeyPath/ContentView.swift`

```swift
struct ContentView: View {
    @StateObject private var lifecycleManager = KanataLifecycleManager()
    // ... other properties
    
    var body: some View {
        VStack {
            switch lifecycleManager.lifecycleState {
            case .running:
                KeyMappingInterface()
            case .requirementsNotMet, .conflictDetected, .failed:
                ErrorBanner(
                    state: lifecycleManager.lifecycleState,
                    onAction: handleUserAction
                )
            case .readyToStart:
                ReadyToStartView { Task { await lifecycleManager.requestStart() } }
            default:
                LoadingView()
            }
        }
        .task {
            await lifecycleManager.initialize()
        }
    }
    
    private func handleUserAction(_ action: UserAction) {
        Task {
            let result = await lifecycleManager.handleUserAction(action)
            // Handle result
        }
    }
}
```

### Testing Strategy

#### Unit Tests
```swift
class StateMachineTests: XCTestCase {
    var stateMachine: LifecycleStateMachine!
    
    override func setUp() {
        stateMachine = LifecycleStateMachine()
    }
    
    func testValidStateTransitions() {
        let correlationId = "test-transition"
        
        // Valid transition
        XCTAssertTrue(stateMachine.transition(to: .checkingRequirements, reason: "Test", correlationId: correlationId))
        XCTAssertEqual(stateMachine.currentState, .checkingRequirements)
        
        // Invalid transition should be blocked
        XCTAssertFalse(stateMachine.transition(to: .running(process: mockProcess), reason: "Invalid", correlationId: correlationId))
        XCTAssertEqual(stateMachine.currentState, .checkingRequirements)
    }
    
    func testStateTransitionLogging() {
        let mockLogger = MockStructuredLogger()
        let correlationId = "test-logging"
        
        stateMachine.transition(to: .checkingRequirements, reason: "Test logging", correlationId: correlationId)
        
        XCTAssertEqual(mockLogger.logEntries.count, 1)
        let entry = mockLogger.logEntries.first!
        XCTAssertEqual(entry.category, .stateTransition)
        XCTAssertEqual(entry.correlationId, correlationId)
    }
}

class LifecycleManagerTests: XCTestCase {
    var lifecycleManager: KanataLifecycleManager!
    var mockKanataManager: MockKanataManager!
    var mockRequirementsChecker: MockSystemRequirementsChecker!
    
    override func setUp() {
        mockKanataManager = MockKanataManager()
        mockRequirementsChecker = MockSystemRequirementsChecker()
        lifecycleManager = KanataLifecycleManager(
            kanataManager: mockKanataManager,
            requirementsChecker: mockRequirementsChecker
        )
    }
    
    func testInitializationWithAllRequirementsMet() async {
        mockRequirementsChecker.allRequirementsMet = true
        mockRequirementsChecker.conflictingProcesses = []
        
        await lifecycleManager.initialize()
        
        XCTAssertEqual(lifecycleManager.lifecycleState, .readyToStart)
    }
    
    func testInitializationWithMissingRequirements() async {
        mockRequirementsChecker.allRequirementsMet = false
        mockRequirementsChecker.missingRequirements = [.binaryNotInstalled, .permissionsNotGranted]
        
        await lifecycleManager.initialize()
        
        if case .requirementsNotMet(let missing) = lifecycleManager.lifecycleState {
            XCTAssertEqual(missing, [.binaryNotInstalled, .permissionsNotGranted])
        } else {
            XCTFail("Expected requirementsNotMet state")
        }
    }
    
    func testUserStartRequest() async {
        // Setup ready state
        lifecycleManager.stateMachine.transition(to: .readyToStart, reason: "Test setup", correlationId: "test")
        mockKanataManager.startResult = .success(mockProcess)
        
        let result = await lifecycleManager.requestStart()
        
        XCTAssertEqual(result, .completed)
        if case .running(let process) = lifecycleManager.lifecycleState {
            XCTAssertEqual(process.pid, mockProcess.pid)
        } else {
            XCTFail("Expected running state")
        }
    }
}
```

### Acceptance Criteria
- [ ] State machine enforces valid transitions only
- [ ] All state changes are logged with correlation IDs
- [ ] KanataLifecycleManager coordinates all actions
- [ ] Existing UI continues to work
- [ ] ContentView reacts to state changes
- [ ] Unit tests cover all state transitions
- [ ] Integration tests verify end-to-end flow

---

## Phase 3: Wizard Redesign (Days 7-11)

### Objective
Convert wizard to purely reactive UI component with no automatic actions.

### Changes

#### 3.1 Create Reactive Wizard Pages
**File**: `Sources/KeyPath/WizardPages/RequirementsNotMetView.swift`

```swift
struct RequirementsNotMetView: View {
    let missingRequirements: [RequirementType]
    let onGrantPermission: (RequirementType) -> Void
    let onInstallComponent: (RequirementType) -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Setup Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("KeyPath needs some components installed and permissions granted to work properly.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 16) {
                ForEach(missingRequirements, id: \.self) { requirement in
                    RequirementCard(
                        requirement: requirement,
                        onAction: { action in
                            switch action {
                            case .grantPermission:
                                onGrantPermission(requirement)
                            case .installComponent:
                                onInstallComponent(requirement)
                            }
                        }
                    )
                }
            }
        }
        .padding()
    }
}
```

#### 3.2 Create Conflict Resolution View
**File**: `Sources/KeyPath/WizardPages/ConflictDetectedView.swift`

```swift
struct ConflictDetectedView: View {
    let processes: [ConflictingProcess]
    let onResolve: (ConflictResolution) -> Void
    
    @State private var showProcessDetails = false
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Conflicting Processes")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Other keyboard tools are running that may conflict with KeyPath.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Found \(processes.count) conflicting process\(processes.count == 1 ? "" : "es"):")
                    .font(.headline)
                
                ForEach(processes, id: \.pid) { process in
                    ProcessInfoCard(process: process)
                }
                
                Button("Show Technical Details") {
                    showProcessDetails.toggle()
                }
                .buttonStyle(.link)
            }
            
            if showProcessDetails {
                ProcessDetailsView(processes: processes)
                    .transition(.opacity)
            }
            
            VStack(spacing: 12) {
                Button("Terminate Conflicting Processes") {
                    onResolve(.terminate(processes))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Cancel Setup") {
                    onResolve(.cancel)
                }
                .buttonStyle(.bordered)
                
                InfoPanel(
                    title: "What happens when I terminate?",
                    content: """
                    KeyPath will safely stop the conflicting processes so it can access your keyboard.
                    You can restart those applications later if needed.
                    """
                )
            }
        }
        .padding()
        .animation(.easeInOut, value: showProcessDetails)
    }
}
```

#### 3.3 Redesign Main Wizard View
**File**: `Sources/KeyPath/InstallationWizardView.swift`

```swift
struct InstallationWizardView: View {
    @ObservedObject var lifecycleManager: KanataLifecycleManager
    @Environment(\.dismiss) private var dismiss
    
    private let logger = StructuredLogger.shared
    
    var body: some View {
        NavigationView {
            WizardContentView(
                state: lifecycleManager.lifecycleState,
                requirements: lifecycleManager.systemRequirements,
                onUserAction: handleUserAction
            )
            .navigationTitle("KeyPath Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        logWizardDismissal(reason: "User closed")
                        dismiss()
                    }
                    .disabled(!canDismiss)
                }
            }
        }
        .onAppear {
            logWizardPresentation()
        }
        .frame(width: 700, height: 600)
    }
    
    private var canDismiss: Bool {
        switch lifecycleManager.lifecycleState {
        case .running, .readyToStart:
            return true
        case .conflictDetected:
            return false // Must resolve conflicts
        default:
            return true
        }
    }
    
    private func handleUserAction(_ action: UserAction) {
        let correlationId = CorrelationContext.current.generateId(for: "WIZARD_ACTION")
        
        logger.log(
            level: .info,
            category: .userAction,
            message: "User action in wizard",
            correlationId: correlationId,
            context: [
                "action": String(describing: action),
                "currentState": String(describing: lifecycleManager.lifecycleState)
            ],
            component: "InstallationWizard"
        )
        
        Task {
            let result = await lifecycleManager.handleUserAction(action)
            
            await MainActor.run {
                logger.log(
                    level: result.isSuccess ? .info : .warn,
                    category: .userAction,
                    message: "User action result",
                    correlationId: correlationId,
                    context: [
                        "action": String(describing: action),
                        "result": String(describing: result),
                        "newState": String(describing: lifecycleManager.lifecycleState)
                    ],
                    component: "InstallationWizard"
                )
                
                if case .failed(let error) = result {
                    showErrorAlert(error)
                }
            }
        }
    }
    
    private func logWizardPresentation() {
        let correlationId = CorrelationContext.current.generateId(for: "WIZARD_SHOW")
        
        logger.log(
            level: .info,
            category: .wizard,
            message: "Installation wizard presented",
            correlationId: correlationId,
            context: [
                "currentState": String(describing: lifecycleManager.lifecycleState),
                "systemRequirements": lifecycleManager.systemRequirements.summary
            ],
            component: "InstallationWizard"
        )
    }
}

struct WizardContentView: View {
    let state: LifecycleState
    let requirements: SystemRequirements
    let onUserAction: (UserAction) -> Void
    
    var body: some View {
        Group {
            switch state {
            case .checkingRequirements:
                CheckingRequirementsView()
                
            case .requirementsNotMet(let missing):
                RequirementsNotMetView(
                    missingRequirements: missing,
                    onGrantPermission: { requirement in
                        onUserAction(.grantPermission(requirement))
                    },
                    onInstallComponent: { requirement in
                        onUserAction(.installComponent(requirement))
                    }
                )
                
            case .conflictDetected(let processes):
                ConflictDetectedView(
                    processes: processes,
                    onResolve: { resolution in
                        onUserAction(.resolveConflict(resolution))
                    }
                )
                
            case .readyToStart:
                ReadyToStartView {
                    onUserAction(.startKanata)
                }
                
            case .starting:
                StartingView()
                
            case .running:
                CompletedView {
                    onUserAction(.dismissWizard)
                }
                
            case .failed(let error, let recovery):
                FailedView(
                    error: error,
                    recovery: recovery,
                    onRetry: { onUserAction(.retryAfterFailure) },
                    onAlternative: { option in onUserAction(.tryAlternative(option)) }
                )
                
            default:
                LoadingView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: state)
    }
}
```

### Testing Strategy

#### Unit Tests
```swift
class WizardPageTests: XCTestCase {
    
    func testRequirementsNotMetViewActions() {
        let missing: [RequirementType] = [.binaryNotInstalled, .permissionsNotGranted]
        var receivedActions: [RequirementType] = []
        
        let view = RequirementsNotMetView(
            missingRequirements: missing,
            onGrantPermission: { requirement in
                receivedActions.append(requirement)
            }
        )
        
        // Simulate user tapping permission button
        view.simulatePermissionButtonTap(for: .permissionsNotGranted)
        
        XCTAssertEqual(receivedActions, [.permissionsNotGranted])
    }
    
    func testConflictDetectedViewUserChoices() {
        let processes = [ConflictingProcess(pid: 123, name: "karabiner_grabber")]
        var receivedResolution: ConflictResolution?
        
        let view = ConflictDetectedView(
            processes: processes,
            onResolve: { resolution in
                receivedResolution = resolution
            }
        )
        
        // Simulate user choosing to terminate
        view.simulateTerminateButtonTap()
        
        XCTAssertEqual(receivedResolution, .terminate(processes))
    }
}

class WizardNavigationTests: XCTestCase {
    
    func testWizardReactsToStateChanges() {
        let lifecycleManager = MockKanataLifecycleManager()
        let wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        // Start with requirements not met
        lifecycleManager.setState(.requirementsNotMet(missing: [.binaryNotInstalled]))
        XCTAssertTrue(wizard.isShowingRequirementsPage)
        
        // Transition to ready
        lifecycleManager.setState(.readyToStart)
        XCTAssertTrue(wizard.isShowingReadyPage)
        
        // Transition to running
        lifecycleManager.setState(.running(process: mockProcess))
        XCTAssertTrue(wizard.isShowingCompletedPage)
    }
    
    func testWizardCannotBeDismissedDuringConflicts() {
        let lifecycleManager = MockKanataLifecycleManager()
        let wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        lifecycleManager.setState(.conflictDetected(processes: [mockProcess]))
        
        XCTAssertFalse(wizard.canDismiss)
        XCTAssertTrue(wizard.closeButtonDisabled)
    }
}
```

#### Integration Tests
```swift
class WizardIntegrationTests: XCTestCase {
    
    func testCompleteWizardFlow() async {
        let lifecycleManager = KanataLifecycleManager()
        let wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        // Start wizard
        await wizard.appear()
        await lifecycleManager.initialize()
        
        // Should show requirements page if not all met
        if !lifecycleManager.systemRequirements.allMet {
            XCTAssertTrue(wizard.isShowingRequirementsPage)
            
            // Simulate user granting permissions
            await wizard.simulateGrantPermissions()
            
            // Should progress to next step
            XCTAssertFalse(wizard.isShowingRequirementsPage)
        }
        
        // Eventually should reach ready state
        await waitForState(.readyToStart, timeout: 10)
        XCTAssertTrue(wizard.isShowingReadyPage)
        
        // User starts Kanata  
        await wizard.simulateStartButton()
        
        // Should reach running state
        await waitForState(.running, timeout: 10)
        XCTAssertTrue(wizard.isShowingCompletedPage)
    }
    
    func testWizardHandlesErrorsGracefully() async {
        let lifecycleManager = MockKanataLifecycleManager()
        let wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        lifecycleManager.simulateStartFailure(error: .processStartFailed("Permission denied"))
        
        await wizard.simulateStartButton()
        
        XCTAssertTrue(wizard.isShowingFailedPage)
        XCTAssertTrue(wizard.isShowingRetryButton)
    }
}
```

### Acceptance Criteria
- [ ] Wizard shows appropriate page for each lifecycle state
- [ ] No automatic actions taken by wizard
- [ ] All user interactions go through lifecycleManager
- [ ] Cannot dismiss wizard during conflicts
- [ ] Error states show clear recovery options
- [ ] State transitions trigger smooth UI animations
- [ ] Comprehensive logging of all user actions
- [ ] Unit tests cover all wizard pages
- [ ] Integration tests verify complete flow

---

## Phase 4: System Requirements Separation (Days 12-15)

### Objective
Extract and modularize system requirements checking and configuration management.

### Changes

#### 4.1 Create SystemRequirementsChecker
**File**: `Sources/KeyPath/SystemRequirementsChecker.swift`

```swift
struct SystemRequirement {
    let type: RequirementType
    let state: RequirementState
    let lastChecked: Date
    let checkDuration: TimeInterval
}

enum RequirementType: CaseIterable {
    case binaryInstalled
    case permissionsGranted
    case driverInstalled
    case daemonRunning
    
    var displayName: String {
        switch self {
        case .binaryInstalled: return "Kanata Binary"
        case .permissionsGranted: return "System Permissions"
        case .driverInstalled: return "Virtual HID Driver"
        case .daemonRunning: return "HID Daemon"
        }
    }
    
    var description: String {
        switch self {
        case .binaryInstalled: return "Core keyboard remapping engine"
        case .permissionsGranted: return "Input monitoring and accessibility access"
        case .driverInstalled: return "Virtual keyboard driver for input capture"
        case .daemonRunning: return "Background service for hardware access"
        }
    }
}

enum RequirementState: Equatable {
    case unknown
    case checking
    case satisfied
    case notSatisfied(reason: String, action: RequiredAction)
    
    var isSatisfied: Bool {
        if case .satisfied = self {
            return true
        }
        return false
    }
}

enum RequiredAction {
    case installBinary(url: URL)
    case grantPermissions(types: [PermissionType])
    case installDriver(url: URL)
    case startDaemon
    case manualIntervention(instructions: String)
}

struct SystemRequirements {
    let requirements: [RequirementType: SystemRequirement]
    let lastFullCheck: Date
    let checkDuration: TimeInterval
    
    var allMet: Bool {
        requirements.values.allSatisfy { $0.state.isSatisfied }
    }
    
    var missingRequirements: [RequirementType] {
        requirements.compactMap { (type, requirement) in
            requirement.state.isSatisfied ? nil : type
        }
    }
    
    var summary: String {
        let satisfied = requirements.values.filter { $0.state.isSatisfied }.count
        let total = requirements.count
        return "\(satisfied)/\(total) requirements met"
    }
}

class SystemRequirementsChecker {
    private let logger = StructuredLogger.shared
    private let component = "RequirementsChecker"
    private var lastCheck: SystemRequirements?
    
    func checkAllRequirements() async -> SystemRequirements {
        let correlationId = CorrelationContext.current.generateId(for: "REQ_CHECK")
        let startTime = Date()
        
        logger.log(
            level: .info,
            category: .systemRequirements,
            message: "Starting comprehensive requirements check",
            correlationId: correlationId,
            context: [
                "previousCheck": lastCheck?.lastFullCheck.timeIntervalSinceNow ?? -1,
                "systemInfo": getSystemInfo()
            ],
            component: component
        )
        
        var requirements: [RequirementType: SystemRequirement] = [:]
        
        // Check each requirement concurrently
        await withTaskGroup(of: (RequirementType, SystemRequirement).self) { group in
            for type in RequirementType.allCases {
                group.addTask {
                    let requirement = await self.checkRequirement(type, correlationId: correlationId)
                    return (type, requirement)
                }
            }
            
            for await (type, requirement) in group {
                requirements[type] = requirement
            }
        }
        
        let checkDuration = Date().timeIntervalSince(startTime)
        let systemRequirements = SystemRequirements(
            requirements: requirements,
            lastFullCheck: Date(),
            checkDuration: checkDuration
        )
        
        logger.log(
            level: systemRequirements.allMet ? .info : .warn,
            category: .systemRequirements,
            message: "Requirements check completed",
            correlationId: correlationId,
            context: [
                "allMet": systemRequirements.allMet,
                "duration": "\(checkDuration * 1000)ms",
                "summary": systemRequirements.summary,
                "missing": systemRequirements.missingRequirements.map { $0.displayName }
            ],
            component: component
        )
        
        lastCheck = systemRequirements
        return systemRequirements
    }
    
    private func checkRequirement(_ type: RequirementType, correlationId: String) async -> SystemRequirement {
        let startTime = Date()
        
        logger.log(
            level: .debug,
            category: .systemRequirements,
            message: "Checking individual requirement",
            correlationId: correlationId,
            context: [
                "requirement": type.displayName
            ],
            component: component
        )
        
        let state: RequirementState
        
        switch type {
        case .binaryInstalled:
            state = await checkBinaryInstallation()
        case .permissionsGranted:
            state = await checkPermissions()
        case .driverInstalled:
            state = await checkDriver()
        case .daemonRunning:
            state = await checkDaemon()
        }
        
        let checkDuration = Date().timeIntervalSince(startTime)
        
        logger.log(
            level: state.isSatisfied ? .debug : .warn,
            category: .systemRequirements,
            message: "Individual requirement check completed",
            correlationId: correlationId,
            context: [
                "requirement": type.displayName,
                "satisfied": state.isSatisfied,
                "duration": "\(checkDuration * 1000)ms",
                "state": String(describing: state)
            ],
            component: component
        )
        
        return SystemRequirement(
            type: type,
            state: state,
            lastChecked: Date(),
            checkDuration: checkDuration
        )
    }
    
    private func checkBinaryInstallation() async -> RequirementState {
        let kanataPath = "/usr/local/bin/kanata"
        
        guard FileManager.default.fileExists(atPath: kanataPath) else {
            return .notSatisfied(
                reason: "Kanata binary not found at \(kanataPath)",
                action: .installBinary(url: URL(string: "https://github.com/jtroo/kanata")!)
            )
        }
        
        // Check if binary is executable
        guard FileManager.default.isExecutableFile(atPath: kanataPath) else {
            return .notSatisfied(
                reason: "Kanata binary is not executable",
                action: .manualIntervention(instructions: "Run: chmod +x \(kanataPath)")
            )
        }
        
        // Try to get version
        let versionResult = await checkKanataVersion(path: kanataPath)
        if versionResult.success {
            return .satisfied
        } else {
            return .notSatisfied(
                reason: "Kanata binary exists but is not functional: \(versionResult.error ?? "Unknown error")",
                action: .installBinary(url: URL(string: "https://github.com/jtroo/kanata")!)
            )
        }
    }
    
    private func checkPermissions() async -> RequirementState {
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let accessibility = AXIsProcessTrusted()
        
        var missingPermissions: [PermissionType] = []
        if !inputMonitoring { missingPermissions.append(.inputMonitoring) }
        if !accessibility { missingPermissions.append(.accessibility) }
        
        if missingPermissions.isEmpty {
            return .satisfied
        } else {
            return .notSatisfied(
                reason: "Missing permissions: \(missingPermissions.map { $0.displayName }.joined(separator: ", "))",
                action: .grantPermissions(types: missingPermissions)
            )
        }
    }
    
    private func getSystemInfo() -> [String: Any] {
        return [
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": ProcessInfo.processInfo.processorCount,
            "bundlePath": Bundle.main.bundlePath
        ]
    }
}
```

#### 4.2 Create KanataConfigManager
**File**: `Sources/KeyPath/KanataConfigManager.swift`

```swift
enum ConfigError: Error, LocalizedError {
    case invalidSyntax(errors: [String])
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    case validationFailed(errors: [String])
    case repairFailed(originalErrors: [String], repairErrors: [String])
    
    var errorDescription: String? {
        switch self {
        case .invalidSyntax(let errors):
            return "Configuration syntax errors: \(errors.joined(separator: ", "))"
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied accessing: \(path)"
        case .validationFailed(let errors):
            return "Configuration validation failed: \(errors.joined(separator: ", "))"
        case .repairFailed(let originalErrors, let repairErrors):
            return "Failed to repair config. Original: \(originalErrors.joined(separator: ", ")), Repair: \(repairErrors.joined(separator: ", "))"
        }
    }
    
    var recoveryOptions: [RecoveryOption] {
        switch self {
        case .invalidSyntax, .validationFailed:
            return [.repairConfig, .resetToDefault, .editManually]
        case .fileNotFound:
            return [.createDefault, .selectExisting]
        case .permissionDenied:
            return [.fixPermissions, .selectAlternativeLocation]
        case .repairFailed:
            return [.resetToDefault, .editManually, .restoreBackup]
        }
    }
}

enum RecoveryOption {
    case repairConfig
    case resetToDefault
    case editManually
    case createDefault
    case selectExisting
    case fixPermissions
    case selectAlternativeLocation
    case restoreBackup
    
    var displayName: String {
        switch self {
        case .repairConfig: return "Attempt Automatic Repair"
        case .resetToDefault: return "Reset to Default Configuration"
        case .editManually: return "Edit Configuration Manually"
        case .createDefault: return "Create Default Configuration"
        case .selectExisting: return "Select Existing Configuration"
        case .fixPermissions: return "Fix File Permissions"
        case .selectAlternativeLocation: return "Use Different Location"
        case .restoreBackup: return "Restore from Backup"
        }
    }
}

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let suggestions: [String]
    
    static let valid = ValidationResult(isValid: true, errors: [], warnings: [], suggestions: [])
}

class KanataConfigManager {
    private let logger = StructuredLogger.shared
    private let component = "ConfigManager"
    
    private let defaultConfigPath: String
    private let backupDirectory: String
    
    init(configPath: String) {
        self.defaultConfigPath = configPath
        self.backupDirectory = URL(fileURLWithPath: configPath)
            .deletingLastPathComponent()
            .appendingPathComponent("backups")
            .path
    }
    
    func generateConfig(from mappings: [KeyMapping]) -> Result<String, ConfigError> {
        let correlationId = CorrelationContext.current.generateId(for: "CONFIG_GEN")
        
        logger.log(
            level: .info,
            category: .configuration,
            message: "Generating Kanata configuration",
            correlationId: correlationId,
            context: [
                "mappingCount": mappings.count,
                "mappings": mappings.map { "\($0.input) -> \($0.output)" }
            ],
            component: component
        )
        
        guard !mappings.isEmpty else {
            return .success(generateDefaultConfig())
        }
        
        let config = buildConfigString(from: mappings)
        
        // Validate generated config
        let validation = validateConfigSyntax(config)
        if validation.isValid {
            logger.log(
                level: .info,
                category: .configuration,
                message: "Configuration generated successfully",
                correlationId: correlationId,
                context: [
                    "configLength": config.count,
                    "warnings": validation.warnings
                ],
                component: component
            )
            return .success(config)
        } else {
            logger.log(
                level: .error,
                category: .configuration,
                message: "Generated configuration is invalid",
                correlationId: correlationId,
                context: [
                    "errors": validation.errors,
                    "configContent": config
                ],
                component: component
            )
            return .failure(.invalidSyntax(errors: validation.errors))
        }
    }
    
    func validateConfig(_ config: String) async -> ValidationResult {
        let correlationId = CorrelationContext.current.generateId(for: "CONFIG_VALIDATE")
        
        logger.log(
            level: .debug,
            category: .configuration,
            message: "Validating configuration",
            correlationId: correlationId,
            context: [
                "configLength": config.count
            ],
            component: component
        )
        
        // First, check syntax
        let syntaxResult = validateConfigSyntax(config)
        if !syntaxResult.isValid {
            return syntaxResult
        }
        
        // Then, validate with Kanata itself
        let processResult = await validateWithKanata(config, correlationId: correlationId)
        
        return ValidationResult(
            isValid: processResult.isValid,
            errors: syntaxResult.errors + processResult.errors,
            warnings: syntaxResult.warnings + processResult.warnings,
            suggestions: syntaxResult.suggestions + processResult.suggestions
        )
    }
    
    func saveConfig(_ config: String, to path: String? = nil) async -> Result<Void, ConfigError> {
        let targetPath = path ?? defaultConfigPath
        let correlationId = CorrelationContext.current.generateId(for: "CONFIG_SAVE")
        
        logger.log(
            level: .info,
            category: .configuration,
            message: "Saving configuration",
            correlationId: correlationId,
            context: [
                "path": targetPath,
                "configLength": config.count
            ],
            component: component
        )
        
        do {
            // Create directory if needed
            let directory = URL(fileURLWithPath: targetPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            // Create backup of existing config
            if FileManager.default.fileExists(atPath: targetPath) {
                try await createBackup(of: targetPath, correlationId: correlationId)
            }
            
            // Write new config
            try config.write(toFile: targetPath, atomically: true, encoding: .utf8)
            
            logger.log(
                level: .info,
                category: .configuration,
                message: "Configuration saved successfully",
                correlationId: correlationId,
                context: [
                    "path": targetPath,
                    "size": config.count
                ],
                component: component
            )
            
            return .success(())
            
        } catch {
            logger.log(
                level: .error,
                category: .configuration,
                message: "Failed to save configuration",
                correlationId: correlationId,
                context: [
                    "path": targetPath,
                    "error": error.localizedDescription
                ],
                component: component
            )
            
            if (error as NSError).code == NSFileWriteNoPermissionError {
                return .failure(.permissionDenied(path: targetPath))
            } else {
                return .failure(.invalidSyntax(errors: [error.localizedDescription]))
            }
        }
    }
    
    private func validateWithKanata(_ config: String, correlationId: String) async -> ValidationResult {
        // Write config to temporary file
        let tempPath = NSTemporaryDirectory() + "keypath-validation-\(UUID().uuidString).kbd"
        
        do {
            try config.write(toFile: tempPath, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: tempPath) }
            
            // Run kanata --check
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/kanata")
            process.arguments = ["--cfg", tempPath, "--check"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let outputString = String(data: output, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                return ValidationResult(
                    isValid: true,
                    errors: [],
                    warnings: parseWarnings(from: outputString),
                    suggestions: []
                )
            } else {
                return ValidationResult(
                    isValid: false,
                    errors: parseErrors(from: outputString),
                    warnings: [],
                    suggestions: generateSuggestions(from: outputString)
                )
            }
            
        } catch {
            return ValidationResult(
                isValid: false,
                errors: ["Validation process failed: \(error.localizedDescription)"],
                warnings: [],
                suggestions: []
            )
        }
    }
}
```

### Testing Strategy

#### Unit Tests
```swift
class SystemRequirementsCheckerTests: XCTestCase {
    var checker: SystemRequirementsChecker!
    
    override func setUp() {
        checker = SystemRequirementsChecker()
    }
    
    func testAllRequirementsMet() async {
        let mockChecker = MockSystemRequirementsChecker()
        mockChecker.binaryExists = true
        mockChecker.permissionsGranted = true
        mockChecker.driverInstalled = true
        mockChecker.daemonRunning = true
        
        let requirements = await mockChecker.checkAllRequirements()
        
        XCTAssertTrue(requirements.allMet)
        XCTAssertEqual(requirements.missingRequirements.count, 0)
    }
    
    func testMissingRequirements() async {
        let mockChecker = MockSystemRequirementsChecker()
        mockChecker.binaryExists = false
        mockChecker.permissionsGranted = false
        
        let requirements = await mockChecker.checkAllRequirements()
        
        XCTAssertFalse(requirements.allMet)
        XCTAssertEqual(requirements.missingRequirements.count, 2)
        XCTAssertTrue(requirements.missingRequirements.contains(.binaryInstalled))
        XCTAssertTrue(requirements.missingRequirements.contains(.permissionsGranted))
    }
    
    func testRequirementCheckLogging() async {
        let mockLogger = MockStructuredLogger()
        let checker = SystemRequirementsChecker(logger: mockLogger)
        
        _ = await checker.checkAllRequirements()
        
        let logEntries = mockLogger.logEntries.filter { $0.category == .systemRequirements }
        XCTAssertGreaterThan(logEntries.count, 0)
        
        let startEntry = logEntries.first { $0.message.contains("Starting comprehensive") }
        let completeEntry = logEntries.first { $0.message.contains("completed") }
        
        XCTAssertNotNil(startEntry)
        XCTAssertNotNil(completeEntry)
        XCTAssertEqual(startEntry?.correlationId, completeEntry?.correlationId)
    }
}

class KanataConfigManagerTests: XCTestCase {
    var configManager: KanataConfigManager!
    var tempConfigPath: String!
    
    override func setUp() {
        tempConfigPath = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).kbd"
        configManager = KanataConfigManager(configPath: tempConfigPath)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempConfigPath)
    }
    
    func testConfigGeneration() {
        let mappings = [
            KeyMapping(input: "caps", output: "escape"),
            KeyMapping(input: "tab", output: "ctrl")
        ]
        
        let result = configManager.generateConfig(from: mappings)
        
        XCTAssertTrue(result.isSuccess)
        if case .success(let config) = result {
            XCTAssertTrue(config.contains("caps"))
            XCTAssertTrue(config.contains("escape"))
            XCTAssertTrue(config.contains("tab"))
            XCTAssertTrue(config.contains("ctrl"))
        }
    }
    
    func testConfigValidation() async {
        let validConfig = """
        (defcfg
          process-unmapped-keys no
          danger-enable-cmd yes
        )
        
        (defsrc caps)
        (deflayer base esc)
        """
        
        let result = await configManager.validateConfig(validConfig)
        
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.errors.count, 0)
    }
    
    func testInvalidConfigValidation() async {
        let invalidConfig = """
        (defcfg
          invalid-option yes
        )
        
        (defsrc caps)
        (deflayer base invalid-key)
        """
        
        let result = await configManager.validateConfig(invalidConfig)
        
        XCTAssertFalse(result.isValid)
        XCTAssertGreaterThan(result.errors.count, 0)
    }
    
    func testConfigSaveAndBackup() async {
        let config = "(defcfg process-unmapped-keys no)\n(defsrc caps)\n(deflayer base esc)"
        
        // Save initial config
        let saveResult1 = await configManager.saveConfig(config)
        XCTAssertTrue(saveResult1.isSuccess)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempConfigPath))
        
        // Save updated config (should create backup)
        let updatedConfig = config + "\n; Updated"
        let saveResult2 = await configManager.saveConfig(updatedConfig)
        XCTAssertTrue(saveResult2.isSuccess)
        
        // Verify backup was created
        let backupDir = URL(fileURLWithPath: tempConfigPath).deletingLastPathComponent().appendingPathComponent("backups")
        let backupFiles = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
        XCTAssertGreaterThan(backupFiles?.count ?? 0, 0)
    }
}
```

### Acceptance Criteria
- [ ] SystemRequirementsChecker runs all checks concurrently
- [ ] Individual requirement states are tracked separately
- [ ] KanataConfigManager validates configs with Kanata binary
- [ ] Config generation produces syntactically correct output
- [ ] Automatic backups are created before config updates
- [ ] Comprehensive error handling with recovery options
- [ ] All operations are logged with correlation IDs
- [ ] Unit tests achieve >95% coverage
- [ ] Integration tests verify end-to-end functionality

---

## Phase 5: Polish & Comprehensive Testing (Days 16-20)

### Objective
Add final polish, comprehensive logging, and complete test coverage.

### Changes

#### 5.1 Enhanced Logging and Debugging Tools
**File**: `Sources/KeyPath/Debugging/LogAnalyzer.swift`

```swift
class LogAnalyzer {
    static let shared = LogAnalyzer()
    
    private let logger = StructuredLogger.shared
    
    func analyzeStartupSequence(correlationId: String) -> StartupAnalysis {
        let entries = logger.getEntries(correlationId: correlationId)
        
        return StartupAnalysis(
            totalDuration: calculateDuration(entries),
            stateTransitions: extractStateTransitions(entries),
            performanceMetrics: calculatePerformanceMetrics(entries),
            errors: extractErrors(entries),
            recommendations: generateRecommendations(entries)
        )
    }
    
    func generateDebugReport() -> String {
        let recentEntries = logger.getRecentEntries(limit: 1000)
        
        var report = "=== KeyPath Debug Report ===\n\n"
        report += "Generated: \(Date())\n"
        report += "Total Log Entries: \(recentEntries.count)\n\n"
        
        // System Information
        report += "=== System Information ===\n"
        report += "OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        report += "App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\n"
        report += "Architecture: \(ProcessInfo.processInfo.machineArchitecture)\n\n"
        
        // Recent State Transitions
        let stateTransitions = recentEntries.filter { $0.category == .stateTransition }
        report += "=== Recent State Transitions ===\n"
        for entry in stateTransitions.suffix(10) {
            report += "\(entry.timestamp): \(entry.message)\n"
        }
        report += "\n"
        
        // Error Summary
        let errors = recentEntries.filter { $0.level == .error }
        report += "=== Recent Errors ===\n"
        for entry in errors.suffix(10) {
            report += "\(entry.timestamp): \(entry.message)\n"
            report += "  Context: \(entry.context)\n"
        }
        report += "\n"
        
        // Performance Metrics
        report += "=== Performance Metrics ===\n"
        let perfEntries = recentEntries.filter { $0.category == .performance }
        if !perfEntries.isEmpty {
            let avgDuration = perfEntries.compactMap { entry in
                entry.context["duration"] as? String
            }.compactMap { durationStr in
                Double(durationStr.replacingOccurrences(of: "ms", with: ""))
            }.reduce(0, +) / Double(perfEntries.count)
            
            report += "Average Operation Duration: \(avgDuration)ms\n"
        }
        
        return report
    }
    
    func exportLogsToFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let fileName = "keypath-debug-\(timestamp).log"
        let documentsPath = FileManager.default.urls(for: .documentsDirectory, in: .userDomainMask).first!
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        let report = generateDebugReport()
        
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            logger.log(
                level: .error,
                category: .error,
                message: "Failed to export logs",
                context: ["error": error.localizedDescription],
                component: "LogAnalyzer"
            )
            return nil
        }
    }
}
```

#### 5.2 Performance Monitoring
**File**: `Sources/KeyPath/Performance/PerformanceMonitor.swift`

```swift
class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = StructuredLogger.shared
    private var operationStartTimes: [String: Date] = [:]
    private let queue = DispatchQueue(label: "performance.monitor")
    
    func startOperation(_ operationId: String, type: OperationType) {
        queue.sync {
            operationStartTimes[operationId] = Date()
        }
        
        logger.log(
            level: .debug,
            category: .performance,
            message: "Operation started",
            correlationId: operationId,
            context: [
                "operationType": type.rawValue
            ],
            component: "PerformanceMonitor"
        )
    }
    
    func endOperation(_ operationId: String, success: Bool = true) {
        let endTime = Date()
        let duration: TimeInterval
        
        queue.sync {
            guard let startTime = operationStartTimes.removeValue(forKey: operationId) else {
                return
            }
            duration = endTime.timeIntervalSince(startTime)
        }
        
        logger.log(
            level: success ? .debug : .warn,
            category: .performance,
            message: "Operation completed",
            correlationId: operationId,
            context: [
                "duration": "\(duration * 1000)ms",
                "success": success
            ],
            component: "PerformanceMonitor"
        )
        
        // Alert if operation took too long
        if duration > 5.0 { // 5 seconds threshold
            logger.log(
                level: .warn,
                category: .performance,
                message: "Slow operation detected",
                correlationId: operationId,
                context: [
                    "duration": "\(duration * 1000)ms",
                    "threshold": "5000ms"
                ],
                component: "PerformanceMonitor"
            )
        }
    }
    
    func measureOperation<T>(_ operationId: String, type: OperationType, operation: () async throws -> T) async rethrows -> T {
        startOperation(operationId, type: type)
        
        do {
            let result = try await operation()
            endOperation(operationId, success: true)
            return result
        } catch {
            endOperation(operationId, success: false)
            throw error
        }
    }
}

enum OperationType: String, CaseIterable {
    case startup = "startup"
    case stateTransition = "state_transition"
    case processStart = "process_start"
    case processStop = "process_stop"
    case requirementCheck = "requirement_check"
    case configGeneration = "config_generation"
    case configValidation = "config_validation"
    case userAction = "user_action"
}
```

#### 5.3 Comprehensive Integration Tests
**File**: `Tests/KeyPathTests/IntegrationTests/FullFlowIntegrationTests.swift`

```swift
class FullFlowIntegrationTests: XCTestCase {
    var lifecycleManager: KanataLifecycleManager!
    var wizard: InstallationWizardView!
    var contentView: ContentView!
    
    override func setUp() async throws {
        lifecycleManager = KanataLifecycleManager()
        wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        contentView = ContentView(lifecycleManager: lifecycleManager)
        
        // Ensure clean state
        await cleanupAllKanataProcesses()
    }
    
    override func tearDown() async throws {
        await cleanupAllKanataProcesses()
    }
    
    func testCompleteUserJourney() async throws {
        // Simulate app launch
        await lifecycleManager.initialize()
        
        // Should start in checking requirements state
        XCTAssertEqual(lifecycleManager.lifecycleState, .checkingRequirements)
        
        // Wait for requirements check to complete
        await waitForState(.requirementsNotMet, .readyToStart, .conflictDetected, timeout: 10)
        
        // Handle each possible state
        switch lifecycleManager.lifecycleState {
        case .requirementsNotMet(let missing):
            // Simulate user resolving requirements
            for requirement in missing {
                await simulateRequirementResolution(requirement)
            }
            
            await waitForState(.readyToStart, timeout: 30)
            
        case .conflictDetected(let processes):
            // Simulate user resolving conflicts
            let result = await lifecycleManager.resolveConflicts(action: .terminate(processes))
            XCTAssertTrue(result.isSuccess)
            
            await waitForState(.readyToStart, timeout: 10)
            
        case .readyToStart:
            break // Already ready
            
        default:
            XCTFail("Unexpected state: \(lifecycleManager.lifecycleState)")
        }
        
        // User starts Kanata
        let startResult = await lifecycleManager.requestStart()
        XCTAssertTrue(startResult.isSuccess, "Failed to start Kanata: \(startResult)")
        
        // Should reach running state
        await waitForState(.running, timeout: 10)
        
        if case .running(let process) = lifecycleManager.lifecycleState {
            // Verify process is actually running
            XCTAssertTrue(isProcessRunning(pid: process.pid))
            
            // Test keyboard functionality
            let keyboardWorks = await testKeyboardRemapping()
            XCTAssertTrue(keyboardWorks, "Keyboard remapping not working")
        } else {
            XCTFail("Expected running state, got: \(lifecycleManager.lifecycleState)")
        }
        
        // Test stopping
        let stopResult = await lifecycleManager.requestStop()
        XCTAssertTrue(stopResult.isSuccess)
        
        await waitForState(.readyToStart, timeout: 10)
        
        // Verify no processes remain
        let remainingProcesses = await findKanataProcesses()
        XCTAssertEqual(remainingProcesses.count, 0, "Processes not cleaned up properly")
    }
    
    func testErrorRecoveryFlow() async throws {
        await lifecycleManager.initialize()
        await waitForStateChange(timeout: 10)
        
        // Force an error by corrupting the config
        let configManager = KanataConfigManager(configPath: lifecycleManager.configPath)
        let invalidConfig = "invalid kanata config syntax"
        _ = await configManager.saveConfig(invalidConfig)
        
        // Try to start - should fail
        let result = await lifecycleManager.requestStart()
        XCTAssertFalse(result.isSuccess)
        
        // Should be in failed state
        if case .failed(let error, let recovery) = lifecycleManager.lifecycleState {
            XCTAssertTrue(recovery.contains(.resetToDefault))
            
            // Simulate user choosing to reset to default
            let recoveryResult = await lifecycleManager.performRecovery(.resetToDefault)
            XCTAssertTrue(recoveryResult.isSuccess)
            
            // Should be able to start now
            await waitForState(.readyToStart, timeout: 10)
            let startResult = await lifecycleManager.requestStart()
            XCTAssertTrue(startResult.isSuccess)
            
        } else {
            XCTFail("Expected failed state, got: \(lifecycleManager.lifecycleState)")
        }
    }
    
    func testWizardGuidedSetup() async throws {
        // Start with no requirements met
        let mockChecker = MockSystemRequirementsChecker()
        mockChecker.allRequirementsMet = false
        mockChecker.missingRequirements = [.binaryInstalled, .permissionsGranted]
        
        lifecycleManager = KanataLifecycleManager(requirementsChecker: mockChecker)
        wizard = InstallationWizardView(lifecycleManager: lifecycleManager)
        
        await lifecycleManager.initialize()
        await waitForState(.requirementsNotMet, timeout: 5)
        
        // Wizard should show requirements page
        XCTAssertTrue(wizard.isShowingRequirementsPage)
        
        // Simulate user installing binary
        mockChecker.binaryInstalled = true
        await wizard.simulateGrantPermissions()
        
        // Should progress through wizard
        await waitForWizardState(.permissionsPage, timeout: 10)
        
        // Simulate user granting permissions
        mockChecker.permissionsGranted = true
        await wizard.simulateGrantPermissions()
        
        // Should reach ready state
        await waitForState(.readyToStart, timeout: 10)
        XCTAssertTrue(wizard.isShowingReadyPage)
        
        // User starts from wizard
        await wizard.simulateStartButton()
        
        await waitForState(.running, timeout: 10)
        XCTAssertTrue(wizard.isShowingCompletedPage)
    }
    
    func testConcurrentOperations() async throws {
        await lifecycleManager.initialize()
        await waitForState(.readyToStart, timeout: 10)
        
        // Try to start multiple operations concurrently
        async let result1 = lifecycleManager.requestStart()
        async let result2 = lifecycleManager.requestStart()
        async let result3 = lifecycleManager.requestStart()
        
        let results = await [result1, result2, result3]
        
        // Only one should succeed
        let successCount = results.filter { $0.isSuccess }.count
        XCTAssertEqual(successCount, 1, "Multiple concurrent starts should be prevented")
        
        // Should have exactly one running process
        let processes = await findKanataProcesses()
        XCTAssertEqual(processes.count, 1, "Should have exactly one Kanata process")
    }
    
    func testLoggingAndDebugging() async throws {
        let mockLogger = MockStructuredLogger()
        StructuredLogger.setInstance(mockLogger)
        
        await lifecycleManager.initialize()
        await waitForState(.readyToStart, timeout: 10)
        
        let correlationId = CorrelationContext.current.generateId(for: "TEST_LOGGING")
        
        CorrelationContext.current.setContext(correlationId)
        await lifecycleManager.requestStart()
        
        // Verify comprehensive logging
        let logEntries = mockLogger.logEntries.filter { $0.correlationId == correlationId }
        XCTAssertGreaterThan(logEntries.count, 5, "Should have comprehensive logging")
        
        // Verify different log categories are present
        let categories = Set(logEntries.map { $0.category })
        XCTAssertTrue(categories.contains(.lifecycle))
        XCTAssertTrue(categories.contains(.stateTransition))
        XCTAssertTrue(categories.contains(.processManagement))
        
        // Verify correlation ID consistency
        for entry in logEntries {
            XCTAssertEqual(entry.correlationId, correlationId, "Correlation ID should be consistent")
        }
    }
    
    // Helper methods
    private func waitForState(_ expectedStates: LifecycleState..., timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            if expectedStates.contains(lifecycleManager.lifecycleState) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        XCTFail("Timeout waiting for state \(expectedStates), current: \(lifecycleManager.lifecycleState)")
    }
    
    private func simulateRequirementResolution(_ requirement: RequirementType) async {
        switch requirement {
        case .binaryInstalled:
            // Mock binary installation
            break
        case .permissionsGranted:
            // Mock permission granting
            break
        case .driverInstalled:
            // Mock driver installation
            break
        case .daemonRunning:
            // Mock daemon starting
            break
        }
    }
    
    private func testKeyboardRemapping() async -> Bool {
        // Implementation to test if keyboard remapping is working
        // This would involve sending test key events and verifying remapping
        return true // Simplified for this example
    }
}
```

### Automated Testing Strategy

#### 5.4 Continuous Integration Setup
**File**: `.github/workflows/test.yml`

```yaml
name: KeyPath Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Kanata
      run: |
        brew install kanata
        
    - name: Setup Test Environment
      run: |
        # Create test directories
        mkdir -p ~/Library/Application\ Support/KeyPath/Test
        mkdir -p ~/Library/Logs/KeyPath
        
        # Grant permissions for testing (would need manual setup in real CI)
        # This is a simplified example
        
    - name: Run Unit Tests
      run: |
        swift test --parallel
        
    - name: Run Integration Tests
      run: |
        swift test --filter IntegrationTests
        
    - name: Generate Test Report
      run: |
        swift test --enable-code-coverage
        xcrun llvm-cov export -format="lcov" .build/debug/KeyPathPackageTests.xctest/Contents/MacOS/KeyPathPackageTests -instr-profile .build/debug/codecov/default.profdata > coverage.lcov
        
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
      with:
        file: coverage.lcov
        
    - name: Cleanup Test Environment
      if: always()
      run: |
        # Kill any test processes
        sudo pkill -f kanata || true
        
        # Clean up test files
        rm -rf ~/Library/Application\ Support/KeyPath/Test
```

### Acceptance Criteria
- [ ] Comprehensive logging covers all operations with correlation IDs
- [ ] Performance monitoring identifies slow operations
- [ ] Debug report generation provides actionable insights
- [ ] Log export functionality works for user support
- [ ] Full integration tests cover complete user journeys
- [ ] Error recovery scenarios are tested
- [ ] Concurrent operation handling is verified
- [ ] CI/CD pipeline runs all tests automatically
- [ ] Code coverage exceeds 90% for all components
- [ ] No memory leaks or performance regressions

---

## Testing Strategy Summary

### Test Categories

#### Unit Tests (Target: >95% Coverage)
- **State Machine**: All state transitions and validation
- **Lifecycle Manager**: User actions and state coordination
- **Requirements Checker**: Individual requirement checks and aggregation
- **Config Manager**: Config generation, validation, and error handling
- **Wizard Components**: User interactions and reactive behavior
- **Logging System**: Log formatting, correlation IDs, and structured data

#### Integration Tests (Target: >90% Coverage)
- **Complete User Flows**: App launch through successful setup
- **Error Recovery**: Various failure modes and recovery paths
- **Wizard Integration**: Multi-step guided setup process
- **Process Management**: Start/stop/restart scenarios
- **Configuration Pipeline**: Generate → Validate → Save → Apply

#### End-to-End Tests
- **Real System Tests**: Using actual Kanata binary and system permissions
- **Performance Tests**: Startup time, memory usage, responsiveness
- **Stress Tests**: Rapid user actions, concurrent operations
- **Compatibility Tests**: Different macOS versions and system configurations

### Automated Testing Pipeline

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Unit Tests    │    │Integration Tests│    │  E2E Tests      │
│                 │    │                 │    │                 │
│ • Fast (<1s)    │───▶│ • Medium (10s)  │───▶│ • Slow (60s)    │
│ • Isolated      │    │ • Components    │    │ • Full System   │
│ • Mocked Deps   │    │ • Real Services │    │ • Real Hardware │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CI/CD Pipeline                               │
│                                                                 │
│ 1. Code Push → Unit Tests (parallel)                          │
│ 2. Unit Pass → Integration Tests (sequential)                  │
│ 3. Integration Pass → E2E Tests (macOS runner)                │
│ 4. All Pass → Coverage Report → Deployment                     │
└─────────────────────────────────────────────────────────────────┘
```

### Complete Test Infrastructure

#### Standardized Mock Objects Framework
```swift
// Base protocol for all mock objects
protocol MockObjectProtocol {
    func reset() // Reset to initial state
    func verify() throws // Verify expectations were met
    var callHistory: [String] { get } // Track method calls
}

// Example comprehensive mock
class MockKanataManager: KanataManagerProtocol, MockObjectProtocol {
    // Configuration flags
    var shouldFailStart = false
    var shouldFailStop = false
    var startDelay: TimeInterval = 0
    
    // Call tracking
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var callHistory: [String] = []
    
    func startKanataProcess() async throws -> ProcessInfo {
        callHistory.append("startKanataProcess()")
        startCallCount += 1
        
        if startDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
        }
        
        if shouldFailStart {
            throw KanataError.processStartFailed("Mock start failure")
        }
        
        return ProcessInfo(pid: 12345, command: "kanata")
    }
    
    func reset() {
        shouldFailStart = false
        shouldFailStop = false
        startDelay = 0
        startCallCount = 0
        stopCallCount = 0
        callHistory.removeAll()
    }
    
    func verify() throws {
        // Override in specific tests to verify expectations
    }
}
```

#### Test Utilities and Fixtures
```swift
struct TestFixtures {
    static let validKanataConfig = """
    (defcfg process-unmapped-keys no danger-enable-cmd yes)
    (defsrc caps)
    (deflayer base esc)
    """
    
    static let mockProcessInfo = ProcessInfo(pid: 12345, command: "kanata")
    static let mockError = KanataError.processStartFailed("Mock error")
}

class TestUtilities {
    static func waitForCondition(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 5.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw TestError.conditionTimeout("Condition not met within \(timeout)s")
    }
}
```

- **Mock Objects**: Comprehensive mocks with call tracking and verification
- **Test Fixtures**: Pre-built configurations for all common scenarios
- **Correlation IDs**: UUID-based tracking across all test operations
- **Cleanup Procedures**: Async utilities for reliable test environment teardown
- **Test Utilities**: Common functions for waiting, timing, and condition checking

---

## Detailed Testing Framework

### Unit Testing Architecture

Each component will have comprehensive unit tests with the following structure:

```swift
// Example: KanataLifecycleManagerTests.swift
class KanataLifecycleManagerTests: XCTestCase {
    var lifecycleManager: KanataLifecycleManager!
    var mockStateMachine: MockLifecycleStateMachine!
    var mockKanataManager: MockKanataManager!
    var mockLogger: MockStructuredLogger!
    
    override func setUp() {
        mockStateMachine = MockLifecycleStateMachine()
        mockKanataManager = MockKanataManager()
        mockLogger = MockStructuredLogger()
        
        lifecycleManager = KanataLifecycleManager(
            stateMachine: mockStateMachine,
            kanataManager: mockKanataManager,
            logger: mockLogger
        )
    }
    
    func testInitialization() async {
        // Test: Manager initializes in correct state
        await lifecycleManager.initialize()
        
        XCTAssertEqual(lifecycleManager.currentState, .checkingRequirements)
        XCTAssertEqual(mockLogger.logCount(category: .lifecycle), 1)
    }
    
    func testUserActionHandling() async {
        // Test: User actions are processed correctly
        mockStateMachine.currentState = .readyToStart
        
        let result = await lifecycleManager.handleUserAction(.startKanata)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(mockStateMachine.transitionCount, 1)
    }
    
    func testErrorRecovery() async {
        // Test: Errors trigger proper recovery flows
        mockKanataManager.shouldFailStart = true
        
        let result = await lifecycleManager.requestStart()
        
        XCTAssertFalse(result.isSuccess)
        if case .failed(let error, let recovery) = lifecycleManager.currentState {
            XCTAssertNotNil(error)
            XCTAssertFalse(recovery.isEmpty)
        } else {
            XCTFail("Expected failed state")
        }
    }
}
```

### Mock Objects Framework

```swift
// Standardized mock objects for consistent testing
class MockKanataManager: KanataManagerProtocol {
    var shouldFailStart = false
    var shouldFailStop = false
    var startCallCount = 0
    var stopCallCount = 0
    var mockProcess: ProcessInfo?
    
    func startKanataProcess() async throws -> ProcessInfo {
        startCallCount += 1
        
        if shouldFailStart {
            throw KanataError.processStartFailed("Mock start failure")
        }
        
        let process = ProcessInfo(pid: 12345, command: "kanata")
        mockProcess = process
        return process
    }
    
    func stopKanataProcess() async throws {
        stopCallCount += 1
        
        if shouldFailStop {
            throw KanataError.processStopFailed("Mock stop failure")
        }
        
        mockProcess = nil
    }
}

class MockStructuredLogger: StructuredLoggerProtocol {
    private(set) var logEntries: [LogEntry] = []
    
    func log(
        level: LogLevel,
        category: LogCategory, 
        message: String,
        correlationId: String,
        context: [String: Any],
        component: String
    ) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            correlationId: correlationId,
            context: context,
            component: component
        )
        logEntries.append(entry)
    }
    
    func logCount(category: LogCategory) -> Int {
        return logEntries.filter { $0.category == category }.count
    }
}
```

### Integration Testing Strategy

#### Test Environment Setup

```swift
class IntegrationTestEnvironment {
    static let shared = IntegrationTestEnvironment()
    
    private let testConfigPath: String
    private let testLogPath: String
    
    init() {
        let testId = UUID().uuidString.prefix(8)
        testConfigPath = NSTemporaryDirectory() + "keypath-test-\(testId).kbd"
        testLogPath = NSTemporaryDirectory() + "keypath-test-\(testId).log"
    }
    
    func setUp() async throws {
        // Create clean test environment
        try await cleanupExistingProcesses()
        try createTestDirectories()
        try setupTestConfiguration()
    }
    
    func tearDown() async throws {
        // Clean up test environment
        try await cleanupExistingProcesses()
        try removeTestFiles()
        try clearTestLogs()
    }
    
    private func cleanupExistingProcesses() async throws {
        let processes = try await findKanataProcesses()
        for process in processes {
            try await terminateProcess(pid: process.pid)
        }
        
        // Wait for processes to fully terminate
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }
}
```

#### Comprehensive Integration Tests

```swift
class SystemIntegrationTests: XCTestCase {
    var testEnvironment: IntegrationTestEnvironment!
    
    override func setUp() async throws {
        testEnvironment = IntegrationTestEnvironment.shared
        try await testEnvironment.setUp()
    }
    
    override func tearDown() async throws {
        try await testEnvironment.tearDown()
    }
    
    func testCompleteSetupFlow() async throws {
        // Test the complete user journey from app launch to working keyboard remapping
        let lifecycleManager = KanataLifecycleManager()
        
        // Phase 1: Initialization
        await lifecycleManager.initialize()
        try await waitForState(.checkingRequirements, timeout: 5)
        
        // Phase 2: Requirements handling
        try await waitForStableState(timeout: 30)
        
        switch lifecycleManager.currentState {
        case .requirementsNotMet(let missing):
            try await resolveRequirements(missing, lifecycleManager: lifecycleManager)
            
        case .conflictDetected(let processes):
            try await resolveConflicts(processes, lifecycleManager: lifecycleManager)
            
        case .readyToStart:
            break // Already ready
            
        default:
            XCTFail("Unexpected state after initialization: \(lifecycleManager.currentState)")
        }
        
        // Phase 3: Starting Kanata
        try await waitForState(.readyToStart, timeout: 30)
        
        let startResult = await lifecycleManager.requestStart()
        XCTAssertTrue(startResult.isSuccess, "Failed to start: \(startResult)")
        
        try await waitForState(.running, timeout: 10)
        
        // Phase 4: Verify functionality
        if case .running(let process) = lifecycleManager.currentState {
            XCTAssertTrue(try await isProcessActuallyRunning(pid: process.pid))
            XCTAssertTrue(try await verifyKeyboardRemapping())
        } else {
            XCTFail("Expected running state")
        }
        
        // Phase 5: Clean shutdown
        let stopResult = await lifecycleManager.requestStop()
        XCTAssertTrue(stopResult.isSuccess)
        
        try await waitForState(.readyToStart, timeout: 10)
        
        // Verify cleanup
        let remainingProcesses = try await findKanataProcesses()
        XCTAssertEqual(remainingProcesses.count, 0, "Processes not cleaned up")
    }
    
    func testErrorRecoveryScenarios() async throws {
        let lifecycleManager = KanataLifecycleManager()
        await lifecycleManager.initialize()
        
        // Test 1: Invalid configuration recovery
        let configManager = KanataConfigManager(configPath: testEnvironment.configPath)
        let invalidConfig = "invalid kanata config"
        _ = await configManager.saveConfig(invalidConfig)
        
        let failedResult = await lifecycleManager.requestStart()
        XCTAssertFalse(failedResult.isSuccess)
        
        if case .failed(_, let recovery) = lifecycleManager.currentState {
            XCTAssertTrue(recovery.contains(.resetToDefault))
            
            let recoveryResult = await lifecycleManager.performRecovery(.resetToDefault)
            XCTAssertTrue(recoveryResult.isSuccess)
            
            try await waitForState(.readyToStart, timeout: 10)
        } else {
            XCTFail("Expected failed state")
        }
        
        // Test 2: Process crash recovery
        let startResult = await lifecycleManager.requestStart()
        XCTAssertTrue(startResult.isSuccess)
        
        try await waitForState(.running, timeout: 10)
        
        if case .running(let process) = lifecycleManager.currentState {
            // Simulate process crash
            try await terminateProcess(pid: process.pid)
            
            // Manager should detect crash and transition to failed state
            try await waitForState(.failed, timeout: 10)
            
            // Should be able to restart
            let restartResult = await lifecycleManager.requestStart()
            XCTAssertTrue(restartResult.isSuccess)
        }
    }
    
    func testConcurrentOperationHandling() async throws {
        let lifecycleManager = KanataLifecycleManager()
        await lifecycleManager.initialize()
        try await waitForState(.readyToStart, timeout: 30)
        
        // Launch multiple concurrent start requests
        let results = await withTaskGroup(of: ActionResult.self) { group in
            for i in 0..<5 {
                group.addTask {
                    return await lifecycleManager.requestStart()
                }
            }
            
            var results: [ActionResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // Only one should succeed
        let successCount = results.filter { $0.isSuccess }.count
        XCTAssertEqual(successCount, 1, "Multiple concurrent starts succeeded")
        
        // Should have exactly one process
        let processes = try await findKanataProcesses()
        XCTAssertEqual(processes.count, 1, "Wrong number of processes")
    }
}
```

### Performance Testing Framework

```swift
class PerformanceTests: XCTestCase {
    func testStartupPerformance() throws {
        measure {
            let lifecycleManager = KanataLifecycleManager()
            
            let expectation = XCTestExpectation(description: "Startup completed")
            
            Task {
                await lifecycleManager.initialize()
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 2.0) // Should complete within 2 seconds
        }
    }
    
    func testMemoryUsage() async throws {
        let initialMemory = getMemoryUsage()
        
        let lifecycleManager = KanataLifecycleManager()
        await lifecycleManager.initialize()
        
        // Run through complete cycle multiple times
        for _ in 0..<10 {
            _ = await lifecycleManager.requestStart()
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            _ = await lifecycleManager.requestStop()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory increase should be minimal (< 10MB)
        XCTAssertLessThan(memoryIncrease, 10 * 1024 * 1024, "Memory leak detected")
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}
```

---

## Migration Timeline

### Week 1: Foundation (Days 1-5)
- **Days 1-2**: Phase 1 - Immediate stabilization
- **Days 3-5**: Phase 2 - State machine foundation

### Week 2: UI Transformation (Days 6-10)
- **Days 6-8**: Phase 3 - Wizard redesign  
- **Days 9-10**: Integration and testing

### Week 3: Architecture Completion (Days 11-15)
- **Days 11-13**: Phase 4 - System requirements separation
- **Days 14-15**: Configuration management completion

### Week 4: Polish and Launch (Days 16-20)
- **Days 16-18**: Phase 5 - Comprehensive testing and polish
- **Days 19-20**: Documentation, deployment preparation

### Risk Mitigation

- **Daily Testing**: Each phase includes immediate testing
- **Rollback Plan**: Each phase can be independently reverted
- **Feature Flags**: New components can be disabled if issues arise
- **Gradual Migration**: Existing functionality preserved throughout

---

## Success Metrics

### Technical Metrics
- [ ] Zero multiple instance creation during normal operation  
- [ ] <2 second average app startup time
- [ ] >95% unit test coverage
- [ ] >90% integration test coverage
- [ ] Zero memory leaks in 24-hour stress test
- [ ] All state transitions logged with correlation IDs

### User Experience Metrics
- [ ] <30 second average setup time for new users
- [ ] <3 clicks required for common operations
- [ ] Clear error messages with actionable recovery steps
- [ ] No automatic actions without explicit user consent
- [ ] Wizard can be dismissed when safe to do so

### Maintainability Metrics
- [ ] New features can be added without touching existing state machine
- [ ] Bug reproduction time reduced by >50% due to logging
- [ ] Component coupling reduced (measured by dependency graph)
- [ ] Code complexity scores within acceptable ranges

---

## Milestone Definitions & Acceptance Criteria

### Milestone 1: Immediate Stabilization (Days 1-2)

**Objective**: Stop multiple Kanata instances from being created

**Deliverables**:
- [ ] Process synchronization lock implemented in KanataManager
- [ ] Wizard auto-kill logic removed and replaced with user confirmation
- [ ] ContentView debouncing prevents rapid requirement checks
- [ ] Unit tests for all synchronization mechanisms
- [ ] Integration test verifying single instance behavior

**Acceptance Criteria**:
- [ ] **Zero Multiple Instances**: App launch never creates more than 1 Kanata process
- [ ] **Startup Time**: App startup completes within 3 seconds on average
- [ ] **Wizard Behavior**: Wizard presents conflicts but doesn't auto-resolve them
- [ ] **Test Coverage**: >90% unit test coverage for changed components
- [ ] **Integration Test**: Full app launch test passes consistently
- [ ] **Regression Testing**: All existing functionality preserved
- [ ] **Logging**: All startup events logged with correlation IDs

**Testing Requirements**:
```swift
// Required test cases
func testNoMultipleInstancesOnStartup() // MUST PASS
func testWizardDoesNotAutoKill() // MUST PASS  
func testContentViewDebouncing() // MUST PASS
func testStartupLockPreventsRaceConditions() // MUST PASS
```

**Success Metrics**:
- 0 instances of multiple Kanata processes in 100 test runs
- <3 second average startup time
- User can dismiss conflicts instead of auto-termination

---

### Milestone 2: State Machine Foundation (Days 3-6)

**Objective**: Centralized state management with predictable transitions

**Deliverables**:
- [ ] LifecycleStateMachine with validation rules implemented
- [ ] KanataLifecycleManager coordinating all user actions
- [ ] ContentView and existing components updated to use state machine
- [ ] Comprehensive state transition logging
- [ ] Complete unit test suite for state machine

**Acceptance Criteria**:
- [ ] **State Validation**: Invalid state transitions are blocked and logged
- [ ] **Centralized Control**: All Kanata operations go through LifecycleManager
- [ ] **UI Reactivity**: UI updates automatically reflect state changes
- [ ] **Error Handling**: Failed operations transition to appropriate error states
- [ ] **Correlation Tracking**: All operations tracked with correlation IDs
- [ ] **Test Coverage**: >95% coverage for state machine components
- [ ] **Performance**: State transitions complete within 100ms

**Testing Requirements**:
```swift
// State machine tests
func testAllValidStateTransitions() // MUST PASS
func testInvalidTransitionsBlocked() // MUST PASS
func testStateTransitionLogging() // MUST PASS
func testCorrelationIdConsistency() // MUST PASS

// Integration tests
func testLifecycleManagerCoordination() // MUST PASS
func testUIReactivity() // MUST PASS
```

**Success Metrics**:
- 100% of invalid state transitions blocked
- All state changes logged with correlation IDs
- UI state always matches lifecycle manager state
- <100ms average state transition time

---

### Milestone 3: Reactive Wizard (Days 7-11)

**Objective**: Convert wizard to purely reactive UI with no automatic actions

**Deliverables**:
- [ ] Individual wizard pages for each lifecycle state
- [ ] Conflict resolution view with user choice options
- [ ] Requirements view with clear action buttons
- [ ] Main wizard coordinator with smooth transitions
- [ ] Complete wizard test suite including user interaction flows

**Acceptance Criteria**:
- [ ] **No Auto-Actions**: Wizard never performs actions without explicit user consent
- [ ] **Clear UI States**: Each lifecycle state has appropriate wizard page
- [ ] **User Control**: User can see all conflicts and choose resolution
- [ ] **Smooth Transitions**: Page transitions are animated and responsive
- [ ] **Dismissal Control**: Wizard can only be dismissed when safe
- [ ] **Error Recovery**: Failed actions show clear recovery options
- [ ] **Test Coverage**: >90% coverage for all wizard components

**Testing Requirements**:
```swift
// Wizard behavior tests
func testWizardShowsCorrectPageForState() // MUST PASS
func testNoAutomaticActions() // MUST PASS
func testUserCanChooseConflictResolution() // MUST PASS
func testCannotDismissDuringCriticalStates() // MUST PASS

// User interaction tests  
func testCompleteWizardFlow() // MUST PASS
func testErrorRecoveryInWizard() // MUST PASS
```

**Success Metrics**:
- 0 automatic actions taken by wizard in 100 test runs
- User can complete setup in <5 clicks for common scenarios
- All error states provide clear recovery paths
- Wizard dismissal blocked only when necessary

---

### Milestone 4: Modular System Components (Days 12-15)

**Objective**: Extract and modularize system requirements and configuration management

**Deliverables**:
- [ ] SystemRequirementsChecker with concurrent requirement checking
- [ ] KanataConfigManager with validation and backup functionality
- [ ] Error handling with specific recovery options
- [ ] Performance monitoring for all operations
- [ ] Comprehensive unit and integration tests

**Acceptance Criteria**:
- [ ] **Concurrent Checking**: All requirements checked in parallel within 2 seconds
- [ ] **Config Validation**: Generated configs validated against Kanata binary
- [ ] **Automatic Backups**: Config backups created before any changes
- [ ] **Error Recovery**: Specific recovery options for each error type
- [ ] **Performance Monitoring**: Slow operations (>1s) automatically logged
- [ ] **Test Coverage**: >95% coverage for all new components
- [ ] **Integration**: Components work together seamlessly

**Testing Requirements**:
```swift
// Requirements checker tests
func testConcurrentRequirementChecking() // MUST PASS
func testRequirementCheckPerformance() // MUST PASS <2s
func testIndividualRequirementStates() // MUST PASS

// Config manager tests
func testConfigValidationWithKanata() // MUST PASS
func testAutomaticBackupCreation() // MUST PASS
func testErrorRecoveryOptions() // MUST PASS
```

**Success Metrics**:
- <2 second requirement checking time
- 100% config validation accuracy
- 0 data loss incidents (backups working)
- All error types have recovery options

---

### Milestone 5: Production Ready (Days 16-20)

**Objective**: Complete testing, logging, and production readiness

**Deliverables**:
- [ ] Comprehensive logging with structured format and correlation IDs
- [ ] Performance monitoring and alerting
- [ ] Debug report generation and log export
- [ ] Complete integration test suite covering all user journeys
- [ ] CI/CD pipeline with automated testing
- [ ] Performance benchmarks and monitoring

**Acceptance Criteria**:
- [ ] **Complete Logging**: All operations logged with context and correlation IDs
- [ ] **Debug Reports**: Users can generate and export diagnostic information
- [ ] **Performance Monitoring**: Automatic detection of slow operations
- [ ] **Integration Testing**: Complete user journeys tested end-to-end
- [ ] **CI/CD Pipeline**: All tests run automatically on code changes
- [ ] **Performance Benchmarks**: Startup <2s, memory usage <50MB
- [ ] **Zero Regressions**: No existing functionality broken

**Testing Requirements**:
```swift
// Complete system tests
func testCompleteUserJourney() // MUST PASS
func testAllErrorRecoveryScenarios() // MUST PASS
func testConcurrentOperationHandling() // MUST PASS
func testPerformanceBenchmarks() // MUST PASS
func testMemoryLeakDetection() // MUST PASS

// Logging and debugging tests
func testComprehensiveLogging() // MUST PASS
func testDebugReportGeneration() // MUST PASS
func testLogExportFunctionality() // MUST PASS
```

**Success Metrics**:
- 100% of operations logged with correlation IDs
- <2 second average startup time
- <50MB memory usage in steady state
- 0 memory leaks in 24-hour stress test
- >95% overall test coverage

---

## Quality Gates

Each milestone must pass these quality gates before proceeding:

### Code Quality Gates
- [ ] **Test Coverage**: >90% unit test coverage for changed components
- [ ] **Performance**: No operations slower than defined thresholds
- [ ] **Memory**: No memory leaks detected in automated testing
- [ ] **Logging**: All operations logged with structured format
- [ ] **Documentation**: All public APIs documented

### Functional Quality Gates
- [ ] **Core Functionality**: All existing features continue to work
- [ ] **Error Handling**: All error scenarios have recovery paths
- [ ] **User Experience**: No degradation in user experience
- [ ] **Edge Cases**: Common edge cases handled gracefully
- [ ] **Integration**: All components work together correctly

### Production Readiness Gates
- [ ] **Stability**: No crashes in 100 test runs
- [ ] **Performance**: Meets all performance benchmarks
- [ ] **Diagnostics**: Users can generate debug reports
- [ ] **Monitoring**: Automatic detection of issues
- [ ] **Recovery**: System can recover from all known failure modes

---

## Risk Mitigation

### Technical Risks

**Risk**: State machine complexity causes bugs
**Mitigation**: 
- Extensive unit testing of all state transitions
- Visual state diagram validation
- Gradual rollout with feature flags
- Rollback plan to previous simple state

**Risk**: Performance degradation from centralized state
**Mitigation**:
- Performance benchmarks for each milestone
- Async operations to prevent UI blocking
- Caching of expensive operations
- Profiling at each milestone

**Risk**: Integration issues between new components
**Mitigation**:
- Integration tests at each milestone
- Continuous integration pipeline
- Incremental integration approach
- Mock objects for isolated testing

### Process Risks

**Risk**: Timeline delays due to testing complexity
**Mitigation**:
- Parallel development and testing
- Automated test generation where possible
- Prioritized testing (critical paths first)
- Daily progress tracking

**Risk**: Regression in existing functionality
**Mitigation**:
- Comprehensive regression test suite
- Feature flags for new components
- Gradual migration approach
- Quick rollback procedures

## Final Implementation Checklist

### Pre-Implementation Setup
- [ ] Development environment configured with Swift 5.9+
- [ ] Testing frameworks and mock objects implemented
- [ ] CI/CD pipeline configured in GitHub Actions
- [ ] Performance monitoring tools integrated
- [ ] Documentation templates prepared

### Phase-by-Phase Deliverables

#### Phase 1: Immediate Stabilization
- [ ] Process synchronization lock in KanataManager
- [ ] Wizard auto-kill logic removed
- [ ] ContentView debouncing implemented
- [ ] Unit tests achieving >90% coverage
- [ ] Integration tests verifying single instance behavior

#### Phase 2: State Machine Foundation
- [ ] LifecycleStateMachine with transition validation
- [ ] KanataLifecycleManager coordinating all actions
- [ ] Updated UI components using state machine
- [ ] Comprehensive state transition logging
- [ ] >95% test coverage for state components

#### Phase 3: Reactive Wizard
- [ ] Individual wizard pages for each state
- [ ] User-controlled conflict resolution
- [ ] Smooth page transitions with animations
- [ ] Dismissal control based on safety
- [ ] Complete wizard test suite

#### Phase 4: Modular System Components
- [ ] SystemRequirementsChecker with concurrent checking
- [ ] KanataConfigManager with validation
- [ ] Automatic config backups
- [ ] Specific error recovery options
- [ ] Performance monitoring integration

#### Phase 5: Production Ready
- [ ] Comprehensive logging with correlation IDs
- [ ] Debug report generation
- [ ] Complete integration test coverage
- [ ] CI/CD pipeline with quality gates
- [ ] Performance benchmarks met

### Success Metrics Verification
- [ ] Zero multiple Kanata instances in 100 test runs
- [ ] App startup time < 2 seconds average
- [ ] Memory usage < 50MB in steady state
- [ ] >95% overall test coverage achieved
- [ ] All quality gates passing in CI/CD
- [ ] User setup time < 30 seconds for common scenarios

This comprehensive migration plan provides a systematic, test-driven approach to eliminating the multiple instance issue while building a robust, maintainable architecture with complete observability and production-ready quality assurance processes.
