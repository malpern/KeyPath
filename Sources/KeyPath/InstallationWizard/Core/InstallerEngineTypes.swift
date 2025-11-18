import Foundation
import KeyPathCore
import KeyPathWizardCore
import KeyPathPermissions

// MARK: - Install Intent

/// Declarative enum describing the desired installation action
public enum InstallIntent: Sendable, Equatable {
    /// Fresh installation (new system, first time setup)
    case install
    /// Fix broken/unhealthy services (services exist but not working)
    case repair
    /// Remove services (cleanup)
    case uninstall
    /// Detect without changes (dry-run, diagnostics)
    case inspectOnly
}

// MARK: - Requirement

/// Status of a requirement check
public enum RequirementStatus: Sendable, Equatable {
    /// Requirement is satisfied
    case met
    /// Requirement is not met but not blocking
    case missing
    /// Requirement is missing and blocks execution
    case blocked
}

/// Named precondition that must be satisfied
public struct Requirement: Sendable, Equatable {
    /// Human-readable name (e.g., "Admin privileges available")
    public let name: String
    /// Current state
    public let status: RequirementStatus
    
    public init(name: String, status: RequirementStatus) {
        self.name = name
        self.status = status
    }
}

// MARK: - System Context

/// Snapshot of detected system state
/// Consolidates data from SystemSnapshotAdapter, SystemRequirements, ServiceStatusEvaluator
public struct SystemContext: Sendable {
    /// Current permission status (Input Monitoring, Accessibility, Full Disk Access)
    public let permissions: PermissionOracle.Snapshot
    /// Status of all services (Kanata, VHID daemon, VHID manager)
    public let services: HealthStatus
    /// Any detected conflicts (root-owned processes, etc.)
    public let conflicts: ConflictStatus
    /// Installed components (Kanata binary, Karabiner driver, etc.)
    public let components: ComponentStatus
    /// Privileged helper installation status
    public let helper: HelperStatus
    /// macOS version, driver compatibility, etc.
    public let system: EngineSystemInfo
    /// When this snapshot was taken
    public let timestamp: Date
    
    public init(
        permissions: PermissionOracle.Snapshot,
        services: HealthStatus,
        conflicts: ConflictStatus,
        components: ComponentStatus,
        helper: HelperStatus,
        system: EngineSystemInfo,
        timestamp: Date
    ) {
        self.permissions = permissions
        self.services = services
        self.conflicts = conflicts
        self.components = components
        self.helper = helper
        self.system = system
        self.timestamp = timestamp
    }
}

/// System information (macOS version, driver compatibility, etc.)
public struct EngineSystemInfo: Sendable, Equatable {
    /// macOS version string
    public let macOSVersion: String
    /// Driver compatibility status
    public let driverCompatible: Bool
    
    public init(macOSVersion: String, driverCompatible: Bool) {
        self.macOSVersion = macOSVersion
        self.driverCompatible = driverCompatible
    }
}

// MARK: - Service Recipe

/// Type of operation a recipe performs
public enum RecipeType: Sendable, Equatable {
    /// Install a LaunchDaemon service
    case installService
    /// Restart an existing service
    case restartService
    /// Install a component (Kanata binary, driver, etc.)
    case installComponent
    /// Write configuration file
    case writeConfig
    /// Validate a prerequisite
    case checkRequirement
}

/// Launchctl action to perform
public enum LaunchctlAction: Sendable, Equatable {
    /// Bootstrap a service
    case bootstrap(serviceID: String)
    /// Kickstart a service
    case kickstart(serviceID: String)
    /// Bootout a service
    case bootout(serviceID: String)
}

/// Criteria for verifying recipe success
public struct HealthCheckCriteria: Sendable, Equatable {
    /// Service ID to check
    public let serviceID: String
    /// Whether service should be running
    public let shouldBeRunning: Bool
    
    public init(serviceID: String, shouldBeRunning: Bool) {
        self.serviceID = serviceID
        self.shouldBeRunning = shouldBeRunning
    }
}

