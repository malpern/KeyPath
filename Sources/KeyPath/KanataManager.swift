import ApplicationServices
import Foundation
import IOKit.hidsystem
import SwiftUI

/// Actor for process synchronization to prevent multiple concurrent Kanata starts
actor ProcessSynchronizationActor {
  func synchronize<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
    return try await operation()
  }
}

/// Errors related to configuration management
enum ConfigError: Error, LocalizedError {
  case corruptedConfigDetected(errors: [String])
  case claudeRepairFailed(reason: String)
  case validationFailed(errors: [String])
  case repairFailedNeedsUserAction(
    originalConfig: String,
    repairedConfig: String?,
    originalErrors: [String],
    repairErrors: [String],
    mappings: [KeyMapping]
  )

  var errorDescription: String? {
    switch self {
    case .corruptedConfigDetected(let errors):
      return "Configuration file is corrupted: \(errors.joined(separator: ", "))"
    case .claudeRepairFailed(let reason):
      return "Failed to repair configuration with Claude: \(reason)"
    case .validationFailed(let errors):
      return "Configuration validation failed: \(errors.joined(separator: ", "))"
    case .repairFailedNeedsUserAction:
      return "Configuration repair failed - user intervention required"
    }
  }
}

/// Represents a simple key mapping from input to output
struct KeyMapping: Codable, Equatable, Identifiable {
  let id = UUID()
  let input: String
  let output: String

  init(input: String, output: String) {
    self.input = input
    self.output = output
  }
}

/// Manages the Kanata process lifecycle and configuration directly.
// Detailed diagnostic information for Kanata issues
struct KanataDiagnostic {
  let timestamp: Date
  let severity: DiagnosticSeverity
  let category: DiagnosticCategory
  let title: String
  let description: String
  let technicalDetails: String
  let suggestedAction: String
  let canAutoFix: Bool
}

enum DiagnosticSeverity: String, CaseIterable {
  case info
  case warning
  case error
  case critical

  var emoji: String {
    switch self {
    case .info: return "ℹ️"
    case .warning: return "⚠️"
    case .error: return "❌"
    case .critical: return "🚨"
    }
  }
}

enum DiagnosticCategory: String, CaseIterable {
  case configuration = "Configuration"
  case permissions = "Permissions"
  case process = "Process"
  case system = "System"
  case conflict = "Conflict"
}

class KanataManager: ObservableObject {
  @Published var isRunning = false
  @Published var lastError: String?
  @Published var keyMappings: [KeyMapping] = []
  @Published var diagnostics: [KanataDiagnostic] = []
  @Published var lastProcessExitCode: Int32?
  @Published var lastConfigUpdate: Date = .init()

  private var kanataProcess: Process?
  private let configDirectory = "\(NSHomeDirectory())/Library/Application Support/KeyPath"
  private let configFileName = "keypath.kbd"
  private var isStartingKanata = false
  private var isInitializing = false

  // MARK: - Process Synchronization (Phase 1)

  private static let startupActor = ProcessSynchronizationActor()
  private var lastStartAttempt: Date?
  private let minStartInterval: TimeInterval = 2.0

  // Real-time log monitoring for VirtualHID connection failures
  private var logMonitorTask: Task<Void, Never>?
  private var connectionFailureCount = 0
  private let maxConnectionFailures = 10  // Trigger recovery after 10 consecutive failures

  var configPath: String {
    "\(configDirectory)/\(configFileName)"
  }

  init() {
    // Dispatch heavy initialization work to background thread
    Task.detached { [weak self] in
      await self?.performInitialization()
    }
  }

  private func performInitialization() async {
    // Prevent concurrent initialization
    if isInitializing {
      AppLogger.shared.log("⚠️ [Init] Already initializing - skipping duplicate initialization")
      return
    }

    isInitializing = true
    defer { isInitializing = false }

    await updateStatus()
    // Try to start Kanata automatically on launch if all requirements are met
    let status = getSystemRequirementsStatus()

    // Check if Kanata is already running before attempting to start
    if isRunning {
      AppLogger.shared.log("✅ [Init] Kanata is already running - skipping initialization")
      return
    }

    // Auto-start kanata if all requirements are met
    AppLogger.shared.log(
      "🔍 [Init] Status: installed=\(status.installed), permissions=\(status.permissions), driver=\(status.driver), daemon=\(status.daemon)"
    )

    if status.installed, status.permissions, status.driver, status.daemon {
      AppLogger.shared.log("✅ [Init] All requirements met - auto-starting Kanata")
      await startKanata()
    } else {
      AppLogger.shared.log("⚠️ [Init] Requirements not met - skipping auto-start")
      if !status.installed { AppLogger.shared.log("  - Missing: Kanata binary") }
      if !status.permissions { AppLogger.shared.log("  - Missing: Required permissions") }
      if !status.driver { AppLogger.shared.log("  - Missing: VirtualHID driver") }
      if !status.daemon { AppLogger.shared.log("  - Missing: VirtualHID daemon") }
    }
  }

  // MARK: - Diagnostics

  func addDiagnostic(_ diagnostic: KanataDiagnostic) {
    diagnostics.append(diagnostic)
    AppLogger.shared.log(
      "\(diagnostic.severity.emoji) [Diagnostic] \(diagnostic.title): \(diagnostic.description)")

    // Keep only last 50 diagnostics to prevent memory bloat
    if diagnostics.count > 50 {
      diagnostics.removeFirst(diagnostics.count - 50)
    }
  }

  func clearDiagnostics() {
    diagnostics.removeAll()
  }

  /// Attempts to recover from zombie keyboard capture when VirtualHID connection fails
  private func attemptKeyboardRecovery() async {
    AppLogger.shared.log("🔧 [Recovery] Starting keyboard recovery process...")

    // Step 1: Ensure all Kanata processes are killed
    AppLogger.shared.log("🔧 [Recovery] Step 1: Killing any remaining Kanata processes")
    await killAllKanataProcesses()

    // Step 2: Wait for system to release keyboard control
    AppLogger.shared.log("🔧 [Recovery] Step 2: Waiting 2 seconds for keyboard release...")
    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

    // Step 3: Restart VirtualHID daemon
    AppLogger.shared.log("🔧 [Recovery] Step 3: Attempting to restart Karabiner daemon...")
    await restartKarabinerDaemon()

    // Step 4: Wait before retry
    AppLogger.shared.log("🔧 [Recovery] Step 4: Waiting 3 seconds before retry...")
    try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds

    // Step 5: Try starting Kanata again with validation
    AppLogger.shared.log(
      "🔧 [Recovery] Step 5: Attempting to restart Kanata with VirtualHID validation...")
    await startKanataWithValidation()

    AppLogger.shared.log("🔧 [Recovery] Keyboard recovery process complete")
  }

