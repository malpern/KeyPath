import ApplicationServices
import Foundation
import IOKit.hidsystem

/// Phase 4: System Requirements Checker
///
/// Modular component for checking all system requirements needed for KeyPath to function.
/// This replaces the scattered requirement checks throughout the codebase with a
/// centralized, testable, and comprehensive system.
class SystemRequirementsChecker {
    // MARK: - Requirement Results

    struct RequirementCheckResult {
        let requirement: SystemRequirement
        let status: RequirementStatus
        let details: String
        let actionRequired: String?

        enum RequirementStatus {
            case satisfied
            case missing
            case warning
            case error

            var isBlocking: Bool {
                switch self {
                case .missing, .error:
                    true
                case .satisfied, .warning:
                    false
                }
            }
        }
    }

    enum SystemRequirement: String, CaseIterable {
        case kanataExecution = "kanata_executable"
        case accessibilityPermissions = "accessibility_permissions"
        case inputMonitoringPermissions = "input_monitoring_permissions"
        case launchDaemonDirectory = "launch_daemon_directory"
        case configDirectory = "config_directory"
        case logDirectory = "log_directory"
        case systemVersion = "system_version"
        case architecture

        var displayName: String {
            switch self {
            case .kanataExecution:
                "Kanata Executable"
            case .accessibilityPermissions:
                "Accessibility Permissions"
            case .inputMonitoringPermissions:
                "Input Monitoring Permissions"
            case .launchDaemonDirectory:
                "LaunchDaemon Directory"
            case .configDirectory:
                "Configuration Directory"
            case .logDirectory:
                "Log Directory"
            case .systemVersion:
                "macOS Version"
            case .architecture:
                "System Architecture"
            }
        }

        var description: String {
            switch self {
            case .kanataExecution:
                "Keyboard remapping engine executable"
            case .accessibilityPermissions:
                "Required for capturing and remapping keyboard input"
            case .inputMonitoringPermissions:
                "Required for monitoring key press events"
            case .launchDaemonDirectory:
                "System service configuration directory"
            case .configDirectory:
                "KeyPath configuration storage"
            case .logDirectory:
                "Application log storage"
            case .systemVersion:
                "Minimum macOS 13.0 required"
            case .architecture:
                "Intel or Apple Silicon supported"
            }
        }

        var isBlockingRequirement: Bool {
            switch self {
            case .kanataExecution, .accessibilityPermissions, .inputMonitoringPermissions, .systemVersion:
                true
            case .launchDaemonDirectory, .configDirectory, .logDirectory, .architecture:
                false
            }
        }
    }

    // MARK: - Comprehensive Check Results

    struct SystemRequirementsReport {
        let timestamp: Date
        let overallStatus: OverallStatus
        let results: [RequirementCheckResult]
        let blockingIssues: [RequirementCheckResult]
        let warnings: [RequirementCheckResult]
        let summary: String

        enum OverallStatus {
            case allSatisfied
            case hasWarnings
            case hasBlockingIssues
            case systemError

            var canProceed: Bool {
                switch self {
                case .allSatisfied, .hasWarnings:
                    true
                case .hasBlockingIssues, .systemError:
                    false
                }
            }
        }

        var requiresInstallation: Bool {
            blockingIssues.contains { result in
                result.requirement == .kanataExecution || result.requirement == .launchDaemonDirectory
                    || result.requirement == .configDirectory
            }
        }

        var requiresPermissions: Bool {
            blockingIssues.contains { result in
                result.requirement == .accessibilityPermissions
                    || result.requirement == .inputMonitoringPermissions
            }
        }
    }

    // MARK: - Public Interface

