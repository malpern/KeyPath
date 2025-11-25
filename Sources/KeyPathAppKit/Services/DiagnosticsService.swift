import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle

// MARK: - Diagnostic Types

/// Detailed diagnostic information for Kanata issues
struct KanataDiagnostic: Sendable {
    let timestamp: Date
    let severity: DiagnosticSeverity
    let category: DiagnosticCategory
    let title: String
    let description: String
    let technicalDetails: String
    let suggestedAction: String
    let canAutoFix: Bool
}

enum DiagnosticSeverity: String, CaseIterable, Sendable {
    case info
    case warning
    case error
    case critical

    var emoji: String {
        switch self {
        case .info: "ℹ️"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🚨"
        }
    }
}

enum DiagnosticCategory: String, CaseIterable, Sendable {
    case configuration = "Configuration"
    case permissions = "Permissions"
    case process = "Process"
    case system = "System"
    case conflict = "Conflict"
}

// MARK: - Shared Types

struct VirtualHIDDaemonStatus: Sendable {
    let pids: [String]
    let owners: [String]
    let serviceInstalled: Bool
    let serviceState: String
    /// Optional launchctl health signal. nil means unknown (command failed / not permitted).
    let serviceHealthy: Bool?
}

enum DiagnosticsLogEvent: Sendable {
    case virtualHIDConnectionFailed
    case virtualHIDConnected
}

// MARK: - Protocol

/// Service responsible for generating and analyzing system diagnostics
protocol DiagnosticsServiceProtocol: Sendable {
    /// Analyze a Kanata failure and return diagnostics
    func diagnoseKanataFailure(exitCode: Int32, output: String) -> [KanataDiagnostic]

    /// Get comprehensive system diagnostics
    func getSystemDiagnostics() async -> [KanataDiagnostic]
    /// Overload used by managers expecting to pass an engine client
    func getSystemDiagnostics(engineClient: EngineClient?) async -> [KanataDiagnostic]

    /// Check for Kanata process conflicts
    func checkProcessConflicts() async -> [KanataDiagnostic]

    /// Analyze log file for issues
    func analyzeLogFile(path: String) async -> [KanataDiagnostic]
    /// VirtualHID daemon low-level status (used for summaries)
    func virtualHIDDaemonStatus() -> VirtualHIDDaemonStatus
    /// Parse a log chunk into high-level events
    func analyzeKanataLogChunk(_ chunk: String) -> [DiagnosticsLogEvent]
}

// MARK: - Implementation

final class DiagnosticsService: DiagnosticsServiceProtocol, @unchecked Sendable {
    // Dependencies
    private let processLifecycleManager: ProcessLifecycleManager

    init(processLifecycleManager: ProcessLifecycleManager) {
        self.processLifecycleManager = processLifecycleManager
    }

    nonisolated func virtualHIDDaemonStatus() -> VirtualHIDDaemonStatus {
        // Get actual VirtualHID daemon status with real PIDs
        let vhid = VHIDDeviceManager()
        let pids = vhid.getDaemonPIDs() // Get real PIDs instead of placeholder
        let installed = vhid.detectActivation()
        let running = !pids.isEmpty
        let health = vhid.checkLaunchctlHealth()

        return VirtualHIDDaemonStatus(
            pids: pids, // Real PIDs from pgrep
            owners: [],
            serviceInstalled: installed,
            serviceState: running ? "running" : "stopped",
            serviceHealthy: health
        )
    }

    nonisolated func analyzeKanataLogChunk(_ chunk: String) -> [DiagnosticsLogEvent] {
        var events: [DiagnosticsLogEvent] = []
        let lower = chunk.lowercased()
        if lower.contains("connection established") || lower.contains("vhid connected") {
            events.append(.virtualHIDConnected)
        }
        if lower.contains("asio.system") || lower.contains("connection failed")
            || lower.contains("vhid error")
        {
            events.append(.virtualHIDConnectionFailed)
        }
        return events
    }

