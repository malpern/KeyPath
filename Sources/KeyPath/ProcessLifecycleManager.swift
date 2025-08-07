import Foundation

/// ProcessLifecycleManager - Unified process management for KeyPath
///
/// This component replaces fragmented process detection with intent-based
/// process lifecycle management. It prevents conflicts by establishing
/// intent before action and maintaining accurate process ownership records.
///
/// Key Principles:
/// 1. Intent Before Action - Set desired state, then reconcile
/// 2. Single Source of Truth - All process state centralized here
/// 3. Conflict Prevention - Resolve conflicts before they cause issues
/// 4. Temporal Coordination - Handle timing edge cases gracefully
@MainActor
class ProcessLifecycleManager: ObservableObject {
  // MARK: - Types

  struct ProcessInfo {
    let pid: pid_t
    let command: String
    let executable: String
    let startTime: Date?

    init(pid: pid_t, command: String) {
      self.pid = pid
      self.command = command
      executable = command.components(separatedBy: " ").first ?? ""
      startTime = Date()
    }
  }

  private struct ProcessRecord {
    let pid: pid_t
    let command: String
    let startTime: Date
    let ownership: ProcessOwnership
    let intent: ProcessIntent
    let source: String
  }

  enum ProcessOwnership: Equatable {
    case keyPathOwned(reason: String)
    case external
    case unknown

    static func == (lhs: ProcessOwnership, rhs: ProcessOwnership) -> Bool {
      switch (lhs, rhs) {
      case (.keyPathOwned, .keyPathOwned):
        return true
      case (.external, .external):
        return true
      case (.unknown, .unknown):
        return true
      default:
        return false
      }
    }
  }

  enum ProcessIntent: Equatable {
    case shouldBeRunning(source: String)  // KeyPath wants this running
    case shouldBeStopped  // KeyPath wants this stopped
    case dontCare  // External process, not our concern
  }

  enum ProcessAction {
    case startNew
    case adoptExisting(ProcessInfo)
    case resolveConflict([ProcessInfo])
    case stop(ProcessInfo)
    case none
  }

  struct ConflictResolution {
    let externalProcesses: [ProcessInfo]
    let recommendedAction: RecommendedAction
    let canAutoResolve: Bool

    enum RecommendedAction {
      case terminateExternal
      case adoptExternal
      case startNew
      case userDecision
    }
  }

  // MARK: - State

  @Published private(set) var currentIntent: ProcessIntent = .shouldBeStopped
  @Published private(set) var activeProcesses: [ProcessInfo] = []
  @Published private(set) var lastConflictCheck: Date?

  private var processRecords: [pid_t: ProcessRecord] = [:]
  private var lastProcessStart: Date?
  private let graceWindow: TimeInterval = 5.0  // 5 seconds for startup coordination

  // MARK: - Dependencies

  private let kanataManager: KanataManager?

  init(kanataManager: KanataManager? = nil) {
    self.kanataManager = kanataManager
    AppLogger.shared.log("🏗️ [ProcessLifecycleManager] Initialized")
  }

  // MARK: - Intent-Based API

  /// Set the intended process state
  func setIntent(_ intent: ProcessIntent) {
    AppLogger.shared.log("🎯 [ProcessLifecycleManager] Intent changed: \(currentIntent) → \(intent)")
    currentIntent = intent
  }

  /// Make reality match the intended state
  func reconcileWithIntent() async throws {
    AppLogger.shared.log(
      "🔄 [ProcessLifecycleManager] ========== RECONCILING WITH INTENT ==========")
    AppLogger.shared.log("🔄 [ProcessLifecycleManager] Current intent: \(currentIntent)")

    let currentProcesses = await detectCurrentProcesses()
    let actions = await determineActions(current: currentProcesses, intended: currentIntent)

    AppLogger.shared.log("🔄 [ProcessLifecycleManager] Determined \(actions.count) actions to take")

    try await executeActions(actions)

    // Update our published state
    activeProcesses = currentProcesses.filter { isOwnedByKeyPath($0) }

    AppLogger.shared.log(
      "🔄 [ProcessLifecycleManager] ========== RECONCILIATION COMPLETE ==========")
    AppLogger.shared.log(
      "🔄 [ProcessLifecycleManager] Active KeyPath processes: \(activeProcesses.count)")
  }