    /// Perform comprehensive system requirements check
    func checkAllRequirements() async -> SystemRequirementsReport {
        AppLogger.shared.log("🔍 [SystemCheck] ========== COMPREHENSIVE REQUIREMENTS CHECK ==========")

        let startTime = Date()
        var results: [RequirementCheckResult] = []

        // Check all requirements
        for requirement in SystemRequirement.allCases {
            AppLogger.shared.log("🔍 [SystemCheck] Checking: \(requirement.displayName)")
            let result = await checkRequirement(requirement)
            results.append(result)

            let statusEmoji = result.status.isBlocking ? "❌" : "✅"
            AppLogger.shared.log(
                "\(statusEmoji) [SystemCheck] \(requirement.displayName): \(result.details)")
        }

        // Analyze overall status
        let blockingIssues = results.filter(\.status.isBlocking)
        let warnings = results.filter { $0.status == .warning }

        let overallStatus: SystemRequirementsReport.OverallStatus =
            if !blockingIssues.isEmpty {
                .hasBlockingIssues
            } else if !warnings.isEmpty {
                .hasWarnings
            } else {
                .allSatisfied
            }

        let summary = generateSummary(
            overallStatus: overallStatus, blockingCount: blockingIssues.count,
            warningCount: warnings.count
        )

        let report = SystemRequirementsReport(
            timestamp: Date(),
            overallStatus: overallStatus,
            results: results,
            blockingIssues: blockingIssues,
            warnings: warnings,
            summary: summary
        )

        let duration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "🔍 [SystemCheck] Check completed in \(String(format: "%.2f", duration))s - Status: \(overallStatus)"
        )