    func getSystemDiagnostics(engineClient _: EngineClient?) async -> [KanataDiagnostic] {
        await getSystemDiagnostics()
    }

    // MARK: - Failure Analysis

    nonisolated func diagnoseKanataFailure(exitCode: Int32, output: String) -> [KanataDiagnostic] {
        var diagnostics: [KanataDiagnostic] = []

        // Analyze exit code
        switch exitCode {
        case 1:
            if output.contains("IOHIDDeviceOpen error") {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .permissions,
                        title: "Permission Denied",
                        description: "Kanata cannot access keyboard devices due to missing permissions.",
                        technicalDetails: "IOHIDDeviceOpen error: exclusive access denied",
                        suggestedAction: "Use the Installation Wizard to grant required permissions",
                        canAutoFix: false
                    ))
            } else if output.contains("Error in configuration") {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .configuration,
                        title: "Invalid Configuration",
                        description: "The Kanata configuration file contains syntax errors.",
                        technicalDetails: output,
                        suggestedAction: "Review and fix the configuration file, or reset to default",
                        canAutoFix: true
                    ))
            } else if output.contains("device already open") {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .conflict,
                        title: "Device Conflict",
                        description: "Another process is already using the keyboard device.",
                        technicalDetails: output,
                        suggestedAction:
                        "Check for conflicting keyboard software (Karabiner-Elements grabber, other keyboard tools)",
                        canAutoFix: false
                    ))
            }
        case -9:
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .warning,
                    category: .process,
                    title: "Process Terminated",
                    description: "Kanata was forcefully terminated (SIGKILL).",
                    technicalDetails: "Exit code: -9",
                    suggestedAction: "This usually happens during shutdown or restart. Try starting again.",
                    canAutoFix: true
                ))
        case -15:
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .info,
                    category: .process,
                    title: "Process Stopped",
                    description: "Kanata was gracefully terminated (SIGTERM).",
                    technicalDetails: "Exit code: -15",
                    suggestedAction: "This is normal shutdown behavior.",
                    canAutoFix: false
                ))
        case 6:
            // Exit code 6 has different causes - check for VirtualHID connection issues
            if output.contains("connect_failed asio.system:61")
                || output.contains("connect_failed asio.system:2")
            {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .conflict,
                        title: "VirtualHID Connection Failed",
                        description:
                        "Kanata captured keyboard input but failed to connect to VirtualHID driver, causing unresponsive keyboard.",
                        technicalDetails: "Exit code: 6 (VirtualHID connection failure)\nOutput: \(output)",
                        suggestedAction:
                        "Restart Karabiner-VirtualHIDDevice daemon or try starting KeyPath again",
                        canAutoFix: true
                    ))
            } else {
                // Generic exit code 6 - permission issues
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .permissions,
                        title: "Access Denied",
                        description: "Kanata cannot access system resources (exit code 6).",
                        technicalDetails: "Exit code: 6\nOutput: \(output)",
                        suggestedAction: "Use the Installation Wizard to check and grant required permissions",
                        canAutoFix: false
                    ))
            }
        default:
            // For unknown exit codes, check if it might be permission-related
            let isPermissionRelated =
                output.contains("permission") || output.contains("access") || output.contains("denied")
                    || output.contains("IOHIDDeviceOpen") || output.contains("privilege")

            if isPermissionRelated {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .permissions,
                        title: "Possible Permission Issue",
                        description: "Kanata exited with code \(exitCode), possibly due to permission issues.",
                        technicalDetails: "Exit code: \(exitCode)\nOutput: \(output)",
                        suggestedAction: "Use the Installation Wizard to check and grant required permissions",
                        canAutoFix: false
                    ))
            } else {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .process,
                        title: "Unexpected Exit",
                        description: "Kanata exited unexpectedly with code \(exitCode).",
                        technicalDetails: "Exit code: \(exitCode)\nOutput: \(output)",
                        suggestedAction: "Check the logs for more details or try restarting Kanata",
                        canAutoFix: false
                    ))
            }
        }

        return diagnostics
    }

    // MARK: - System Diagnostics

    func getSystemDiagnostics() async -> [KanataDiagnostic] {
        // Fast path for tests - skip all process/system checks
        if TestEnvironment.isRunningTests {
            return []
        }

        var diagnostics: [KanataDiagnostic] = []

        // Check Kanata installation
        if !isKanataInstalled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .critical,
                    category: .system,
                    title: "Kanata Not Installed",
                    description: "Kanata binary not found at \(WizardSystemPaths.kanataActiveBinary)",
                    technicalDetails: "Expected path: \(WizardSystemPaths.kanataActiveBinary)",
                    suggestedAction: "Use KeyPath's Installation Wizard to install Kanata automatically",
                    canAutoFix: false
                ))
        }

        // NOTE: Permission checks are handled by the Installation Wizard
        // We don't duplicate permission diagnostics here to avoid confusion

        // Check for conflicts
        if isKarabinerElementsRunning() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .warning,
                    category: .conflict,
                    title: "Karabiner-Elements Conflict",
                    description: "Karabiner-Elements grabber is running and may conflict with Kanata",
                    technicalDetails: "karabiner_grabber process detected",
                    suggestedAction: "Stop Karabiner-Elements or configure it to not interfere",
                    canAutoFix: false
                ))
        }

        // Check driver status
        if !isKarabinerDriverInstalled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .system,
                    title: "Missing Virtual HID Driver",
                    description: "Karabiner VirtualHID driver is required for Kanata to function",
                    technicalDetails: "Driver not found at expected location",
                    suggestedAction: "Install Karabiner-Elements to get the VirtualHID driver",
                    canAutoFix: false
                ))
        } else if !isKarabinerDaemonRunning() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .warning,
                    category: .system,
                    title: "VirtualHID Daemon Not Running",
                    description: "Karabiner VirtualHID daemon is installed but not running",
                    technicalDetails: "VirtualHIDDevice-Daemon process not found",
                    suggestedAction: "The app will try to start the daemon automatically",
                    canAutoFix: true
                ))
        }

        // Check for karabiner_grabber conflict
        if isKarabinerElementsRunning() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .conflict,
                    title: "Karabiner Grabber Conflict",
                    description: "karabiner_grabber is running and will prevent Kanata from starting",
                    technicalDetails: "This causes 'exclusive access and device already open' errors",
                    suggestedAction: "Quit Karabiner-Elements or disable its key remapping",
                    canAutoFix: true // We can kill it
                ))
        }

        // Check for Kanata process conflicts
        let processConflicts = await checkProcessConflicts()
        diagnostics.append(contentsOf: processConflicts)

        // Check driver extension status
        if isKarabinerDriverInstalled(), !isKarabinerDriverExtensionEnabled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .system,
                    title: "Driver Extension Not Enabled",
                    description: "Karabiner driver is installed but not enabled in System Settings",
                    technicalDetails: "Driver extension shows as not [activated enabled]",
                    suggestedAction: "Enable in System Settings > Privacy & Security > Driver Extensions",
                    canAutoFix: false
                ))
        }

        // Karabiner background services
        // If they are disabled, that's OK for KeyPath (it avoids conflicts). Downgrade to info.
        if !areKarabinerBackgroundServicesEnabled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .info,
                    category: .system,
                    title: "Karabiner Background Services Disabled (OK)",
                    description:
                    "Karabiner-Elements background services are not enabled. This is fine when using KeyPath.",
                    technicalDetails: "No org.pqrs.karabiner services detected in launchctl",
                    suggestedAction: "No action needed unless you intend to use Karabiner-Elements.",
                    canAutoFix: false
                ))
        }

        // TCP engine status (non-blocking informational)
        if let tcpInfo = await fetchTcpStatusInfo() {
            if let last = tcpInfo.last_reload {
                let dur = last.duration_ms.map(String.init) ?? "-"
                let ep = last.epoch.map(String.init) ?? "-"
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .info,
                        category: .system,
                        title: "Last Reload",
                        description: "ok=\(last.ok) duration_ms=\(dur) epoch=\(ep)",
                        technicalDetails: "Reported by TCP StatusInfo",
                        suggestedAction: "",
                        canAutoFix: false
                    ))
            }
        }

        // TCP handshake summary (protocol/capabilities)
        if let hello = await fetchTcpHello() {
            let caps = hello.capabilities.joined(separator: ", ")
            let proto = hello.protocolVersion
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .info,
                    category: .system,
                    title: "TCP Handshake",
                    description: "version=\(hello.version) protocol=\(proto) caps=[\(caps)]",
                    technicalDetails: "HelloOk(version, protocol, capabilities)",
                    suggestedAction: "",
                    canAutoFix: false
                ))

            // Enforce protocol v2 for full functionality
            if proto < 2 {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .system,
                        title: "Kanata protocol too old",
                        description:
                        "Detected protocol v\(proto). KeyPath requires v2 for blocking reload and richer status.",
                        technicalDetails: "HelloOk reported protocol=\(proto)",
                        suggestedAction:
                        "Use Regenerate Services to install the bundled Kanata and reload services.",
                        canAutoFix: true
                    ))
            }
        }

        // Include log-based integration health (Diagnostics-only, non-blocking)
        let logDiagnostics = await analyzeLogFile(path: WizardSystemPaths.kanataLogFile)
        diagnostics.append(contentsOf: logDiagnostics)

        return diagnostics
    }

    // MARK: - Process Conflict Checking

    func checkProcessConflicts() async -> [KanataDiagnostic] {
        var diagnostics: [KanataDiagnostic] = []
        let conflicts = await processLifecycleManager.detectConflicts()

        // Show managed processes (informational)
        if !conflicts.managedProcesses.isEmpty {
            let processDetails = conflicts.managedProcesses.map { process in
                "PID \(process.pid): \(process.command)"
            }.joined(separator: "\n")

            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .info,
                    category: .system,
                    title: "KeyPath Managed Processes (\(conflicts.managedProcesses.count))",
                    description: "Kanata processes currently managed by KeyPath",
                    technicalDetails: processDetails,
                    suggestedAction: "",
                    canAutoFix: false
                ))
        }

        // Show external conflicts (errors that need attention)
        if !conflicts.externalProcesses.isEmpty {
            let conflictDetails = conflicts.externalProcesses.map { process in
                "PID \(process.pid): \(process.command)"
            }.joined(separator: "\n")

            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .conflict,
                    title: "External Kanata Conflicts (\(conflicts.externalProcesses.count))",
                    description: "External Kanata processes that conflict with KeyPath",
                    technicalDetails: conflictDetails,
                    suggestedAction: "Terminate conflicting processes or let KeyPath auto-fix them",
                    canAutoFix: true
                ))
        }

        return diagnostics
    }

    // MARK: - Log Analysis

    func analyzeLogFile(path: String) async -> [KanataDiagnostic] {
        var diagnostics: [KanataDiagnostic] = []

        guard FileManager.default.fileExists(atPath: path) else {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .warning,
                    category: .system,
                    title: "Log File Not Found",
                    description: "Log file does not exist at \(path)",
                    technicalDetails: "Path: \(path)",
                    suggestedAction: "Ensure Kanata has been started at least once",
                    canAutoFix: false
                ))
            return diagnostics
        }

        do {
            let logContent = try String(contentsOfFile: path, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)

            // Look for common error patterns
            for line in lines.suffix(100) { // Check last 100 lines
                if line.contains("IOHIDDeviceOpen error") {
                    diagnostics.append(
                        KanataDiagnostic(
                            timestamp: Date(),
                            severity: .error,
                            category: .permissions,
                            title: "Permission Error in Logs",
                            description: "Kanata cannot access keyboard devices",
                            technicalDetails: line,
                            suggestedAction: "Grant Input Monitoring permission",
                            canAutoFix: false
                        ))
                } else if line.contains("connect_failed") {
                    diagnostics.append(
                        KanataDiagnostic(
                            timestamp: Date(),
                            severity: .error,
                            category: .conflict,
                            title: "VirtualHID Connection Error in Logs",
                            description: "Failed to connect to VirtualHID driver",
                            technicalDetails: line,
                            suggestedAction: "Restart Karabiner-VirtualHIDDevice daemon",
                            canAutoFix: true
                        ))
                } else if line.contains("ERROR") || line.contains("FATAL") {
                    diagnostics.append(
                        KanataDiagnostic(
                            timestamp: Date(),
                            severity: .error,
                            category: .process,
                            title: "Error Found in Logs",
                            description: "Kanata encountered an error",
                            technicalDetails: line,
                            suggestedAction: "Check the full logs for details",
                            canAutoFix: false
                        ))
                }
            }
        } catch {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .error,
                    category: .system,
                    title: "Failed to Read Log File",
                    description: "Could not read log file at \(path)",
                    technicalDetails: error.localizedDescription,
                    suggestedAction: "Check file permissions",
                    canAutoFix: false
                ))
        }

        return diagnostics
    }

    // MARK: - Helper Methods

    private func isKanataInstalled() -> Bool {
        FileManager.default.fileExists(atPath: WizardSystemPaths.kanataActiveBinary)
    }

    private func isKarabinerElementsRunning() -> Bool {
        // Skip process checks in test mode
        if TestEnvironment.isRunningTests { return false }

        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/usr/bin/pgrep"
        process.arguments = ["-x", "karabiner_grabber"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func isKarabinerDriverInstalled() -> Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice")
    }

    private func isKarabinerDaemonRunning() -> Bool {
        // Skip process checks in test mode
        if TestEnvironment.isRunningTests { return false }

        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/usr/bin/pgrep"
        process.arguments = ["-f", "Karabiner-VirtualHIDDevice"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func isKarabinerDriverExtensionEnabled() -> Bool {
        // Skip process checks in test mode
        if TestEnvironment.isRunningTests { return true }

        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/usr/bin/systemextensionsctl"
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("org.pqrs.Karabiner-DriverKit-VirtualHIDDevice")
                    && (output.contains("[activated enabled]") || output.contains("enabled"))
            }
        } catch {
            AppLogger.shared.log("⚠️ [Diagnostics] Failed to check driver extension status: \(error)")
        }

        return false
    }

    private func areKarabinerBackgroundServicesEnabled() -> Bool {
        // Skip launchctl checks in test mode
        if TestEnvironment.isRunningTests { return true }

        let process = Process()
        let pipe = Pipe()

        process.launchPath = "/bin/launchctl"
        process.arguments = ["list"]
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("org.pqrs.karabiner")
            }
        } catch {
            AppLogger.shared.log("⚠️ [Diagnostics] Failed to check background services: \(error)")
        }

        return false
    }

    // MARK: - TCP helpers (best-effort)

    private func fetchTcpStatusInfo() async -> KanataTCPClient.TcpStatusInfo? {
        let client = KanataTCPClient(port: 37001)

        do {
            _ = try await client.hello()
            let status = try await client.getStatus()

            // FIX #1: Explicitly close connection to prevent file descriptor leak
            await client.cancelInflightAndCloseConnection()

            return status
        } catch {
            // FIX #1: Clean up connection even on error path
            await client.cancelInflightAndCloseConnection()
            return nil
        }
    }

    private func fetchTcpHello() async -> KanataTCPClient.TcpHelloOk? {
        let client = KanataTCPClient(port: 37001)

        do {
            let hello = try await client.hello()

            // FIX #1: Explicitly close connection to prevent file descriptor leak
            await client.cancelInflightAndCloseConnection()

            return hello
        } catch {
            // FIX #1: Clean up connection even on error path
            await client.cancelInflightAndCloseConnection()
            return nil
        }
    }
}
