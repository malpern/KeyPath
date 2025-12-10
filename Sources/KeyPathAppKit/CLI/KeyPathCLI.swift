import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

@MainActor
public protocol InstallerEngineProtocol: AnyObject {
    func inspectSystem() async -> SystemContext
    func makePlan(for intent: InstallIntent, context: SystemContext) async -> InstallPlan
    func run(intent: InstallIntent, using broker: PrivilegeBroker) async -> InstallerReport
    func uninstall(deleteConfig: Bool, using broker: PrivilegeBroker) async -> InstallerReport
}

extension InstallerEngine: InstallerEngineProtocol {}

/// CLI handler for KeyPath command-line operations
@MainActor
public struct KeyPathCLI {
    private let installerEngine: InstallerEngineProtocol
    private let privilegeBrokerFactory: () -> PrivilegeBroker

    public init(
        installerEngine: InstallerEngineProtocol = InstallerEngine(),
        privilegeBrokerFactory: (() -> PrivilegeBroker)? = nil
    ) {
        self.installerEngine = installerEngine
        if let privilegeBrokerFactory {
            self.privilegeBrokerFactory = privilegeBrokerFactory
        } else {
            self.privilegeBrokerFactory = { PrivilegeBroker() }
        }
    }

    /// Run CLI command based on arguments
    public func run(arguments: [String]) async -> Int32 {
        guard arguments.count > 1 else {
            printUsage()
            return 1
        }

        let command = arguments[1]

        switch command {
        case "status":
            return await runStatus()
        case "install":
            return await runInstall()
        case "repair":
            return await runRepair()
        case "uninstall":
            let deleteConfig = arguments.contains("--delete-config")
            return await runUninstall(deleteConfig: deleteConfig)
        case "inspect":
            return await runInspect()
        case "help", "--help", "-h":
            printUsage()
            return 0
        default:
            print("Error: Unknown command '\(command)'")
            printUsage()
            return 1
        }
    }

    /// Print usage information
    private func printUsage() {
        print(
            """
            KeyPath CLI - Command-line interface for KeyPath

            Usage: keypath-cli <command> [options]

            Commands:
              status      Check system status and wizard readiness
              install     Install KeyPath services and components
              repair      Repair broken or unhealthy services
              uninstall   Remove KeyPath services and components
              inspect     Inspect system state without making changes
              help        Show this help message

            Options:
              --delete-config    (uninstall only) Delete user configuration files

            Examples:
              keypath-cli status
              keypath-cli install
              keypath-cli repair
              keypath-cli uninstall
              keypath-cli uninstall --delete-config
              keypath-cli inspect
            """)
    }

    /// Run status command
    private func runStatus() async -> Int32 {
        print("Checking system status...")

        let context = await installerEngine.inspectSystem()

        print("\n=== System Status ===")
        print("Timestamp: \(formatDate(context.timestamp))")
        print("System Ready: \(context.isOperational ? "✅ Yes" : "❌ No")")

        // Helper status
        print("\n--- Helper ---")
        print("Installed: \(context.helper.isInstalled ? "✅" : "❌")")
        print("Working: \(context.helper.isWorking ? "✅" : "❌")")
        if let version = context.helper.version {
            print("Version: \(version)")
        }

        // Permissions
        // NOTE: Kanata doesn't need TCC permissions - it uses the Karabiner driver
        print("\n--- Permissions ---")
        print("KeyPath:")
        print("  Accessibility: \(context.permissions.keyPath.accessibility.isReady ? "✅" : "❌")")
        print("  Input Monitoring: \(context.permissions.keyPath.inputMonitoring.isReady ? "✅" : "❌")")
        print("Kanata:")
        print("  (Uses Karabiner driver - no TCC permissions needed) ✅")

        // Components
        print("\n--- Components ---")
        print(
            "Kanata Binary: \(context.components.kanataBinaryInstalled ? "✅ Installed" : "❌ Missing")")
        print(
            "Karabiner Driver: \(context.components.karabinerDriverInstalled ? "✅ Installed" : "❌ Missing")"
        )
        print("VHID Device: \(context.components.vhidDeviceHealthy ? "✅ Healthy" : "❌ Unhealthy")")
        if context.components.vhidVersionMismatch {
            print("⚠️  VHID Version Mismatch detected")
        }

        // Services
        print("\n--- Services ---")
        print("Kanata Running: \(context.services.kanataRunning ? "✅" : "❌")")
        print("Karabiner Daemon: \(context.services.karabinerDaemonRunning ? "✅" : "❌")")
        print("VHID Healthy: \(context.services.vhidHealthy ? "✅" : "❌")")

        // Conflicts
        if context.conflicts.hasConflicts {
            print("\n--- Conflicts ---")
            for conflict in context.conflicts.conflicts {
                print("⚠️  \(formatConflict(conflict))")
            }
        }

        // Issues
        printIssuesIfNeeded(for: context)

        print("\n=== Summary ===")
        if context.isOperational {
            print("✅ System is ready and operational")
            return 0
        } else {
            print("❌ System has blocking issue(s)")
            print("   Run 'keypath-cli repair' to attempt automatic fixes")
            return 1
        }
    }

