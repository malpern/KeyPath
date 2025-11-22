# Type Contracts

**Status:** ✅ DEFINED - Required fields/properties for each type

**Date Defined:** 2025-11-17

---

## SystemContext

**Purpose:** Snapshot of detected system state

**Required Fields:**
- `permissions: PermissionState` - Current permission status (Input Monitoring, Accessibility, Full Disk Access)
- `services: ServiceStatus` - Status of all services (Kanata, VHID daemon, VHID manager)
- `conflicts: ConflictState` - Any detected conflicts (root-owned processes, etc.)
- `components: ComponentState` - Installed components (Kanata binary, Karabiner driver, etc.)
- `helper: HelperState` - Privileged helper installation status
- `system: SystemInfo` - macOS version, driver compatibility, etc.
- `timestamp: Date` - When this snapshot was taken

**Note:** Watch for god-struct during implementation. Consider splitting into sub-views (ServiceContext, PermissionsContext) if needed.

**Source:** Consolidates data from `SystemSnapshotAdapter`, `SystemRequirements`, `ServiceStatusEvaluator`

---

## InstallIntent

**Purpose:** Declarative enum describing the desired action

**Enum Cases:**
- `.install` - Fresh installation (new system, first time setup)
- `.repair` - Fix broken/unhealthy services (services exist but not working)
- `.uninstall` - Remove services (cleanup)
- `.inspectOnly` - Detect without changes (dry-run, diagnostics)

**Source:** Maps to existing wizard flows and AutoFix actions

---

## Requirement

**Purpose:** Named precondition that must be satisfied

**Required Fields:**
- `name: String` - Human-readable name (e.g., "Admin privileges available")
- `status: RequirementStatus` - Current state (see below)

**RequirementStatus Enum:**
- `.met` - Requirement is satisfied
- `.missing` - Requirement is not met but not blocking
- `.blocked` - Requirement is missing and blocks execution

**Examples:**
- "Writable LaunchDaemons directory"
- "Helper registered"
- "Admin privileges available"
- "SMAppService approved"

---

## ServiceRecipe

**Purpose:** Minimal executable unit - specification for a single service operation

**Required Fields:**
- `id: String` - Unique identifier for this recipe
- `type: RecipeType` - What kind of operation (see below)
- `serviceID: String?` - Service identifier if applicable (e.g., "com.keypath.kanata")
- `plistContent: String?` - Plist XML content if installing a service
- `launchctlActions: [LaunchctlAction]` - Ordered list of launchctl commands
- `healthCheck: HealthCheckCriteria?` - How to verify success
- `dependencies: [String]` - IDs of recipes that must complete first

**RecipeType Enum:**
- `.installService` - Install a LaunchDaemon service
- `.restartService` - Restart an existing service
- `.installComponent` - Install a component (Kanata binary, driver, etc.)
- `.writeConfig` - Write configuration file
- `.checkRequirement` - Validate a prerequisite

**Source:** Captures logic from `LaunchDaemonInstaller.create...Service` methods

---

## InstallPlan

**Purpose:** Ordered collection of operations to execute

**Required Fields:**
- `recipes: [ServiceRecipe]` - Ordered list of operations (respects dependencies)
- `status: PlanStatus` - Current plan state (see below)
- `intent: InstallIntent` - Original intent that generated this plan
- `blockedBy: Requirement?` - If blocked, which requirement failed
- `metadata: PlanMetadata` - Additional info (needs reboot, prompts needed, etc.)

**PlanStatus Enum:**
- `.ready` - Plan is ready to execute
- `.blocked(requirement: Requirement)` - Plan cannot execute due to unmet requirement

**Source:** Effectively a serialized version of what `LaunchDaemonInstaller` + `WizardAutoFixer` already orchestrate

---

## PrivilegeBroker

**Purpose:** Strategy object for executing privileged commands

**Initial Implementation:** Concrete struct wrapping `PrivilegedOperationsCoordinator.shared`

**Required Methods (to be defined):**
- `executePrivilegedCommand(_ command: String) async throws -> CommandResult`
- `installLaunchDaemon(plistPath: String, serviceID: String) async throws`
- `bootstrapService(serviceID: String) async throws`
- `kickstartService(serviceID: String) async throws`

**Note:** Start with concrete type. Add protocol if we need test doubles later.

**Source:** Wraps `PrivilegedOperationsCoordinator`, `HelperManager`, Authorization Services fallbacks

---

## InstallerReport

**Purpose:** Comprehensive execution summary

**Required Fields:**
- `timestamp: Date` - When execution completed
- `success: Bool` - Overall success/failure
- `failureReason: String?` - Human-readable failure description
- `unmetRequirements: [Requirement]` - Requirements that blocked execution (if any)
- `executedRecipes: [RecipeResult]` - Results for each recipe executed
- `finalContext: SystemContext?` - System state after execution (if available)

**RecipeResult:**
- `recipeID: String` - Which recipe
- `success: Bool` - Did it succeed?
- `error: String?` - Error message if failed
- `duration: TimeInterval` - How long it took

**Source:** Extends existing `LaunchDaemonInstaller.InstallerReport` struct:
```swift
// Existing:
struct InstallerReport: Sendable {
    let timestamp: Date
    let success: Bool
    let failureReason: String?
}

// We'll extend with:
// - unmetRequirements
// - executedRecipes
// - finalContext
```

---

## Notes

- All types should be `Sendable` for async/await safety
- Use structs (value types) where possible for immutability
- Enums should be exhaustive (no default cases that hide errors)
- Optional fields should be truly optional (not "sometimes nil")