  /// Check for conflicts without resolving them
  func detectConflicts() async -> ConflictResolution {
    AppLogger.shared.log("🔍 [ProcessLifecycleManager] Detecting conflicts...")

    let currentProcesses = await detectCurrentProcesses()
    let externalProcesses = currentProcesses.filter { !isOwnedByKeyPath($0) }

    lastConflictCheck = Date()

    if externalProcesses.isEmpty {
      AppLogger.shared.log("✅ [ProcessLifecycleManager] No conflicts detected")
      return ConflictResolution(
        externalProcesses: [],
        recommendedAction: .startNew,
        canAutoResolve: true
      )
    }

    AppLogger.shared.log(
      "⚠️ [ProcessLifecycleManager] Found \(externalProcesses.count) external processes")

    // Determine best conflict resolution approach
    let recommendedAction: ConflictResolution.RecommendedAction
    let canAutoResolve: Bool

    if externalProcesses.count == 1 && looksLikeKeyPathProcess(externalProcesses[0]) {
      // Single process that might be ours from previous run
      recommendedAction = .adoptExternal
      canAutoResolve = true
    } else if externalProcesses.allSatisfy({ $0.executable == "kanata" }) {
      // All are kanata processes - safe to terminate
      recommendedAction = .terminateExternal
      canAutoResolve = true
    } else {
      // Mixed or unknown processes - need user decision
      recommendedAction = .userDecision
      canAutoResolve = false
    }

    return ConflictResolution(
      externalProcesses: externalProcesses,
      recommendedAction: recommendedAction,
      canAutoResolve: canAutoResolve
    )
  }

  // MARK: - Process Detection