    /// Run install command
    private func runInstall() async -> Int32 {
        print("Starting installation...")

        let broker = privilegeBrokerFactory()
        let report = await installerEngine.run(intent: .install, using: broker)

        print("\n=== Installation Report ===")
        print("Success: \(report.success ? "✅ Yes" : "❌ No")")
        print("Timestamp: \(formatDate(report.timestamp))")

        if let failureReason = report.failureReason {
            print("Failure Reason: \(failureReason)")
        }

        if !report.unmetRequirements.isEmpty {
            print("\nUnmet Requirements:")
            for req in report.unmetRequirements {
                print("  - \(req.name) (\(req.status))")
            }
        }

        if !report.executedRecipes.isEmpty {
            print("\nExecuted Recipes:")
            for recipe in report.executedRecipes {
                let status = recipe.success ? "✅" : "❌"
                let duration = String(format: "%.2f", recipe.duration)
                print("  \(status) \(recipe.recipeID) (\(duration)s)")
                if let error = recipe.error {
                    print("     Error: \(error)")
                }
            }
        }

        if report.success {
            print("\n✅ Installation completed successfully")
            return 0
        } else {
            print("\n❌ Installation failed")
            return 1
        }
    }

    /// Run repair command
    private func runRepair() async -> Int32 {
        print("Starting repair...")

        if await attemptFastRepair() {
            print("\n✅ Repair completed via KanataService restart")
            return 0
        }

        let broker = privilegeBrokerFactory()
        let report = await installerEngine.run(intent: .repair, using: broker)

        print("\n=== Repair Report ===")
        print("Success: \(report.success ? "✅ Yes" : "❌ No")")
        print("Timestamp: \(formatDate(report.timestamp))")

        if let failureReason = report.failureReason {
            print("Failure Reason: \(failureReason)")
        }

        if !report.unmetRequirements.isEmpty {
            print("\nUnmet Requirements:")
            for req in report.unmetRequirements {
                print("  - \(req.name) (\(req.status))")
            }
        }

        if !report.executedRecipes.isEmpty {
            print("\nExecuted Recipes:")
            for recipe in report.executedRecipes {
                let status = recipe.success ? "✅" : "❌"
                let duration = String(format: "%.2f", recipe.duration)
                print("  \(status) \(recipe.recipeID) (\(duration)s)")
                if let error = recipe.error {
                    print("     Error: \(error)")
                }
            }
        }

        if report.success {
            print("\n✅ Repair completed successfully")
            return 0
        } else {
            print("\n❌ Repair failed")
            return 1
        }
    }

    private func attemptFastRepair() async -> Bool {
        print("Attempting KanataService restart before full repair...")
        let coordinator = ProcessCoordinator()
        let restarted = await coordinator.restartService()

        guard restarted else {
            print("Fast-path restart failed; continuing with InstallerEngine repair.")
            return false
        }

        let context = await installerEngine.inspectSystem()
        if context.isOperational {
            print("Kanata service healthy after restart; skipping InstallerEngine repair.")
            return true
        } else {
            print("System still has issues after restart; running full repair.")
            return false
        }
    }

    /// Run uninstall command
    private func runUninstall(deleteConfig: Bool) async -> Int32 {
        print("Starting uninstall...")
        print(
            deleteConfig
                ? "⚠️  User configuration will be deleted" : "💾 User configuration will be preserved")
        print("")

        let broker = privilegeBrokerFactory()
        let report = await installerEngine.uninstall(deleteConfig: deleteConfig, using: broker)

        if !report.logs.isEmpty {
            print("--- Uninstall Log ---")
            report.logs.forEach { print($0) }
            print("")
        }

        if !report.executedRecipes.isEmpty {
            print("Executed Steps:")
            for recipe in report.executedRecipes {
                let status = recipe.success ? "✅" : "❌"
                let duration = String(format: "%.2f", recipe.duration)
                print("  \(status) \(recipe.recipeID) (\(duration)s)")
                if let error = recipe.error {
                    print("     Error: \(error)")
                }
            }
            print("")
        }

        if report.success {
            print("✅ Uninstall completed successfully")
            return 0
        } else {
            print("❌ Uninstall failed: \(report.failureReason ?? "Unknown error")")
            return 1
        }
    }

