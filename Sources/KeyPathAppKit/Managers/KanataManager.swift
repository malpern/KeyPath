import ApplicationServices
@preconcurrency import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
import Network
import SwiftUI

struct WizardSnapshotRecord {
  let state: WizardSystemState
  let issues: [WizardIssue]
}

// ProcessSynchronizationActor removed (unused)

/// Represents a simple key mapping from input to output
/// Used throughout the codebase for representing user-configured key remappings
public struct KeyMapping: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let input: String
  public let output: String

  public init(id: UUID = UUID(), input: String, output: String) {
    self.id = id
    self.input = input
    self.output = output
  }

  private enum CodingKeys: String, CodingKey { case id, input, output }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
    input = try container.decode(String.self, forKey: .input)
    output = try container.decode(String.self, forKey: .output)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(input, forKey: .input)
    try container.encode(output, forKey: .output)
  }
}

// SimpleKanataState enum removed (superseded by InstallerEngine)

/// Manages the Kanata process lifecycle and configuration directly.
///
/// # Architecture: Main Coordinator + Extension Files (2,820 lines total)
///
/// KanataManager is the main orchestrator for Kanata process management and configuration.
/// It's split across multiple extension files for maintainability:
///
/// ## Extension Files (organized by concern):
///
/// **KanataManager.swift** (main file, ~1,200 lines)
/// - Core initialization and state managemen
/// - UI state snapshots and ViewModel interface
/// - Health monitoring and auto-start logic
/// - Diagnostics and error handling
///
/// **KanataManager+Lifecycle.swift** (~400 lines)
/// - Process start/stop/restart operations
/// - LaunchDaemon service managemen
/// - State machine transitions
/// - Recovery and health checks
///
/// **KanataManager+Configuration.swift** (~500 lines)
/// - Config file I/O and validation
/// - Key mapping CRUD operations
/// - Backup and repair logic
/// - TCP server configuration
///
/// **KanataManager+Engine.swift** (~300 lines)
/// - Kanata engine communication
/// - TCP protocol handling
/// - Config reload and layer managemen
///
/// **KanataManager+EventTaps.swift** (~200 lines)
/// - CGEvent monitoring and key capture
/// - Keyboard input recording
/// - Event tap lifecycle
///
/// **KanataManager+Output.swift** (~150 lines)
/// - Log parsing and monitoring
/// - Output processing from Kanata daemon
///
/// ## Key Dependencies (used by extensions):
///
/// - **ConfigurationService**: File I/O, parsing, validation (Configuration extension)
/// - **ProcessLifecycleManager**: PID tracking, daemon registration (Lifecycle extension)
/// - **ServiceHealthMonitor**: Restart cooldown, recovery (Lifecycle extension)
/// - **DiagnosticsService**: System analysis, failure diagnosis (main file)
/// - **PermissionOracle**: Permission state (main file + Lifecycle)
///
/// ## Navigation Tips:
///
/// - Starting Kanata? → See `+Lifecycle.swift`
/// - Reading/writing config? → See `+Configuration.swift`
/// - Talking to Kanata? → See `+Engine.swift`
/// - Recording keypresses? → See `+EventTaps.swift`
/// - Parsing logs? → See `+Output.swift`
///
/// ## MVVM Architecture Note:
///
/// KanataManager is **not** an ObservableObject. UI state is handled by `KanataViewModel`,
/// which reads snapshots via `getCurrentUIState()`. This separation keeps business logic
/// independent of SwiftUI reactivity.
///
/// ## Public API (Views → ViewModel → Manager)
/// The UI should call ONLY the following methods via `KanataViewModel`:
/// - Lifecycle
///   - `startAutoLaunch(presentWizardOnFailure:)`
///   - `manualStart()` / `manualStop()`
///   - `startKanata()` / `stopKanata()`
///   - `forceRefreshStatus()`
/// - Wizard
///   - `requestWizardPresentation(initialPage:)`
///   - `onWizardClosed()`
/// - UI State
///   - `getCurrentUIState()` (snapshot for ViewModel sync)
/// - Configuration (UI-level operations)
///   - `createDefaultUserConfigIfMissing()`
///   - `backupFailedConfigAndApplySafe(failedConfig:mappings:)`
///   - `validateConfigFile()`
///   - `resetToDefaultConfig()`
///
/// All other methods are internal implementation details and may change.

/// Actions available in validation error dialogs
struct ValidationAlertAction {
  let title: String
  let style: ActionStyle
  let action: () -> Void

  enum ActionStyle {
    case `default`
    case cancel
    case destructive
  }
}

/// Save operation status for UI feedback
enum SaveStatus {
  case idle
  case saving
  case validating
  case success
  case failed(String)

  var message: String {
    switch self {
    case .idle: ""
    case .saving: "Saving..."
    case .validating: "Validating..."
    case .success: "✅ Done"
    case .failed(let error): "❌ Config Invalid: \(error)"
    }
  }

  var isActive: Bool {
    switch self {
    case .idle, .success: false
    default: true
    }
  }
}

@MainActor
class KanataManager {
  // MARK: - Internal State Properties

  // Note: These are internal (not private) to allow extensions to access them
  // ViewModel reads these via getCurrentUIState() snapshot method

  // Core status tracking
  // Removed: isRunning
  var lastError: String?
  var keyMappings: [KeyMapping] = []
  var ruleCollections: [RuleCollection] = []
  var customRules: [CustomRule] = []
  var currentLayerName: String = RuleCollectionLayer.base.displayName
  var diagnostics: [KanataDiagnostic] = []
  var lastProcessExitCode: Int32?
  var lastConfigUpdate: Date = .init()

  // UI state properties (Legacy removed)
  var lastWizardSnapshot: WizardSnapshotRecord?

  // Removed: errorReason, showWizard, launchFailureStatus
  // Removed: autoStartAttempts, lastHealthCheck, retryCount, isRetryingAfterFix, userManuallyStopped
  // Removed: lifecycleState, lifecycleErrorMessage, isBusy, canPerformActions, autoStartAttempted, autoStartSucceeded, autoStartFailureReason, shouldShowWizard

  // Validation-specific UI state
  var showingValidationAlert = false
  var validationAlertTitle = ""
  var validationAlertMessage = ""
  var validationAlertActions: [ValidationAlertAction] = []

  // Save progress feedback
  var saveStatus: SaveStatus = .idle

  // MARK: - UI State Snapshot (Phase 4: MVVM)

  /// AsyncStream for UI state changes (replaces polling)
  /// Only emits when state actually changes, dramatically reducing unnecessary UI updates
  private var stateChangeContinuation: AsyncStream<KanataUIState>.Continuation?

  /// Stream of UI state changes for reactive ViewModel updates
  nonisolated var stateChanges: AsyncStream<KanataUIState> {
    AsyncStream { continuation in
      Task { @MainActor in
        self.stateChangeContinuation = continuation
        // Emit initial state
        continuation.yield(self.getCurrentUIState())
      }
    }
  }

  /// Notify observers that state has changed
  /// Call this after any operation that modifies UI-visible state
  private func notifyStateChanged() {
    let state = getCurrentUIState()
    stateChangeContinuation?.yield(state)
  }

  /// Refresh process running state from system (call after service operations)
  /// This is more efficient than checking on every UI state sync
  func refreshProcessState() {
    // Deprecated: State is now managed by InstallerEngine/SystemContext
    notifyStateChanged()
  }

  /// Returns a snapshot of current UI state for ViewModel synchronization
  /// This method allows KanataViewModel to read UI state without @Published properties
  func getCurrentUIState() -> KanataUIState {
    // Sync diagnostics from DiagnosticsManager
    diagnostics = diagnosticsManager.getDiagnostics()

    return KanataUIState(
      // Core Status
      // Removed: isRunning
      lastError: lastError,
      keyMappings: keyMappings,
      ruleCollections: ruleCollections,
      customRules: customRules,
      currentLayerName: currentLayerName,
      diagnostics: diagnostics,
      lastProcessExitCode: lastProcessExitCode,
      lastConfigUpdate: lastConfigUpdate,

      // UI State (Legacy status removed - passed as nil/default)

      // Validation & Save Status
      showingValidationAlert: showingValidationAlert,
      validationAlertTitle: validationAlertTitle,
      validationAlertMessage: validationAlertMessage,
      validationAlertActions: validationAlertActions,
      saveStatus: saveStatus
    )
  }

  // Removed kanataProcess: Process? - now using LaunchDaemon service exclusively
  let configDirectory = "\(NSHomeDirectory())/.config/keypath"
  let configFileName = "keypath.kbd"

  // MARK: - Manager Dependencies (Refactored Architecture)

  let processManager: ProcessManaging
  let configurationManager: ConfigurationManaging
  let diagnosticsManager: DiagnosticsManaging

  // Manager dependencies (exposed for extensions that need direct access)
  let engineClient: EngineClient

  // Legacy dependencies (kept for backward compatibility during transition)
  let configurationService: ConfigurationService
  let processLifecycleManager: ProcessLifecycleManager

  // Additional dependencies needed by extensions
  private let healthMonitor: ServiceHealthMonitorProtocol
  private nonisolated let diagnosticsService: DiagnosticsServiceProtocol
  let reloadSafetyMonitor = ReloadSafetyMonitor()  // internal for use by extensions
  private let karabinerConflictService: KarabinerConflictManaging
  private let configBackupManager: ConfigBackupManager
  private let ruleCollectionStore: RuleCollectionStore
  private let customRulesStore: CustomRulesStore
  private let layerChangeListener = LayerChangeListener()

  private var isStartingKanata = false
  var isInitializing = false
  private let isHeadlessMode: Bool

  // MARK: - UI State Management Properties (Legacy removed)

  // MARK: - Lifecycle State Machine (Legacy removed)

  // Note: Removed stateMachine to avoid MainActor isolation issues
  // Lifecycle management is now handled directly in this class

  // MARK: - Process Synchronization (Phase 1)

  private var lastStartAttempt: Date?  // Still used for backward compatibility
  private var lastServiceKickstart: Date?  // Still used for grace period tracking

