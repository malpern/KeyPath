import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

// Import InstallIntent from KeyPath executable (needs to be extracted to shared library)
// For now, we'll access it via the InstallerEngine

/// CLI handler for KeyPath command-line operations
@MainActor
public struct KeyPathCLI {
    private let installerEngine: InstallerEngine
    private let systemValidator: SystemValidator

    public init() {
        installerEngine = InstallerEngine()
        let processManager = ProcessLifecycleManager()
        systemValidator = SystemValidator(processLifecycleManager: processManager)
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
        print("""
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

        let snapshot = await systemValidator.checkSystem()

        print("\n=== System Status ===")
        print("Timestamp: \(formatDate(snapshot.timestamp))")
        print("System Ready: \(snapshot.isReady ? "✅ Yes" : "❌ No")")

        // Helper status
        print("\n--- Helper ---")
        print("Installed: \(snapshot.helper.isInstalled ? "✅" : "❌")")
        print("Working: \(snapshot.helper.isWorking ? "✅" : "❌")")
        if let version = snapshot.helper.version {
            print("Version: \(version)")
        }

        // Permissions
        print("\n--- Permissions ---")
        print("KeyPath:")
        print("  Accessibility: \(snapshot.permissions.keyPath.accessibility.isReady ? "✅" : "❌")")
        print("  Input Monitoring: \(snapshot.permissions.keyPath.inputMonitoring.isReady ? "✅" : "❌")")
        print("Kanata:")
        print("  Accessibility: \(snapshot.permissions.kanata.accessibility.isReady ? "✅" : "❌")")
        print("  Input Monitoring: \(snapshot.permissions.kanata.inputMonitoring.isReady ? "✅" : "❌")")

        // Components
        print("\n--- Components ---")
        print("Kanata Binary: \(snapshot.components.kanataBinaryInstalled ? "✅ Installed" : "❌ Missing")")
        print("Karabiner Driver: \(snapshot.components.karabinerDriverInstalled ? "✅ Installed" : "❌ Missing")")
        print("VHID Device: \(snapshot.components.vhidDeviceHealthy ? "✅ Healthy" : "❌ Unhealthy")")
        if snapshot.components.vhidVersionMismatch {
            print("⚠️  VHID Version Mismatch detected")
        }

        // Services
        print("\n--- Services ---")
        print("Kanata Running: \(snapshot.health.kanataRunning ? "✅" : "❌")")
        print("Karabiner Daemon: \(snapshot.health.karabinerDaemonRunning ? "✅" : "❌")")
        print("VHID Healthy: \(snapshot.health.vhidHealthy ? "✅" : "❌")")

        // Conflicts
        if snapshot.conflicts.hasConflicts {
            print("\n--- Conflicts ---")
            for conflict in snapshot.conflicts.conflicts {
                print("⚠️  \(formatConflict(conflict))")
            }
        }

        // Issues
        let issues = snapshot.blockingIssues
        if !issues.isEmpty {
            print("\n--- Issues ---")
            for issue in issues {
                print("\(issue.canAutoFix ? "🔧" : "⚠️")  \(issue.title)")
                if !issue.action.isEmpty {
                    print("   Action: \(issue.action)")
                }
            }
        }

        print("\n=== Summary ===")
        if snapshot.isReady {
            print("✅ System is ready and operational")
            return 0
        } else {
            print("❌ System has \(issues.count) blocking issue(s)")
            print("   Run 'keypath-cli repair' to attempt automatic fixes")
            return 1
        }
    }

    /// Run install command
    private func runInstall() async -> Int32 {
        print("Starting installation...")

        let broker = PrivilegeBroker()
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

        let broker = PrivilegeBroker()
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

    /// Run uninstall command
    private func runUninstall(deleteConfig: Bool) async -> Int32 {
        fputs("Starting uninstall...\n", stderr)
        print("Starting uninstall...")
        if deleteConfig {
            print("⚠️  User configuration will be deleted")
        } else {
            print("💾 User configuration will be preserved")
        }
        print("")

        let coordinator = UninstallCoordinator()
        let success = await coordinator.uninstall(deleteConfig: deleteConfig)

        // Print log lines from coordinator
        for line in coordinator.logLines {
            print(line)
        }

        print("")
        if success {
            print("✅ Uninstall completed successfully")
            return 0
        } else {
            if let error = coordinator.lastError {
                print("❌ Uninstall failed: \(error)")
            } else {
                print("❌ Uninstall failed")
            }
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
}