  /// Kills all Kanata processes for recovery purposes
  private func killAllKanataProcesses() async {
    let script = """
      do shell script "/usr/bin/pkill -f kanata" with administrator privileges
      """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus == 0 {
        AppLogger.shared.log("🔧 [Recovery] Killed all Kanata processes")
      } else {
        AppLogger.shared.log(
          "⚠️ [Recovery] Failed to kill Kanata processes - exit code: \(task.terminationStatus)")
      }
    } catch {
      AppLogger.shared.log("⚠️ [Recovery] Failed to kill Kanata processes: \(error)")
    }
  }

  /// Restarts the Karabiner VirtualHID daemon to fix connection issues
  private func restartKarabinerDaemon() async {
    // First kill the daemon
    let killScript =
      "do shell script \"/usr/bin/pkill -f Karabiner-VirtualHIDDevice-Daemon\" with administrator privileges with prompt \"KeyPath needs to restart the virtual keyboard daemon.\""

    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    killTask.arguments = ["-e", killScript]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      if killTask.terminationStatus == 0 {
        AppLogger.shared.log("🔧 [Recovery] Killed Karabiner daemon")
      } else {
        AppLogger.shared.log(
          "⚠️ [Recovery] Failed to kill Karabiner daemon - exit code: \(killTask.terminationStatus)")
      }

      // Wait a moment then check if it auto-restarts
      try? await Task.sleep(nanoseconds: 2_000_000_000)

      if !isKarabinerDaemonRunning() {
        AppLogger.shared.log("🔧 [Recovery] Daemon not auto-restarted, attempting manual start...")

        let startScript =
          "do shell script \\\"\\\"/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon\\\" > /dev/null 2>&1 &\\\" with administrator privileges with prompt \\\"KeyPath needs to manually start the virtual keyboard daemon.\\\""

        let startTask = Process()
        startTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        startTask.arguments = ["-e", startScript]

        try? startTask.run()
        AppLogger.shared.log("🔧 [Recovery] Attempted to start Karabiner daemon")
      }
    } catch {
      AppLogger.shared.log("⚠️ [Recovery] Failed to restart Karabiner daemon: \(error)")
    }
  }

  /// Starts Kanata with VirtualHID connection validation
  private func startKanataWithValidation() async {
    // Check if VirtualHID daemon is running first
    if !isKarabinerDaemonRunning() {
      AppLogger.shared.log("⚠️ [Recovery] Karabiner daemon not running - recovery failed")
      await updatePublishedProperties(
        isRunning: isRunning,
        lastProcessExitCode: lastProcessExitCode,
        lastError: "Recovery failed: Karabiner daemon not available"
      )
      return
    }

    // Try starting Kanata normally
    await startKanata()
  }

  func validateConfigFile() -> (isValid: Bool, errors: [String]) {
    guard FileManager.default.fileExists(atPath: configPath) else {
      return (false, ["Config file does not exist at: \(configPath)"])
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: WizardSystemPaths.kanataActiveBinary)
    task.arguments = ["--cfg", configPath, "--check"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var errors: [String] = []

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus != 0 {
        // Parse Kanata error output
        errors = parseKanataErrors(output)
        return (false, errors)
      } else {
        return (true, [])
      }
    } catch {
      return (false, ["Failed to validate config: \(error.localizedDescription)"])
    }
  }

  private func parseKanataErrors(_ output: String) -> [String] {
    var errors: [String] = []
    let lines = output.components(separatedBy: .newlines)

    for line in lines {
      if line.contains("[ERROR]") {
        // Extract the actual error message
        if let errorRange = line.range(of: "[ERROR]") {
          let errorMessage = String(line[errorRange.upperBound...]).trimmingCharacters(
            in: .whitespaces)
          errors.append(errorMessage)
        }
      }
    }

    return errors.isEmpty ? [output] : errors
  }

  func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
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

        // This is the "zombie keyboard capture" bug - automatically attempt recovery
        Task {
          AppLogger.shared.log(
            "🚨 [Recovery] Detected zombie keyboard capture - attempting automatic recovery")
          await self.attemptKeyboardRecovery()
        }
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

    // Add all diagnostics
    for diagnostic in diagnostics {
      addDiagnostic(diagnostic)
    }
  }

  // MARK: - Auto-Fix Capabilities

  func autoFixDiagnostic(_ diagnostic: KanataDiagnostic) async -> Bool {
    guard diagnostic.canAutoFix else { return false }

    switch diagnostic.category {
    case .configuration:
      // Reset to default config
      do {
        try await resetToDefaultConfig()
        AppLogger.shared.log("🔧 [AutoFix] Reset configuration to default")
        return true
      } catch {
        AppLogger.shared.log("❌ [AutoFix] Failed to reset config: \(error)")
        return false
      }

    case .process:
      if diagnostic.title == "Process Terminated" {
        // Try restarting Kanata
        await startKanata()
        AppLogger.shared.log("🔧 [AutoFix] Attempted to restart Kanata")
        return isRunning
      }

    default:
      return false
    }

    return false
  }

  func getSystemDiagnostics() -> [KanataDiagnostic] {
    var diagnostics: [KanataDiagnostic] = []

    // Check Kanata installation
    if !isInstalled() {
      diagnostics.append(
        KanataDiagnostic(
          timestamp: Date(),
          severity: .critical,
          category: .system,
          title: "Kanata Not Installed",
          description: "Kanata binary not found at \(WizardSystemPaths.kanataActiveBinary)",
          technicalDetails: "Expected path: \(WizardSystemPaths.kanataActiveBinary)",
          suggestedAction: "Install Kanata using: brew install kanata",
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
          canAutoFix: true  // We can kill it
        ))
    }

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

  // Check if permission issues should trigger the wizard
  func shouldShowWizardForPermissions() -> Bool {
    return !PermissionService.shared.hasInputMonitoringPermission()
      || !PermissionService.shared.hasAccessibilityPermission()
  }

  // MARK: - Public Interface

  func startKanataIfConfigured() async {
    AppLogger.shared.log("🔍 [StartIfConfigured] Checking if config exists at: \(configPath)")

    // Only start if config file exists and is valid
    if FileManager.default.fileExists(atPath: configPath) {
      AppLogger.shared.log("✅ [StartIfConfigured] Config file exists - starting Kanata")
      await startKanata()
    } else {
      AppLogger.shared.log("⚠️ [StartIfConfigured] Config file does not exist - skipping start")
    }
  }

  func startKanata() async {
    // Trace who is calling startKanata
    AppLogger.shared.log("📞 [Trace] startKanata() called from:")
    for (index, symbol) in Thread.callStackSymbols.prefix(5).enumerated() {
      AppLogger.shared.log("📞 [Trace] [\(index)] \(symbol)")
    }

    // Phase 1: Process synchronization using actor (async-safe)
    return await KanataManager.startupActor.synchronize { [self] in
      await self.performStartKanata()
    }
  }

  /// Start Kanata with automatic safety timeout - stops if no user interaction for 30 seconds
  func startKanataWithSafetyTimeout() async {
    await startKanata()

    // Only start safety timer if Kanata actually started
    if isRunning {
      AppLogger.shared.log("🛡️ [Safety] Starting 30-second safety timeout for Kanata")

      // Start safety timeout in background
      Task.detached { [weak self] in
        // Wait 30 seconds
        try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30 seconds

        // Check if Kanata is still running and stop it
        guard let self = self else { return }

        if await MainActor.run { self.isRunning } {
          AppLogger.shared.log(
            "⚠️ [Safety] 30-second timeout reached - automatically stopping Kanata for safety")
          await self.stopKanata()

          // Show safety notification
          await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Safety Timeout Activated"
            alert.informativeText = """
              KeyPath automatically stopped the keyboard remapping service after 30 seconds as a safety precaution.

              If the service was working correctly, you can restart it from the main app window.

              If you experienced keyboard issues, this timeout prevented them from continuing.
              """
            alert.alertStyle = .informational
            alert.runModal()
          }
        }
      }
    }
  }

  private func performStartKanata() async {
    let startTime = Date()
    AppLogger.shared.log("🚀 [Start] ========== KANATA START ATTEMPT ==========")
    AppLogger.shared.log("🚀 [Start] Time: \(startTime)")
    AppLogger.shared.log("🚀 [Start] Starting Kanata with synchronization lock...")

    // Prevent rapid successive starts
    if let lastAttempt = lastStartAttempt,
      Date().timeIntervalSince(lastAttempt) < minStartInterval
    {
      AppLogger.shared.log("⚠️ [Start] Ignoring rapid start attempt within \(minStartInterval)s")
      return
    }
    lastStartAttempt = Date()

    // Check if already running or starting
    if isRunning || isStartingKanata {
      let currentPID = kanataProcess?.processIdentifier ?? -1
      AppLogger.shared.log("⚠️ [Start] Kanata is already running or starting - skipping start")
      AppLogger.shared.log(
        "⚠️ [Start] Current state: isRunning=\(isRunning), isStartingKanata=\(isStartingKanata), PID=\(currentPID)"
      )
      return
    }

    // Set flag to prevent concurrent starts
    isStartingKanata = true
    defer { isStartingKanata = false }

    // Pre-flight checks
    let validation = validateConfigFile()
    if !validation.isValid {
      let diagnostic = KanataDiagnostic(
        timestamp: Date(),
        severity: .error,
        category: .configuration,
        title: "Invalid Configuration",
        description: "Cannot start Kanata due to configuration errors.",
        technicalDetails: validation.errors.joined(separator: "\n"),
        suggestedAction: "Fix configuration errors or reset to default",
        canAutoFix: true
      )
      addDiagnostic(diagnostic)
      await updatePublishedProperties(
        isRunning: isRunning,
        lastProcessExitCode: lastProcessExitCode,
        lastError: "Configuration Error: \(validation.errors.first ?? "Unknown error")"
      )
      return
    }

    // Check for karabiner_grabber conflict
    if isKarabinerElementsRunning() {
      AppLogger.shared.log("⚠️ [Start] Detected karabiner_grabber running - attempting to kill it")
      let killed = await killKarabinerGrabber()
      if !killed {
        let diagnostic = KanataDiagnostic(
          timestamp: Date(),
          severity: .error,
          category: .conflict,
          title: "Karabiner Grabber Conflict",
          description: "karabiner_grabber is running and preventing Kanata from starting",
          technicalDetails: "This causes 'exclusive access and device already open' errors",
          suggestedAction: "Quit Karabiner-Elements manually",
          canAutoFix: false
        )
        addDiagnostic(diagnostic)
        await updatePublishedProperties(
          isRunning: isRunning,
          lastProcessExitCode: lastProcessExitCode,
          lastError: "Conflict: karabiner_grabber is running"
        )
        return
      }
    }

    // Stop existing process if running
    if let existingProcess = kanataProcess, existingProcess.isRunning {
      AppLogger.shared.log("🛑 [Start] Terminating existing Kanata process...")
      existingProcess.terminate()
      kanataProcess = nil
    }

    // ProcessLifecycleManager now handles conflict resolution - no need for manual cleanup
    AppLogger.shared.log(
      "ℹ️ [Start] ProcessLifecycleManager handles conflict resolution - skipping manual cleanup")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    task.arguments = [
      "-n",  // Non-interactive mode - don't prompt for password
      WizardSystemPaths.kanataActiveBinary, "--cfg", configPath, "--watch", "--debug",
      "--log-layer-changes",
    ]

    // Set environment to ensure proper execution
    task.environment = ProcessInfo.processInfo.environment

    // Capture both stdout and stderr for diagnostics
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    // Also log to file
    let logPath = "\(NSHomeDirectory())/Library/Logs/KeyPath/kanata.log"
    let logDirectory = URL(fileURLWithPath: logPath).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

    do {
      try task.run()
      kanataProcess = task

      // Start real-time log monitoring for VirtualHID connection issues
      startLogMonitoring()

      // Check for other Kanata processes immediately after starting
      Task.detached {
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        let psTask = Process()
        psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
        psTask.arguments = ["aux"]
        let pipe = Pipe()
        psTask.standardOutput = pipe
        try? psTask.run()
        psTask.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let kanataProcesses = output.components(separatedBy: .newlines).filter {
          $0.contains("kanata") && !$0.contains("grep")
        }

        AppLogger.shared.log(
          "🔍 [ProcessCheck] Found \(kanataProcesses.count) Kanata processes after start:")
        for (index, process) in kanataProcesses.enumerated() {
          AppLogger.shared.log("🔍 [ProcessCheck] [\(index)] \(process)")
        }
      }
      // Update state and clear old diagnostics when successfully starting
      await updatePublishedProperties(
        isRunning: true,
        lastProcessExitCode: nil,
        lastError: nil,
        shouldClearDiagnostics: true
      )

      AppLogger.shared.log(
        "✅ [Start] Successfully started Kanata process (PID: \(task.processIdentifier))")
      AppLogger.shared.log("✅ [Start] ========== KANATA START SUCCESS ==========")

      // Monitor process in background
      Task {
        await monitorKanataProcess(task, outputPipe: outputPipe, errorPipe: errorPipe)
      }

    } catch {
      await updatePublishedProperties(
        isRunning: false,
        lastProcessExitCode: lastProcessExitCode,
        lastError: "Failed to start Kanata: \(error.localizedDescription)"
      )
      AppLogger.shared.log("❌ [Start] Failed to start Kanata: \(error.localizedDescription)")

      let diagnostic = KanataDiagnostic(
        timestamp: Date(),
        severity: .error,
        category: .process,
        title: "Process Start Failed",
        description: "Failed to launch Kanata process.",
        technicalDetails: error.localizedDescription,
        suggestedAction: "Check if Kanata is installed and permissions are granted",
        canAutoFix: false
      )
      addDiagnostic(diagnostic)
    }

    await updateStatus()
  }

  private func monitorKanataProcess(_ process: Process, outputPipe: Pipe, errorPipe: Pipe) async {
    AppLogger.shared.log(
      "👁️ [Monitor] Starting process monitoring for PID \(process.processIdentifier)")

    // Monitor output in real-time while process is running
    Task.detached { [weak self] in
      let outputHandle = outputPipe.fileHandleForReading
      let errorHandle = errorPipe.fileHandleForReading

      // Set up async reading for real-time debug output
      outputHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty {
          let output = String(data: data, encoding: .utf8) ?? ""
          AppLogger.shared.log(
            "🔍 [Debug/Output] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
      }

      errorHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty {
          let error = String(data: data, encoding: .utf8) ?? ""
          AppLogger.shared.log(
            "🔍 [Debug/Error] \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
      }
    }

    // Wait for process to exit (this will block until process terminates)
    process.waitUntilExit()

    let exitCode = process.terminationStatus
    AppLogger.shared.log("📊 [Monitor] Kanata process exited with code: \(exitCode)")

    // Capture output and error streams
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let outputString = String(data: outputData, encoding: .utf8) ?? ""
    let errorString = String(data: errorData, encoding: .utf8) ?? ""
    let combinedOutput = "\(outputString)\n\(errorString)".trimmingCharacters(
      in: .whitespacesAndNewlines)

    AppLogger.shared.log("📋 [Monitor] Process output: \(combinedOutput)")

    // Update state
    if kanataProcess?.processIdentifier == process.processIdentifier {
      kanataProcess = nil
    }

    // Diagnose the failure if it wasn't a normal shutdown
    let errorMessage: String?
    if exitCode != 0, exitCode != -15 {  // -15 is SIGTERM (normal shutdown)
      diagnoseKanataFailure(exitCode, combinedOutput)
      errorMessage = "Kanata exited with code \(exitCode)"
    } else {
      errorMessage = nil
    }

    await updatePublishedProperties(
      isRunning: false,
      lastProcessExitCode: exitCode,
      lastError: errorMessage
    )

    // Update status after process exits
    await updateStatus()
  }

  func stopKanata() async {
    AppLogger.shared.log("🛑 [Stop] Stopping Kanata process...")

    if let process = kanataProcess, process.isRunning {
      process.terminate()
      // Wait a moment for graceful termination
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

      // Force kill if still running
      if process.isRunning {
        process.interrupt()
      }

      kanataProcess = nil
      AppLogger.shared.log("✅ [Stop] Successfully stopped Kanata process")
    } else {
      AppLogger.shared.log("ℹ️ [Stop] No Kanata process to stop")
    }

    // Stop log monitoring when Kanata stops
    stopLogMonitoring()

    await updatePublishedProperties(
      isRunning: false,
      lastProcessExitCode: lastProcessExitCode,
      lastError: nil
    )
    await updateStatus()
  }

  func restartKanata() async {
    AppLogger.shared.log("🔄 [Restart] Restarting Kanata...")
    await stopKanata()
    await startKanata()
  }

  func saveConfiguration(input: String, output: String) async throws {
    // Parse existing mappings from config file
    loadExistingMappings()

    // Create new mapping
    let newMapping = KeyMapping(input: input, output: output)

    // Remove any existing mapping with the same input
    keyMappings.removeAll { $0.input == input }

    // Add the new mapping
    keyMappings.append(newMapping)

    // Generate config with all mappings
    let config = generateKanataConfigWithMappings(keyMappings)

    // Validate the generated config before saving
    let validation = await validateGeneratedConfig(config)
    if !validation.isValid {
      AppLogger.shared.log(
        "❌ [Config] Generated config is invalid: \(validation.errors.joined(separator: ", "))")

      // Attempt Claude-powered recovery
      do {
        let repairedConfig = try await repairConfigWithClaude(
          config: config, errors: validation.errors, mappings: keyMappings
        )
        let repairedValidation = await validateGeneratedConfig(repairedConfig)

        if repairedValidation.isValid {
          AppLogger.shared.log("✅ [Config] Claude successfully repaired the config")
          try await saveValidatedConfig(repairedConfig)
          return
        } else {
          AppLogger.shared.log("❌ [Config] Claude repair failed, prompting user for action")
          throw ConfigError.repairFailedNeedsUserAction(
            originalConfig: config,
            repairedConfig: repairedConfig,
            originalErrors: validation.errors,
            repairErrors: repairedValidation.errors,
            mappings: keyMappings
          )
        }
      } catch {
        AppLogger.shared.log("❌ [Config] Claude repair failed: \(error)")
        throw ConfigError.repairFailedNeedsUserAction(
          originalConfig: config,
          repairedConfig: nil,
          originalErrors: validation.errors,
          repairErrors: [error.localizedDescription],
          mappings: keyMappings
        )
      }
    }

    // Config is valid, save it
    try await saveValidatedConfig(config)

    AppLogger.shared.log(
      "💾 [Config] Configuration saved with \(keyMappings.count) mappings to \(configPath)")
    AppLogger.shared.log("🔄 [Config] Hot reload via --watch should apply changes automatically")

    // Fallback: If changes are not applied quickly, perform a one-shot restart
    // This mitigates the macOS-specific file watching issue documented in WATCHBUG.md
    Task.detached { [weak self] in
      guard let self = self else { return }
      // Small grace period for --watch to pick up changes
      try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
      // Heuristic: if still running, force a lightweight restart to ensure new config is active
      if await MainActor.run({ self.isRunning }) {
        AppLogger.shared.log("🔄 [Config] Fallback restart to ensure config changes apply")
        await self.restartKanata()
      }
    }
  }

  func updateStatus() async {
    // Synchronize status updates to prevent concurrent access to @Published properties
    return await KanataManager.startupActor.synchronize { [self] in
      await self.performUpdateStatus()
    }
  }

  /// Main actor function to safely update all @Published properties
  @MainActor
  private func updatePublishedProperties(
    isRunning: Bool,
    lastProcessExitCode: Int32?,
    lastError: String?,
    shouldClearDiagnostics: Bool = false
  ) {
    self.isRunning = isRunning
    self.lastProcessExitCode = lastProcessExitCode
    self.lastError = lastError

    if shouldClearDiagnostics {
      let initialCount = diagnostics.count

      // Remove diagnostics related to process failures and permission issues
      // Keep configuration-related diagnostics as they may still be relevant
      diagnostics.removeAll { diagnostic in
        diagnostic.category == .process || diagnostic.category == .permissions
          || (diagnostic.category == .conflict && diagnostic.title.contains("Exit"))
      }

      let removedCount = initialCount - diagnostics.count
      if removedCount > 0 {
        AppLogger.shared.log(
          "🔄 [Diagnostics] Cleared \(removedCount) stale process/permission diagnostics")
      }
    }
  }

  private func performUpdateStatus() async {
    // Check if our process is still running
    if let process = kanataProcess {
      let processRunning = process.isRunning
      if isRunning != processRunning {
        AppLogger.shared.log("⚠️ [Status] Process state changed: \(processRunning)")
        await updatePublishedProperties(
          isRunning: processRunning,
          lastProcessExitCode: lastProcessExitCode,
          lastError: lastError
        )
        if !processRunning {
          kanataProcess = nil
        }
      }
    } else {
      // No process tracked, check if any kanata is running externally
      let externalRunning = await checkExternalKanataProcess()
      if isRunning != externalRunning {
        AppLogger.shared.log("⚠️ [Status] External kanata process detected: \(externalRunning)")

        // Clear exit code, error message, and stale diagnostics when we detect external process is running
        // This prevents showing stale information for currently running processes
        if externalRunning {
          await updatePublishedProperties(
            isRunning: externalRunning,
            lastProcessExitCode: nil,
            lastError: nil,
            shouldClearDiagnostics: true
          )
          AppLogger.shared.log(
            "🔄 [Status] Cleared stale exit code, error, and diagnostics - external process is running"
          )
        } else {
          await updatePublishedProperties(
            isRunning: externalRunning,
            lastProcessExitCode: lastProcessExitCode,
            lastError: lastError
          )
        }
      }
    }
  }

  /// Stop Kanata when the app is terminating.
  func cleanup() async {
    await stopKanata()
  }

  private func checkExternalKanataProcess() async -> Bool {
    // Use more specific search for actual kanata binary processes
    // instead of any process with "kanata" in command line (which can match KeyPath's own processes)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    // Look for processes where the executable name is kanata, not just command lines containing kanata
    task.arguments = ["-x", "kanata"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      let isRunning = !trimmed.isEmpty

      // Debug logging removed - fix confirmed working

      return isRunning
    } catch {
      AppLogger.shared.log(
        "🔍 [KanataManager] checkExternalKanataProcess() - pgrep failed: \(error)")
      return false
    }
  }

  // MARK: - Installation and Permissions

  func isInstalled() -> Bool {
    let kanataPath = WizardSystemPaths.kanataActiveBinary
    return FileManager.default.fileExists(atPath: kanataPath)
  }

  func isCompletelyInstalled() -> Bool {
    return isInstalled()
  }

  // REMOVED: hasInputMonitoringPermission() - now handled by PermissionService

  // REMOVED: hasAccessibilityPermission() - now handled by PermissionService

  // REMOVED: checkAccessibilityForPath() - now handled by PermissionService.checkTCCForAccessibility()

  // REMOVED: checkTCCForAccessibility() - now handled by PermissionService

  func checkBothAppsHavePermissions() -> (
    keyPathHasPermission: Bool, kanataHasPermission: Bool, permissionDetails: String
  ) {
    let keyPathPath = Bundle.main.bundlePath
    let kanataPath = WizardSystemPaths.kanataActiveBinary

    let keyPathHasInputMonitoring = PermissionService.shared.hasInputMonitoringPermission()
    let keyPathHasAccessibility = PermissionService.shared.hasAccessibilityPermission()

    let kanataHasInputMonitoring = PermissionService.shared.checkTCCForInputMonitoring(
      path: kanataPath)
    let kanataHasAccessibility = PermissionService.shared.checkTCCForAccessibility(path: kanataPath)

    let keyPathOverall = keyPathHasInputMonitoring && keyPathHasAccessibility
    let kanataOverall = kanataHasInputMonitoring && kanataHasAccessibility

    let details = """
      KeyPath.app (\(keyPathPath)):
      - Input Monitoring: \(keyPathHasInputMonitoring ? "✅" : "❌")
      - Accessibility: \(keyPathHasAccessibility ? "✅" : "❌")

      kanata (\(kanataPath)):
      - Input Monitoring: \(kanataHasInputMonitoring ? "✅" : "❌")
      - Accessibility: \(kanataHasAccessibility ? "✅" : "❌")
      """

    return (keyPathOverall, kanataOverall, details)
  }

  // REMOVED: checkTCCForInputMonitoring() - now handled by PermissionService

  func hasAllRequiredPermissions() -> Bool {
    return PermissionService.shared.hasInputMonitoringPermission()
      && PermissionService.shared.hasAccessibilityPermission()
  }

  func hasAllSystemRequirements() -> Bool {
    return isInstalled() && hasAllRequiredPermissions() && isKarabinerDriverInstalled()
      && isKarabinerDaemonRunning()
  }

  func getSystemRequirementsStatus() -> (
    installed: Bool, permissions: Bool, driver: Bool, daemon: Bool
  ) {
    return (
      installed: isInstalled(),
      permissions: hasAllRequiredPermissions(),
      driver: isKarabinerDriverInstalled(),
      daemon: isKarabinerDaemonRunning()
    )
  }

  func openInputMonitoringSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    {
      NSWorkspace.shared.open(url)
    }
  }

  func openAccessibilitySettings() {
    if #available(macOS 13.0, *) {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    } else {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      } else {
        NSWorkspace.shared.open(
          URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
      }
    }
  }

  func isKarabinerDriverInstalled() -> Bool {
    // Check if Karabiner VirtualHID driver is installed
    let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    return FileManager.default.fileExists(atPath: driverPath)
  }

  func isKarabinerDriverExtensionEnabled() -> Bool {
    // Check if the Karabiner driver extension is actually enabled in the system
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
    task.arguments = ["list"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      // Look for Karabiner driver with [activated enabled] status
      let lines = output.components(separatedBy: .newlines)
      for line in lines {
        if line.contains("org.pqrs.Karabiner-DriverKit-VirtualHIDDevice")
          && line.contains("[activated enabled]")
        {
          AppLogger.shared.log("✅ [Driver] Karabiner driver extension is enabled")
          return true
        }
      }

      AppLogger.shared.log("⚠️ [Driver] Karabiner driver extension not enabled or not found")
      AppLogger.shared.log("⚠️ [Driver] systemextensionsctl output:\n\(output)")
      return false
    } catch {
      AppLogger.shared.log("❌ [Driver] Error checking driver extension status: \(error)")
      return false
    }
  }

  func areKarabinerBackgroundServicesEnabled() -> Bool {
    // Check if Karabiner background services are enabled in Login Items
    // This is harder to check programmatically on modern macOS
    // We'll check if the services are actually running as a proxy
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["list"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      // Check for Karabiner services in the user's launchctl list
      // Look for the actual service patterns that are created by Login Items
      let hasServices = output.contains("org.pqrs.service.agent.karabiner")

      if hasServices {
        AppLogger.shared.log("✅ [Services] Karabiner background services detected")
      } else {
        AppLogger.shared.log(
          "⚠️ [Services] Karabiner background services not found - may not be enabled in Login Items"
        )
      }

      return hasServices
    } catch {
      AppLogger.shared.log("❌ [Services] Error checking background services: \(error)")
      return false
    }
  }

  func isKarabinerElementsRunning() -> Bool {
    // First check if we've permanently disabled the grabber
    let markerPath = "\(NSHomeDirectory())/.keypath/karabiner-grabber-disabled"
    if FileManager.default.fileExists(atPath: markerPath) {
      AppLogger.shared.log(
        "ℹ️ [Conflict] karabiner_grabber permanently disabled by KeyPath - skipping conflict check")
      return false
    }

    // Check if Karabiner-Elements grabber is running (conflicts with Kanata)
    // We check more broadly for karabiner_grabber process
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "karabiner_grabber"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let isRunning = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

      if isRunning {
        AppLogger.shared.log(
          "⚠️ [Conflict] karabiner_grabber is running - will conflict with Kanata")
        AppLogger.shared.log(
          "⚠️ [Conflict] This causes 'exclusive access' errors when starting Kanata")
      } else {
        AppLogger.shared.log("✅ [Conflict] No karabiner_grabber detected")
      }

      return isRunning
    } catch {
      AppLogger.shared.log("❌ [Conflict] Error checking karabiner_grabber: \(error)")
      return false
    }
  }

  func getKillKarabinerCommand() -> String {
    return """
      sudo launchctl unload /Library/LaunchDaemons/org.pqrs.karabiner.karabiner_grabber.plist
      sudo pkill -f karabiner_grabber
      """
  }

  /// Permanently disable all Karabiner Elements services with user permission
  func disableKarabinerElementsPermanently() async -> Bool {
    AppLogger.shared.log("🔧 [Karabiner] Starting permanent disable of Karabiner Elements services")

    // Ask user for permission first
    let userConsented = await requestPermissionToDisableKarabiner()
    guard userConsented else {
      AppLogger.shared.log("❌ [Karabiner] User declined permission to disable Karabiner Elements")
      return false
    }

    // Get the disable script
    let script = getDisableKarabinerElementsScript()

    // Execute with elevated privileges
    return await executeScriptWithSudo(
      script: script, description: "Disable Karabiner Elements Services"
    )
  }

  /// Request user permission to disable Karabiner Elements
  private func requestPermissionToDisableKarabiner() async -> Bool {
    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Disable Karabiner Elements?"
        alert.informativeText = """
          Karabiner Elements is conflicting with Kanata.

          Disable the conflicting services to allow KeyPath to work?

          Note: Event Viewer and other Karabiner apps will continue working.
          """
        alert.addButton(withTitle: "Disable Conflicting Services")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        continuation.resume(returning: response == .alertFirstButtonReturn)
      }
    }
  }

  /// Generate script to disable only conflicting Karabiner Elements services
  private func getDisableKarabinerElementsScript() -> String {
    return """
      #!/bin/bash

      echo "🔧 Permanently disabling conflicting Karabiner Elements services..."
      echo "ℹ️  Keeping Event Viewer and menu apps working"

      # Kill conflicting processes - karabiner_grabber and VirtualHIDDevice
      echo "Stopping conflicting processes..."
      pkill -f "karabiner_grabber" 2>/dev/null || true
      pkill -f "VirtualHIDDevice" 2>/dev/null || true
      echo "  ✓ Stopped karabiner_grabber and VirtualHIDDevice processes"

      echo "ℹ️  Keeping other Karabiner services running (they don't conflict)"
      echo "ℹ️  - karabiner_console_user_server: provides configuration interface"
      echo "ℹ️  - karabiner_session_monitor: monitors session changes"

      # Step 1: Disable and unload all conflicting services
      echo "Disabling conflicting Karabiner services permanently..."

      # Disable karabiner_grabber services
      launchctl disable gui/$(id -u)/org.pqrs.service.agent.karabiner_grabber 2>/dev/null || true
      launchctl bootout gui/$(id -u) org.pqrs.service.agent.karabiner_grabber 2>/dev/null || true
      launchctl disable system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
      launchctl bootout system/org.pqrs.service.daemon.karabiner_grabber 2>/dev/null || true
      launchctl disable gui/$(id -u)/org.pqrs.Karabiner-Elements.karabiner_grabber 2>/dev/null || true
      launchctl bootout gui/$(id -u) org.pqrs.Karabiner-Elements.karabiner_grabber 2>/dev/null || true

      # Disable VirtualHIDDevice services
      launchctl disable gui/$(id -u)/org.pqrs.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
      launchctl bootout gui/$(id -u) org.pqrs.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null || true
      launchctl disable system/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice 2>/dev/null || true
      launchctl bootout system/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice 2>/dev/null || true

      echo "  ✓ Disabled and unloaded conflicting Karabiner services"

      # Step 2: Find and disable ALL conflicting Karabiner plist files
      echo "Disabling conflicting Karabiner plist files permanently..."

      # Common locations for Karabiner plist files
      PLIST_LOCATIONS=(
          "$HOME/Library/LaunchAgents"
          "/Library/LaunchAgents"
          "/Library/LaunchDaemons"
          "/System/Library/LaunchAgents"
          "/System/Library/LaunchDaemons"
      )

      for location in "${PLIST_LOCATIONS[@]}"; do
          if [ -d "$location" ]; then
              # Disable karabiner_grabber plists
              find "$location" -name "*karabiner*grabber*.plist" 2>/dev/null | while read plist; do
                  if [ -f "$plist" ]; then
                      echo "  📦 Backing up and disabling: $plist"
                      cp "$plist" "$plist.keypath-backup" 2>/dev/null || true
                      mv "$plist" "$plist.keypath-disabled" 2>/dev/null || true
                  fi
              done

              # Disable VirtualHIDDevice plists
              find "$location" -name "*VirtualHIDDevice*.plist" 2>/dev/null | while read plist; do
                  if [ -f "$plist" ]; then
                      echo "  📦 Backing up and disabling: $plist"
                      cp "$plist" "$plist.keypath-backup" 2>/dev/null || true
                      mv "$plist" "$plist.keypath-disabled" 2>/dev/null || true
                  fi
              done
          fi
      done

      # Step 3: Create a marker file to prevent automatic restart
      echo "Creating permanent disable marker..."
      mkdir -p "$HOME/.keypath"
      echo "$(date): Karabiner conflicts permanently disabled by KeyPath" > "$HOME/.keypath/karabiner-conflicts-disabled"
      echo "  ✓ Created disable marker at ~/.keypath/karabiner-conflicts-disabled"

      # Step 4: Kill any remaining conflicting processes more aggressively
      echo "Final cleanup of any remaining conflicting processes..."
      pkill -9 -f "karabiner_grabber" 2>/dev/null || true
      pkill -9 -f "VirtualHIDDevice" 2>/dev/null || true
      sleep 1

      echo "ℹ️  All Karabiner menu apps and other services remain running"
      echo "ℹ️  Only conflicting services (karabiner_grabber + VirtualHIDDevice) have been permanently disabled"

      # Step 5: Comprehensive verification
      echo ""
      echo "🔍 Verifying permanent karabiner_grabber removal..."
      sleep 2  # Give processes time to fully terminate

      GRABBER_FOUND=false

      # Check for running processes
      if pgrep -f "karabiner_grabber" > /dev/null 2>&1; then
          echo "❌ VERIFICATION FAILED: karabiner_grabber process is still running"
          GRABBER_FOUND=true
      fi

      # Check for enabled services
      if launchctl print gui/$(id -u)/org.pqrs.service.agent.karabiner_grabber 2>/dev/null | grep -q "state = running"; then
          echo "❌ VERIFICATION FAILED: karabiner_grabber service is still enabled"
          GRABBER_FOUND=true
      fi

      # Check for active plist files
      for location in "${PLIST_LOCATIONS[@]}"; do
          if [ -d "$location" ]; then
              if find "$location" -name "*karabiner*grabber*.plist" 2>/dev/null | grep -q "\\.plist$"; then
                  echo "❌ VERIFICATION FAILED: Active karabiner_grabber plist files still exist"
                  GRABBER_FOUND=true
                  break
              fi
          fi
      done

      if [ "$GRABBER_FOUND" = false ]; then
          echo "✅ VERIFICATION SUCCESSFUL: karabiner_grabber permanently disabled"
          echo "✅ Conflicts resolved - Kanata can now run without interference"
          echo "✅ Changes will persist across reboots and app restarts"
      else
          echo "⚠️  VERIFICATION INCOMPLETE: Some karabiner_grabber components may still be active"
          echo "   This may cause conflicts to reappear after restart"
      fi

      # Step 6: Show what's still running (for user awareness)
      echo ""
      echo "📊 Remaining Karabiner processes (these are OK and don't conflict):"
      pgrep -f "karabiner" | grep -v "karabiner_grabber" | while read pid; do
          ps -p "$pid" -o pid,comm 2>/dev/null | tail -n +2 || true
      done

      echo ""
      echo "🎉 Permanent disable complete!"
      echo "   Restart your system to test persistence."
      """
  }

  /// Execute a script with sudo privileges using osascript
  private func executeScriptWithSudo(script: String, description: String) async -> Bool {
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        // Create temporary script file
        let tempDir = NSTemporaryDirectory()
        let scriptPath = "\(tempDir)disable_karabiner_\(UUID().uuidString).sh"

        do {
          // Write script to temporary file
          try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

          // Make script executable
          let chmodTask = Process()
          chmodTask.executableURL = URL(fileURLWithPath: "/bin/chmod")
          chmodTask.arguments = ["+x", scriptPath]
          try chmodTask.run()
          chmodTask.waitUntilExit()

          // Execute script with sudo using osascript for password prompt
          let osascriptCommand = """
            do shell script "\(scriptPath)" with administrator privileges with prompt "KeyPath needs to \(description.lowercased()) to fix keyboard conflicts."
            """

          let osascriptTask = Process()
          osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
          osascriptTask.arguments = ["-e", osascriptCommand]

          let pipe = Pipe()
          osascriptTask.standardOutput = pipe
          osascriptTask.standardError = pipe

          try osascriptTask.run()
          osascriptTask.waitUntilExit()

          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          let output = String(data: data, encoding: .utf8) ?? ""

          // Clean up temporary file
          try? FileManager.default.removeItem(atPath: scriptPath)

          if osascriptTask.terminationStatus == 0 {
            AppLogger.shared.log("✅ [Karabiner] Successfully disabled Karabiner Elements services")
            AppLogger.shared.log("📝 [Karabiner] Output: \(output)")

            // Perform additional verification from Swift side
            Task {
              try? await Task.sleep(nanoseconds: 1_000_000_000)  // Wait 1 second
              await self.verifyKarabinerGrabberRemoval()
            }

            continuation.resume(returning: true)
          } else {
            AppLogger.shared.log("❌ [Karabiner] Failed to disable Karabiner Elements services")
            AppLogger.shared.log("📝 [Karabiner] Error output: \(output)")
            continuation.resume(returning: false)
          }

        } catch {
          AppLogger.shared.log("❌ [Karabiner] Error executing disable script: \(error)")
          // Clean up temporary file
          try? FileManager.default.removeItem(atPath: scriptPath)
          continuation.resume(returning: false)
        }
      }
    }
  }

  /// Verify that karabiner_grabber has been successfully removed
  private func verifyKarabinerGrabberRemoval() async {
    AppLogger.shared.log("🔍 [Karabiner] Performing post-disable verification...")

    // Check if process is still running
    let isStillRunning = isKarabinerElementsRunning()
    if isStillRunning {
      AppLogger.shared.log(
        "⚠️ [Karabiner] WARNING: karabiner_grabber still detected after disable attempt")
      AppLogger.shared.log("⚠️ [Karabiner] This may cause conflicts with Kanata")
    } else {
      AppLogger.shared.log("✅ [Karabiner] VERIFIED: karabiner_grabber successfully removed")
    }

    // Check if service is still in launchctl list
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["list"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if output.contains("org.pqrs.service.agent.karabiner_grabber") {
        AppLogger.shared.log(
          "⚠️ [Karabiner] WARNING: karabiner_grabber service still in launchctl list")
        AppLogger.shared.log("⚠️ [Karabiner] Service may restart on next login")
      } else {
        AppLogger.shared.log(
          "✅ [Karabiner] VERIFIED: karabiner_grabber service successfully unloaded")
      }
    } catch {
      AppLogger.shared.log("❌ [Karabiner] Error checking launchctl status: \(error)")
    }
  }

  func killKarabinerGrabber() async -> Bool {
    AppLogger.shared.log("🔧 [Conflict] Attempting to stop Karabiner conflicting services")

    // Enhanced to handle both old karabiner_grabber and new VirtualHIDDevice processes
    // We need to stop LaunchDaemon services and kill running processes

    let stopScript = """
      # Stop old Karabiner Elements system LaunchDaemon (runs as root)
      launchctl bootout system "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons.app/Contents/Library/LaunchDaemons/org.pqrs.service.daemon.karabiner_grabber.plist" 2>/dev/null || true

      # Stop old Karabiner Elements user LaunchAgent
      launchctl bootout gui/$(id -u) "/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents.app/Contents/Library/LaunchAgents/org.pqrs.service.agent.karabiner_grabber.plist" 2>/dev/null || true

      # Kill old karabiner_grabber processes
      pkill -f karabiner_grabber 2>/dev/null || true

      # Kill VirtualHIDDevice processes that conflict with Kanata
      pkill -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
      pkill -f "Karabiner-DriverKit-VirtualHIDDevice" 2>/dev/null || true

      # Wait for processes to terminate
      sleep 2

      # Final cleanup - force kill any stubborn processes
      pkill -9 -f karabiner_grabber 2>/dev/null || true
      pkill -9 -f "Karabiner-VirtualHIDDevice-Daemon" 2>/dev/null || true
      pkill -9 -f "Karabiner-DriverKit-VirtualHIDDevice" 2>/dev/null || true
      """

    let stopTask = Process()
    stopTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    stopTask.arguments = [
      "-e",
      "do shell script \"\(stopScript)\" with administrator privileges with prompt \"KeyPath needs to stop conflicting keyboard services.\"",
    ]

    do {
      try stopTask.run()
      stopTask.waitUntilExit()
      AppLogger.shared.log("🔧 [Conflict] Attempted to stop all Karabiner grabber services")

      // Wait a moment for cleanup
      try await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds

      // Verify no conflicting processes are still running
      let success = await verifyConflictingProcessesStopped()

      if success {
        AppLogger.shared.log(
          "✅ [Conflict] All conflicting Karabiner processes successfully stopped")
      } else {
        AppLogger.shared.log("⚠️ [Conflict] Some conflicting processes may still be running")
      }

      return success

    } catch {
      AppLogger.shared.log("❌ [Conflict] Failed to stop Karabiner grabber: \(error)")
      return false
    }
  }

  /// Verify that all conflicting processes have been stopped
  private func verifyConflictingProcessesStopped() async -> Bool {
    AppLogger.shared.log("🔍 [Conflict] Verifying conflicting processes have been stopped")

    // Check for old karabiner_grabber processes
    let grabberCheck = await checkProcessStopped(
      pattern: "karabiner_grabber", processName: "karabiner_grabber"
    )

    // Check for VirtualHIDDevice processes
    let vhidDaemonCheck = await checkProcessStopped(
      pattern: "Karabiner-VirtualHIDDevice-Daemon", processName: "VirtualHIDDevice Daemon"
    )
    let vhidDriverCheck = await checkProcessStopped(
      pattern: "Karabiner-DriverKit-VirtualHIDDevice", processName: "VirtualHIDDevice Driver"
    )

    let allStopped = grabberCheck && vhidDaemonCheck && vhidDriverCheck

    if allStopped {
      AppLogger.shared.log("✅ [Conflict] Verification complete: No conflicting processes running")
    } else {
      AppLogger.shared.log("⚠️ [Conflict] Verification failed: Some processes still running")
    }

    return allStopped
  }

  /// Check if a specific process pattern is stopped
  private func checkProcessStopped(pattern: String, processName: String) async -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", pattern]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let isStopped = task.terminationStatus != 0  // pgrep returns 1 if no processes found

      if isStopped {
        AppLogger.shared.log("✅ [Conflict] \(processName) successfully stopped")
      } else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        AppLogger.shared.log(
          "⚠️ [Conflict] \(processName) still running: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
      }

      return isStopped
    } catch {
      AppLogger.shared.log("❌ [Conflict] Error checking \(processName): \(error)")
      return false  // Assume process is still running if we can't check
    }
  }

  func isKarabinerDaemonRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "VirtualHIDDevice-Daemon"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let isRunning = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

      AppLogger.shared.log("🔍 [Daemon] Karabiner VirtualHIDDevice-Daemon running: \(isRunning)")
      return isRunning
    } catch {
      AppLogger.shared.log("❌ [Daemon] Error checking VirtualHIDDevice-Daemon: \(error)")
      return false
    }
  }

  func startKarabinerDaemon() async -> Bool {
    let daemonPath =
      "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"

    guard FileManager.default.fileExists(atPath: daemonPath) else {
      AppLogger.shared.log("❌ [Daemon] VirtualHIDDevice-Daemon not found at \(daemonPath)")
      return false
    }

    // First try to start without admin privileges (if directories are prepared)
    AppLogger.shared.log("🔄 [Daemon] Attempting to start daemon without admin privileges...")
    let userTask = Process()
    userTask.executableURL = URL(fileURLWithPath: daemonPath)

    // Redirect output to capture any errors
    let userPipe = Pipe()
    userTask.standardOutput = userPipe
    userTask.standardError = userPipe

    do {
      try userTask.run()

      // Give it a moment to start
      try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

      if isKarabinerDaemonRunning() {
        AppLogger.shared.log("✅ [Daemon] Successfully started daemon without admin privileges")
        return true
      } else {
        // Check if it failed due to permissions
        userTask.terminate()
        let userData = userPipe.fileHandleForReading.readDataToEndOfFile()
        let userOutput = String(data: userData, encoding: .utf8) ?? ""
        AppLogger.shared.log(
          "⚠️ [Daemon] User-mode start failed, trying with admin privileges. Error: \(userOutput)")
      }
    } catch {
      AppLogger.shared.log(
        "⚠️ [Daemon] User-mode start failed: \(error), trying with admin privileges")
    }

    // Fallback: Use admin privileges via AppleScript
    AppLogger.shared.log("🔄 [Daemon] Starting daemon with admin privileges...")
    let adminScript =
      "do shell script \"\(daemonPath) > /dev/null 2>&1 &\" with administrator privileges with prompt \"KeyPath needs to start the virtual keyboard daemon.\""

    let adminTask = Process()
    adminTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    adminTask.arguments = ["-e", adminScript]

    let adminPipe = Pipe()
    adminTask.standardOutput = adminPipe
    adminTask.standardError = adminPipe

    do {
      try adminTask.run()
      adminTask.waitUntilExit()

      if adminTask.terminationStatus == 0 {
        AppLogger.shared.log("✅ [Daemon] Started daemon with admin privileges")

        // Give it a moment to start
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        return isKarabinerDaemonRunning()
      } else {
        let adminData = adminPipe.fileHandleForReading.readDataToEndOfFile()
        let adminOutput = String(data: adminData, encoding: .utf8) ?? ""
        AppLogger.shared.log("❌ [Daemon] Failed to start with admin privileges: \(adminOutput)")
        return false
      }
    } catch {
      AppLogger.shared.log("❌ [Daemon] Failed to start VirtualHIDDevice-Daemon: \(error)")
      return false
    }
  }

  func performTransparentInstallation() async -> Bool {
    AppLogger.shared.log("🔧 [Installation] Starting transparent installation...")

    // 1. Ensure Kanata binary exists
    let kanataBinaryPath = WizardSystemPaths.kanataActiveBinary
    if !FileManager.default.fileExists(atPath: kanataBinaryPath) {
      AppLogger.shared.log("❌ [Installation] Kanata binary not found at \(kanataBinaryPath)")
      AppLogger.shared.log("ℹ️ [Installation] Please install Kanata: brew install kanata")
      return false
    }

    AppLogger.shared.log("✅ [Installation] Kanata binary verified at \(kanataBinaryPath)")

    // 2. Check if Karabiner driver is installed
    let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    if !FileManager.default.fileExists(atPath: driverPath) {
      AppLogger.shared.log("⚠️ [Installation] Karabiner driver not found at \(driverPath)")
      AppLogger.shared.log("ℹ️ [Installation] User should install Karabiner-Elements first")
      // Don't fail installation for this - just warn
    } else {
      AppLogger.shared.log("✅ [Installation] Karabiner driver verified at \(driverPath)")
    }

    // 3. Prepare Karabiner daemon directories
    await prepareDaemonDirectories()

    // 4. Create initial config if needed
    await createInitialConfigIfNeeded()

    AppLogger.shared.log("✅ [Installation] Installation completed successfully")
    return true
  }

  private func createInitialConfigIfNeeded() async {
    // Create config directory if it doesn't exist
    do {
      try FileManager.default.createDirectory(
        atPath: configDirectory, withIntermediateDirectories: true, attributes: nil
      )
      AppLogger.shared.log("✅ [Config] Config directory created at \(configDirectory)")
    } catch {
      AppLogger.shared.log("❌ [Config] Failed to create config directory: \(error)")
      return
    }

    // Create initial config if it doesn't exist
    if !FileManager.default.fileExists(atPath: configPath) {
      let initialConfig = generateKanataConfig(input: "caps", output: "escape")

      do {
        try initialConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
        AppLogger.shared.log("✅ [Config] Initial config created at \(configPath)")
      } catch {
        AppLogger.shared.log("❌ [Config] Failed to create initial config: \(error)")
      }
    }
  }

  private func prepareDaemonDirectories() async {
    AppLogger.shared.log("🔧 [Daemon] Preparing Karabiner daemon directories...")

    // The daemon needs access to /Library/Application Support/org.pqrs/tmp/rootonly
    // We'll create this directory with proper permissions during installation
    let rootOnlyPath = "/Library/Application Support/org.pqrs/tmp/rootonly"
    let tmpPath = "/Library/Application Support/org.pqrs/tmp"

    // Use AppleScript to run commands with admin privileges
    let createDirScript =
      "do shell script \"mkdir -p '\(rootOnlyPath)' && chown -R \(NSUserName()) '\(tmpPath)' && chmod -R 755 '\(tmpPath)'\" with administrator privileges with prompt \"KeyPath needs to prepare system directories for the virtual keyboard.\""

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", createDirScript]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus == 0 {
        AppLogger.shared.log("✅ [Daemon] Successfully prepared daemon directories")

        // Also ensure log directory exists and is accessible
        let logDirScript =
          "do shell script \"mkdir -p '/var/log/karabiner' && chmod 755 '/var/log/karabiner'\" with administrator privileges with prompt \"KeyPath needs to create system log directories.\""

        let logTask = Process()
        logTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        logTask.arguments = ["-e", logDirScript]

        try logTask.run()
        logTask.waitUntilExit()

        if logTask.terminationStatus == 0 {
          AppLogger.shared.log("✅ [Daemon] Log directory permissions set")
        } else {
          AppLogger.shared.log("⚠️ [Daemon] Could not set log directory permissions")
        }
      } else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        AppLogger.shared.log("❌ [Daemon] Failed to prepare directories: \(output)")
      }
    } catch {
      AppLogger.shared.log("❌ [Daemon] Error preparing daemon directories: \(error)")
    }
  }

  // MARK: - Configuration Management

  private func loadExistingMappings() {
    keyMappings.removeAll()

    guard FileManager.default.fileExists(atPath: configPath) else {
      AppLogger.shared.log("ℹ️ [Config] No existing config file found, starting with empty mappings")
      return
    }

    do {
      let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
      keyMappings = parseKanataConfig(configContent)
      AppLogger.shared.log("✅ [Config] Loaded \(keyMappings.count) existing mappings")
    } catch {
      AppLogger.shared.log("❌ [Config] Failed to load existing config: \(error)")
      keyMappings = []
    }
  }

  private func parseKanataConfig(_ configContent: String) -> [KeyMapping] {
    var mappings: [KeyMapping] = []
    let lines = configContent.components(separatedBy: .newlines)

    var inDefsrc = false
    var inDeflayer = false
    var srcKeys: [String] = []
    var layerKeys: [String] = []

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmed.hasPrefix("(defsrc") {
        inDefsrc = true
        inDeflayer = false
        continue
      } else if trimmed.hasPrefix("(deflayer") {
        inDefsrc = false
        inDeflayer = true
        continue
      } else if trimmed == ")" {
        inDefsrc = false
        inDeflayer = false
        continue
      }

      if inDefsrc, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
        srcKeys.append(
          contentsOf: trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
      } else if inDeflayer, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
        layerKeys.append(
          contentsOf: trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
      }
    }

    // Match up src and layer keys
    for (index, srcKey) in srcKeys.enumerated() {
      if index < layerKeys.count {
        mappings.append(KeyMapping(input: srcKey, output: layerKeys[index]))
      }
    }

    AppLogger.shared.log("🔍 [Parse] Found \(srcKeys.count) src keys, \(layerKeys.count) layer keys")
    return mappings
  }

  private func generateKanataConfigWithMappings(_ mappings: [KeyMapping]) -> String {
    guard !mappings.isEmpty else {
      // Return default config with caps->esc if no mappings
      return generateKanataConfig(input: "caps", output: "escape")
    }

    let mappingsList = mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: ", ")
    let srcKeys = mappings.map { convertToKanataKey($0.input) }.joined(separator: " ")
    let layerKeys = mappings.map { convertToKanataSequence($0.output) }.joined(separator: " ")

    return """
      ;; Generated by KeyPath
      ;; Mappings: \(mappingsList)
      ;;
      ;; SAFETY FEATURES:
      ;; - process-unmapped-keys no: Only process explicitly mapped keys

      (defcfg
        process-unmapped-keys no
      )

      (defsrc
        \(srcKeys)
      )

      (deflayer base
        \(layerKeys)
      )
      """
  }

  // MARK: - Methods Expected by Tests

  func generateKanataConfig(input: String, output: String) -> String {
    let inputKey = convertToKanataKey(input)
    let outputKey = convertToKanataSequence(output)

    return """
      ;; Generated by KeyPath
      ;; Input: \(input) -> Output: \(output)
      ;;
      ;; SAFETY FEATURES:
      ;; - process-unmapped-keys no: Only process explicitly mapped keys

      (defcfg
        process-unmapped-keys no
      )

      (defsrc
        \(inputKey)
      )

      (deflayer base
        \(outputKey)
      )
      """
  }

  func isServiceInstalled() -> Bool {
    return true  // No service needed - kanata runs directly
  }

  func getInstallationStatus() -> String {
    let binaryInstalled = isInstalled()
    let driverInstalled = isKarabinerDriverInstalled()

    if binaryInstalled && driverInstalled {
      return "✅ Fully installed"
    } else if !binaryInstalled {
      return "❌ Kanata not installed"
    } else if !driverInstalled {
      return "⚠️ Driver missing"
    } else {
      return "⚠️ Installation incomplete"
    }
  }

  func resetToDefaultConfig() async throws {
    let defaultConfig = generateKanataConfig(input: "caps", output: "escape")
    let configURL = URL(fileURLWithPath: configPath)

    // Ensure config directory exists
    let configDir = URL(fileURLWithPath: configDirectory)
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

    // Write the default config
    try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

    AppLogger.shared.log("💾 [Config] Reset to default configuration")

    // Restart Kanata to apply changes if it's running
    if isRunning {
      await restartKanata()
    }
  }

  func convertToKanataKey(_ key: String) -> String {
    let keyMap: [String: String] = [
      "caps": "caps",
      "capslock": "caps",
      "space": "spc",
      "enter": "ret",
      "return": "ret",
      "tab": "tab",
      "escape": "esc",
      "backspace": "bspc",
      "delete": "del",
      "cmd": "lmet",
      "command": "lmet",
      "lcmd": "lmet",
      "rcmd": "rmet",
      "leftcmd": "lmet",
      "rightcmd": "rmet",
    ]

    let lowercaseKey = key.lowercased()
    return keyMap[lowercaseKey] ?? lowercaseKey
  }

  func convertToKanataSequence(_ sequence: String) -> String {
    // Handle empty sequence
    if sequence.isEmpty {
      AppLogger.shared.log("⚠️ [Convert] Empty sequence provided - returning _")
      return "_"  // Use underscore for unmapped keys in Kanata
    }

    // Try to convert as a single key first (handles multi-character key names like "esc", "caps", etc.)
    let converted = convertToKanataKey(sequence)
    if converted != sequence.lowercased() {
      // Key was found in our mapping table
      return converted
    }

    // Check if it's already a valid kanata key name (like "esc", "ret", "spc", etc.)
    let validKanataKeys = Set([
      "esc", "ret", "tab", "spc", "bspc", "del", "caps", "lsft", "rsft", "lctl", "rctl",
      "lalt", "ralt", "lmet", "rmet", "menu", "ins", "home", "end", "pgup", "pgdn",
      "up", "down", "left", "right", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8",
      "f9", "f10", "f11", "f12", "pause", "pscr", "slck", "nlck",
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
      "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    ])

    if validKanataKeys.contains(sequence.lowercased()) {
      return sequence.lowercased()
    }

    // Handle single characters
    if sequence.count == 1 {
      return convertToKanataKey(sequence)
    }

    // For multi-character sequences that aren't recognized keys,
    // convert character by character (for things like "hello" -> (h e l l o))
    let keys = sequence.map { convertToKanataKey(String($0)) }
    return "(\(keys.joined(separator: " ")))"
  }

  // MARK: - Real-Time VirtualHID Connection Monitoring

  /// Start monitoring Kanata logs for VirtualHID connection failures
  private func startLogMonitoring() {
    // Cancel any existing monitoring
    logMonitorTask?.cancel()

    logMonitorTask = Task.detached { [weak self] in
      guard let self = self else { return }

      let logPath = "/var/log/kanata.log"
      guard FileManager.default.fileExists(atPath: logPath) else {
        AppLogger.shared.log("⚠️ [LogMonitor] Kanata log file not found at \(logPath)")
        return
      }

      AppLogger.shared.log("🔍 [LogMonitor] Starting real-time VirtualHID connection monitoring")

      // Monitor log file for connection failures
      var lastPosition: UInt64 = 0

      while !Task.isCancelled {
        do {
          let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: logPath))
          defer { fileHandle.closeFile() }

          let fileSize = fileHandle.seekToEndOfFile()
          if fileSize > lastPosition {
            fileHandle.seek(toFileOffset: lastPosition)
            let newData = fileHandle.readDataToEndOfFile()
            lastPosition = fileSize

            if let logContent = String(data: newData, encoding: .utf8) {
              await self.analyzeLogContent(logContent)
            }
          }

          // Check every 2 seconds
          try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
          AppLogger.shared.log("⚠️ [LogMonitor] Error reading log file: \(error)")
          try? await Task.sleep(nanoseconds: 5_000_000_000)  // Wait 5 seconds before retry
        }
      }

      AppLogger.shared.log("🔍 [LogMonitor] Stopped log monitoring")
    }
  }

  /// Stop log monitoring
  private func stopLogMonitoring() {
    logMonitorTask?.cancel()
    logMonitorTask = nil
    connectionFailureCount = 0
  }

  /// Analyze new log content for VirtualHID connection issues
  private func analyzeLogContent(_ content: String) async {
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
      if line.contains("connect_failed asio.system:2")
        || line.contains("connect_failed asio.system:61")
      {
        connectionFailureCount += 1
        AppLogger.shared.log(
          "⚠️ [LogMonitor] VirtualHID connection failure detected (\(connectionFailureCount)/\(maxConnectionFailures))"
        )

        if connectionFailureCount >= maxConnectionFailures {
          AppLogger.shared.log(
            "🚨 [LogMonitor] Maximum connection failures reached - triggering recovery")
          await triggerVirtualHIDRecovery()
          connectionFailureCount = 0  // Reset counter after recovery attempt
        }
      } else if line.contains("driver_connected 1") {
        // Reset failure count on successful connection
        if connectionFailureCount > 0 {
          AppLogger.shared.log(
            "✅ [LogMonitor] VirtualHID connection restored - resetting failure count")
          connectionFailureCount = 0
        }
      }
    }
  }

  /// Trigger VirtualHID recovery when connection failures are detected
  private func triggerVirtualHIDRecovery() async {
    AppLogger.shared.log("🚨 [Recovery] VirtualHID connection failure detected in real-time")

    // Create diagnostic for the UI
    let diagnostic = KanataDiagnostic(
      timestamp: Date(),
      severity: .error,
      category: .conflict,
      title: "VirtualHID Connection Failed",
      description:
        "Real-time monitoring detected repeated VirtualHID connection failures. Keyboard remapping is not functioning.",
      technicalDetails:
        "Detected \(connectionFailureCount) consecutive asio.system connection failures",
      suggestedAction:
        "KeyPath will attempt automatic recovery. If issues persist, restart the application.",
      canAutoFix: true
    )

    await MainActor.run {
      addDiagnostic(diagnostic)
    }

    // Attempt automatic recovery
    await attemptKeyboardRecovery()
  }

  // MARK: - Enhanced Config Validation and Recovery

  /// Validates a generated config string using Kanata's --check command
  private func validateGeneratedConfig(_ config: String) async -> (isValid: Bool, errors: [String])
  {
    // Write config to a temporary file for validation
    let tempConfigPath = "\(configDirectory)/temp_validation.kbd"

    do {
      let tempConfigURL = URL(fileURLWithPath: tempConfigPath)
      let configDir = URL(fileURLWithPath: configDirectory)
      try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
      try config.write(to: tempConfigURL, atomically: true, encoding: .utf8)

      // Use kanata --check to validate
      let task = Process()
      task.executableURL = URL(fileURLWithPath: WizardSystemPaths.kanataActiveBinary)
      task.arguments = ["--cfg", tempConfigPath, "--check"]

      let pipe = Pipe()
      task.standardOutput = pipe
      task.standardError = pipe

      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      // Clean up temp file
      try? FileManager.default.removeItem(at: tempConfigURL)

      if task.terminationStatus == 0 {
        return (true, [])
      } else {
        let errors = parseKanataErrors(output)
        return (false, errors)
      }
    } catch {
      // Clean up temp file on error
      try? FileManager.default.removeItem(atPath: tempConfigPath)
      return (false, ["Validation failed: \(error.localizedDescription)"])
    }
  }

  /// Uses Claude to repair a corrupted Kanata config
  private func repairConfigWithClaude(config: String, errors: [String], mappings: [KeyMapping])
    async throws -> String
  {
    // TODO: Integrate with Claude API using the following prompt:
    //
    // "The following Kanata keyboard configuration file is invalid and needs to be repaired:
    //
    // INVALID CONFIG:
    // ```
    // \(config)
    // ```
    //
    // VALIDATION ERRORS:
    // \(errors.joined(separator: "\n"))
    //
    // INTENDED KEY MAPPINGS:
    // \(mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: "\n"))
    //
    // Please generate a corrected Kanata configuration that:
    // 1. Fixes all validation errors
    // 2. Preserves the intended key mappings
    // 3. Uses proper Kanata syntax
    // 4. Includes defcfg with process-unmapped-keys no and danger-enable-cmd yes
    // 5. Has proper defsrc and deflayer sections
    //
    // Return ONLY the corrected configuration file content, no explanations."

    // For now, use rule-based repair as fallback
    return try await performRuleBasedRepair(config: config, errors: errors, mappings: mappings)
  }

  /// Fallback rule-based repair when Claude is not available
  private func performRuleBasedRepair(config: String, errors: [String], mappings: [KeyMapping])
    async throws -> String
  {
    AppLogger.shared.log("🔧 [Config] Performing rule-based repair for \(errors.count) errors")

    // Common repair strategies
    var repairedConfig = config

    for error in errors {
      let lowerError = error.lowercased()

      // Fix common syntax errors
      if lowerError.contains("missing") && lowerError.contains("defcfg") {
        // Add missing defcfg
        if !repairedConfig.contains("(defcfg") {
          let defcfgSection = """
            (defcfg
              process-unmapped-keys no
            )

            """
          repairedConfig = defcfgSection + repairedConfig
        }
      }

      // Fix empty parentheses issues
      if lowerError.contains("()") || lowerError.contains("empty") {
        repairedConfig = repairedConfig.replacingOccurrences(of: "()", with: "_")
        repairedConfig = repairedConfig.replacingOccurrences(of: "( )", with: "_")
      }

      // Fix mismatched defsrc/deflayer lengths
      if lowerError.contains("mismatch") || lowerError.contains("length") {
        // Regenerate from scratch using our proven template
        return generateKanataConfigWithMappings(mappings)
      }
    }

    return repairedConfig
  }

  /// Saves a validated config to disk
  private func saveValidatedConfig(_ config: String) async throws {
    let configDir = URL(fileURLWithPath: configDirectory)
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

    let configURL = URL(fileURLWithPath: configPath)
    try config.write(to: configURL, atomically: true, encoding: .utf8)

    // Notify UI that config was updated
    lastConfigUpdate = Date()
  }

  /// Backs up a failed config and applies safe default, returning backup path
  func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
    -> String
  {
    AppLogger.shared.log("🛡️ [Config] Backing up failed config and applying safe default")

    // Create backup directory if it doesn't exist
    let backupDir = "\(configDirectory)/backups"
    let backupDirURL = URL(fileURLWithPath: backupDir)
    try FileManager.default.createDirectory(at: backupDirURL, withIntermediateDirectories: true)

    // Create timestamped backup filename
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let timestamp = formatter.string(from: Date())

    let backupPath = "\(backupDir)/failed_config_\(timestamp).kbd"
    let backupURL = URL(fileURLWithPath: backupPath)

    // Write the failed config to backup
    let backupContent = """
      ;; FAILED CONFIG - AUTOMATICALLY BACKED UP
      ;; Timestamp: \(timestamp)
      ;; Original mappings: \(mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: ", "))
      ;;
      ;; This configuration failed validation and was automatically backed up.
      ;; You can examine and manually repair this configuration if needed.
      ;;
      ;; Original config follows:

      \(failedConfig)
      """

    try backupContent.write(to: backupURL, atomically: true, encoding: .utf8)
    AppLogger.shared.log("💾 [Config] Failed config backed up to: \(backupPath)")

    // Create and apply safe config
    let safeConfig = generateKanataConfig(input: "caps", output: "escape")
    try await saveValidatedConfig(safeConfig)

    // Update in-memory mappings to reflect the safe state
    keyMappings = [KeyMapping(input: "caps", output: "escape")]

    return backupPath
  }

  /// Opens a file in Zed editor with fallback options
  func openFileInZed(_ filePath: String) {
    // Try to open with Zed first
    let zedProcess = Process()
    zedProcess.launchPath = "/usr/local/bin/zed"
    zedProcess.arguments = [filePath]

    do {
      try zedProcess.run()
      AppLogger.shared.log("📝 [Config] Opened file in Zed: \(filePath)")
      return
    } catch {
      // Try Homebrew path for Zed
      let homebrewZedProcess = Process()
      homebrewZedProcess.launchPath = "/opt/homebrew/bin/zed"
      homebrewZedProcess.arguments = [filePath]

      do {
        try homebrewZedProcess.run()
        AppLogger.shared.log("📝 [Config] Opened file in Zed (Homebrew): \(filePath)")
        return
      } catch {
        // Try using 'open' command with Zed
        let openZedProcess = Process()
        openZedProcess.launchPath = "/usr/bin/open"
        openZedProcess.arguments = ["-a", "Zed", filePath]

        do {
          try openZedProcess.run()
          AppLogger.shared.log("📝 [Config] Opened file in Zed (via open): \(filePath)")
          return
        } catch {
          // Fallback: Try to open with default text editor
          let fallbackProcess = Process()
          fallbackProcess.launchPath = "/usr/bin/open"
          fallbackProcess.arguments = ["-t", filePath]

          do {
            try fallbackProcess.run()
            AppLogger.shared.log("📝 [Config] Opened file in default text editor: \(filePath)")
          } catch {
            // Last resort: Open containing folder
            let folderPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
            NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
            AppLogger.shared.log("📁 [Config] Opened containing folder: \(folderPath)")
          }
        }
      }
    }
  }
}