  // Configuration file watching for hot reload
  private var configFileWatcher: ConfigFileWatcher?

  var configPath: String {
    configurationManager.configPath
  }

  deinit {
    let listener = layerChangeListener
    Task.detached(priority: .background) {
      await listener.stop()
    }
  }

  init(engineClient: EngineClient? = nil, injectedConfigurationService: ConfigurationService? = nil)
  {
    AppLogger.shared.log("🏗️ [KanataManager] init() called")

    // Check if running in headless mode
    isHeadlessMode =
      ProcessInfo.processInfo.arguments.contains("--headless")
      || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

    // Initialize TCP server grace period timestamp at app startup
    // This prevents immediate admin requests on launch
    lastServiceKickstart = Date()

    // Initialize legacy service dependencies (for backward compatibility)
    if let injected = injectedConfigurationService {
      configurationService = injected
    } else {
      configurationService = ConfigurationService(
        configDirectory: "\(NSHomeDirectory())/.config/keypath")
    }
    processLifecycleManager = ProcessLifecycleManager()
    ruleCollectionStore = RuleCollectionStore.shared
    customRulesStore = CustomRulesStore.shared

    // Initialize configuration file watcher for hot reload
    configFileWatcher = ConfigFileWatcher()

    // Initialize configuration backup manager
    let configBackupManager = ConfigBackupManager(
      configPath: "\(NSHomeDirectory())/.config/keypath/keypath.kbd")

    // Initialize manager dependencies
    let karabinerConflictService = KarabinerConflictService()
    let diagnosticsService = DiagnosticsService(processLifecycleManager: processLifecycleManager)
    let healthMonitor = ServiceHealthMonitor(processLifecycle: processLifecycleManager)

    // Store for extensions
    self.healthMonitor = healthMonitor
    self.diagnosticsService = diagnosticsService
    self.karabinerConflictService = karabinerConflictService
    self.configBackupManager = configBackupManager

    // Initialize ProcessManager
    processManager = ProcessManager(
      processLifecycleManager: processLifecycleManager,
      karabinerConflictService: karabinerConflictService
    )

    // Initialize ConfigurationManager
    configurationManager = ConfigurationManager(
      configurationService: configurationService,
      configBackupManager: configBackupManager,
      configFileWatcher: configFileWatcher
    )

    // Initialize DiagnosticsManager
    diagnosticsManager = DiagnosticsManager(
      diagnosticsService: diagnosticsService,
      healthMonitor: healthMonitor,
      processLifecycleManager: processLifecycleManager
    )

    // Initialize EngineClien
    self.engineClient = engineClient ?? TCPEngineClient()

    // Dispatch heavy initialization work to background thread (skip during unit tests)
    // Prefer structured concurrency; a plain Task{} runs off the main actor by defaul
    if !TestEnvironment.isRunningTests {
      Task { [weak self] in
        // Clean up any orphaned processes firs
        await self?.processLifecycleManager.cleanupOrphanedProcesses()
        await self?.performInitialization()
      }
    } else {
      AppLogger.shared.debug(
        "🧪 [KanataManager] Skipping background initialization in test environment")
    }

    if isHeadlessMode {
      AppLogger.shared.log("🤖 [KanataManager] Initialized in headless mode")
    }

    AppLogger.shared.log(
      "🏗️ [KanataManager] About to call bootstrapRuleCollections and startLayerMonitoring")
    Task { await bootstrapRuleCollections() }
    startLayerMonitoring()
    AppLogger.shared.log("🏗️ [KanataManager] init() completed")
  }

  // MARK: - Rule Collections

  private func bootstrapRuleCollections() async {
    async let storedCollectionsTask = ruleCollectionStore.loadCollections()
    async let storedCustomRulesTask = customRulesStore.loadRules()

    var storedCollections = await storedCollectionsTask
    var storedCustomRules = await storedCustomRulesTask

    if storedCustomRules.isEmpty,
      let customIndex = storedCollections.firstIndex(where: {
        $0.id == RuleCollectionIdentifier.customMappings
      })
    {
      let legacy = storedCollections.remove(at: customIndex)
      storedCustomRules = legacy.mappings.map { mapping in
        CustomRule(
          id: mapping.id,
          title: "",
          input: mapping.input,
          output: mapping.output,
          isEnabled: legacy.isEnabled
        )
      }
      AppLogger.shared.log(
        "♻️ [RuleCollections] Migrated \(storedCustomRules.count) legacy custom mapping(s) into CustomRulesStore"
      )
      do {
        try await customRulesStore.saveRules(storedCustomRules)
      } catch {
        AppLogger.shared.log(
          "⚠️ [RuleCollections] Failed to persist migrated custom rules: \(error)")
      }
      do {
        try await ruleCollectionStore.saveCollections(storedCollections)
      } catch {
        AppLogger.shared.log(
          "⚠️ [RuleCollections] Failed to persist collections after migration: \(error)")
      }
    }

    await MainActor.run {
      self.ruleCollections = storedCollections
      self.customRules = storedCustomRules
      ensureDefaultCollectionsIfNeeded()
      refreshLayerIndicatorState()
    }
    await regenerateConfigFromCollections()
  }

  func replaceRuleCollections(_ collections: [RuleCollection]) async {
    await MainActor.run {
      ruleCollections = collections
      refreshLayerIndicatorState()
    }
    await regenerateConfigFromCollections()
  }

  func enabledMappingsFromCollections() -> [KeyMapping] {
    ruleCollections.enabledMappings() + customRules.enabledMappings()
  }

  @MainActor
  private func ensureDefaultCollectionsIfNeeded() {
    if ruleCollections.isEmpty {
      ruleCollections = RuleCollectionCatalog().defaultCollections()
    }
    refreshLayerIndicatorState()
  }

  @MainActor
  private func refreshLayerIndicatorState() {
    let hasLayered = ruleCollections.contains { $0.isEnabled && $0.targetLayer != .base }
    if !hasLayered {
      updateActiveLayerName(RuleCollectionLayer.base.kanataName)
    }
  }

  private func normalizedKeys(for collection: RuleCollection) -> Set<String> {
    Set(collection.mappings.map { KanataKeyConverter.convertToKanataKey($0.input) })
  }

  private func normalizedActivator(for collection: RuleCollection) -> String? {
    collection.momentaryActivator?.input.lowercased()
  }

  @MainActor
  private struct RuleConflictInfo {
    enum Source {
      case collection(RuleCollection)
      case customRule(CustomRule)

      var name: String {
        switch self {
        case .collection(let collection): collection.name
        case .customRule(let rule): rule.displayTitle
        }
      }
    }

    let source: Source
    let keys: [String]

    var displayName: String { source.name }
  }

  private func conflictInfo(for candidate: RuleCollection) -> RuleConflictInfo? {
    let candidateKeys = normalizedKeys(for: candidate)
    let candidateActivator = normalizedActivator(for: candidate)

    for other in ruleCollections where other.isEnabled && other.id != candidate.id {
      if candidate.targetLayer == other.targetLayer {
        let overlap = candidateKeys.intersection(normalizedKeys(for: other))
        if !overlap.isEmpty {
          return RuleConflictInfo(source: .collection(other), keys: Array(overlap))
        }
      }

      if let act1 = candidateActivator,
        let act2 = normalizedActivator(for: other),
        act1 == act2
      {
        return RuleConflictInfo(source: .collection(other), keys: [act1])
      }
    }

    if candidate.targetLayer == .base {
      if let conflict = conflictWithCustomRules(candidateKeys) {
        return conflict
      }
    }

    return nil
  }

  private func conflictInfo(for rule: CustomRule) -> RuleConflictInfo? {
    let normalizedKey = KanataKeyConverter.convertToKanataKey(rule.input)

    for collection in ruleCollections where collection.isEnabled && collection.targetLayer == .base
    {
      if normalizedKeys(for: collection).contains(normalizedKey) {
        return RuleConflictInfo(source: .collection(collection), keys: [normalizedKey])
      }
    }

    for other in customRules where other.isEnabled && other.id != rule.id {
      if KanataKeyConverter.convertToKanataKey(other.input) == normalizedKey {
        return RuleConflictInfo(source: .customRule(other), keys: [normalizedKey])
      }
    }

    return nil
  }

  private func conflictWithCustomRules(_ keys: Set<String>) -> RuleConflictInfo? {
    for rule in customRules where rule.isEnabled {
      let normalized = KanataKeyConverter.convertToKanataKey(rule.input)
      if keys.contains(normalized) {
        return RuleConflictInfo(source: .customRule(rule), keys: [normalized])
      }
    }
    return nil
  }

  private func startLayerMonitoring() {
    AppLogger.shared.log("🌐 [KanataManager] startLayerMonitoring() called")
    guard !TestEnvironment.isRunningTests else {
      AppLogger.shared.log("🌐 [KanataManager] Skipping layer monitoring (test environment)")
      return
    }
    let port = PreferencesService.shared.tcpServerPort
    AppLogger.shared.log("🌐 [KanataManager] Starting layer monitoring on port \(port)")
    Task.detached(priority: .background) { [weak self] in
      guard let self else {
        AppLogger.shared.log("🌐 [KanataManager] Layer monitoring task: self is nil")
        return
      }
      AppLogger.shared.log("🌐 [KanataManager] Calling layerChangeListener.start()")
      await layerChangeListener.start(port: port) { [weak self] layer in
        guard let self else { return }
        await MainActor.run {
          self.updateActiveLayerName(layer)
        }
      }
    }
  }

  @MainActor
  private func updateActiveLayerName(_ rawName: String) {
    let normalized = rawName.isEmpty ? RuleCollectionLayer.base.kanataName : rawName
    let display = normalized.capitalized
    AppLogger.shared.log(
      "🎯 [KanataManager] updateActiveLayerName: raw='\(rawName)' normalized='\(normalized)' display='\(display)' current='\(currentLayerName)'"
    )

    if currentLayerName == display { return }

    if display.caseInsensitiveCompare(RuleCollectionLayer.base.displayName) != .orderedSame {
      SoundManager.shared.playTinkSound()
    }

    currentLayerName = display

    // Show visual layer indicator
    AppLogger.shared.log("🎯 [KanataManager] Calling LayerIndicatorManager.showLayer('\(display)')")
    LayerIndicatorManager.shared.showLayer(display)
  }