/// Minimal executable unit - specification for a single service operation
public struct ServiceRecipe: Sendable, Equatable {
    /// Unique identifier for this recipe
    public let id: String
    /// What kind of operation
    public let type: RecipeType
    /// Service identifier if applicable (e.g., "com.keypath.kanata")
    public let serviceID: String?
    /// Plist XML content if installing a service
    public let plistContent: String?
    /// Ordered list of launchctl commands
    public let launchctlActions: [LaunchctlAction]
    /// How to verify success
    public let healthCheck: HealthCheckCriteria?
    /// IDs of recipes that must complete first
    public let dependencies: [String]
    
    public init(
        id: String,
        type: RecipeType,
        serviceID: String? = nil,
        plistContent: String? = nil,
        launchctlActions: [LaunchctlAction] = [],
        healthCheck: HealthCheckCriteria? = nil,
        dependencies: [String] = []
    ) {
        self.id = id
        self.type = type
        self.serviceID = serviceID
        self.plistContent = plistContent
        self.launchctlActions = launchctlActions
        self.healthCheck = healthCheck
        self.dependencies = dependencies
    }
}

// MARK: - Install Plan

/// Current plan state
public enum PlanStatus: Sendable, Equatable {
    /// Plan is ready to execute
    case ready
    /// Plan cannot execute due to unmet requirement
    case blocked(requirement: Requirement)
}

/// Additional plan metadata
public struct PlanMetadata: Sendable, Equatable {
    /// Whether execution requires reboot
    public let needsReboot: Bool
    /// Whether user prompts are needed
    public let promptsNeeded: Bool
    
    public init(needsReboot: Bool = false, promptsNeeded: Bool = false) {
        self.needsReboot = needsReboot
        self.promptsNeeded = promptsNeeded
    }
}

/// Ordered collection of operations to execute
public struct InstallPlan: Sendable, Equatable {
    /// Ordered list of operations (respects dependencies)
    public let recipes: [ServiceRecipe]
    /// Current plan state
    public let status: PlanStatus
    /// Original intent that generated this plan
    public let intent: InstallIntent
    /// If blocked, which requirement failed
    public let blockedBy: Requirement?
    /// Additional info
    public let metadata: PlanMetadata
    
    public init(
        recipes: [ServiceRecipe],
        status: PlanStatus,
        intent: InstallIntent,
        blockedBy: Requirement? = nil,
        metadata: PlanMetadata = PlanMetadata()
    ) {
        self.recipes = recipes
        self.status = status
        self.intent = intent
        self.blockedBy = blockedBy
        self.metadata = metadata
    }
}

// MARK: - Installer Report

/// Result of executing a single recipe
public struct RecipeResult: Sendable, Equatable {
    /// Which recipe
    public let recipeID: String
    /// Did it succeed?
    public let success: Bool
    /// Error message if failed
    public let error: String?
    /// How long it took (seconds)
    public let duration: TimeInterval
    
    public init(recipeID: String, success: Bool, error: String? = nil, duration: TimeInterval = 0) {
        self.recipeID = recipeID
        self.success = success
        self.error = error
        self.duration = duration
    }
}

/// Comprehensive execution summary
/// Extends existing LaunchDaemonInstaller.InstallerReport
public struct InstallerReport: Sendable {
    /// When execution completed
    public let timestamp: Date
    /// Overall success/failure
    public let success: Bool
    /// Human-readable failure description
    public let failureReason: String?
    /// Requirements that blocked execution (if any)
    public let unmetRequirements: [Requirement]
    /// Results for each recipe executed
    public let executedRecipes: [RecipeResult]
    /// System state after execution (if available)
    public let finalContext: SystemContext?
    
    public init(
        timestamp: Date = Date(),
        success: Bool,
        failureReason: String? = nil,
        unmetRequirements: [Requirement] = [],
        executedRecipes: [RecipeResult] = [],
        finalContext: SystemContext? = nil
    ) {
        self.timestamp = timestamp
        self.success = success
        self.failureReason = failureReason
        self.unmetRequirements = unmetRequirements
        self.executedRecipes = executedRecipes
        self.finalContext = finalContext
    }
}

