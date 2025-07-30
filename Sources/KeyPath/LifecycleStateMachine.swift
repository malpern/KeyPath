import Foundation

/// Phase 2: Centralized State Machine for Kanata Lifecycle Management
/// 
/// This state machine provides predictable state transitions and eliminates race conditions
/// by ensuring only valid state transitions can occur. All Kanata lifecycle operations
/// must go through this state machine.
@MainActor
class LifecycleStateMachine: ObservableObject {
    
    // MARK: - State Definition
    
    /// Comprehensive state enumeration covering all possible Kanata states
    enum KanataState: String, CaseIterable, Equatable {
        case uninitialized = "uninitialized"
        case initializing = "initializing"
        case requirementsCheck = "requirements_check"
        case requirementsFailed = "requirements_failed"
        case installing = "installing"
        case installationFailed = "installation_failed"
        case starting = "starting"
        case running = "running"
        case stopping = "stopping"
        case stopped = "stopped"
        case restarting = "restarting"
        case error = "error"
        case configuring = "configuring"
        case configurationError = "configuration_error"
        
        /// Human-readable description for UI display
        var displayName: String {
            switch self {
            case .uninitialized: return "Not Started"
            case .initializing: return "Initializing..."
            case .requirementsCheck: return "Checking Requirements"
            case .requirementsFailed: return "Requirements Failed"
            case .installing: return "Installing..."
            case .installationFailed: return "Installation Failed"
            case .starting: return "Starting..."
            case .running: return "Running"
            case .stopping: return "Stopping..."
            case .stopped: return "Stopped"
            case .restarting: return "Restarting..."
            case .error: return "Error"
            case .configuring: return "Configuring..."
            case .configurationError: return "Configuration Error"
            }
        }
        
        /// Whether this state indicates Kanata is operational
        var isOperational: Bool {
            switch self {
            case .running: return true
            default: return false
            }
        }
        
        /// Whether this state indicates an error condition
        var isError: Bool {
            switch self {
            case .requirementsFailed, .installationFailed, .error, .configurationError:
                return true
            default:
                return false
            }
        }
        
        /// Whether this state indicates a transitional operation in progress
        var isTransitioning: Bool {
            switch self {
            case .initializing, .requirementsCheck, .installing, .starting, .stopping, .restarting, .configuring:
                return true
            default:
                return false
            }
        }
        
        /// Whether the user can initiate actions from this state
        var allowsUserActions: Bool {
            return !isTransitioning
        }
    }
    
    // MARK: - Events
    
    /// Events that can trigger state transitions
    enum LifecycleEvent: String, CaseIterable {
        case initialize = "initialize"
        case checkRequirements = "check_requirements"
        case requirementsPassed = "requirements_passed"
        case requirementsFailed = "requirements_failed"
        case startInstallation = "start_installation"
        case installationCompleted = "installation_completed"
        case installationFailed = "installation_failed"
        case startKanata = "start_kanata"
        case kanataStarted = "kanata_started"
        case kanataFailed = "kanata_failed"
        case stopKanata = "stop_kanata"
        case kanataStopped = "kanata_stopped"
        case restartKanata = "restart_kanata"
        case configurationChanged = "configuration_changed"
        case configurationApplied = "configuration_applied"
        case configurationFailed = "configuration_failed"
        case errorOccurred = "error_occurred"
        case reset = "reset"
    }
    
    // MARK: - State Machine Properties
    
    @Published private(set) var currentState: KanataState = .uninitialized
    @Published private(set) var lastEvent: LifecycleEvent?
    @Published private(set) var lastTransition: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var stateContext: [String: Any] = [:]
    
    // MARK: - State Machine Logic
    
    /// Valid state transitions defined as [currentState: [event: nextState]]
    private let stateTransitions: [KanataState: [LifecycleEvent: KanataState]] = [
        .uninitialized: [
            .initialize: .initializing
        ],
        
        .initializing: [
            .checkRequirements: .requirementsCheck,
            .errorOccurred: .error
        ],
        
        .requirementsCheck: [
            .requirementsPassed: .stopped,
            .requirementsFailed: .requirementsFailed,
            .errorOccurred: .error
        ],
        
        .requirementsFailed: [
            .startInstallation: .installing,
            .reset: .uninitialized
        ],
        
        .installing: [
            .installationCompleted: .stopped,
            .installationFailed: .installationFailed,
            .errorOccurred: .error
        ],
        
        .installationFailed: [
            .startInstallation: .installing,
            .reset: .uninitialized
        ],
        
        .stopped: [
            .startKanata: .starting,
            .configurationChanged: .configuring,
            .reset: .uninitialized
        ],
        
        .starting: [
            .kanataStarted: .running,
            .kanataFailed: .error,
            .errorOccurred: .error
        ],
        
        .running: [
            .stopKanata: .stopping,
            .restartKanata: .restarting,
            .configurationChanged: .configuring,
            .kanataFailed: .error,
            .errorOccurred: .error
        ],
        
        .stopping: [
            .kanataStopped: .stopped,
            .errorOccurred: .error
        ],
        
        .restarting: [
            .kanataStopped: .starting,
            .kanataStarted: .running,
            .errorOccurred: .error
        ],
        
        .configuring: [
            .configurationApplied: .running,
            .configurationFailed: .configurationError,
            .errorOccurred: .error
        ],
        
        .configurationError: [
            .configurationChanged: .configuring,
            .reset: .uninitialized
        ],
        
        .error: [
            .reset: .uninitialized,
            .startKanata: .starting,
            .stopKanata: .stopping
        ]
    ]
    