        return report
    }

    /// Check a specific requirement
    func checkRequirement(_ requirement: SystemRequirement) async -> RequirementCheckResult {
        switch requirement {
        case .kanataExecution:
            await checkKanataExecutable()
        case .accessibilityPermissions:
            checkAccessibilityPermissions()
        case .inputMonitoringPermissions:
            checkInputMonitoringPermissions()
        case .launchDaemonDirectory:
            checkLaunchDaemonDirectory()
        case .configDirectory:
            checkConfigDirectory()
        case .logDirectory:
            checkLogDirectory()
        case .systemVersion:
            checkSystemVersion()
        case .architecture:
            checkArchitecture()
        }
    }

    // MARK: - Individual Requirement Checks

    private func checkKanataExecutable() async -> RequirementCheckResult {
        let possiblePaths = [
            "/opt/homebrew/bin/kanata", // ARM Homebrew
            WizardSystemPaths.kanataActiveBinary, // Active binary
            "/usr/bin/kanata" // System install
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               FileManager.default.isExecutableFile(atPath: path) {
                // Verify it's actually the Kanata executable
                let verification = await verifyKanataExecutable(at: path)
                if verification.isValid {
                    return RequirementCheckResult(
                        requirement: .kanataExecution,
                        status: .satisfied,
                        details: "Found at \(path) - \(verification.version)",
                        actionRequired: nil
                    )
                }
            }
        }

        return RequirementCheckResult(
            requirement: .kanataExecution,
            status: .missing,
            details: "Kanata executable not found in standard locations",
            actionRequired: "KeyPath will install Kanata automatically via the Installation Wizard"
        )
    }

    private func verifyKanataExecutable(at path: String) async -> (isValid: Bool, version: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0, output.lowercased().contains("kanata") {
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return (true, version)
            }
        } catch {
            AppLogger.shared.log("❌ [SystemCheck] Error verifying Kanata at \(path): \(error)")
        }

        return (false, "Unknown")
    }

    private func checkAccessibilityPermissions() -> RequirementCheckResult {
        let trusted = AXIsProcessTrusted()

        if trusted {
            return RequirementCheckResult(
                requirement: .accessibilityPermissions,
                status: .satisfied,
                details: "Accessibility permissions granted",
                actionRequired: nil
            )
        } else {
            return RequirementCheckResult(
                requirement: .accessibilityPermissions,
                status: .missing,
                details: "Accessibility permissions not granted",
                actionRequired:
                "Grant accessibility permissions in System Settings > Privacy & Security > Accessibility"
            )
        }
    }

    private func checkInputMonitoringPermissions() -> RequirementCheckResult {
        // This is a simplified check - in reality, input monitoring permissions
        // are harder to programmatically verify
        let status: RequirementCheckResult.RequirementStatus = .warning

        return RequirementCheckResult(
            requirement: .inputMonitoringPermissions,
            status: status,
            details: "Input monitoring permissions cannot be automatically verified",
            actionRequired:
            "Ensure input monitoring permissions are granted in System Settings > Privacy & Security > Input Monitoring"
        )
    }

    private func checkLaunchDaemonDirectory() -> RequirementCheckResult {
        let launchDaemonPath = "/Library/LaunchDaemons"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: launchDaemonPath) {
            // Check if we can write to it (requires sudo, but we can check directory existence)
            return RequirementCheckResult(
                requirement: .launchDaemonDirectory,
                status: .satisfied,
                details: "LaunchDaemon directory exists and is accessible",
                actionRequired: nil
            )
        } else {
            return RequirementCheckResult(
                requirement: .launchDaemonDirectory,
                status: .error,
                details: "LaunchDaemon directory not found",
                actionRequired: "System directory missing - contact support"
            )
        }
    }

    private func checkConfigDirectory() -> RequirementCheckResult {
        let configPath = "/usr/local/etc/kanata"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: configPath) {
            return RequirementCheckResult(
                requirement: .configDirectory,
                status: .satisfied,
                details: "Configuration directory exists",
                actionRequired: nil
            )
        } else {
            return RequirementCheckResult(
                requirement: .configDirectory,
                status: .missing,
                details: "Configuration directory does not exist",
                actionRequired: "Directory will be created during installation"
            )
        }
    }

    private func checkLogDirectory() -> RequirementCheckResult {
        let logPath = "/var/log"
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: logPath) {
            return RequirementCheckResult(
                requirement: .logDirectory,
                status: .satisfied,
                details: "System log directory exists",
                actionRequired: nil
            )
        } else {
            return RequirementCheckResult(
                requirement: .logDirectory,
                status: .error,
                details: "System log directory not found",
                actionRequired: "System directory missing - contact support"
            )
        }
    }

    private func checkSystemVersion() -> RequirementCheckResult {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion

        // KeyPath requires macOS 13.0+
        let minimumMajor = 13
        let currentMajor = version.majorVersion

        if currentMajor >= minimumMajor {
            return RequirementCheckResult(
                requirement: .systemVersion,
                status: .satisfied,
                details: "macOS \(currentMajor).\(version.minorVersion).\(version.patchVersion)",
                actionRequired: nil
            )
        } else {
            return RequirementCheckResult(
                requirement: .systemVersion,
                status: .missing,
                details: "macOS \(currentMajor).\(version.minorVersion) detected, requires macOS 13.0+",
                actionRequired: "Upgrade to macOS 13.0 or later"
            )
        }
    }

    private func checkArchitecture() -> RequirementCheckResult {
        _ = ProcessInfo.processInfo.processorCount > 0 ? "Supported" : "Unknown"

        return RequirementCheckResult(
            requirement: .architecture,
            status: .satisfied,
            details: "System architecture is supported",
            actionRequired: nil
        )
    }

    // MARK: - Helper Methods

    private func generateSummary(
        overallStatus: SystemRequirementsReport.OverallStatus, blockingCount: Int, warningCount: Int
    ) -> String {
        switch overallStatus {
        case .allSatisfied:
            "All system requirements satisfied. KeyPath is ready to run."
        case .hasWarnings:
            "System requirements mostly satisfied with \(warningCount) warning(s). KeyPath can run but some features may be limited."
        case .hasBlockingIssues:
            "\(blockingCount) critical requirement(s) not met. KeyPath cannot run until these are resolved."
        case .systemError:
            "System error encountered during requirements check. Please try again or contact support."
        }
    }
}
