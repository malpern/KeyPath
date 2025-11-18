import Foundation
import KeyPathCore
import KeyPathWizardCore
import KeyPathPermissions
import KeyPathDaemonLifecycle

/// Façade for installer operations
/// Provides a simple, unified API for installation, repair, and uninstallation
/// Wraps existing installer logic (LaunchDaemonInstaller, WizardAutoFixer, etc.)
@MainActor
public final class InstallerEngine {
    // MARK: - Dependencies

    /// System validator for detecting current system state
    private let systemValidator: SystemValidator

    /// System requirements checker for compatibility info
    private let systemRequirements: SystemRequirements

    /// Create a new installer engine
    /// No DI initially - calls singletons directly
    public init() {
        // Create ProcessLifecycleManager for SystemValidator
        let processManager = ProcessLifecycleManager()

        // Create SystemValidator (stateless, can be reused)
        self.systemValidator = SystemValidator(processLifecycleManager: processManager)

        // Create SystemRequirements instance
        self.systemRequirements = SystemRequirements()

        AppLogger.shared.log("🔧 [InstallerEngine] Initialized")
    }

    // MARK: - Public API

    /// Capture current system state
    /// Returns: Read-only snapshot of service states, file/permission status, and helper availability
    public func inspectSystem() async -> SystemContext {
        AppLogger.shared.log("🔍 [InstallerEngine] Starting inspectSystem()")

        // Phase 2: Wire up SystemValidator to get system snapshot
        let snapshot = await systemValidator.checkSystem()

        // Get system compatibility info from SystemRequirements
        let systemInfo = systemRequirements.getSystemInfo()

        // Convert SystemInfo to EngineSystemInfo
        let engineSystemInfo = EngineSystemInfo(
            macOSVersion: systemInfo.macosVersion.versionString,
            driverCompatible: systemInfo.compatibilityResult.isCompatible
        )

        // Convert SystemSnapshot to SystemContext
        let context = SystemContext(
            permissions: snapshot.permissions,
            services: snapshot.health,
            conflicts: snapshot.conflicts,
            components: snapshot.components,
            helper: snapshot.helper,
            system: engineSystemInfo,
            timestamp: snapshot.timestamp
        )

        AppLogger.shared.log("✅ [InstallerEngine] inspectSystem() complete - ready=\(snapshot.isReady), blocking=\(snapshot.blockingIssues.count)")
        return context
    }

    /// Create an execution plan without running it
    /// Returns: Ordered list of operations tailored to the observed context.
    /// If prerequisites are unmet, the plan will be marked as `.blocked` with details about missing requirements.
    public func makePlan(for intent: InstallIntent, context: SystemContext) async -> InstallPlan {
        AppLogger.shared.log("📋 [InstallerEngine] Starting makePlan(for: \(intent), context:)")

        // TODO: Phase 3 - Wire up WizardAutoFixer, LaunchDaemonInstaller, etc.
        // For now, return a minimal stub plan
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: intent,
            blockedBy: nil,
            metadata: PlanMetadata()
        )

        AppLogger.shared.log("✅ [InstallerEngine] makePlan() complete - status: \(plan.status)")
        return plan
    }

    /// Execute the planned operations
    /// Returns: Structured report with success/failure details and final state.
    /// If the plan was blocked by unmet requirements, execution stops immediately and the report indicates which requirement failed.
    public func execute(plan: InstallPlan, using broker: PrivilegeBroker) async -> InstallerReport {
        AppLogger.shared.log("⚙️ [InstallerEngine] Starting execute(plan:, using:)")

        // Check if plan is blocked
        if case .blocked(let requirement) = plan.status {
            AppLogger.shared.log("⚠️ [InstallerEngine] Plan is blocked by requirement: \(requirement.name)")
            return InstallerReport(
                success: false,
                failureReason: "Plan blocked by requirement: \(requirement.name)",
                unmetRequirements: [requirement],
                executedRecipes: []
            )
        }

        // TODO: Phase 4 - Wire up PrivilegedOperationsCoordinator, execute recipes
        // For now, return a stub report
        let report = InstallerReport(
            success: true,
            failureReason: nil,
            unmetRequirements: [],
            executedRecipes: []
        )

        AppLogger.shared.log("✅ [InstallerEngine] execute() complete - success: \(report.success)")
        return report
    }

    /// Convenience wrapper that chains inspectSystem() → makePlan() → execute() internally
    /// Useful for CLI "one-button repair" automation or simple GUI flows
    public func run(intent: InstallIntent, using broker: PrivilegeBroker) async -> InstallerReport {
        AppLogger.shared.log("🚀 [InstallerEngine] Starting run(intent: \(intent), using:)")

        // Chain the steps
        let context = await inspectSystem()
        let plan = await makePlan(for: intent, context: context)
        let report = await execute(plan: plan, using: broker)

        AppLogger.shared.log("✅ [InstallerEngine] run() complete - success: \(report.success)")
        return report
    }
}


