import Foundation
import SwiftUI

/// Simple, user-focused Kanata lifecycle manager
/// Replaces the complex 14-state LifecycleStateMachine with 4 clear states
@MainActor
class SimpleKanataManager: ObservableObject {

  // MARK: - Simple State Model

  enum State: String, CaseIterable {
    case starting = "starting"  // App launched, attempting auto-start
    case running = "running"  // Kanata is running successfully
    case needsHelp = "needs_help"  // Auto-start failed, user intervention required
    case stopped = "stopped"  // User manually stopped

    var displayName: String {
      switch self {
      case .starting: return "Starting..."
      case .running: return "Running"
      case .needsHelp: return "Needs Help"
      case .stopped: return "Stopped"
      }
    }

    var isWorking: Bool {
      return self == .running
    }

    var needsUserAction: Bool {
      return self == .needsHelp
    }
  }

  // MARK: - Published Properties

  @Published private(set) var currentState: State = .starting
  @Published private(set) var errorReason: String?
  @Published private(set) var showWizard: Bool = false
  @Published private(set) var autoStartAttempts: Int = 0
  @Published private(set) var lastHealthCheck: Date?
  @Published private(set) var retryCount: Int = 0
  @Published private(set) var isRetryingAfterFix: Bool = false

  // MARK: - Dependencies

  private let kanataManager: KanataManager
  private var healthTimer: Timer?
  private let maxAutoStartAttempts = 2
  private let maxRetryAttempts = 3
  private var lastPermissionState: (input: Bool, accessibility: Bool) = (false, false)

  // MARK: - Initialization

  init(kanataManager: KanataManager) {
    self.kanataManager = kanataManager
    AppLogger.shared.log("🏗️ [SimpleKanataManager] Initialized - starting auto-launch sequence")

    // Initialize permission state
    Task {
      await updatePermissionState()
    }
  }

  // MARK: - Public Interface

  /// Start the automatic Kanata launch sequence
  func startAutoLaunch() async {
    AppLogger.shared.log("🚀 [SimpleKanataManager] ========== AUTO-LAUNCH START ==========")
    currentState = .starting
    errorReason = nil
    showWizard = false
    autoStartAttempts = 0

    await attemptAutoStart()
  }

  /// Manual start requested by user (from wizard)
  func manualStart() async {
    AppLogger.shared.log("👤 [SimpleKanataManager] Manual start requested by user")
    currentState = .starting
    errorReason = nil
    showWizard = false

    await attemptAutoStart()
  }

  /// Manual stop requested by user
  func manualStop() async {
    AppLogger.shared.log("👤 [SimpleKanataManager] Manual stop requested by user")
    stopHealthMonitoring()

    await kanataManager.stopKanata()

    currentState = .stopped
    AppLogger.shared.log("✅ [SimpleKanataManager] Manual stop completed")
  }

  /// Refresh current status
  func refreshStatus() async {
    await kanataManager.updateStatus()

    if kanataManager.isRunning {
      if currentState != .running {
        AppLogger.shared.log("✅ [SimpleKanataManager] Detected Kanata now running")
        currentState = .running
        errorReason = nil
        showWizard = false
        isRetryingAfterFix = false
        retryCount = 0
        startHealthMonitoring()
      }
    } else {
      if currentState == .running {
        AppLogger.shared.log("❌ [SimpleKanataManager] Detected Kanata stopped running")
        await handleServiceFailure("Service stopped unexpectedly")
      } else if currentState == .needsHelp {
        // Check if permissions changed or user might have fixed things
        let permissionChanged = await checkForPermissionChanges()

        if permissionChanged || isRetryingAfterFix {
          AppLogger.shared.log(
            "🔄 [SimpleKanataManager] Permissions changed or retry requested - attempting auto-start"
          )
          await retryAfterFix("Retrying after permission changes...")
        } else {
          AppLogger.shared.log(
            "🔄 [SimpleKanataManager] In needsHelp state - attempting standard retry")
          await attemptAutoStart()
        }
      }
    }

    lastHealthCheck = Date()
  }

  // MARK: - Auto-Start Logic

