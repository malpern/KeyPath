import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
import os.lock

/// Stateless system validation service
///
/// This replaces StartupValidator + SystemStatusChecker with a single, simple validator.
/// Key design principles:
/// - STATELESS: No @Published properties, no cached results
/// - PULL-BASED: UI explicitly calls checkSystem() when it wants state
/// - NO SIDE EFFECTS: Only inspects system, doesn't change anything
/// - DEFENSIVE: Assertions catch validation spam and other bugs
///
/// The Oracle already has its own 1.5s cache, so we don't need another cache layer.
@MainActor
class SystemValidator {
  // MARK: - Validation Spam Detection

  /// Track active validations to detect spam (concurrent validations)
  private static var activeValidations = 0

  /// Per-instance validation task - prevents concurrent validations for this instance
  private var inProgressValidation: Task<SystemSnapshot, Never>?

  /// Track validation timing to detect rapid-fire calls (indicates automatic triggers)
  private static var lastValidationStart: Date?
  private static var validationCount = 0
  /// In test mode, only the "owner" instance contributes to the global counters to prevent cross-test interference.
  private static var countingOwner: ObjectIdentifier?
  /// Serialize validations across the test process to avoid cross-test interference
  private actor TestGate {
    func run(
      _ validator: SystemValidator,
      progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> SystemSnapshot {
      await validator.performValidationBody(progressCallback: progressCallback)
    }
  }

  private static let testGate = TestGate()

  // MARK: - Dependencies

  private let launchDaemonInstaller: LaunchDaemonInstaller
  private let vhidDeviceManager: VHIDDeviceManager
  private let processLifecycleManager: ProcessLifecycleManager
  private weak var kanataManager: KanataManager?

  init(
    launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
    vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
    processLifecycleManager: ProcessLifecycleManager,
    kanataManager: KanataManager? = nil
  ) {
    self.launchDaemonInstaller = launchDaemonInstaller
    self.vhidDeviceManager = vhidDeviceManager
    self.processLifecycleManager = processLifecycleManager
    self.kanataManager = kanataManager

    AppLogger.shared.log("🔍 [SystemValidator] Initialized (stateless, no cache)")

    // In tests, designate the first validator created after resetCounters() as the counting owner
    if TestEnvironment.isRunningTests, Self.countingOwner == nil {
      Self.countingOwner = ObjectIdentifier(self)
    }
  }

  // MARK: - Main Validation Method

  /// Check complete system state
  /// This is the ONLY public method - returns fresh state every time
  ///
  /// If validation is already in progress, this will wait for it to complete
  /// rather than starting a concurrent validation. This prevents validation spam
  /// when multiple UI components request validation simultaneously.
  ///
  /// - Parameter progressCallback: Optional callback that receives progress updates (0.0 to 1.0)
  func checkSystem(progressCallback: @escaping @Sendable (Double) -> Void = { _ in }) async
    -> SystemSnapshot
  {
    // If validation is already in progress, wait for it
    if let inProgress = inProgressValidation {
      AppLogger.shared.log(
        "🔍 [SystemValidator] Validation already in progress - waiting for result")
      return await inProgress.value
    }

    // Start new validation
    let validationTask = Task<SystemSnapshot, Never> { @MainActor in
      await self.performValidation(progressCallback: progressCallback)
    }

    inProgressValidation = validationTask
    defer { inProgressValidation = nil }

    return await validationTask.value
  }

  /// Perform the actual validation work
  /// This is called by checkSystem() and should not be called directly
  private func performValidation(progressCallback: @escaping @Sendable (Double) -> Void = { _ in })
    async -> SystemSnapshot
  {
    if TestEnvironment.isRunningTests {
      return await Self.testGate.run(self, progressCallback: progressCallback)
    }
    return await performValidationBody(progressCallback: progressCallback)
  }

  private func performValidationBody(
    progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
  ) async -> SystemSnapshot {
    // If cancelled before we start, return a minimal snapshot without mutating counters
    if Task.isCancelled {
      return Self.makeCancelledSnapshot()
    }
    Self.activeValidations += 1
    defer { Self.activeValidations -= 1 }

    // Respect cancellation before counting
    if Task.isCancelled { return Self.makeCancelledSnapshot() }
    // Only count owner in tests to avoid cross-test interference
    if !TestEnvironment.isRunningTests || Self.countingOwner == ObjectIdentifier(self) {
      Self.validationCount += 1
    }
    let myID = Self.validationCount

    // 🚨 DEFENSIVE WARNING: Detect rapid-fire validations (indicates automatic triggers)
    if let lastStart = Self.lastValidationStart {
      let interval = Date().timeIntervalSince(lastStart)
      if interval < 0.5 {
        AppLogger.shared.log(
          """
          ⚠️ [SystemValidator] RAPID VALIDATION: \(String(format: "%.3f", interval))s since last validation
          This might indicate automatic triggers. Expected: manual user actions only.
          """)
      }
    }
    Self.lastValidationStart = Date()

    let startTime = Date()
    AppLogger.shared.log("🔍 [SystemValidator] Starting validation #\(myID)")

    // Check system state in parallel for maximum performance
    // All checks are independent - no dependencies between them
    progressCallback(0.0)  // Start: 0%

    // Track completion count for incremental progress updates
    let progressLock = OSAllocatedUnfairLock(initialState: 0)
    let totalSteps = 5.0
    // Capture progressCallback in a nonisolated closure
    let callback = progressCallback
    let updateProgress = { @Sendable (_: Int) in
      let completed = progressLock.withLock { (count: inout Int) -> Int in
        count += 1
        return count
      }
      let progress = Double(completed) / totalSteps
      callback(progress)
      AppLogger.shared.log(
        "📊 [SystemValidator] Progress: \(Int(progress * 100))% (\(completed)/\(Int(totalSteps)) steps)"
      )
    }

    // Track start times for individual step timing
    let helperStart = Date()
    let permissionsStart = Date()
    let componentsStart = Date()
    let conflictsStart = Date()
    let healthStart = Date()

    // Log validation start with structured timing marker
    AppLogger.shared.log(
      "⏱️ [TIMING] Validation #\(myID) START: \(String(format: "%.3f", startTime.timeIntervalSince1970))"
    )

    // Run all checks in parallel, tracking progress as each completes
    // Use a Sendable enum to wrap results
    enum ValidationResult: Sendable {
      case helper(HelperStatus)
      case permissions(PermissionOracle.Snapshot)
      case components(ComponentStatus)
      case conflicts(ConflictStatus)
      case health(HealthStatus)
    }

    let (helper, permissions, components, conflicts, health) = await withTaskGroup(
      of: ValidationResult.self
    ) { group in
      var helperResult: HelperStatus?
      var permissionsResult: PermissionOracle.Snapshot?
      var componentsResult: ComponentStatus?
      var conflictsResult: ConflictStatus?
      var healthResult: HealthStatus?

      // Add all tasks to group with progress tracking
      group.addTask {
        let start = helperStart
        let result = await self.checkHelper()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
          "⏱️ [TIMING] Step 1 (Helper) completed in \(String(format: "%.3f", duration))s")
        updateProgress(1)
        return .helper(result)
      }
      group.addTask {
        let start = permissionsStart
        let result = await self.checkPermissions()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
          "⏱️ [TIMING] Step 2 (Permissions) completed in \(String(format: "%.3f", duration))s")
        updateProgress(2)
        return .permissions(result)
      }
      group.addTask {
        let start = componentsStart
        let result = await self.checkComponents()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
          "⏱️ [TIMING] Step 3 (Components) completed in \(String(format: "%.3f", duration))s")
        updateProgress(3)
        return .components(result)
      }
      group.addTask {
        let start = conflictsStart
        let result = await self.checkConflicts()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
          "⏱️ [TIMING] Step 4 (Conflicts) completed in \(String(format: "%.3f", duration))s")
        updateProgress(4)
        return .conflicts(result)
      }
      group.addTask {
        let start = healthStart
        let result = await self.checkHealth()
        let duration = Date().timeIntervalSince(start)
        AppLogger.shared.log(
          "⏱️ [TIMING] Step 5 (Health) completed in \(String(format: "%.3f", duration))s")
        updateProgress(5)
        return .health(result)
      }

      // Collect results as they complete
      for await result in group {
        switch result {
        case .helper(let value): helperResult = value
        case .permissions(let value): permissionsResult = value
        case .components(let value): componentsResult = value
        case .conflicts(let value): conflictsResult = value
        case .health(let value): healthResult = value
        }
      }

      // Extract results with fallback values if cast fails
      return (
        helperResult ?? HelperStatus.empty,
        permissionsResult
          ?? {
            let now = Date()
            let defaultSet = PermissionOracle.PermissionSet(
              accessibility: .unknown,
              inputMonitoring: .unknown,
              source: "fallback",
              confidence: .low,
              timestamp: now
            )
            return PermissionOracle.Snapshot(
              keyPath: defaultSet,
              kanata: defaultSet,
              timestamp: now
            )
          }(),
        componentsResult ?? ComponentStatus.empty,
        conflictsResult ?? ConflictStatus.empty,
        healthResult ?? HealthStatus.empty
      )
    }

    progressCallback(1.0)  // All done: 100%

    let totalDuration = Date().timeIntervalSince(startTime)
    AppLogger.shared.log(
      "⏱️ [TIMING] Validation #\(myID) COMPLETE: Total duration \(String(format: "%.3f", totalDuration))s"
    )

    let snapshot = SystemSnapshot(
      permissions: permissions,
      components: components,
      conflicts: conflicts,
      health: health,
      helper: helper,
      timestamp: Date()
    )

    let duration = Date().timeIntervalSince(startTime)
    AppLogger.shared.log(
      "🔍 [SystemValidator] Validation #\(myID) complete in \(String(format: "%.3f", duration))s")
    AppLogger.shared.log(
      "🔍 [SystemValidator] Result: ready=\(snapshot.isReady), blocking=\(snapshot.blockingIssues.count), total=\(snapshot.allIssues.count)"
    )

    // 🚨 DEFENSIVE ASSERTION: Verify snapshot is fresh
    snapshot.validate()

    return snapshot
  }

  // MARK: - Helper Checking

  private func checkHelper() async -> HelperStatus {
    AppLogger.shared.log("🔍 [SystemValidator] Checking privileged helper")

    // Check if helper is installed (BTM registered AND binary exists)
    // This catches phantom registrations where BTM says yes but binary is missing
    let isInstalled = HelperManager.shared.isHelperInstalled()

    // Get version if installed (also tests XPC communication)
    let version = await HelperManager.shared.getHelperVersion()

    // Test actual functionality via XPC
    // This is the definitive test - returns true ONLY if helper responds
    let isWorking = await HelperManager.shared.testHelperFunctionality()

    AppLogger.shared.log(
      "🔍 [SystemValidator] Helper: installed=\(isInstalled), version=\(version ?? "nil"), working=\(isWorking)"
    )

    // Log warnings for inconsistent states
    if isInstalled, !isWorking {
      AppLogger.shared.log(
        "⚠️ [SystemValidator] Helper installed but not working - may be phantom registration or XPC issue"
      )
    } else if !isInstalled, isWorking {
      AppLogger.shared.log(
        "🚨 [SystemValidator] Impossible state: Not installed but working - logic error!")
    }

    return HelperStatus(
      isInstalled: isInstalled,
      version: version,
      isWorking: isWorking
    )
  }

  // MARK: - Permission Checking

  private func checkPermissions() async -> PermissionOracle.Snapshot {
    AppLogger.shared.log("🔍 [SystemValidator] Checking permissions via Oracle")

    // Oracle has its own 1.5s cache - we don't add another layer
    let snapshot = await PermissionOracle.shared.currentSnapshot()

    // 🚨 DEFENSIVE ASSERTION 4: Verify Oracle snapshot is fresh
    let oracleAge = Date().timeIntervalSince(snapshot.timestamp)
    assert(
      oracleAge < 5.0,
      "Oracle snapshot is \(String(format: "%.1f", oracleAge))s old - Oracle cache may be broken")

    AppLogger.shared.log(
      "🔍 [SystemValidator] Oracle snapshot: ready=\(snapshot.isSystemReady), age=\(String(format: "%.3f", oracleAge))s"
    )

    return snapshot
  }

  // MARK: - Component Checking

  private func checkComponents() async -> ComponentStatus {
    AppLogger.shared.log("🔍 [SystemValidator] Checking components")

    // Check Kanata binary installation
    // When SMAppService is active, bundled Kanata is sufficient (via BundleProgram).
    // When launchctl is active, system installation is required (for TCC permissions).
    let kanataBinaryDetector = KanataBinaryDetector.shared
    let kanataBinaryInstalled = kanataBinaryDetector.isInstalled()

    // Check Karabiner driver - use extension enabled check for accurate status
    let karabinerDriverInstalled = kanataManager?.isKarabinerDriverExtensionEnabled() ?? false
    let karabinerDaemonRunning = kanataManager?.isKarabinerDaemonRunning() ?? false

    // Check VirtualHID Device
    let vhidInstalled = vhidDeviceManager.detectInstallation()
    let vhidHealthy = vhidDeviceManager.detectConnectionHealth()
    let vhidVersionMismatch = vhidDeviceManager.hasVersionMismatch()

    // Check LaunchDaemon services
    let daemonStatus = launchDaemonInstaller.getServiceStatus()
    let launchDaemonServicesHealthy = daemonStatus.allServicesHealthy

    AppLogger.shared
      .log(
        "🔍 [SystemValidator] Components: kanata=\(kanataBinaryInstalled), driver=\(karabinerDriverInstalled), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy), vhidVersionMismatch=\(vhidVersionMismatch)"
      )

    return ComponentStatus(
      kanataBinaryInstalled: kanataBinaryInstalled,
      karabinerDriverInstalled: karabinerDriverInstalled,
      karabinerDaemonRunning: karabinerDaemonRunning,
      vhidDeviceInstalled: vhidInstalled,
      vhidDeviceHealthy: vhidHealthy,
      launchDaemonServicesHealthy: launchDaemonServicesHealthy,
      vhidVersionMismatch: vhidVersionMismatch
    )
  }

  // MARK: - Conflict Detection

  private func checkConflicts() async -> ConflictStatus {
    AppLogger.shared.log("🔍 [SystemValidator] Checking for conflicts")

    var allConflicts: [SystemConflict] = []

    // Check for external kanata processes
    let conflictResolution = await processLifecycleManager.detectConflicts()
    allConflicts.append(
      contentsOf: conflictResolution.externalProcesses.map { process in
        .kanataProcessRunning(pid: Int(process.pid), command: process.command)
      })

    // Check for Karabiner-Elements conflicts
    if let manager = kanataManager {
      let karabinerRunning = manager.isKarabinerElementsRunning()
      if karabinerRunning {
        AppLogger.shared.log(
          "⚠️ [SystemValidator] Karabiner-Elements grabber is running - conflicts with Kanata")
        // Get PID for karabiner_grabber
        if let pid = getKarabinerGrabberPID() {
          allConflicts.append(.karabinerGrabberRunning(pid: pid))
        }
      }
    }

    AppLogger.shared
      .log(
        "🔍 [SystemValidator] Total conflicts: \(allConflicts.count) (\(conflictResolution.externalProcesses.count) kanata, \(allConflicts.count - conflictResolution.externalProcesses.count) karabiner)"
      )

    return ConflictStatus(
      conflicts: allConflicts,
      canAutoResolve: conflictResolution.canAutoResolve
    )
  }

  /// Get PID of karabiner_grabber process
  private func getKarabinerGrabberPID() -> Int? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "karabiner_grabber"]

    let pipe = Pipe()
    task.standardOutput = pipe

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""
      let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines)

      if let pid = Int(pidString) {
        AppLogger.shared.log("🔍 [SystemValidator] Found karabiner_grabber PID: \(pid)")
        return pid
      }
    } catch {
      AppLogger.shared.log("❌ [SystemValidator] Error getting karabiner_grabber PID: \(error)")
    }

    return nil
  }

  // MARK: - Health Checking

  private func checkHealth() async -> HealthStatus {
    AppLogger.shared.log("🔍 [SystemValidator] Checking system health")

    let kanataRunning = kanataManager?.isRunning ?? false
    let karabinerDaemonRunning = kanataManager?.isKarabinerDaemonRunning() ?? false
    let vhidHealthy = vhidDeviceManager.detectConnectionHealth()

    AppLogger.shared.log(
      "🔍 [SystemValidator] Health: kanata=\(kanataRunning), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy)"
    )

    return HealthStatus(
      kanataRunning: kanataRunning,
      karabinerDaemonRunning: karabinerDaemonRunning,
      vhidHealthy: vhidHealthy
    )
  }

  // MARK: - Debug Support

  /// Get current validation stats (for debugging)
  static func getValidationStats() -> (activeCount: Int, totalCount: Int, lastStart: Date?) {
    (activeValidations, validationCount, lastValidationStart)
  }

  /// Reset validation counters (for testing)
  static func resetCounters() {
    activeValidations = 0
    validationCount = 0
    lastValidationStart = nil
    countingOwner = nil
    AppLogger.shared.log("🔍 [SystemValidator] Counters reset")
  }

  /// Create a minimal snapshot used when a validation task is cancelled
  private static func makeCancelledSnapshot() -> SystemSnapshot {
    let now = Date()
    let placeholder = PermissionOracle.PermissionSet(
      accessibility: .unknown,
      inputMonitoring: .unknown,
      source: "cancelled",
      confidence: .low,
      timestamp: now
    )
    return SystemSnapshot(
      permissions: PermissionOracle.Snapshot(
        keyPath: placeholder, kanata: placeholder, timestamp: now),
      components: ComponentStatus(
        kanataBinaryInstalled: false,
        karabinerDriverInstalled: false,
        karabinerDaemonRunning: false,
        vhidDeviceInstalled: false,
        vhidDeviceHealthy: false,
        launchDaemonServicesHealthy: false,
        vhidVersionMismatch: false
      ),
      conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
      health: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: false),
      helper: HelperStatus(isInstalled: false, version: nil, isWorking: false),
      timestamp: now
    )
  }
}