    // MARK: - Public Interface
    
    /// Send an event to trigger a state transition
    /// - Parameters:
    ///   - event: The event to process
    ///   - context: Additional context data for the transition
    /// - Returns: True if the transition was successful, false if invalid
    func sendEvent(_ event: LifecycleEvent, context: [String: Any] = [:]) -> Bool {
        let correlationId = UUID().uuidString.prefix(8)
        
        AppLogger.shared.log("🔄 [StateMachine-\(correlationId)] Event: \(event.rawValue) in state: \(currentState.rawValue)")
        
        // Check if transition is valid
        guard let validTransitions = stateTransitions[currentState],
              let nextState = validTransitions[event] else {
            AppLogger.shared.log("❌ [StateMachine-\(correlationId)] Invalid transition: \(event.rawValue) from \(currentState.rawValue)")
            return false
        }
        
        // Update state and metadata
        let previousState = currentState
        currentState = nextState
        lastEvent = event
        lastTransition = Date()
        
        // Merge context
        stateContext.merge(context) { _, new in new }
        
        // Clear error message on successful transitions (except to error states)
        if !nextState.isError {
            errorMessage = nil
        }
        
        AppLogger.shared.log("✅ [StateMachine-\(correlationId)] Transition: \(previousState.rawValue) → \(nextState.rawValue)")
        
        // Emit state change notification
        objectWillChange.send()
        
        return true
    }
    
    /// Set an error message and transition to error state
    func setError(_ message: String) {
        errorMessage = message
        _ = sendEvent(.errorOccurred, context: ["error": message])
    }
    
    /// Check if a specific event is valid from the current state
    func canSendEvent(_ event: LifecycleEvent) -> Bool {
        return stateTransitions[currentState]?[event] != nil
    }
    
    /// Get all valid events from the current state
    func validEvents() -> [LifecycleEvent] {
        guard let transitions = stateTransitions[currentState] else { return [] }
        return Array(transitions.keys)
    }
    
    /// Reset to initial state
    func reset() {
        AppLogger.shared.log("🔄 [StateMachine] Resetting to uninitialized state")
        currentState = .uninitialized
        lastEvent = nil
        lastTransition = nil
        errorMessage = nil
        stateContext.removeAll()
        objectWillChange.send()
    }
    
    /// Get current state information for debugging/monitoring
    func getStateInfo() -> [String: Any] {
        var info: [String: Any] = [
            "currentState": currentState.rawValue,
            "displayName": currentState.displayName,
            "isOperational": currentState.isOperational,
            "isError": currentState.isError,
            "isTransitioning": currentState.isTransitioning,
            "allowsUserActions": currentState.allowsUserActions
        ]
        
        if let lastEvent = lastEvent {
            info["lastEvent"] = lastEvent.rawValue
        }
        
        if let lastTransition = lastTransition {
            info["lastTransition"] = lastTransition.timeIntervalSince1970
        }
        
        if let errorMessage = errorMessage {
            info["errorMessage"] = errorMessage
        }
        
        info["validEvents"] = validEvents().map(\.rawValue)
        info["context"] = stateContext
        
        return info
    }
}

// MARK: - Convenience Properties

extension LifecycleStateMachine {
    
    /// Whether Kanata is currently running and operational
    var isRunning: Bool {
        return currentState.isOperational
    }
    
    /// Whether the system is currently in an error state
    var hasError: Bool {
        return currentState.isError
    }
    
    /// Whether the system is currently performing an operation
    var isBusy: Bool {
        return currentState.isTransitioning
    }
    
    /// Whether user can perform actions
    var canPerformActions: Bool {
        return currentState.allowsUserActions
    }
    
    /// Current state display string for UI
    var stateDisplay: String {
        return currentState.displayName
    }
}

// MARK: - Debug Support

extension LifecycleStateMachine {
    
    /// Generate a state transition diagram for debugging
    func generateTransitionDiagram() -> String {
        var diagram = "# Kanata Lifecycle State Machine\n\n"
        
        for (fromState, transitions) in stateTransitions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            diagram += "## \(fromState.rawValue) (\(fromState.displayName))\n"
            
            for (event, toState) in transitions.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                diagram += "- \(event.rawValue) → \(toState.rawValue)\n"
            }
            
            diagram += "\n"
        }
        
        return diagram
    }
    
    /// Validate the state machine configuration
    func validateStateMachine() -> [String] {
        var issues: [String] = []
        
        // Check that all states have at least one valid transition
        let allStates = Set(KanataState.allCases)
        let reachableStates = Set(stateTransitions.keys)
        
        for state in allStates {
            if !reachableStates.contains(state) && state != .uninitialized {
                issues.append("State \(state.rawValue) has no outgoing transitions")
            }
        }
        
        // Check for unreachable states
        let targetStates = Set(stateTransitions.values.flatMap { $0.values })
        for state in allStates {
            if !targetStates.contains(state) && state != .uninitialized {
                issues.append("State \(state.rawValue) is not reachable from any other state")
            }
        }
        
        return issues
    }
}