  private func attemptAutoStart() async {
    autoStartAttempts += 1
    AppLogger.shared.log("🔄 [SimpleKanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) ==========")

    // Check if we're already running
    AppLogger.shared.log("🔄 [SimpleKanataManager] Step 0: Checking if Kanata is already running...")
    await kanataManager.updateStatus()
    if kanataManager.isRunning {
      AppLogger.shared.log("✅ [SimpleKanataManager] Kanata already running - no start needed")
      currentState = .running
      startHealthMonitoring()
      return
    }
    AppLogger.shared.log("🔄 [SimpleKanataManager] Kanata not running, proceeding with start sequence")

    // Step 1: Check Kanata installation
    AppLogger.shared.log("🔄 [SimpleKanataManager] Step 1: Checking Kanata installation...")
    let kanataPath = await findKanataExecutable()
    if kanataPath.isEmpty {
      AppLogger.shared.log("❌ [SimpleKanataManager] Step 1 FAILED: Kanata not found")
      await setNeedsHelp("Kanata not installed. Install with: brew install kanata")
      return
    }
    AppLogger.shared.log("✅ [SimpleKanataManager] Step 1 PASSED: Kanata found at \(kanataPath)")

    // Step 2: Check permissions
    AppLogger.shared.log("🔄 [SimpleKanataManager] Step 2: Checking permissions...")
    if let permissionError = await checkPermissions() {
      AppLogger.shared.log("❌ [SimpleKanataManager] Step 2 FAILED: \(permissionError)")
      await setNeedsHelp(permissionError)
      return
    }
    AppLogger.shared.log("✅ [SimpleKanataManager] Step 2 PASSED: All permissions granted")

    // Step 3: Check for conflicts
    AppLogger.shared.log("🔄 [SimpleKanataManager] Step 3: Checking for conflicts...")
    if let conflictError = await checkForConflicts() {
      AppLogger.shared.log("❌ [SimpleKanataManager] Step 3 FAILED: \(conflictError)")
      await setNeedsHelp(conflictError)
      return
    }
    AppLogger.shared.log("✅ [SimpleKanataManager] Step 3 PASSED: No conflicts detected")

    // Step 4: Start Kanata
    AppLogger.shared.log("🚀 [SimpleKanataManager] Step 4: All checks passed - starting Kanata")
    await kanataManager.startKanata()

    // Step 5: Verify it started
    AppLogger.shared.log("🔄 [SimpleKanataManager] Step 5: Waiting 2 seconds for Kanata to start...")
    try? await Task.sleep(nanoseconds: 2_000_000_000)  // Wait 2 seconds
    await kanataManager.updateStatus()

    if kanataManager.isRunning {
      AppLogger.shared.log("✅ [SimpleKanataManager] Step 5 PASSED: Auto-start successful!")
      currentState = .running
      errorReason = nil
      startHealthMonitoring()
    } else {
      AppLogger.shared.log("❌ [SimpleKanataManager] Step 5 FAILED: Kanata did not start")
      await handleStartFailure()
    }
    
    AppLogger.shared.log("🔄 [SimpleKanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) COMPLETE ==========")
  }

  private func handleStartFailure() async {
    AppLogger.shared.log("❌ [SimpleKanataManager] Auto-start failed")

    // Check if we should retry
    if autoStartAttempts < maxAutoStartAttempts {
      AppLogger.shared.log("🔄 [SimpleKanataManager] Retrying auto-start...")
      try? await Task.sleep(nanoseconds: 3_000_000_000)  // Wait 3 seconds
      await attemptAutoStart()
      return
    }

    // Max attempts reached - check what went wrong
    let failureReason = await diagnoseStartFailure()
    await setNeedsHelp(failureReason)
  }

  private func diagnoseStartFailure() async -> String {
    // Check log file for specific errors
    let logPath = "/var/log/kanata.log"

    if let logData = try? String(contentsOfFile: logPath, encoding: .utf8) {
      let lines = logData.components(separatedBy: .newlines)
      let recentLines = lines.suffix(10)

      for line in recentLines.reversed() {
        if line.contains("Permission denied") {
          return "Permission denied - check Input Monitoring permissions in System Settings"
        } else if line.contains("Config") && line.contains("error") {
          return "Configuration file error - check your keypath.kbd file"
        } else if line.contains("Device") && line.contains("not found") {
          return "Keyboard device not found - ensure keyboard is connected"
        } else if line.contains("Address already in use") {
          return "Another keyboard service is running - check for conflicts"
        }
      }
    }

    return "Kanata failed to start - check system requirements and permissions"
  }

