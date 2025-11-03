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

// MARK: - Protocol

/// Service responsible for generating and analyzing system diagnostics
protocol DiagnosticsServiceProtocol: Sendable {
    /// Analyze a Kanata failure and return diagnostics
    func diagnoseKanataFailure(exitCode: Int32, output: String) -> [KanataDiagnostic]

    /// Get comprehensive system diagnostics
    func getSystemDiagnostics(engineClient: EngineClient?) async -> [KanataDiagnostic]

    /// Check for Kanata process conflicts
    func checkProcessConflicts() async -> [KanataDiagnostic]

    /// Analyze log file for issues
    func analyzeLogFile(path: String) async -> [KanataDiagnostic]

    /// Low-level status for Karabiner VirtualHID daemon used in summaries/toasts
    func virtualHIDDaemonStatus() -> (pids: [String], owners: [String], serviceInstalled: Bool, serviceState: String)

    /// Analyze a chunk of kanata log content and emit structured events
    func analyzeKanataLogChunk(_ content: String) -> [DiagnosticsService.LogEvent]

    /// Get Kanata engine status via TCP Status endpoint (if available)
    func getKanataEngineStatus(engineClient: EngineClient?) async -> KanataEngineStatus?
}

// MARK: - Implementation

final class DiagnosticsService: DiagnosticsServiceProtocol, @unchecked Sendable {
    // Dependencies
    private let processLifecycleManager: ProcessLifecycleManager

    init(processLifecycleManager: ProcessLifecycleManager) {
        self.processLifecycleManager = processLifecycleManager
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
                || output.contains("connect_failed asio.system:2") {
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

    // MARK: - Engine Status

    /// Result of checking Kanata engine status via TCP
    struct KanataEngineStatus: Sendable {
        let engineVersion: String
        let uptimeSeconds: UInt64
        let ready: Bool
        let lastReloadOk: Bool
        let lastReloadAt: String? // Epoch seconds timestamp
    }

    func getKanataEngineStatus(engineClient: EngineClient?) async -> KanataEngineStatus? {
        guard let engineClient = engineClient as? TCPEngineClient else {
            return nil
        }

        switch await engineClient.getStatus() {
        case .success(let statusInfo):
            return KanataEngineStatus(
                engineVersion: statusInfo.engine_version,
                uptimeSeconds: statusInfo.uptime_s,
                ready: statusInfo.ready,
                lastReloadOk: statusInfo.last_reload.ok,
                lastReloadAt: statusInfo.last_reload.at
            )
        case .failure:
            return nil
        }
    }

    // MARK: - System Diagnostics

    func getSystemDiagnostics(engineClient: EngineClient? = nil) async -> [KanataDiagnostic] {
        var diagnostics: [KanataDiagnostic] = []

        // Check Kanata engine status via TCP (if available)
        if let engineStatus = await getKanataEngineStatus(engineClient: engineClient) {
            // Add engine status diagnostic
            if !engineStatus.ready {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .warning,
                        category: .process,
                        title: "Kanata Engine Not Ready",
                        description: "Engine is running but not ready to remap keys (uptime: \(engineStatus.uptimeSeconds)s)",
                        technicalDetails: "Engine version: \(engineStatus.engineVersion), Last reload: \(engineStatus.lastReloadOk ? "OK" : "Failed")",
                        suggestedAction: "Wait for engine to become ready or check configuration",
                        canAutoFix: false
                    ))
            } else if !engineStatus.lastReloadOk {
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .error,
                        category: .configuration,
                        title: "Last Configuration Reload Failed",
                        description: "Engine is running but last configuration reload failed",
                        technicalDetails: "Engine version: \(engineStatus.engineVersion), Uptime: \(engineStatus.uptimeSeconds)s",
                        suggestedAction: "Check configuration file for errors",
                        canAutoFix: true
                    ))
            } else {
                // Engine is healthy - add informational diagnostic
                diagnostics.append(
                    KanataDiagnostic(
                        timestamp: Date(),
                        severity: .info,
                        category: .process,
                        title: "Kanata Engine Healthy",
                        description: "Engine is running and ready (version: \(engineStatus.engineVersion), uptime: \(formatUptime(engineStatus.uptimeSeconds)))",
                        technicalDetails: "TCP Status endpoint indicates healthy state",
                        suggestedAction: "",
                        canAutoFix: false
                    ))
            }
        }

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

        // Check background services
        if !areKarabinerBackgroundServicesEnabled() {
            diagnostics.append(
                KanataDiagnostic(
                    timestamp: Date(),
                    severity: .warning,
                    category: .system,
                    title: "Background Services Not Enabled",
                    description: "Karabiner background services may not be enabled",
                    technicalDetails: "Services not detected in launchctl",
                    suggestedAction: "Enable in System Settings > General > Login Items & Extensions",
                    canAutoFix: false
                ))
        }

        return diagnostics
    }

    // MARK: - VirtualHID Daemon Status

    func virtualHIDDaemonStatus() -> (pids: [String], owners: [String], serviceInstalled: Bool, serviceState: String) {
        // pgrep VirtualHID daemon
        let pids: [String] = {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-f", "Karabiner-VirtualHIDDevice-Daemon"]
            let pipe = Pipe(); task.standardOutput = pipe
            do { try task.run(); task.waitUntilExit() } catch {}
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }()

        // ps owners
        var owners: [String] = []
        for pid in pids {
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-o", "pid,ppid,user,command", "-p", pid]
            let pp = Pipe(); ps.standardOutput = pp
            if (try? ps.run()) != nil {
                ps.waitUntilExit()
                let d = pp.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: d, encoding: .utf8) {
                    owners.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        // launchctl state
        let label = "com.keypath.karabiner-vhiddaemon"
        let plistPath = "/Library/LaunchDaemons/\(label).plist"
        let serviceInstalled = FileManager.default.fileExists(atPath: plistPath)
        var serviceState = "unknown"
        if serviceInstalled {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/bin/launchctl"); t.arguments = ["print", "system/\(label)"]
            let p = Pipe(); t.standardOutput = p; t.standardError = p
            if (try? t.run()) != nil {
                t.waitUntilExit()
                let d = p.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: d, encoding: .utf8) ?? ""
                if let line = s.split(separator: "\n").first(where: { $0.contains("state =") }) {
                    serviceState = String(line).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return (pids, owners, serviceInstalled, serviceState)
    }

    // MARK: - Log Parsing

    enum LogEvent: Sendable, Equatable {
        case virtualHIDConnectionFailed
        case virtualHIDConnected
    }

    func analyzeKanataLogChunk(_ content: String) -> [LogEvent] {
        var events: [LogEvent] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("connect_failed asio.system:2") || line.contains("connect_failed asio.system:61") {
                events.append(.virtualHIDConnectionFailed)
            } else if line.contains("driver_connected 1") {
                events.append(.virtualHIDConnected)
            }
        }
        return events
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
        FileManager.default.fileExists(atPath: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice")
    }

    private func isKarabinerDaemonRunning() -> Bool {
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

    private func formatUptime(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