  /// Detect all kanata-related processes currently running
  func detectCurrentProcesses() async -> [ProcessInfo] {
    AppLogger.shared.log("🔍 [ProcessLifecycleManager] Detecting current processes...")

    var processes: [ProcessInfo] = []

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-fl", "kanata"]  // Full command line with kanata

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus == 0,
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
          let components = line.components(separatedBy: " ")
          guard let pidString = components.first,
            let pid = pid_t(pidString),
            components.count > 1
          else {
            continue
          }

          let command = components.dropFirst().joined(separator: " ")

          // Skip the pgrep command itself
          if command.contains("pgrep") {
            continue
          }

          let processInfo = ProcessInfo(pid: pid, command: command)
          processes.append(processInfo)

          AppLogger.shared.log(
            "🔍 [ProcessLifecycleManager] Found process: PID=\(pid), Command=\(command)")
        }
      }
    } catch {
      AppLogger.shared.log("❌ [ProcessLifecycleManager] Error detecting processes: \(error)")
    }

    AppLogger.shared.log(
      "🔍 [ProcessLifecycleManager] Detection complete: found \(processes.count) processes")
    return processes
  }

  // MARK: - Process Ownership

  /// Determine if a process is owned by KeyPath
  func isOwnedByKeyPath(_ process: ProcessInfo) -> Bool {
    // 1. Check explicit records first
    if let record = processRecords[process.pid] {
      switch record.ownership {
      case .keyPathOwned:
        AppLogger.shared.log(
          "📋 [ProcessLifecycleManager] Process \(process.pid) found in records: KeyPath-owned")
        return true
      case .external, .unknown:
        AppLogger.shared.log(
          "📋 [ProcessLifecycleManager] Process \(process.pid) found in records: not KeyPath-owned")
        return false
      }
    }

    // 2. Check command patterns
    if matchesKeyPathCommandPattern(process.command) {
      AppLogger.shared.log(
        "✅ [ProcessLifecycleManager] Process \(process.pid) matches KeyPath patterns")

      // Auto-register as KeyPath-owned
      registerProcess(
        process,
        ownership: .keyPathOwned(reason: "command_pattern_match"),
        intent: currentIntent
      )
      return true
    }

    // 3. Grace period check - did we recently start something?
    if let lastStart = lastProcessStart,
      Date().timeIntervalSince(lastStart) < graceWindow
    {
      AppLogger.shared.log(
        "🕐 [ProcessLifecycleManager] Grace period active for PID \(process.pid) - assuming KeyPath ownership"
      )

      registerProcess(
        process,
        ownership: .keyPathOwned(reason: "grace_period"),
        intent: currentIntent
      )
      return true
    }

    AppLogger.shared.log(
      "❌ [ProcessLifecycleManager] Process \(process.pid) not recognized as KeyPath-owned")
    return false
  }

  /// Check if a process looks like it could be a KeyPath process
  private func looksLikeKeyPathProcess(_ process: ProcessInfo) -> Bool {
    return matchesKeyPathCommandPattern(process.command)
  }

  /// Match command patterns that indicate KeyPath ownership
  private func matchesKeyPathCommandPattern(_ command: String) -> Bool {
    let patterns = [
      // Direct kanata with KeyPath config files
      #"kanata.*keypath\.kbd"#,
      #"kanata.*KeyPath.*keypath\.kbd"#,

      // LaunchDaemon related
      #"com\.keypath\.kanata"#,

      // Sudo wrappers with KeyPath paths
      #"sudo.*kanata.*keypath"#,

      // KeyPath application bundles
      #"KeyPath\.app.*kanata"#,

      // Configuration files in KeyPath directories
      #"/Users/.*/Library/Application Support/KeyPath/"#,
      #"/usr/local/etc/kanata/keypath"#,
    ]

    for pattern in patterns {
      if command.range(of: pattern, options: .regularExpression) != nil {
        AppLogger.shared.log(
          "✅ [ProcessLifecycleManager] Command matches pattern '\(pattern)': \(command)")
        return true
      }
    }

    return false
  }

  // MARK: - Process Registration

  /// Register a process as KeyPath-owned
  func registerProcess(_ process: ProcessInfo, ownership: ProcessOwnership, intent: ProcessIntent) {
    let record = ProcessRecord(
      pid: process.pid,
      command: process.command,
      startTime: process.startTime ?? Date(),
      ownership: ownership,
      intent: intent,
      source: "explicit_registration"
    )

    processRecords[process.pid] = record
    AppLogger.shared.log(
      "📝 [ProcessLifecycleManager] Registered process: PID=\(process.pid), ownership=\(ownership)")
  }

  /// Mark that we just started a process (for grace period)
  func markProcessStartAttempt() {
    lastProcessStart = Date()
    AppLogger.shared.log("🚀 [ProcessLifecycleManager] Marked process start attempt at \(Date())")
  }

  // MARK: - Action Determination and Execution

  private func determineActions(current: [ProcessInfo], intended: ProcessIntent) async
    -> [ProcessAction]
  {
    var actions: [ProcessAction] = []

    let keyPathProcesses = current.filter { isOwnedByKeyPath($0) }
    let externalProcesses = current.filter { !isOwnedByKeyPath($0) }

    AppLogger.shared.log(
      "🔄 [ProcessLifecycleManager] Current state: \(keyPathProcesses.count) owned, \(externalProcesses.count) external"
    )

    switch intended {
    case .shouldBeRunning:
      if keyPathProcesses.isEmpty, externalProcesses.isEmpty {
        // Clean slate - start new process
        actions.append(.startNew)
        AppLogger.shared.log("🆕 [ProcessLifecycleManager] Action: Start new process")

      } else if !keyPathProcesses.isEmpty {
        // Already have our process running
        actions.append(.adoptExisting(keyPathProcesses.first!))
        AppLogger.shared.log("✅ [ProcessLifecycleManager] Action: Adopt existing KeyPath process")

      } else if !externalProcesses.isEmpty {
        // External processes exist - need conflict resolution
        actions.append(.resolveConflict(externalProcesses))
        AppLogger.shared.log(
          "⚠️ [ProcessLifecycleManager] Action: Resolve conflict with \(externalProcesses.count) external processes"
        )
      }

    case .shouldBeStopped:
      // Stop all KeyPath-owned processes, ignore external ones
      for process in keyPathProcesses {
        actions.append(.stop(process))
        AppLogger.shared.log(
          "🛑 [ProcessLifecycleManager] Action: Stop KeyPath process \(process.pid)")
      }

    case .dontCare:
      // No action needed
      actions.append(.none)
      AppLogger.shared.log("🤷 [ProcessLifecycleManager] Action: No action (don't care)")
    }

    return actions
  }

  private func executeActions(_ actions: [ProcessAction]) async throws {
    for action in actions {
      try await executeAction(action)
    }
  }

  private func executeAction(_ action: ProcessAction) async throws {
    switch action {
    case .startNew:
      try await startNewKanataProcess()

    case .adoptExisting(let process):
      adoptExistingProcess(process)

    case .resolveConflict(let externalProcesses):
      try await resolveConflictWithExternalProcesses(externalProcesses)

    case .stop(let process):
      try await stopProcess(process)

    case .none:
      AppLogger.shared.log("➡️ [ProcessLifecycleManager] No action taken")
    }
  }

  // MARK: - Action Implementations

  private func startNewKanataProcess() async throws {
    AppLogger.shared.log("🚀 [ProcessLifecycleManager] Starting new Kanata process...")

    markProcessStartAttempt()

    guard let kanataManager = kanataManager else {
      throw ProcessLifecycleError.noKanataManager
    }

    await kanataManager.startKanata()

    // Give process time to start, then verify
    try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

    let newProcesses = await detectCurrentProcesses()
    let newKeyPathProcesses = newProcesses.filter { isOwnedByKeyPath($0) }

    if !newKeyPathProcesses.isEmpty {
      AppLogger.shared.log("✅ [ProcessLifecycleManager] Successfully started new process")
    } else {
      AppLogger.shared.log("❌ [ProcessLifecycleManager] Failed to start new process")
      throw ProcessLifecycleError.processStartFailed
    }
  }

  private func adoptExistingProcess(_ process: ProcessInfo) {
    AppLogger.shared.log("🤝 [ProcessLifecycleManager] Adopting existing process: \(process.pid)")

    registerProcess(
      process,
      ownership: .keyPathOwned(reason: "adopted_existing"),
      intent: currentIntent
    )
  }

  private func resolveConflictWithExternalProcesses(_ externalProcesses: [ProcessInfo]) async throws
  {
    AppLogger.shared.log(
      "⚔️ [ProcessLifecycleManager] Resolving conflict with \(externalProcesses.count) external processes"
    )

    // For now, we'll terminate external processes
    // In a more sophisticated implementation, we could ask the user
    for process in externalProcesses {
      try await terminateExternalProcess(process)
    }

    // After clearing conflicts, start our own process
    try await startNewKanataProcess()
  }

  private func stopProcess(_ process: ProcessInfo) async throws {
    AppLogger.shared.log("🛑 [ProcessLifecycleManager] Stopping process: \(process.pid)")

    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    killTask.arguments = ["/bin/kill", "-TERM", String(process.pid)]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      if killTask.terminationStatus == 0 {
        AppLogger.shared.log(
          "✅ [ProcessLifecycleManager] Successfully stopped process \(process.pid)")
        processRecords.removeValue(forKey: process.pid)
      } else {
        AppLogger.shared.log(
          "⚠️ [ProcessLifecycleManager] Kill command returned status \(killTask.terminationStatus)")
      }
    } catch {
      AppLogger.shared.log("❌ [ProcessLifecycleManager] Error stopping process: \(error)")
      throw ProcessLifecycleError.processStopFailed(error)
    }
  }

  private func terminateExternalProcess(_ process: ProcessInfo) async throws {
    AppLogger.shared.log("💀 [ProcessLifecycleManager] Terminating external process: \(process.pid)")

    let killTask = Process()
    killTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    killTask.arguments = ["/usr/bin/pkill", "-TERM", "-f", "kanata"]

    do {
      try killTask.run()
      killTask.waitUntilExit()

      AppLogger.shared.log("✅ [ProcessLifecycleManager] Terminated external processes")
    } catch {
      AppLogger.shared.log(
        "❌ [ProcessLifecycleManager] Error terminating external process: \(error)")
      throw ProcessLifecycleError.processTerminateFailed(error)
    }
  }

  // MARK: - Cleanup and Maintenance

  /// Clean up stale process records
  func cleanup() async {
    AppLogger.shared.log("🧹 [ProcessLifecycleManager] Cleaning up stale records...")

    let currentProcesses = await detectCurrentProcesses()
    let runningPIDs = Set(currentProcesses.map { $0.pid })

    let staleRecords = processRecords.filter { !runningPIDs.contains($0.key) }

    for (pid, _) in staleRecords {
      processRecords.removeValue(forKey: pid)
      AppLogger.shared.log("🗑️ [ProcessLifecycleManager] Removed stale record for PID \(pid)")
    }

    AppLogger.shared.log("✅ [ProcessLifecycleManager] Cleanup complete")
  }

  /// Recover from app crash by discovering orphaned processes
  func recoverFromCrash() async {
    AppLogger.shared.log("🔄 [ProcessLifecycleManager] Recovering from crash...")

    processRecords.removeAll()

    let existingProcesses = await detectCurrentProcesses()
    for process in existingProcesses where matchesKeyPathCommandPattern(process.command) {
      AppLogger.shared.log("🔍 [ProcessLifecycleManager] Adopting orphaned process: \(process.pid)")

      registerProcess(
        process,
        ownership: .keyPathOwned(reason: "crash_recovery"),
        intent: .shouldBeRunning(source: "recovery")
      )
    }

    AppLogger.shared.log("✅ [ProcessLifecycleManager] Crash recovery complete")
  }
}

// MARK: - Error Types

enum ProcessLifecycleError: Error, LocalizedError {
  case noKanataManager
  case processStartFailed
  case processStopFailed(Error)
  case processTerminateFailed(Error)

  var errorDescription: String? {
    switch self {
    case .noKanataManager:
      return "No KanataManager available"
    case .processStartFailed:
      return "Failed to start Kanata process"
    case .processStopFailed(let error):
      return "Failed to stop process: \(error.localizedDescription)"
    case .processTerminateFailed(let error):
      return "Failed to terminate process: \(error.localizedDescription)"
    }
  }
}