  private func setNeedsHelp(_ reason: String) async {
    AppLogger.shared.log("❌ [SimpleKanataManager] ========== SET NEEDS HELP ==========")
    AppLogger.shared.log("❌ [SimpleKanataManager] Reason: \(reason)")
    AppLogger.shared.log("❌ [SimpleKanataManager] Before - showWizard: \(showWizard), currentState: \(currentState)")
    
    currentState = .needsHelp
    errorReason = reason
    showWizard = true
    isRetryingAfterFix = false

    AppLogger.shared.log("❌ [SimpleKanataManager] After - showWizard: \(showWizard), currentState: \(currentState)")

    // Force UI update on main thread
    await MainActor.run {
      AppLogger.shared.log("🎩 [SimpleKanataManager] MainActor UI update: showWizard = \(showWizard), currentState = \(currentState)")
      AppLogger.shared.log("🎩 [SimpleKanataManager] Published properties should now trigger SwiftUI updates")
    }

    // Update permission state for change detection
    await updatePermissionState()
    
    AppLogger.shared.log("❌ [SimpleKanataManager] ========== SET NEEDS HELP COMPLETE ==========")
  }

  // MARK: - Requirement Checks

  private func findKanataExecutable() async -> String {
    let possiblePaths = [
      "/opt/homebrew/bin/kanata",
      "/usr/local/bin/kanata",
      "/usr/bin/kanata"
    ]

    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: path) {
        AppLogger.shared.log("✅ [SimpleKanataManager] Found Kanata at: \(path)")
        return path
      }
    }

    AppLogger.shared.log("❌ [SimpleKanataManager] Kanata executable not found")
    return ""
  }

  private func checkPermissions() async -> String? {
    let hasInputMonitoring = kanataManager.hasInputMonitoringPermission()
    let hasAccessibility = kanataManager.hasAccessibilityPermission()
    
    AppLogger.shared.log("🔐 [SimpleKanataManager] Permission check - Input Monitoring: \(hasInputMonitoring), Accessibility: \(hasAccessibility)")
    
    if !hasInputMonitoring {
      AppLogger.shared.log("❌ [SimpleKanataManager] Missing Input Monitoring permission")
      return "Input Monitoring permission required - enable in System Settings > Privacy & Security"
    }

    if !hasAccessibility {
      AppLogger.shared.log("❌ [SimpleKanataManager] Missing Accessibility permission")
      return "Accessibility permission required - enable in System Settings > Privacy & Security"
    }

    AppLogger.shared.log("✅ [SimpleKanataManager] All permissions granted")
    return nil
  }

  private func checkForConflicts() async -> String? {
    // Use existing ConflictDetector
    let conflictDetector = ConflictDetector(kanataManager: kanataManager)
    let result = await conflictDetector.detectConflicts()

    if !result.conflicts.isEmpty {
      let conflictNames = result.conflicts.map { conflict in
        switch conflict {
        case .karabinerGrabberRunning:
          return "Karabiner Elements"
        case .karabinerVirtualHIDDeviceRunning(_, let processName):
          return processName
        case .karabinerVirtualHIDDaemonRunning:
          return "Karabiner VirtualHID Daemon"
        case .kanataProcessRunning:
          return "Another Kanata process"
        case .exclusiveDeviceAccess(let device):
          return "Device conflict: \(device)"
        }
      }

      return
        "Conflicting processes detected: \(conflictNames.joined(separator: ", ")). These must be resolved first."
    }

    return nil
  }

  // MARK: - Health Monitoring

  private func startHealthMonitoring() {
    AppLogger.shared.log("💓 [SimpleKanataManager] Starting health monitoring")

    healthTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
      Task {
        await self.performHealthCheck()
      }
    }
  }

  private func stopHealthMonitoring() {
    AppLogger.shared.log("💓 [SimpleKanataManager] Stopping health monitoring")
    healthTimer?.invalidate()
    healthTimer = nil
  }

  private func performHealthCheck() async {
    guard currentState == .running else { return }

    await kanataManager.updateStatus()
    lastHealthCheck = Date()

    if !kanataManager.isRunning {
      AppLogger.shared.log("💓 [SimpleKanataManager] Health check failed - service down")
      await handleServiceFailure("Service health check failed")
    }
  }

  private func handleServiceFailure(_ reason: String) async {
    AppLogger.shared.log("❌ [SimpleKanataManager] Service failure: \(reason)")
    stopHealthMonitoring()

    // Attempt one auto-restart
    AppLogger.shared.log("🔄 [SimpleKanataManager] Attempting auto-restart...")
    autoStartAttempts = 0  // Reset for auto-restart
    await attemptAutoStart()
  }

  // MARK: - Enhanced Auto-Retry Logic

  /// Retry auto-start after user has potentially fixed issues
  func retryAfterFix(_ feedbackMessage: String) async {
    guard retryCount < maxRetryAttempts else {
      AppLogger.shared.log(
        "⚠️ [SimpleKanataManager] Max retry attempts (\(maxRetryAttempts)) reached - stopping auto-retry"
      )
      await setNeedsHelp("Multiple retry attempts failed - manual intervention required")
      return
    }

    retryCount += 1
    isRetryingAfterFix = true

    AppLogger.shared.log("🔄 [SimpleKanataManager] Retry attempt #\(retryCount): \(feedbackMessage)")

    // Set to starting state with user feedback
    currentState = .starting
    errorReason = feedbackMessage
    showWizard = false

    // Reset auto-start attempts for fresh retry
    autoStartAttempts = 0

    // Give user visual feedback for a moment
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    await attemptAutoStart()
  }

  /// Called when wizard closes to trigger immediate retry
  func onWizardClosed() async {
    AppLogger.shared.log("🎩 [SimpleKanataManager] Wizard closed - checking if retry is needed")

    if currentState == .needsHelp {
      AppLogger.shared.log("🔄 [SimpleKanataManager] Triggering immediate retry after wizard close")
      await retryAfterFix("Retrying after wizard changes...")
    }
  }

  /// Detect if permissions have changed since last check
  private func checkForPermissionChanges() async -> Bool {
    let currentInput = kanataManager.hasInputMonitoringPermission()
    let currentAccessibility = kanataManager.hasAccessibilityPermission()

    let hadPermissions = lastPermissionState.input && lastPermissionState.accessibility
    let hasPermissions = currentInput && currentAccessibility

    // Update stored state
    lastPermissionState = (currentInput, currentAccessibility)

    // Check if permissions were just granted
    if !hadPermissions && hasPermissions {
      AppLogger.shared.log(
        "✅ [SimpleKanataManager] Permissions granted! Input: \(currentInput), Accessibility: \(currentAccessibility)"
      )
      return true
    }

    // Check if any individual permission changed from false to true
    if (!lastPermissionState.input && currentInput)
      || (!lastPermissionState.accessibility && currentAccessibility) {
      AppLogger.shared.log(
        "✅ [SimpleKanataManager] Permission change detected - Input: \(currentInput), Accessibility: \(currentAccessibility)"
      )
      return true
    }

    return false
  }

  /// Update stored permission state
  private func updatePermissionState() async {
    lastPermissionState = (
      kanataManager.hasInputMonitoringPermission(),
      kanataManager.hasAccessibilityPermission()
    )
    AppLogger.shared.log(
      "📊 [SimpleKanataManager] Updated permission state - Input: \(lastPermissionState.input), Accessibility: \(lastPermissionState.accessibility)"
    )
  }

  // MARK: - State Queries

  var isRunning: Bool {
    return currentState == .running
  }

  var needsUserIntervention: Bool {
    return currentState == .needsHelp
  }

  var stateDescription: String {
    if isRetryingAfterFix {
      return
        "\(currentState.displayName): \(errorReason ?? "Retrying...") (Attempt \(retryCount)/\(maxRetryAttempts))"
    } else if let errorReason = errorReason {
      return "\(currentState.displayName): \(errorReason)"
    } else {
      return currentState.displayName
    }
  }
}
