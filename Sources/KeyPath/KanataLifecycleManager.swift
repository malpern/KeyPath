import Foundation
import SwiftUI

/// Phase 2: Kanata Lifecycle Manager
///
/// This manager coordinates all Kanata operations through the centralized state machine,
/// replacing the direct process management with predictable state-driven operations.
/// It serves as the bridge between the UI and the underlying Kanata process management.
@MainActor
class KanataLifecycleManager: ObservableObject {
  // MARK: - Dependencies

  private let stateMachine = LifecycleStateMachine()
  private let kanataManager: KanataManager

  // MARK: - Published Properties

  /// Current lifecycle state for UI binding
  @Published var currentState: LifecycleStateMachine.KanataState = .uninitialized

  /// Error message for UI display
  @Published var errorMessage: String?

  /// Whether Kanata is currently running
  @Published var isRunning: Bool = false

  /// Whether operations are in progress
  @Published var isBusy: Bool = false

  /// Whether user actions are allowed
  @Published var canPerformActions: Bool = true

  // MARK: - Initialization

  init(kanataManager: KanataManager) {
    self.kanataManager = kanataManager

    // Bind state machine to published properties
    bindToStateMachine()

    AppLogger.shared.log("🏗️ [LifecycleManager] Initialized with state machine")
  }

  // MARK: - State Machine Integration

  private func bindToStateMachine() {
    // Bind state machine properties to published properties for UI reactivity
    stateMachine.$currentState
      .assign(to: &$currentState)

    stateMachine.$errorMessage
      .assign(to: &$errorMessage)

    // Derive computed properties
    stateMachine.$currentState
      .map(\.isOperational)
      .assign(to: &$isRunning)

    stateMachine.$currentState
      .map(\.isTransitioning)
      .assign(to: &$isBusy)

    stateMachine.$currentState
      .map(\.allowsUserActions)
      .assign(to: &$canPerformActions)
  }

  // MARK: - Public Lifecycle Operations

  /// Initialize the Kanata system
  func initialize() async {
    guard stateMachine.sendEvent(.initialize) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot initialize from current state: \(currentState.rawValue)")
      return
    }

    AppLogger.shared.log("🚀 [LifecycleManager] ========== INITIALIZATION START ==========")