    /// Run inspect command (dry-run)
    private func runInspect() async -> Int32 {
        print("Inspecting system state...")

        let context = await installerEngine.inspectSystem()
        let plan = await installerEngine.makePlan(for: .inspectOnly, context: context)

        print("\n=== System Inspection ===")
        print("Timestamp: \(formatDate(context.timestamp))")

        print("\n--- System Info ---")
        print("macOS Version: \(context.system.macOSVersion)")
        print("Driver Compatible: \(context.system.driverCompatible ? "✅" : "❌")")

        print("\n--- Plan Status ---")
        switch plan.status {
        case .ready:
            print("Status: ✅ Ready to execute")
            print("Recipes: \(plan.recipes.count)")
            if !plan.recipes.isEmpty {
                print("\nPlanned Recipes:")
                for recipe in plan.recipes {
                    print("  - \(recipe.id) (\(recipe.type))")
                }
            }
        case let .blocked(requirement):
            print("Status: ❌ Blocked")
            print("Blocking Requirement: \(requirement.name) (\(requirement.status))")
        }

        print("\n=== Inspection Complete ===")
        print("No changes were made to the system")
        return 0
    }

    // MARK: - Helper Methods

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatConflict(_ conflict: SystemConflict) -> String {
        switch conflict {
        case let .kanataProcessRunning(pid, command):
            "Kanata process running (PID: \(pid), Command: \(command))"
        case let .karabinerGrabberRunning(pid):
            "Karabiner Grabber running (PID: \(pid))"
        case let .karabinerVirtualHIDDeviceRunning(pid, processName):
            "Karabiner VirtualHID Device running (PID: \(pid), Process: \(processName))"
        case let .karabinerVirtualHIDDaemonRunning(pid):
            "Karabiner VirtualHID Daemon running (PID: \(pid))"
        case let .exclusiveDeviceAccess(device):
            "Exclusive device access: \(device)"
        }
    }

    private func printIssuesIfNeeded(for context: SystemContext) {
        let issues = deriveIssues(from: context)
        guard !issues.isEmpty else { return }

        print("\n--- Issues ---")
        for issue in issues {
            print("\(issue.canAutoFix ? "🔧" : "⚠️")  \(issue.title)")
            if let action = issue.action {
                print("   Action: \(action)")
            }
        }
    }

    private func deriveIssues(from context: SystemContext) -> [ContextIssue] {
        var issues: [ContextIssue] = []

        if !context.permissions.keyPath.hasAllPermissions {
            issues.append(
                ContextIssue(
                    title: "KeyPath permissions missing",
                    canAutoFix: false,
                    action: "Grant Accessibility & Input Monitoring permissions."
                ))
        }
        // NOTE: Kanata does NOT need TCC permissions - it uses the Karabiner VirtualHIDDevice
        // driver and runs as root via SMAppService/LaunchDaemon. No issue generated for Kanata.
        if !context.components.hasAllRequired {
            issues.append(
                ContextIssue(
                    title: "Required components missing",
                    canAutoFix: true,
                    action: "Run `keypath-cli install` to reinstall components."
                ))
        }
        if !context.services.isHealthy {
            issues.append(
                ContextIssue(
                    title: "Services unhealthy",
                    canAutoFix: true,
                    action: "Run `keypath-cli repair` to restart services."
                ))
        }
        if !context.helper.isReady {
            issues.append(
                ContextIssue(
                    title: "Helper not installed",
                    canAutoFix: true,
                    action: "Run `keypath-cli install` to reinstall helper."
                ))
        }
        if context.conflicts.hasConflicts {
            issues.append(
                contentsOf: context.conflicts.conflicts.map { conflict in
                    ContextIssue(
                        title: formatConflict(conflict), canAutoFix: true,
                        action: "Terminate or stop the conflicting process."
                    )
                })
        }

        return issues
    }
}

private struct ContextIssue {
    let title: String
    let canAutoFix: Bool
    let action: String?
}

private extension SystemContext {
    var isOperational: Bool {
        permissions.isSystemReady && helper.isReady && components.hasAllRequired && services.isHealthy
            && !conflicts.hasConflicts
    }
}