  @MainActor
  private func applyKeyMappings(_ mappings: [KeyMapping], persistCollections _: Bool = true) {
    keyMappings = mappings
    lastConfigUpdate = Date()
  }

  // MARK: - Diagnostics

  func addDiagnostic(_ diagnostic: KanataDiagnostic) {
    diagnosticsManager.addDiagnostic(diagnostic)
    // Update local diagnostics array for UI state
    diagnostics = diagnosticsManager.getDiagnostics()
  }

  func clearDiagnostics() {
    diagnosticsManager.clearDiagnostics()
    diagnostics = []
  }

  // MARK: - Configuration File Watching

  /// Start watching the configuration file for external changes
  func startConfigFileWatching() {
    guard let fileWatcher = configFileWatcher else {
      AppLogger.shared.warn("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
      return
    }

    let configPath = configPath
    AppLogger.shared.log("📁 [FileWatcher] Starting to watch config file: \(configPath)")

    fileWatcher.startWatching(path: configPath) { [weak self] in
      await self?.handleExternalConfigChange()
    }
  }

  /// Stop watching the configuration file
  func stopConfigFileWatching() {
    configFileWatcher?.stopWatching()
    AppLogger.shared.log("📁 [FileWatcher] Stopped watching config file")
  }

  /// Handle external configuration file changes
  private func handleExternalConfigChange() async {
    AppLogger.shared.log("📝 [FileWatcher] External config file change detected")

    // Play the initial sound to indicate detection
    Task { @MainActor in SoundManager.shared.playTinkSound() }

    // Show initial status message
    await MainActor.run {
      saveStatus = .saving
    }

    // Read the updated configuration
    let configPath = configPath
    guard FileManager.default.fileExists(atPath: configPath) else {
      AppLogger.shared.error("❌ [FileWatcher] Config file no longer exists: \(configPath)")
      Task { @MainActor in SoundManager.shared.playErrorSound() }
      await MainActor.run {
        saveStatus = .failed("Config file was deleted")
      }
      return
    }

    do {
      let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
      AppLogger.shared.log(
        "📁 [FileWatcher] Read \(configContent.count) characters from external file")

      // Validate the configuration via CLI
      let validationResult = await configurationService.validateConfiguration(configContent)
      if !validationResult.isValid {
        AppLogger.shared.error(
          "❌ [FileWatcher] External config validation failed: \(validationResult.errors.joined(separator: ", "))"
        )
        Task { @MainActor in SoundManager.shared.playErrorSound() }

        await MainActor.run {
          saveStatus = .failed(
            "Invalid config from external edit: \(validationResult.errors.first ?? "Unknown error")"
          )
        }

        // Auto-reset status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
          self?.saveStatus = .idle
        }
        return
      }

      // Trigger hot reload via TCP
      let reloadResult = await triggerConfigReload()

      if reloadResult.isSuccess {
        AppLogger.shared.info("✅ [FileWatcher] External config successfully reloaded")
        Task { @MainActor in SoundManager.shared.playGlassSound() }

        // Update configuration service with the new conten
        await updateInMemoryConfig(configContent)

        await MainActor.run {
          saveStatus = .success
        }

        AppLogger.shared.log("📝 [FileWatcher] Configuration updated from external file")
      } else {
        let errorMessage = reloadResult.errorMessage ?? "Unknown error"
        AppLogger.shared.error("❌ [FileWatcher] External config reload failed: \(errorMessage)")
        Task { @MainActor in SoundManager.shared.playErrorSound() }

        await MainActor.run {
          saveStatus = .failed("External config reload failed: \(errorMessage)")
        }
      }

      // Auto-reset status after delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.saveStatus = .idle
      }

    } catch {
      AppLogger.shared.error("❌ [FileWatcher] Failed to read external config: \(error)")
      Task { @MainActor in SoundManager.shared.playErrorSound() }

      await MainActor.run {
        saveStatus = .failed("Failed to read external config: \(error.localizedDescription)")
      }

      // Auto-reset status after delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.saveStatus = .idle
      }
    }
  }

  /// Update in-memory configuration without saving to file (to avoid triggering file watcher)
  private func updateInMemoryConfig(_ configContent: String) async {
    // Parse the configuration to update key mappings in memory
    do {
      let parsedConfig = try configurationService.parseConfigurationFromString(configContent)
      await MainActor.run {
        applyKeyMappings(parsedConfig.keyMappings)
      }
    } catch {
      AppLogger.shared.warn("⚠️ [FileWatcher] Failed to parse config for in-memory update: \(error)")
    }
  }

  /// Attempts to recover from zombie keyboard capture when VirtualHID connection fails

  /// Starts Kanata with VirtualHID connection validation
  func startKanataWithValidation() async {
    // Check if VirtualHID daemon is running firs
    if !isKarabinerDaemonRunning() {
      AppLogger.shared.warn("⚠️ [Recovery] Karabiner daemon not running - recovery failed")
      self.lastError = "Recovery failed: Karabiner daemon not available"
      notifyStateChanged()
      return
    }

    // Try starting Kanata normally
    _ = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())
  }

  /// Configuration management errors
  private enum ConfigError: Error, LocalizedError {
    case noBackupAvailable
    case reloadFailed(String)
    case validationFailed([String])
    case postSaveValidationFailed(errors: [String])

    var errorDescription: String? {
      switch self {
      case .noBackupAvailable:
        "No backup configuration available for rollback"
      case .reloadFailed(let message):
        "Config reload failed: \(message)"
      case .validationFailed(let errors):
        "Config validation failed: \(errors.joined(separator: ", "))"
      case .postSaveValidationFailed(let errors):
        "Post-save validation failed: \(errors.joined(separator: ", "))"
      }
    }
  }

  /// Config backup for rollback capability
  private var lastGoodConfig: String?

  /// Backup current working config before making changes
  private func backupCurrentConfig() async {
    do {
      let currentConfig = try String(contentsOfFile: configPath, encoding: .utf8)
      lastGoodConfig = currentConfig
      AppLogger.shared.log("💾 [Backup] Current config backed up successfully")
    } catch {
      AppLogger.shared.warn("⚠️ [Backup] Failed to backup current config: \(error)")
    }
  }

  /// Restore last known good config in case of validation failure
  private func restoreLastGoodConfig() async throws {
    guard let backup = lastGoodConfig else {
      throw KeyPathError.configuration(.backupNotFound)
    }

    try backup.write(toFile: configPath, atomically: true, encoding: .utf8)
    AppLogger.shared.info("🔄 [Restore] Restored last good config successfully")
  }

  func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
    let diagnostics = diagnosticsManager.diagnoseFailure(exitCode: exitCode, output: output)

    // Check for zombie keyboard capture bug (exit code 6 with VirtualHID connection failure)
    if exitCode == 6,
      output.contains("connect_failed asio.system:61")
        || output.contains("connect_failed asio.system:2")
    {
      // This is the "zombie keyboard capture" bug - automatically attempt recovery
      Task {
        AppLogger.shared.log(
          "🚨 [Recovery] Detected zombie keyboard capture - attempting automatic recovery")
        await self.attemptKeyboardRecovery()
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
        AppLogger.shared.error("❌ [AutoFix] Failed to reset config: \(error)")
        return false
      }

    case .process:
      if diagnostic.title == "Process Terminated" {
        // Try restarting Kanata
        let engine = InstallerEngine()
        _ = await engine.run(intent: .repair, using: PrivilegeBroker())
        AppLogger.shared.log("🔧 [AutoFix] Attempted to restart Kanata")
        return await engine.inspectSystem().services.kanataRunning
      }

    default:
      return false
    }

    return false
  }

  func getSystemDiagnostics() async -> [KanataDiagnostic] {
    await diagnosticsManager.getSystemDiagnostics(engineClient: engineClient)
  }

  // Check if permission issues should trigger the wizard
  func shouldShowWizardForPermissions() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.blockingIssue != nil
  }

  // MARK: - Public Interface

  // MARK: - UI-Focused Lifecycle Methods (from SimpleKanataManager)

  /// Check if this is a fresh install (no Kanata binary or config)
  private func isFirstTimeInstall() -> Bool {
    // Check if Kanata binary is installed (considers SMAppService vs launchctl)
    let detector = KanataBinaryDetector.shared
    let isInstalled = detector.isInstalled()

    if !isInstalled {
      AppLogger.shared.log("🆕 [FreshInstall] Kanata binary not installed - fresh install detected")
      return true
    }

    // Check for user config file
    let configPath = NSHomeDirectory() + "/Library/Application Support/KeyPath/keypath.kbd"
    let hasUserConfig = FileManager.default.fileExists(atPath: configPath)

    if !hasUserConfig {
      AppLogger.shared.log(
        "🆕 [FreshInstall] No user config found at \(configPath) - fresh install detected")
      return true
    }

    AppLogger.shared.info(
      "✅ [FreshInstall] Both Kanata binary and user config exist - returning user")
    return false
  }

  // Removed: checkLaunchDaemonStatus, killProcess
  // Removed monitorKanataProcess() - no longer needed with LaunchDaemon service managemen

  /// Save a complete generated configuration (for Claude API generated configs)
  func saveGeneratedConfiguration(_ configContent: String) async throws {
    AppLogger.shared.log("💾 [KanataManager] Saving generated configuration")

    // Suppress file watcher to prevent double reload from our own write
    configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveGeneratedConfiguration")

    // Set saving status
    await MainActor.run {
      saveStatus = .saving
    }

    do {
      // VALIDATE BEFORE SAVING - prevent writing broken configs
      AppLogger.shared.debug("🔍 [KanataManager] Validating generated config before save...")
      let validation = await configurationService.validateConfiguration(configContent)

      if !validation.isValid {
        AppLogger.shared.error(
          "❌ [KanataManager] Generated config validation failed: \(validation.errors.joined(separator: ", "))"
        )
        await MainActor.run {
          saveStatus = .failed("Invalid config: \(validation.errors.first ?? "Unknown error")")
        }
        throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
      }

      AppLogger.shared.info("✅ [KanataManager] Generated config validation passed")

      // Backup current config before making changes
      await backupCurrentConfig()

      // Ensure config directory exists
      let configDirectoryURL = URL(fileURLWithPath: configDirectory)
      try FileManager.default.createDirectory(
        at: configDirectoryURL, withIntermediateDirectories: true)

      // Write the configuration file
      let configURL = URL(fileURLWithPath: configPath)
      try configContent.write(to: configURL, atomically: true, encoding: .utf8)

      AppLogger.shared.info("✅ [KanataManager] Generated configuration saved to \(configPath)")

      // Update last config update timestamp
      lastConfigUpdate = Date()

      // Parse the saved config to update key mappings (for UI display)
      let parsedMappings = parseKanataConfig(configContent)
      await MainActor.run {
        applyKeyMappings(parsedMappings)
      }

      // Play tink sound asynchronously to avoid blocking save pipeline
      Task { @MainActor in SoundManager.shared.playTinkSound() }

      // Trigger hot reload via TCP
      let reloadResult = await triggerConfigReload()
      if reloadResult.isSuccess {
        AppLogger.shared.info("✅ [KanataManager] TCP reload successful, config is active")
        // Play glass sound asynchronously to avoid blocking completion
        Task { @MainActor in SoundManager.shared.playGlassSound() }
        await MainActor.run {
          saveStatus = .success
        }
      } else {
        // TCP reload failed - this is a critical error for validation-on-demand
        let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
        AppLogger.shared.error("❌ [KanataManager] TCP reload FAILED: \(errorMessage)")
        AppLogger.shared.error(
          "❌ [KanataManager] Restoring backup since config couldn't be verified")

        // Play error sound asynchronously
        Task { @MainActor in SoundManager.shared.playErrorSound() }

        // Restore backup since we can't verify the config was applied
        try await restoreLastGoodConfig()

        await MainActor.run {
          saveStatus = .failed("Config reload failed: \(errorMessage)")
        }
        throw KeyPathError.configuration(.loadFailed(reason: "Hot reload failed: \(errorMessage)"))
      }

      // Reset to idle after a delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.saveStatus = .idle
      }

    } catch {
      await MainActor.run {
        saveStatus = .failed(
          "Failed to save generated configuration: \(error.localizedDescription)")
      }
      throw error
    }
  }

  func toggleRuleCollection(id: UUID, isEnabled: Bool) async {
    if isEnabled,
      let candidate = ruleCollections.first(where: { $0.id == id }),
      let conflict = await MainActor.run(body: { self.conflictInfo(for: candidate) })
    {
      await MainActor.run {
        lastError =
          "Cannot enable \(candidate.name). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
      }
      AppLogger.shared.log(
        "⚠️ [RuleCollections] Conflict enabling \(candidate.name) vs \(conflict.displayName) on \(conflict.keys)"
      )
      return
    }

    await MainActor.run {
      if let index = ruleCollections.firstIndex(where: { $0.id == id }) {
        ruleCollections[index].isEnabled = isEnabled
      }
      refreshLayerIndicatorState()
    }
    await regenerateConfigFromCollections()
  }

  func addRuleCollection(_ collection: RuleCollection) async {
    if let conflict = await MainActor.run(body: { self.conflictInfo(for: collection) }) {
      await MainActor.run {
        lastError =
          "Cannot enable \(collection.name). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
      }
      AppLogger.shared.log(
        "⚠️ [RuleCollections] Conflict adding \(collection.name) vs \(conflict.displayName) on \(conflict.keys)"
      )
      return
    }

    await MainActor.run {
      if let index = ruleCollections.firstIndex(where: { $0.id == collection.id }) {
        ruleCollections[index].isEnabled = true
        ruleCollections[index].summary = collection.summary
        ruleCollections[index].mappings = collection.mappings
        ruleCollections[index].category = collection.category
        ruleCollections[index].icon = collection.icon
      } else {
        ruleCollections.append(collection)
      }
      refreshLayerIndicatorState()
    }
    await regenerateConfigFromCollections()
  }

  @discardableResult
  func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
    if rule.isEnabled,
      let conflict = await MainActor.run(body: { self.conflictInfo(for: rule) })
    {
      await MainActor.run {
        lastError =
          "Cannot enable \(rule.displayTitle). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
      }
      AppLogger.shared.log(
        "⚠️ [CustomRules] Conflict saving \(rule.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
      )
      return false
    }

    await MainActor.run {
      if let index = customRules.firstIndex(where: { $0.id == rule.id }) {
        customRules[index] = rule
      } else {
        customRules.append(rule)
      }
    }
    await regenerateConfigFromCollections(skipReload: skipReload)
    return true
  }

  func toggleCustomRule(id: UUID, isEnabled: Bool) async {
    guard
      let existing = await MainActor.run(body: {
        self.customRules.first(where: { $0.id == id })
      })
    else { return }

    if isEnabled,
      let conflict = await MainActor.run(body: { self.conflictInfo(for: existing) })
    {
      await MainActor.run {
        lastError =
          "Cannot enable \(existing.displayTitle). Conflicts with \(conflict.displayName) on \(conflict.keys.joined(separator: ", "))."
      }
      AppLogger.shared.log(
        "⚠️ [CustomRules] Conflict enabling \(existing.displayTitle) vs \(conflict.displayName) on \(conflict.keys)"
      )
      return
    }

    await MainActor.run {
      if let index = customRules.firstIndex(where: { $0.id == id }) {
        customRules[index].isEnabled = isEnabled
      }
    }
    await regenerateConfigFromCollections()
  }

  func removeCustomRule(withID id: UUID) async {
    await MainActor.run {
      customRules.removeAll { $0.id == id }
    }
    await regenerateConfigFromCollections()
  }

  private func regenerateConfigFromCollections(skipReload: Bool = false) async {
    do {
      try await ruleCollectionStore.saveCollections(ruleCollections)
      try await customRulesStore.saveRules(customRules)
      try await configurationService.saveConfiguration(
        ruleCollections: ruleCollections,
        customRules: customRules
      )
      applyKeyMappings(
        ruleCollections.enabledMappings() + customRules.enabledMappings(), persistCollections: false
      )
      if !skipReload {
        _ = await triggerConfigReload()
      }
      notifyStateChanged()
    } catch {
      AppLogger.shared.log("❌ [RuleCollections] Failed to regenerate config: \(error)")
      notifyStateChanged()
    }
  }

  private func makeCustomRuleForSave(input: String, output: String) async -> CustomRule {
    await MainActor.run {
      if let existing = customRules.first(where: {
        $0.input.caseInsensitiveCompare(input) == .orderedSame
      }) {
        CustomRule(
          id: existing.id,
          title: existing.title,
          input: input,
          output: output,
          isEnabled: true,
          notes: existing.notes,
          createdAt: existing.createdAt
        )
      } else {
        CustomRule(input: input, output: output)
      }
    }
  }

  func saveConfiguration(input: String, output: String) async throws {
    // Suppress file watcher to prevent double reload from our own write
    configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal saveConfiguration")

    // Set saving status
    await MainActor.run {
      saveStatus = .saving
    }

    do {
      let sanitizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
      let sanitizedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !sanitizedInput.isEmpty, !sanitizedOutput.isEmpty else {
        throw KeyPathError.configuration(
          .validationFailed(errors: ["Input and output are required."]))
      }

      let rule = await makeCustomRuleForSave(input: sanitizedInput, output: sanitizedOutput)

      // Backup current config before making changes
      await backupCurrentConfig()

      // Persist without triggering reload (handled below)
      let didSave = await saveCustomRule(rule, skipReload: true)
      guard didSave else {
        let message = await MainActor.run { lastError ?? "Unknown conflict" }
        await MainActor.run {
          saveStatus = .failed(message)
        }
        throw KeyPathError.configuration(.validationFailed(errors: [message]))
      }

      // Play tink sound asynchronously to avoid blocking save pipeline
      Task { @MainActor in SoundManager.shared.playTinkSound() }

      // Attempt TCP reload to validate config
      AppLogger.shared.debug("📡 [Config] Triggering TCP reload for validation")
      let tcpResult = await triggerTCPReload()

      if tcpResult.isSuccess {
        // Reload succeeded - config is valid
        AppLogger.shared.info("✅ [Config] Reload successful, config is valid")

        // Play glass sound asynchronously to avoid blocking completion
        Task { @MainActor in SoundManager.shared.playGlassSound() }

        await MainActor.run {
          saveStatus = .success
        }
      } else {
        // TCP reload failed - this is a critical error for validation-on-demand
        let errorMessage = tcpResult.errorMessage ?? "TCP server unresponsive"
        AppLogger.shared.error("❌ [Config] TCP reload FAILED: \(errorMessage)")
        AppLogger.shared.error(
          "❌ [Config] TCP server is required for validation-on-demand - restoring backup")

        // Play error sound asynchronously
        Task { @MainActor in SoundManager.shared.playErrorSound() }

        // Restore backup since we can't verify the config was applied
        try await restoreLastGoodConfig()

        // Set error status
        await MainActor.run {
          saveStatus = .failed("TCP server reload failed: \(errorMessage)")
        }
        throw KeyPathError.configuration(
          .loadFailed(
            reason: "TCP server required for validation-on-demand failed: \(errorMessage)"))
      }

      // Reset to idle after a delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.saveStatus = .idle
      }

    } catch {
      // Handle any errors
      await MainActor.run {
        saveStatus = .failed(error.localizedDescription)
      }
      throw error
    }

    AppLogger.shared.log("⚡ [Config] Validation-on-demand save completed")
  }

  func updateStatus() async {
    // Legacy status update removed - state is now managed by InstallerEngine/SystemContext
    notifyStateChanged()
  }

  // Removed: isProcessRunningFast, waitForServiceReady, updateInternalState, performUpdateStatus

  private func captureRecentKanataErrorMessage() -> String? {
    let stderrPath = "/var/log/com.keypath.kanata.stderr.log"
    guard let contents = try? String(contentsOfFile: stderrPath, encoding: .utf8) else {
      return nil
    }

    let lines =
      contents
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { stripANSICodes(from: String($0)) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    for line in lines.reversed() {
      let lower = line.lowercased()
      if lower.contains("error") || lower.contains("could not") {
        return line
      }
    }
    return lines.last
  }

  private func stripANSICodes(from text: String) -> String {
    text.replacingOccurrences(of: #"\u001B\[[0-9;]*m"#, with: "", options: .regularExpression)
  }

  /// Stop Kanata when the app is terminating (async version).
  func cleanup() async {
    try? await PrivilegeBroker().stopKanataService()
  }

  /// Synchronous cleanup for app termination - blocks until process is killed
  func cleanupSync() {
    AppLogger.shared.log("🛝 [Cleanup] Performing synchronous cleanup...")

    // LaunchDaemon service management - synchronous cleanup not directly supported
    // The LaunchDaemon service will handle process lifecycle automatically
    AppLogger.shared.log(
      "ℹ️ [Cleanup] LaunchDaemon service will handle process cleanup automatically")

    // Clean up PID file
    try? PIDFileManager.removePID()
    AppLogger.shared.info("✅ [Cleanup] Synchronous cleanup complete")
  }

  private func checkExternalKanataProcess() async -> Bool {
    // Delegate to ProcessLifecycleManager for conflict detection
    let conflicts = await processLifecycleManager.detectConflicts()
    return !conflicts.externalProcesses.isEmpty
  }

  // MARK: - Installation and Permissions

  func isInstalled() -> Bool {
    // Use KanataBinaryDetector for consistent detection across wizard and UI
    // This accepts both system installation AND bundled binary (for SMAppService)
    // Note: This is a synchronous wrapper, but KanataBinaryDetector uses fast filesystem checks
    KanataBinaryDetector.shared.isInstalled()
  }

  func isCompletelyInstalled() -> Bool {
    isInstalled() && isServiceInstalled()
  }

  // Compatibility wrappers for legacy tests - using Oracle
  func hasInputMonitoringPermission() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.keyPath.inputMonitoring.isReady
  }

  func hasAccessibilityPermission() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.keyPath.accessibility.isReady
  }

  // REMOVED: checkAccessibilityForPath() - now handled by PermissionService.checkTCCForAccessibility()

  // REMOVED: checkTCCForAccessibility() - now handled by PermissionService

  func checkBothAppsHavePermissions() async -> (
    keyPathHasPermission: Bool, kanataHasPermission: Bool, permissionDetails: String
  ) {
    let snapshot = await PermissionOracle.shared.currentSnapshot()

    let keyPathPath = Bundle.main.bundlePath
    let kanataPath = WizardSystemPaths.kanataActiveBinary

    let keyPathHasInputMonitoring = snapshot.keyPath.inputMonitoring.isReady
    let keyPathHasAccessibility = snapshot.keyPath.accessibility.isReady
    let kanataHasInputMonitoring = snapshot.kanata.inputMonitoring.isReady
    let kanataHasAccessibility = snapshot.kanata.accessibility.isReady

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

  func hasAllRequiredPermissions() async -> Bool {
    let snapshot = await PermissionOracle.shared.currentSnapshot()
    return snapshot.keyPath.hasAllPermissions
  }

  func hasAllSystemRequirements() async -> Bool {
    let hasPermissions = await hasAllRequiredPermissions()
    return isInstalled() && hasPermissions && isKarabinerDriverInstalled()
      && isKarabinerDaemonRunning()
  }

  func getSystemRequirementsStatus() async -> (
    installed: Bool, permissions: Bool, driver: Bool, daemon: Bool
  ) {
    let permissions = await hasAllRequiredPermissions()
    return (
      installed: isInstalled(),
      permissions: permissions,
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

  /// Reveal the canonical kanata binary in Finder to assist drag-and-drop into permissions
  func revealKanataInFinder() {
    let kanataPath = WizardSystemPaths.kanataActiveBinary
    let folderPath = (kanataPath as NSString).deletingLastPathComponent

    let script = """
      tell application "Finder"
          activate
          set targetFolder to POSIX file "\(folderPath)" as alias
          set targetWindow to make new Finder window to targetFolder
          set current view of targetWindow to icon view
          set arrangement of icon view options of targetWindow to arranged by name
          set bounds of targetWindow to {200, 140, 900, 800}
          select POSIX file "\(kanataPath)" as alias
          delay 0.5
      end tell
      """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
      appleScript.executeAndReturnError(&error)
      if let error {
        AppLogger.shared.error("❌ [Finder] AppleScript error revealing kanata: \(error)")
      } else {
        AppLogger.shared.info("✅ [Finder] Revealed kanata in Finder: \(kanataPath)")
        // Show guide bubble slightly below the icon (fallback if we cannot resolve exact AX position)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          self.showDragAndDropHelpBubble()
        }
      }
    } else {
      AppLogger.shared.error("❌ [Finder] Could not create AppleScript to reveal kanata.")
    }
  }

  /// Show floating help bubble near the Finder selection, with fallback positioning
  private func showDragAndDropHelpBubble() {
    // Note: Post a notification for the UI layer to show a contextual help bubble
    // Core library cannot directly call UI components
    AppLogger.shared.log(
      "ℹ️ [Bubble] Help bubble would be shown here (needs notification-based implementation)")
  }

  func isKarabinerDriverInstalled() -> Bool {
    karabinerConflictService.isKarabinerDriverInstalled()
  }

  func isKarabinerDriverExtensionEnabled() -> Bool {
    karabinerConflictService.isKarabinerDriverExtensionEnabled()
  }

  func areKarabinerBackgroundServicesEnabled() -> Bool {
    karabinerConflictService.areKarabinerBackgroundServicesEnabled()
  }

  func isKarabinerElementsRunning() -> Bool {
    karabinerConflictService.isKarabinerElementsRunning()
  }

  // Removed legacy helper command string (avoid exposing unload/load guidance)

  /// Permanently disable all Karabiner Elements services with user permission
  func disableKarabinerElementsPermanently() async -> Bool {
    await karabinerConflictService.disableKarabinerElementsPermanently()
  }

  func killKarabinerGrabber() async -> Bool {
    await karabinerConflictService.killKarabinerGrabber()
  }

  func isKarabinerDaemonRunning() -> Bool {
    karabinerConflictService.isKarabinerDaemonRunning()
  }

  func startKarabinerDaemon() async -> Bool {
    await karabinerConflictService.startKarabinerDaemon()
  }

  func restartKarabinerDaemon() async -> Bool {
    await karabinerConflictService.restartKarabinerDaemon()
  }

  /// Diagnostic summary explaining why VirtualHID service is considered broken
  /// Used to surface a helpful error toast in the wizard
  func getVirtualHIDBreakageSummary() -> String {
    // Gather low-level daemon state via DiagnosticsService
    let status = diagnosticsService.virtualHIDDaemonStatus()

    // Driver extension + version
    let driverEnabled = isKarabinerDriverExtensionEnabled()
    let vhid = VHIDDeviceManager()
    let installedVersion = vhid.getInstalledVersion() ?? "unknown"
    let hasMismatch = vhid.hasVersionMismatch()

    let summary = Self.makeVirtualHIDBreakageSummary(
      status: status,
      driverEnabled: driverEnabled,
      installedVersion: installedVersion,
      hasMismatch: hasMismatch
    )
    AppLogger.shared.log("🔎 [VHID-DIAG] Diagnostic summary:\n\(summary)")
    AppLogger.shared.log(
      "🔎 [RestartOutcome] \(status.pids.count == 1 ? "single-owner" : (status.pids.isEmpty ? "not-running" : "duplicate")) PIDs=\(status.pids.joined(separator: ", "))"
    )
    return summary
  }

  // Extracted for testability
  static func makeVirtualHIDBreakageSummary(
    status: VirtualHIDDaemonStatus,
    driverEnabled: Bool,
    installedVersion: String,
    hasMismatch: Bool
  ) -> String {
    var lines: [String] = []
    if status.pids.count > 1 {
      lines.append("Reason: Multiple VirtualHID daemons detected (\(status.pids.count)).")
      lines.append("PIDs: \(status.pids.joined(separator: ", "))")
      if !status.owners.isEmpty {
        lines.append("Owners:\n\(status.owners.joined(separator: "\n"))")
      }
    } else if status.pids.isEmpty {
      lines.append("Reason: VirtualHID daemon not running.")
    } else {
      // Single PID present
      let serviceHealth = status.serviceHealthy
      if serviceHealth == false {
        lines.append(
          "Reason: Daemon running (PID \(status.pids[0])) but launchctl health check failed.")
        lines.append(
          "This often indicates a stale service registration, but the driver may still work.")
      } else {
        lines.append("Daemon running (PID \(status.pids[0])) and launchctl reports healthy.")
        lines.append("If the wizard still shows red, click Fix to resync status.")
      }
      lines.append("PID: \(status.pids[0])")
      if !status.owners.isEmpty { lines.append("Owner:\n\(status.owners.joined(separator: "\n"))") }
    }
    let launchState = status.serviceInstalled ? "installed" : "not installed"
    let launchSuffix = status.serviceInstalled ? ", \(status.serviceState)" : ""
    lines.append("LaunchDaemon: \(launchState)\(launchSuffix)")
    lines.append("Driver extension: \(driverEnabled ? "enabled" : "disabled")")
    let versionSuffix = hasMismatch ? " (incompatible with current Kanata)" : ""
    lines.append("Driver version: \(installedVersion)\(versionSuffix)")
    return lines.joined(separator: "\n")
  }

  func performTransparentInstallation() async -> Bool {
    AppLogger.shared.log("🔧 [Installation] Starting transparent installation...")

    var stepsCompleted = 0
    var stepsFailed = 0
    let totalSteps = 5

    // 1. Ensure Kanata binary exists - install if missing
    AppLogger.shared.log(
      "🔧 [Installation] Step 1/\(totalSteps): Checking/installing Kanata binary...")

    // Use KanataBinaryDetector for consistent detection logic
    let detector = KanataBinaryDetector.shared

    // With SMAppService, bundled Kanata is sufficient - no system installation needed
    if detector.isInstalled() {
      AppLogger.shared.log(
        "✅ [Installation] Step 1 SUCCESS: Kanata binary ready (SMAppService uses bundled path)")
      stepsCompleted += 1
    } else {
      AppLogger.shared.log(
        "⚠️ [Installation] Step 1 WARNING: Kanata binary not found in bundle (SMAppService mode)")
      stepsFailed += 1
    }

    // 2. Check if Karabiner driver is installed
    AppLogger.shared.log("🔧 [Installation] Step 2/\(totalSteps): Checking Karabiner driver...")
    let driverPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    if !FileManager.default.fileExists(atPath: driverPath) {
      AppLogger.shared.log(
        "⚠️ [Installation] Step 2 WARNING: Karabiner driver not found at \(driverPath)")
      AppLogger.shared.log("ℹ️ [Installation] User should install Karabiner-Elements first")
      // Don't fail installation for this - just warn
    } else {
      AppLogger.shared.log(
        "✅ [Installation] Step 2 SUCCESS: Karabiner driver verified at \(driverPath)")
    }
    stepsCompleted += 1

    // 3. Prepare Karabiner daemon directories
    AppLogger.shared.log("🔧 [Installation] Step 3/\(totalSteps): Preparing daemon directories...")
    await prepareDaemonDirectories()
    AppLogger.shared.info("✅ [Installation] Step 3 SUCCESS: Daemon directories prepared")
    stepsCompleted += 1

    // 4. Create initial config if needed
    AppLogger.shared.log("🔧 [Installation] Step 4/\(totalSteps): Creating user configuration...")
    await createInitialConfigIfNeeded()
    if FileManager.default.fileExists(atPath: configPath) {
      AppLogger.shared.log(
        "✅ [Installation] Step 4 SUCCESS: User config available at \(configPath)")
      stepsCompleted += 1
    } else {
      AppLogger.shared.error("❌ [Installation] Step 4 FAILED: User config missing at \(configPath)")
      stepsFailed += 1
    }

    // 5. No longer needed - LaunchDaemon reads user config directly
    AppLogger.shared.log(
      "🔧 [Installation] Step 5/\(totalSteps): System config step skipped - LaunchDaemon uses user config directly"
    )
    AppLogger.shared.info("✅ [Installation] Step 5 SUCCESS: Using ~/.config/keypath path directly")
    stepsCompleted += 1

    let success = stepsCompleted >= 4  // Require at least user config + binary + directories
    if success {
      AppLogger.shared.log(
        "✅ [Installation] Installation completed successfully (\(stepsCompleted)/\(totalSteps) steps completed)"
      )
    } else {
      AppLogger.shared.log(
        "❌ [Installation] Installation failed (\(stepsFailed) steps failed, only \(stepsCompleted)/\(totalSteps) completed)"
      )
    }

    return success
  }

  // createSystemConfigIfNeeded() removed - no longer needed since LaunchDaemon reads user config directly

  private func prepareDaemonDirectories() async {
    AppLogger.shared.log("🔧 [Daemon] Preparing Karabiner daemon directories...")

    // The daemon needs access to /Library/Application Support/org.pqrs/tmp/rootonly
    // We'll create this directory with proper permissions during installation
    let rootOnlyPath = "/Library/Application Support/org.pqrs/tmp/rootonly"
    let tmpPath = "/Library/Application Support/org.pqrs/tmp"

    // Use AppleScript to run commands with admin privileges
    let createDirScript = """
      do shell script "mkdir -p '\(rootOnlyPath)' && chown -R \(NSUserName()) '\(tmpPath)' && chmod -R 755 '\(tmpPath)'"
      with administrator privileges
      with prompt "KeyPath needs to prepare system directories for the virtual keyboard."
      """

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
        AppLogger.shared.info("✅ [Daemon] Successfully prepared daemon directories")

        // Also ensure log directory exists and is accessible
        let logDirScript =
          "do shell script \"mkdir -p '/var/log/karabiner' && chmod 755 '/var/log/karabiner'\" with administrator privileges with prompt \"KeyPath needs to create system log directories.\""

        let logTask = Process()
        logTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        logTask.arguments = ["-e", logDirScript]

        try logTask.run()
        logTask.waitUntilExit()

        if logTask.terminationStatus == 0 {
          AppLogger.shared.info("✅ [Daemon] Log directory permissions set")
        } else {
          AppLogger.shared.warn("⚠️ [Daemon] Could not set log directory permissions")
        }
      } else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        AppLogger.shared.error("❌ [Daemon] Failed to prepare directories: \(output)")
      }
    } catch {
      AppLogger.shared.error("❌ [Daemon] Error preparing daemon directories: \(error)")
    }
  }

  // MARK: - Configuration Managemen

  /// Load and strictly validate existing configuration with fallback to defaul
  private func loadExistingMappings() async {
    AppLogger.shared.log("📂 [Validation] ========== STARTUP CONFIG VALIDATION BEGIN ==========")
    await MainActor.run {
      applyKeyMappings([], persistCollections: false)
    }

    guard FileManager.default.fileExists(atPath: configPath) else {
      AppLogger.shared.log("ℹ️ [Validation] No existing config file found at: \(configPath)")
      AppLogger.shared.log("ℹ️ [Validation] Starting with empty mappings")
      AppLogger.shared.log("📂 [Validation] ========== STARTUP CONFIG VALIDATION END ==========")
      return
    }

    do {
      AppLogger.shared.log("📖 [Validation] Reading config file from: \(configPath)")
      let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
      AppLogger.shared.log("📖 [Validation] Config file size: \(configContent.count) characters")

      // Strict CLI validation to match engine behavior on startup
      AppLogger.shared.log("🔍 [Validation] Running CLI validation of existing configuration...")
      let cli = configurationService.validateConfigViaFile()
      if cli.isValid {
        AppLogger.shared.log("✅ [Validation] CLI validation PASSED")
        let config = try await configurationService.reload()
        await MainActor.run {
          applyKeyMappings(config.keyMappings)
        }
        AppLogger.shared.log(
          "✅ [Validation] Successfully loaded \(config.keyMappings.count) existing mappings")
      } else {
        AppLogger.shared.log("❌ [Validation] CLI validation FAILED with \(cli.errors.count) errors")
        await handleInvalidStartupConfig(configContent: configContent, errors: cli.errors)
      }
    } catch {
      AppLogger.shared.error("❌ [Validation] Failed to load existing config: \(error)")
      AppLogger.shared.error("❌ [Validation] Error type: \(type(of: error))")
      await MainActor.run {
        applyKeyMappings([], persistCollections: false)
      }
    }

    AppLogger.shared.log("📂 [Validation] ========== STARTUP CONFIG VALIDATION END ==========")
  }

  /// Handle invalid startup configuration with backup and fallback
  private func handleInvalidStartupConfig(configContent: String, errors: [String]) async {
    AppLogger.shared.log("🛡️ [Validation] Handling invalid startup configuration...")

    // Create backup of invalid config
    let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
      of: ":", with: "-")
    let backupPath = "\(configDirectory)/invalid-config-backup-\(timestamp).kbd"

    AppLogger.shared.log("💾 [Validation] Creating backup of invalid config...")
    do {
      try configContent.write(toFile: backupPath, atomically: true, encoding: .utf8)
      AppLogger.shared.log("💾 [Validation] Successfully backed up invalid config to: \(backupPath)")
      AppLogger.shared.log("💾 [Validation] Backup file size: \(configContent.count) characters")
    } catch {
      AppLogger.shared.error("❌ [Validation] Failed to backup invalid config: \(error)")
      AppLogger.shared.error("❌ [Validation] Backup path attempted: \(backupPath)")
    }

    // Generate default configuration
    AppLogger.shared.log("🔧 [Validation] Generating default fallback configuration...")
    let defaultMapping = KeyMapping(input: "caps", output: "esc")
    let defaultConfig = generateKanataConfigWithMappings([defaultMapping])
    AppLogger.shared.log("🔧 [Validation] Default config generated with mapping: caps → esc")

    do {
      AppLogger.shared.log("📝 [Validation] Writing default config to: \(configPath)")
      try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
      await MainActor.run {
        applyKeyMappings([defaultMapping])
      }
      AppLogger.shared.info("✅ [Validation] Successfully replaced invalid config with default")
      AppLogger.shared.info("✅ [Validation] New config has 1 mapping")

      // Schedule user notification about the fallback
      AppLogger.shared.log("📢 [Validation] Scheduling user notification about config fallback...")
      await scheduleConfigValidationNotification(originalErrors: errors, backupPath: backupPath)
    } catch {
      AppLogger.shared.error("❌ [Validation] Failed to write default config: \(error)")
      AppLogger.shared.error("❌ [Validation] Config path: \(configPath)")
      await MainActor.run {
        applyKeyMappings([], persistCollections: false)
      }
    }

    AppLogger.shared.log("🛡️ [Validation] Invalid startup config handling complete")
  }

  /// Schedule notification to inform user about config validation issues
  private func scheduleConfigValidationNotification(originalErrors: [String], backupPath: String)
    async
  {
    AppLogger.shared.log("📢 [Config] Showing validation error dialog to user")

    await MainActor.run {
      if TestEnvironment.isRunningTests {
        AppLogger.shared.debug("🧪 [Config] Suppressing validation alert in test environment")
        return
      }
      validationAlertTitle = "Configuration File Invalid"
      validationAlertMessage = """
        KeyPath detected errors in your configuration file and has automatically created a backup and restored default settings.

        Errors found:
        \(originalErrors.joined(separator: "\n• "))

        Your original configuration has been backed up to:
        \(backupPath)

        KeyPath is now using a default configuration (Caps Lock → Escape).
        """

      validationAlertActions = [
        ValidationAlertAction(title: "OK", style: .default) { [weak self] in
          self?.showingValidationAlert = false
        },
        ValidationAlertAction(title: "Open Backup Location", style: .default) { [weak self] in
          if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
              "🧪 [Config] Suppressing NSWorkspace file viewer in test environment")
          } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
          }
          self?.showingValidationAlert = false
        },
      ]

      showingValidationAlert = true
    }
  }

  /// Show validation error dialog with options to cancel or revert to defaul
  private func showValidationErrorDialog(title: String, errors: [String], config _: String? = nil)
    async
  {
    await MainActor.run {
      validationAlertTitle = title
      validationAlertMessage = """
        KeyPath found errors in the configuration:

        \(errors.joined(separator: "\n• "))

        What would you like to do?
        """

      var actions: [ValidationAlertAction] = []

      // Cancel option
      actions.append(
        ValidationAlertAction(title: "Cancel", style: .cancel) { [weak self] in
          self?.showingValidationAlert = false
        })

      // Revert to default option
      actions.append(
        ValidationAlertAction(title: "Use Default Config", style: .destructive) { [weak self] in
          Task {
            await self?.revertToDefaultConfig()
            await MainActor.run {
              self?.showingValidationAlert = false
            }
          }
        })

      validationAlertActions = actions
      showingValidationAlert = true
    }
  }

  /// Revert to a safe default configuration
  private func revertToDefaultConfig() async {
    AppLogger.shared.info("🔄 [Config] Reverting to default configuration")

    let defaultMapping = KeyMapping(input: "caps", output: "esc")
    let defaultConfig = generateKanataConfigWithMappings([defaultMapping])

    do {
      try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
      await MainActor.run {
        applyKeyMappings([defaultMapping])
      }
      AppLogger.shared.info("✅ [Config] Successfully reverted to default configuration")
    } catch {
      AppLogger.shared.error("❌ [Config] Failed to revert to default configuration: \(error)")
    }
  }

  private func parseKanataConfig(_ configContent: String) -> [KeyMapping] {
    // Delegate to ConfigurationService for parsing
    do {
      let config = try configurationService.parseConfigurationFromString(configContent)
      return config.keyMappings
    } catch {
      AppLogger.shared.warn("⚠️ [Parse] Failed to parse config: \(error)")
      return []
    }
  }

  private func generateKanataConfigWithMappings(_ mappings: [KeyMapping]) -> String {
    // Delegate to KanataConfiguration utility
    guard !mappings.isEmpty else {
      // Return default config with caps->esc if no mappings
      let defaultMapping = KeyMapping(input: "caps", output: "escape")
      return KanataConfiguration.generateFromMappings([defaultMapping])
    }

    return KanataConfiguration.generateFromMappings(mappings)
  }

  // MARK: - Methods Expected by Tests

  func isServiceInstalled() -> Bool {
    let state = KanataDaemonManager.determineServiceManagementState()
    switch state {
    case .uninstalled:
      return false
    case .unknown:
      // Treat unknown as not installed to avoid false positives in tests/UI
      return false
    default:
      return true
    }
  }

  func getInstallationStatus() -> String {
    let detector = KanataBinaryDetector.shared
    let detection = detector.detectCurrentStatus()
    let driverInstalled = isKarabinerDriverInstalled()

    // With SMAppService, bundled Kanata is sufficient
    switch detection.status {
    case .bundledAvailable, .systemInstalled:
      return driverInstalled ? "✅ Fully installed" : "⚠️ Driver missing"
    case .bundledUnsigned:
      return "⚠️ Bundled Kanata unsigned (needs Developer ID signature)"
    case .missing:
      return "❌ Not installed"
    }
  }

  // MARK: - Configuration Backup Managemen

  /// Create a backup before opening config for editing
  /// Returns true if backup was created successfully
  func createPreEditBackup() -> Bool {
    configBackupManager.createPreEditBackup()
  }

  /// Get list of available configuration backups
  func getAvailableBackups() -> [BackupInfo] {
    configBackupManager.getAvailableBackups()
  }

  /// Restore configuration from a specific backup
  func restoreFromBackup(_ backup: BackupInfo) throws {
    try configBackupManager.restoreFromBackup(backup)

    // Trigger reload after restoration
    Task {
      _ = await self.triggerConfigReload()
    }
  }

  func resetToDefaultConfig() async throws {
    // IMPORTANT: Reset should ALWAYS work - it's a recovery mechanism for broken configs
    // Intentionally bypass validation here: force-write a known-good default config (enforced by tests)
    AppLogger.shared.log(
      "🔄 [Reset] Forcing reset to default config (no validation - recovery mode)")

    // Create a safety backup of the current config (if valid) before resetting
    let backupCreated = configBackupManager.createPreEditBackup()
    if backupCreated {
      AppLogger.shared.log("💾 [Reset] Safety backup created before default reset")
    } else {
      AppLogger.shared.log("⚠️ [Reset] No safety backup created (missing/invalid existing config)")
    }

    // Reset to macOS Function Keys collection only (enabled by default)
    let defaultCollections = KanataConfiguration.systemDefaultCollections
    let defaultConfig = KanataConfiguration.generateFromCollections(defaultCollections)
    let configURL = URL(fileURLWithPath: configPath)

    // Ensure config directory exists
    let configDir = URL(fileURLWithPath: configDirectory)
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

    // Write the default config (unconditionally)
    try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

    AppLogger.shared.log("💾 [Config] Reset to default configuration (macOS Function Keys only)")

    // Update the stores to reflect the reset state
    try await ruleCollectionStore.saveCollections(defaultCollections)
    try await customRulesStore.saveRules([])  // Clear custom rules

    // Update manager properties so UI reflects the reset state
    await MainActor.run {
      self.ruleCollections = defaultCollections
      self.customRules = []
      ensureDefaultCollectionsIfNeeded()
      refreshLayerIndicatorState()
    }

    AppLogger.shared.log("🔄 [Reset] Updated stores and manager properties to match default state")

    // Apply changes immediately via TCP reload if service is running
    let context = await InstallerEngine().inspectSystem()
    if context.services.kanataRunning {
      AppLogger.shared.info("🔄 [Reset] Triggering immediate config reload via TCP...")
      let reloadResult = await triggerConfigReload()

      if reloadResult.isSuccess {
        let response = reloadResult.response ?? "Success"
        AppLogger.shared.info("✅ [Reset] Default config applied successfully via TCP: \(response)")
        // Play happy chime on successful reset
        await MainActor.run {
          SoundManager.shared.playGlassSound()
          saveStatus = .success
        }
      } else {
        let error = reloadResult.errorMessage ?? "Unknown error"
        let response = reloadResult.response ?? "No response"
        AppLogger.shared.warn("⚠️ [Reset] TCP reload failed (\(error)), fallback restart initiated")
        AppLogger.shared.log("📝 [Reset] TCP response: \(response)")
        await MainActor.run {
          saveStatus = .failed("Reset reload failed: \(error)")
        }
        // If TCP reload fails, fall back to service restart
        let engine = InstallerEngine()
        _ = await engine.run(intent: .repair, using: PrivilegeBroker())
      }

      // Reset to idle after a delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.saveStatus = .idle
      }
    }
  }

  // MARK: - Pause/Resume Mappings for Recording

  /// Temporarily pause mappings (for raw key capture during recording)
  func pauseMappings() async -> Bool {
    AppLogger.shared.log("⏸️ [Mappings] Attempting to pause mappings for recording...")

    // Preferred: use privileged helper to kill Kanata processes (no admin prompt)
    do {
      try await PrivilegedOperationsCoordinator.shared.killAllKanataProcesses()
      // Small settle to ensure processes exi
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      AppLogger.shared.log("🛑 [Mappings] Paused by killing Kanata processes via helper")
      return true
    } catch {
      AppLogger.shared.warn("⚠️ [Mappings] Helper killAllKanataProcesses failed: \(error)")
      return false
    }
  }

  /// Resume mappings after recording
  func resumeMappings() async -> Bool {
    AppLogger.shared.log("▶️ [Mappings] Attempting to resume mappings after recording...")

    do {
      try await PrivilegedOperationsCoordinator.shared.restartUnhealthyServices()
      // Give it a brief moment to come up
      try? await Task.sleep(nanoseconds: 200_000_000)
      AppLogger.shared.info("🚀 [Mappings] Resumed by restarting unhealthy services via helper")
      return true
    } catch {
      AppLogger.shared.warn("⚠️ [Mappings] Helper restartUnhealthyServices failed: \(error)")
      return false
    }
  }

  func convertToKanataKey(_ key: String) -> String {
    KanataKeyConverter.convertToKanataKey(key)
  }

  func convertToKanataSequence(_ sequence: String) -> String {
    KanataKeyConverter.convertToKanataSequence(sequence)
  }

  // MARK: - Real-Time VirtualHID Connection Monitoring

  // startLogMonitoring/stopLogMonitoring moved to KanataManager+Output.swif

  /// Analyze new log content for VirtualHID connection issues (delegates parsing to DiagnosticsService)
  func analyzeLogContent(_ content: String) async {
    let events = diagnosticsService.analyzeKanataLogChunk(content)
    for event in events {
      switch event {
      case .virtualHIDConnectionFailed:
        let shouldTriggerRecovery = await healthMonitor.recordConnectionFailure()
        if shouldTriggerRecovery {
          AppLogger.shared.log(
            "🚨 [LogMonitor] Maximum connection failures reached - triggering recovery")
          await triggerVirtualHIDRecovery()
        }
      case .virtualHIDConnected:
        await healthMonitor.recordConnectionSuccess()
      }
    }
  }

  // MARK: - One-click Service Regeneration

  /// Regenerate LaunchDaemon services (rewrite plists, bootstrap, kickstart) using current settings.
  /// Returns true on success.
  func regenerateServices() async -> Bool {
    AppLogger.shared.log("🔧 [Services] One-click regenerate services initiated")
    do {
      try await PrivilegedOperationsCoordinator.shared.regenerateServiceConfiguration()
      // Refresh status after regeneration to update UI promptly
      await updateStatus()
      AppLogger.shared.info("✅ [Services] Regenerate services completed")
      return true
    } catch {
      AppLogger.shared.error("❌ [Services] Regenerate services failed: \(error)")
      lastError = "Regenerate services failed: \(error.localizedDescription)"
      return false
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
        "Detected multiple consecutive asio.system connection failures",
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
    // Delegate to ConfigurationService for combined TCP+CLI validation
    await configurationService.validateConfiguration(config)
  }

  /// Uses Claude to repair a corrupted Kanata config
  private func repairConfigWithClaude(config: String, errors: [String], mappings: [KeyMapping])
    async throws -> String
  {
    // Try Claude API first, fallback to rule-based repair
    do {
      let prompt = """
        The following Kanata keyboard configuration file is invalid and needs to be repaired:

        INVALID CONFIG:
        ```
        \(config)
        ```

        VALIDATION ERRORS:
        \(errors.joined(separator: "\n"))

        INTENDED KEY MAPPINGS:
        \(mappings.map { "\($0.input) -> \($0.output)" }.joined(separator: "\n"))

        Please generate a corrected Kanata configuration that:
        1. Fixes all validation errors
        2. Preserves the intended key mappings
        3. Uses proper Kanata syntax
        4. Includes defcfg with process-unmapped-keys no and danger-enable-cmd yes
        5. Has proper defsrc and deflayer sections

        Return ONLY the corrected configuration file content, no explanations.
        """

      return try await callClaudeAPI(prompt: prompt)
    } catch {
      AppLogger.shared.warn(
        "⚠️ [KanataManager] Claude API failed: \(error), falling back to rule-based repair")
      // For now, use rule-based repair as fallback
      return try await performRuleBasedRepair(config: config, errors: errors, mappings: mappings)
    }
  }

  /// Fallback rule-based repair when Claude is not available
  private func performRuleBasedRepair(config: String, errors: [String], mappings: [KeyMapping])
    async throws -> String
  {
    // Delegate to ConfigurationService for rule-based repair
    try await configurationService.repairConfiguration(
      config: config, errors: errors, mappings: mappings)
  }

  /// Saves a validated config to disk
  private func saveValidatedConfig(_ config: String) async throws {
    // DEBUG: Log detailed file save information
    AppLogger.shared.debug("🔍 [DEBUG] saveValidatedConfig called")
    AppLogger.shared.debug("🔍 [DEBUG] Target config path: \(configPath)")
    AppLogger.shared.debug("🔍 [DEBUG] Config size: \(config.count) characters")

    // Config validation is performed by caller before reaching here
    AppLogger.shared.debug("📡 [SaveConfig] Saving validated config (TCP-only mode)")

    let configDir = URL(fileURLWithPath: configDirectory)
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    AppLogger.shared.debug("🔍 [DEBUG] Config directory created/verified: \(configDirectory)")

    let configURL = URL(fileURLWithPath: configPath)

    // Check if file exists before writing
    let fileExists = FileManager.default.fileExists(atPath: configPath)
    AppLogger.shared.debug("🔍 [DEBUG] Config file exists before write: \(fileExists)")

    // Get modification time before write (if file exists)
    var beforeModTime: Date?
    if fileExists {
      let beforeAttributes = try? FileManager.default.attributesOfItem(atPath: configPath)
      beforeModTime = beforeAttributes?[.modificationDate] as? Date
      AppLogger.shared.log(
        "🔍 [DEBUG] Modification time before write: \(beforeModTime?.description ?? "unknown")")
    }

    // Write the config
    try config.write(to: configURL, atomically: true, encoding: .utf8)
    AppLogger.shared.info("✅ [DEBUG] Config written to file successfully")

    // Note: File watcher delay removed - we use TCP reload commands instead of --watch

    // Get modification time after write
    let afterAttributes = try FileManager.default.attributesOfItem(atPath: configPath)
    let afterModTime = afterAttributes[.modificationDate] as? Date
    let fileSize = afterAttributes[.size] as? Int ?? 0

    AppLogger.shared.log(
      "🔍 [DEBUG] Modification time after write: \(afterModTime?.description ?? "unknown")")
    AppLogger.shared.debug("🔍 [DEBUG] File size after write: \(fileSize) bytes")

    // Calculate time difference if we have both times
    if let before = beforeModTime, let after = afterModTime {
      let timeDiff = after.timeIntervalSince(before)
      AppLogger.shared.debug("🔍 [DEBUG] File modification time changed by: \(timeDiff) seconds")
    }

    // Post-save validation: verify the file was saved correctly
    await MainActor.run {
      saveStatus = .validating
    }

    AppLogger.shared.debug(
      "🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION BEGIN ==========")
    AppLogger.shared.debug("🔍 [Validation-PostSave] Validating saved config at: \(configPath)")
    do {
      let savedContent = try String(contentsOfFile: configPath, encoding: .utf8)
      AppLogger.shared.log(
        "📖 [Validation-PostSave] Successfully read saved file (\(savedContent.count) characters)")

      let postSaveStart = Date()
      let postSaveValidation = await validateGeneratedConfig(savedContent)
      let postSaveDuration = Date().timeIntervalSince(postSaveStart)
      AppLogger.shared.log(
        "⏱️ [Validation-PostSave] Validation completed in \(String(format: "%.3f", postSaveDuration)) seconds"
      )

      if postSaveValidation.isValid {
        AppLogger.shared.info("✅ [Validation-PostSave] Post-save validation PASSED")
        AppLogger.shared.info("✅ [Validation-PostSave] Config saved and verified successfully")
      } else {
        AppLogger.shared.error("❌ [Validation-PostSave] Post-save validation FAILED")
        AppLogger.shared.error(
          "❌ [Validation-PostSave] Found \(postSaveValidation.errors.count) errors:")
        for (index, error) in postSaveValidation.errors.enumerated() {
          AppLogger.shared.log("   Error \(index + 1): \(error)")
        }
        AppLogger.shared.log("🎭 [Validation-PostSave] Showing error dialog to user...")
        await showValidationErrorDialog(
          title: "Save Verification Failed", errors: postSaveValidation.errors)
        AppLogger.shared.debug(
          "🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
        throw KeyPathError.configuration(.validationFailed(errors: postSaveValidation.errors))
      }
    } catch {
      AppLogger.shared.error("❌ [Validation-PostSave] Failed to read saved config: \(error)")
      AppLogger.shared.error("❌ [Validation-PostSave] Error type: \(type(of: error))")
      AppLogger.shared.debug(
        "🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
      throw error
    }

    AppLogger.shared.debug("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")

    // Notify UI that config was updated
    lastConfigUpdate = Date()
    AppLogger.shared.debug("🔍 [DEBUG] lastConfigUpdate timestamp set to: \(lastConfigUpdate)")
  }

  // Synchronize config to system path for Kanata --watch compatibility
  // synchronizeConfigToSystemPath removed - no longer needed since LaunchDaemon reads user config directly

  /// Backs up a failed config and applies safe default, returning backup path
  func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
    -> String
  {
    // Delegate to ConfigurationService for backup and safe config application
    let backupPath = try await configurationService.backupFailedConfigAndApplySafe(
      failedConfig: failedConfig,
      mappings: mappings
    )

    // Update in-memory mappings to reflect the safe state
    await MainActor.run {
      applyKeyMappings([KeyMapping(input: "caps", output: "escape")])
    }

    return backupPath
  }

  /// Opens a file in Zed editor with fallback options
  func openFileInZed(_ filePath: String) {
    configurationManager.openInEditor(filePath)
  }

  // MARK: - Kanata Arguments Builder

  /// Builds Kanata command line arguments including TCP port when enabled
  func buildKanataArguments(configPath _: String, checkOnly: Bool = false) -> [String] {
    // Delegate to ConfigurationManager
    configurationManager.buildKanataArguments(checkOnly: checkOnly)
  }

  // MARK: - Claude API Integration

  /// Call Claude API to repair configuration
  private func callClaudeAPI(prompt: String) async throws -> String {
    // Check for API key in environment or keychain
    guard let apiKey = getClaudeAPIKey() else {
      throw NSError(
        domain: "ClaudeAPI", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Claude API key not found. Set ANTHROPIC_API_KEY environment variable or store in Keychain."
        ])
    }

    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
      throw NSError(
        domain: "ClaudeAPI", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid Claude API URL"])
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let requestBody: [String: Any] = [
      "model": "claude-3-5-sonnet-20241022",
      "max_tokens": 4096,
      "messages": [
        [
          "role": "user",
          "content": prompt,
        ]
      ],
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw NSError(
        domain: "ClaudeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }

    guard 200...299 ~= httpResponse.statusCode else {
      let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw NSError(
        domain: "ClaudeAPI", code: httpResponse.statusCode,
        userInfo: [
          NSLocalizedDescriptionKey:
            "API request failed (\(httpResponse.statusCode)): \(errorMessage)"
        ])
    }

    guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let content = jsonResponse["content"] as? [[String: Any]],
      let firstContent = content.first,
      let text = firstContent["text"] as? String
    else {
      throw NSError(
        domain: "ClaudeAPI", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude API response"])
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Get Claude API key from environment variable or keychain
  private func getClaudeAPIKey() -> String? {
    // First try environment variable
    if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
      return envKey
    }

    // Try keychain (using the same pattern as other keychain access in the app)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "KeyPath",
      kSecAttrAccount as String: "claude-api-key",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    guard status == errSecSuccess,
      let data = dataTypeRef as? Data,
      let key = String(data: data, encoding: .utf8)
    else {
      return nil
    }

    return key
  }
}