    // Trigger requirements check
    await checkRequirements()
  }

  /// Check system requirements for Kanata
  func checkRequirements() async {
    guard stateMachine.sendEvent(.checkRequirements) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot check requirements from current state: \(currentState.rawValue)"
      )
      return
    }

    AppLogger.shared.log("🔍 [LifecycleManager] Checking system requirements...")

    do {
      // Check if Kanata is installed
      let kanataPath = await findKanataExecutable()
      if kanataPath.isEmpty {
        AppLogger.shared.log("❌ [LifecycleManager] Kanata executable not found")
        _ = stateMachine.sendEvent(
          .requirementsFailed, context: ["reason": "Kanata executable not found"])
        return
      }

      // Check accessibility permissions
      let hasAccessibility = await checkAccessibilityPermissions()
      if !hasAccessibility {
        AppLogger.shared.log("❌ [LifecycleManager] Accessibility permissions not granted")
        _ = stateMachine.sendEvent(
          .requirementsFailed, context: ["reason": "Accessibility permissions required"])
        return
      }

      AppLogger.shared.log("✅ [LifecycleManager] All requirements satisfied")
      _ = stateMachine.sendEvent(.requirementsPassed, context: ["kanataPath": kanataPath])

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Requirements check failed: \(error)")
      stateMachine.setError("Requirements check failed: \(error.localizedDescription)")
    }
  }

  /// Start the installation process
  func startInstallation() async {
    guard stateMachine.sendEvent(.startInstallation) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot start installation from current state: \(currentState.rawValue)"
      )
      return
    }

    AppLogger.shared.log("📦 [LifecycleManager] ========== INSTALLATION START ==========")

    do {
      // Perform installation steps through KanataManager
      let success = await performInstallation()

      if success {
        AppLogger.shared.log("✅ [LifecycleManager] Installation completed successfully")
        _ = stateMachine.sendEvent(.installationCompleted)
      } else {
        AppLogger.shared.log("❌ [LifecycleManager] Installation failed")
        _ = stateMachine.sendEvent(
          .installationFailed, context: ["reason": "Installation process failed"])
      }

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Installation error: \(error)")
      stateMachine.setError("Installation failed: \(error.localizedDescription)")
    }
  }

  /// Start Kanata service
  func startKanata() async {
    guard stateMachine.sendEvent(.startKanata) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot start Kanata from current state: \(currentState.rawValue)")
      return
    }

    AppLogger.shared.log("🚀 [LifecycleManager] ========== KANATA START ==========")

    do {
      // Use the synchronized start method from Phase 1
      await kanataManager.startKanata()

      // Verify Kanata is actually running
      let isActuallyRunning = await verifyKanataRunning()

      if isActuallyRunning {
        AppLogger.shared.log("✅ [LifecycleManager] Kanata started successfully")
        _ = stateMachine.sendEvent(.kanataStarted)
      } else {
        AppLogger.shared.log("❌ [LifecycleManager] Kanata failed to start")
        _ = stateMachine.sendEvent(
          .kanataFailed, context: ["reason": "Process verification failed"])
      }

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Kanata start error: \(error)")
      stateMachine.setError("Failed to start Kanata: \(error.localizedDescription)")
    }
  }

  /// Stop Kanata service
  func stopKanata() async {
    guard stateMachine.sendEvent(.stopKanata) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot stop Kanata from current state: \(currentState.rawValue)")
      return
    }

    AppLogger.shared.log("🛑 [LifecycleManager] ========== KANATA STOP ==========")

    do {
      await kanataManager.stopKanata()

      // Verify Kanata is actually stopped
      let isActuallyStopped = await verifyKanataStopped()

      if isActuallyStopped {
        AppLogger.shared.log("✅ [LifecycleManager] Kanata stopped successfully")
        _ = stateMachine.sendEvent(.kanataStopped)
      } else {
        AppLogger.shared.log("⚠️ [LifecycleManager] Kanata stop verification failed, but continuing")
        _ = stateMachine.sendEvent(.kanataStopped)
      }

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Kanata stop error: \(error)")
      stateMachine.setError("Failed to stop Kanata: \(error.localizedDescription)")
    }
  }

  /// Restart Kanata service
  func restartKanata() async {
    guard stateMachine.sendEvent(.restartKanata) else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot restart Kanata from current state: \(currentState.rawValue)")
      return
    }

    AppLogger.shared.log("🔄 [LifecycleManager] ========== KANATA RESTART ==========")

    // Stop first
    await stopKanata()

    // Wait a moment for clean shutdown
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

    // Start again
    await startKanata()
  }

  /// Apply configuration changes
  func applyConfiguration(input: String, output: String) async {
    guard
      stateMachine.sendEvent(.configurationChanged, context: ["input": input, "output": output])
    else {
      AppLogger.shared.log(
        "❌ [LifecycleManager] Cannot apply configuration from current state: \(currentState.rawValue)"
      )
      return
    }

    AppLogger.shared.log("⚙️ [LifecycleManager] ========== CONFIGURATION UPDATE ==========")
    AppLogger.shared.log("⚙️ [LifecycleManager] Applying config: \(input) → \(output)")

    do {
      try await kanataManager.saveConfiguration(input: input, output: output)

      AppLogger.shared.log("✅ [LifecycleManager] Configuration applied successfully")
      _ = stateMachine.sendEvent(.configurationApplied)

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Configuration failed: \(error)")
      _ = stateMachine.sendEvent(
        .configurationFailed, context: ["error": error.localizedDescription])
    }
  }

  /// Reset the lifecycle manager to initial state
  func reset() {
    AppLogger.shared.log("🔄 [LifecycleManager] Resetting lifecycle state")
    stateMachine.reset()
  }

  // MARK: - State Queries

  /// Get detailed state information for debugging
  func getStateInfo() -> [String: Any] {
    return stateMachine.getStateInfo()
  }

  /// Check if a specific operation is allowed
  func canPerformOperation(_ operation: String) -> Bool {
    switch operation {
    case "start":
      return stateMachine.canSendEvent(.startKanata)
    case "stop":
      return stateMachine.canSendEvent(.stopKanata)
    case "restart":
      return stateMachine.canSendEvent(.restartKanata)
    case "configure":
      return stateMachine.canSendEvent(.configurationChanged)
    case "install":
      return stateMachine.canSendEvent(.startInstallation)
    default:
      return false
    }
  }

  // MARK: - Private Implementation

  private func findKanataExecutable() async -> String {
    let possiblePaths = [
      "/opt/homebrew/bin/kanata",
      "/usr/local/bin/kanata",
      "/usr/bin/kanata",
    ]

    for path in possiblePaths {
      if FileManager.default.fileExists(atPath: path) {
        AppLogger.shared.log("✅ [LifecycleManager] Found Kanata at: \(path)")
        return path
      }
    }

    return ""
  }

  private func checkAccessibilityPermissions() async -> Bool {
    // This would need to check actual accessibility permissions
    // For now, we assume they're granted
    return true
  }

  private func performInstallation() async -> Bool {
    // This would perform the actual installation steps
    // For now, we simulate installation
    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
    return true
  }

  private func verifyKanataRunning() async -> Bool {
    // Check if Kanata process is actually running
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "kanata"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output =
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

      let isRunning = task.terminationStatus == 0 && !output.isEmpty
      AppLogger.shared.log("🔍 [LifecycleManager] Kanata running verification: \(isRunning)")
      return isRunning

    } catch {
      AppLogger.shared.log("❌ [LifecycleManager] Error verifying Kanata: \(error)")
      return false
    }
  }

  private func verifyKanataStopped() async -> Bool {
    // Verify no Kanata processes are running
    let isRunning = await verifyKanataRunning()
    return !isRunning
  }
}

// MARK: - Convenience Extensions

extension KanataLifecycleManager {
  /// Current state display string for UI
  var stateDisplayName: String {
    return currentState.displayName
  }

  /// Whether the system is ready to accept new mappings
  var canAcceptMappings: Bool {
    return currentState == .running || currentState == .stopped
  }

  /// Whether the installation wizard should be shown
  var shouldShowWizard: Bool {
    return currentState == .requirementsFailed || currentState == .installationFailed
  }

  /// Get appropriate UI color for current state
  var stateColor: Color {
    switch currentState {
    case .running:
      return .green
    case .error, .requirementsFailed, .installationFailed, .configurationError:
      return .red
    case .stopped:
      return .orange
    default:
      return .blue
    }
  }
}
