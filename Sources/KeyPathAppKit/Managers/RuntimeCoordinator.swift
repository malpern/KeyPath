import ApplicationServices
@preconcurrency import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
import Network
import SwiftUI

// KeyMapping is now in Models/KeyMapping.swift

/// Manages the Kanata process lifecycle and configuration directly.
///
/// # Architecture: Main Coordinator + Extension Files (2,820 lines total)
///
/// RuntimeCoordinator is the main orchestrator for Kanata process management and configuration.
/// It's split across multiple extension files for maintainability:
///
/// ## Extension Files (organized by concern):
///
/// **RuntimeCoordinator.swift** (main file, ~1,200 lines)
/// - Core initialization and state managemen
/// - UI state snapshots and ViewModel interface
/// - Health monitoring and auto-start logic
/// - Diagnostics and error handling
///
/// **RuntimeCoordinator+Lifecycle.swift** (~400 lines)
/// - Process start/stop/restart operations
/// - LaunchDaemon service managemen
/// - State machine transitions
/// - Recovery and health checks
///
/// **RuntimeCoordinator+Configuration.swift** (~500 lines)
/// - Config file I/O and validation
/// - Key mapping CRUD operations
/// - Backup and repair logic
/// - TCP server configuration
///
/// **RuntimeCoordinator+Engine.swift** (~300 lines)
/// - Kanata engine communication
/// - TCP protocol handling
/// - Config reload and layer managemen
///
/// **RuntimeCoordinator+EventTaps.swift** (~200 lines)
/// - CGEvent monitoring and key capture
/// - Keyboard input recording
/// - Event tap lifecycle
///
/// **RuntimeCoordinator+Output.swift** (~150 lines)
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
/// RuntimeCoordinator is **not** an ObservableObject. UI state is handled by `KanataViewModel`,
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

// SaveStatus is now in Models/KanataUIState.swift

@MainActor
class RuntimeCoordinator: SaveCoordinatorDelegate {
    // MARK: - Internal State Properties

    // Note: These are internal (not private) to allow extensions to access them
    // ViewModel reads these via getCurrentUIState() snapshot method

    // Core status tracking
    // Removed: isRunning
    var lastError: String?
    var lastWarning: String?
    var keyMappings: [KeyMapping] = []
    var currentLayerName: String = RuleCollectionLayer.base.displayName

    // Conflict resolution state
    var pendingRuleConflict: RuleConflictContext?
    private var conflictResolutionContinuation: CheckedContinuation<RuleConflictChoice?, Never>?

    // Rule collections are now managed by RuleCollectionsCoordinator
    var ruleCollections: [RuleCollection] {
        get { ruleCollectionsCoordinator.ruleCollections }
        set { /* Write access via coordinator methods only */ }
    }

    var customRules: [CustomRule] {
        get { ruleCollectionsCoordinator.customRules }
        set { /* Write access via coordinator methods only */ }
    }

    var diagnostics: [KanataDiagnostic] = []
    var lastProcessExitCode: Int32?
    var lastConfigUpdate: Date = .init()

    // Validation-specific UI state
    var validationError: ConfigValidationError?

    // Save progress feedback
    var saveStatus: SaveStatus = .idle {
        didSet {
            notifyStateChanged()
        }
    }

    // MARK: - SaveCoordinatorDelegate

    func saveStatusDidChange(_ status: SaveStatus) {
        saveStatus = status
    }

    func configDidUpdate(mappings: [KeyMapping]) {
        applyKeyMappings(mappings)
    }

    // MARK: - UI State Snapshot (Phase 4: MVVM - delegates to StatePublisherService)

    /// State publisher for reactive ViewModel updates
    private let statePublisher = StatePublisherService<KanataUIState>()

    /// Stream of UI state changes for reactive ViewModel updates
    nonisolated var stateChanges: AsyncStream<KanataUIState> {
        statePublisher.stateChanges
    }

    /// Configure state publisher (called during init)
    private func configureStatePublisher() {
        statePublisher.configure { [weak self] in
            self?.buildUIState() ?? KanataUIState.empty
        }
    }

    /// Notify observers that state has changed
    /// Call this after any operation that modifies UI-visible state
    private func notifyStateChanged() {
        statePublisher.notifyStateChanged()
    }

    /// Refresh process running state from system (call after service operations)
    /// This is more efficient than checking on every UI state sync
    func refreshProcessState() {
        notifyStateChanged()
    }

    /// Returns a snapshot of current UI state for ViewModel synchronization
    /// This method allows KanataViewModel to read UI state without @Published properties
    func getCurrentUIState() -> KanataUIState {
        buildUIState()
    }

    /// Build the current UI state snapshot
    private func buildUIState() -> KanataUIState {
        // Sync diagnostics from DiagnosticsManager
        diagnostics = diagnosticsManager.getDiagnostics()

        // Debug: Log custom rules count when building state
        AppLogger.shared.log("📊 [RuntimeCoordinator] buildUIState: customRules.count = \(customRules.count)")
        if let error = lastError {
            AppLogger.shared.debug("🚨 [RuntimeCoordinator] buildUIState: lastError = \(error)")
        }

        return KanataUIState(
            // Core Status
            lastError: lastError,
            lastWarning: lastWarning,
            keyMappings: keyMappings,
            ruleCollections: ruleCollections,
            customRules: customRules,
            currentLayerName: currentLayerName,
            diagnostics: diagnostics,
            lastProcessExitCode: lastProcessExitCode,
            lastConfigUpdate: lastConfigUpdate,

            // Validation & Save Status
            validationError: validationError,
            saveStatus: saveStatus,

            // Rule conflict resolution
            pendingRuleConflict: pendingRuleConflict
        )
    }

    let configDirectory = KeyPathConstants.Config.directory
    let configFileName = "keypath.kbd"

    // MARK: - Manager Dependencies (Refactored Architecture)

    let processManager: ProcessManaging
    let configurationManager: ConfigurationManaging
    let diagnosticsManager: DiagnosticsManaging
    let configRepairService: ConfigRepairService

    // Manager dependencies (exposed for extensions that need direct access)
    let engineClient: EngineClient

    // Legacy dependencies (kept for backward compatibility during transition)
    let configurationService: ConfigurationService
    let processLifecycleManager: ProcessLifecycleManager

    // Additional dependencies needed by extensions
    private let processCoordinator: ProcessCoordinating
    let installerEngine: InstallerEngine
    let privilegeBroker: PrivilegeBroker
    let kanataService: KanataService
    private nonisolated let diagnosticsService: DiagnosticsServiceProtocol
    let reloadSafetyMonitor = ReloadSafetyMonitor() // internal for use by extensions
    private let karabinerConflictService: KarabinerConflictManaging
    private let configBackupManager: ConfigBackupManager
    private let ruleCollectionsManager: RuleCollectionsManager
    private let systemRequirementsChecker: SystemRequirementsChecker

    /// Provides access to the rule collections manager for keymap changes
    var rulesManager: RuleCollectionsManager { ruleCollectionsManager }

    // MARK: - Extracted Coordinators (Refactoring: Nov 2025)

    private let saveCoordinator: SaveCoordinator
    let recoveryCoordinator: RecoveryCoordinator // internal for extension access
    private let installationCoordinator: InstallationCoordinator
    private let ruleCollectionsCoordinator: RuleCollectionsCoordinator

    private var isStartingKanata = false
    var isInitializing = false
    private let isHeadlessMode: Bool

    // MARK: - Process Synchronization (Phase 1)

    private var lastStartAttempt: Date? // Still used for backward compatibility
    private var lastServiceKickstart: Date? // Still used for grace period tracking

    // Configuration file watching for hot reload
    private var configFileWatcher: ConfigFileWatcher?

    var configPath: String {
        configurationManager.configPath
    }

    // Note: RuleCollectionsManager handles its own cleanup in deinit

    init(engineClient: EngineClient? = nil, injectedConfigurationService: ConfigurationService? = nil, configRepairService: ConfigRepairService? = nil) {
        AppLogger.shared.log("🏗️ [RuntimeCoordinator] init() called")

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
                configDirectory: KeyPathConstants.Config.directory)
        }

        // Phase 3: Use shared KanataService for dependencies
        let kanataService = KanataService.shared
        let lifecycleManager = ProcessLifecycleManager()
        processLifecycleManager = lifecycleManager

        // Initialize configuration file watcher for hot reload
        configFileWatcher = ConfigFileWatcher()

        // Initialize configuration backup manager
        let configBackupManager = ConfigBackupManager(
            configPath: KeyPathConstants.Config.mainConfigPath)

        // Initialize manager dependencies
        let karabinerConflictService = KarabinerConflictService()
        let diagnosticsService = DiagnosticsService(processLifecycleManager: lifecycleManager)
        privilegeBroker = PrivilegeBroker()
        installerEngine = InstallerEngine()
        let processCoordinator = ProcessCoordinator(
            kanataService: kanataService,
            installerEngine: installerEngine,
            privilegeBroker: privilegeBroker
        )

        // Store for extensions
        self.processCoordinator = processCoordinator
        self.kanataService = kanataService
        self.diagnosticsService = diagnosticsService
        self.karabinerConflictService = karabinerConflictService
        self.configBackupManager = configBackupManager

        // Initialize RuleCollectionsManager
        ruleCollectionsManager = RuleCollectionsManager(
            configurationService: configurationService
        )

        // Initialize SystemRequirementsChecker
        systemRequirementsChecker = SystemRequirementsChecker(
            karabinerConflictService: karabinerConflictService
        )

        // Initialize extracted coordinators
        saveCoordinator = SaveCoordinator(
            configurationService: configurationService,
            engineClient: engineClient ?? TCPEngineClient(),
            configFileWatcher: configFileWatcher
        )
        installationCoordinator = InstallationCoordinator()

        // Initialize ProcessManager
        processManager = ProcessManager(
            processLifecycleManager: lifecycleManager,
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
            kanataService: kanataService
        )

        // Initialize ConfigRepairService
        self.configRepairService = configRepairService ?? AnthropicConfigRepairService()

        // Initialize EngineClien
        self.engineClient = engineClient ?? TCPEngineClient()

        // Initialize RecoveryCoordinator (will be configured after all initialization)
        recoveryCoordinator = RecoveryCoordinator()

        // Initialize RuleCollectionsCoordinator (after all managers, before Task captures self)
        ruleCollectionsCoordinator = RuleCollectionsCoordinator(
            ruleCollectionsManager: ruleCollectionsManager
        )

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
                "🧪 [RuntimeCoordinator] Skipping background initialization in test environment")
        }

        if isHeadlessMode {
            AppLogger.shared.log("🤖 [RuntimeCoordinator] Initialized in headless mode")
        }

        // Configure state publisher for reactive UI updates
        configureStatePublisher()

        // Wire up SaveCoordinator delegate for status change notifications
        saveCoordinator.delegate = self

        // Configure RuleCollectionsCoordinator callbacks (after all initialization)
        ruleCollectionsCoordinator.configure(
            applyMappings: { [weak self] mappings in
                self?.applyKeyMappings(mappings, persistCollections: false)
            },
            notifyStateChanged: { [weak self] in
                self?.notifyStateChanged()
            }
        )

        // Configure RecoveryCoordinator handlers (after all initialization)
        recoveryCoordinator.configure(
            killAllKanataProcesses: { [weak self] in
                guard let self else {
                    throw KeyPathError.process(.noManager)
                }
                let report = await installerEngine
                    .runSingleAction(.terminateConflictingProcesses, using: privilegeBroker)
                if !report.success {
                    throw KeyPathError.process(
                        .terminateFailed(underlyingError: report.failureReason ?? "Unknown error"))
                }
            },
            restartKarabinerDaemon: { [weak self] in
                await self?.restartKarabinerDaemon() ?? false
            },
            restartService: { [weak self] reason in
                await self?.restartServiceWithFallback(reason: reason) ?? false
            }
        )

        // Wire up RuleCollectionsManager callbacks
        ruleCollectionsManager.onRulesChanged = { [weak self] in
            guard let self else { return }
            _ = await triggerConfigReload()
            notifyStateChanged()
            // Notify overlay to rebuild layer mapping
            AppLogger.shared.debug("🔔 [RuntimeCoordinator] Posting kanataConfigChanged notification")

            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
        }
        ruleCollectionsManager.onLayerChanged = { [weak self] layerName in
            self?.currentLayerName = layerName
            self?.notifyStateChanged()
            // Notify overlay about layer change
            NotificationCenter.default.post(
                name: .kanataLayerChanged,
                object: nil,
                userInfo: ["layerName": layerName, "source": "kanata"]
            )
        }
        ruleCollectionsManager.onError = { [weak self] error in
            AppLogger.shared.debug("🚨 [RuntimeCoordinator] onError callback received: \(error)")
            self?.lastError = error
            AppLogger.shared.debug("🚨 [RuntimeCoordinator] lastError set, calling notifyStateChanged()")
            self?.notifyStateChanged()
        }
        ruleCollectionsManager.onWarning = { [weak self] warning in
            self?.lastWarning = warning
            self?.notifyStateChanged()
            // Play warning sound
            SoundManager.shared.playWarningSound()
            // Clear warning after it's been delivered to prevent re-triggering
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                self?.lastWarning = nil
            }
        }
        ruleCollectionsManager.onConflictResolution = { [weak self] context in
            await self?.promptForConflictResolution(context)
        }
        // Note: onActionURI callback not needed - RuleCollectionsManager.handleActionURI()
        // already dispatches to ActionDispatcher. Setting this would cause double dispatch.
        ruleCollectionsManager.onBeforeSave = { [weak self] in
            // Suppress file watcher to prevent double-reload when we save internally
            self?.configFileWatcher?.suppressEvents(for: 1.0, reason: "Internal rule change")
        }

        AppLogger.shared.log(
            "🏗️ [RuntimeCoordinator] About to call bootstrapRuleCollections and startEventMonitoring")
        Task { await ruleCollectionsManager.bootstrap() }
        ruleCollectionsManager.startEventMonitoring(port: PreferencesService.shared.tcpServerPort)
        AppLogger.shared.log("🏗️ [RuntimeCoordinator] init() completed")
    }

    // MARK: - Conflict Resolution

    /// Prompt the user to resolve a rule conflict via the UI
    @MainActor
    private func promptForConflictResolution(_ context: RuleConflictContext) async -> RuleConflictChoice? {
        // Cancel any pending resolution to avoid continuation leak
        conflictResolutionContinuation?.resume(returning: nil)
        conflictResolutionContinuation = nil

        pendingRuleConflict = context
        notifyStateChanged()

        return await withCheckedContinuation { continuation in
            conflictResolutionContinuation = continuation
        }
    }

    /// Called by ViewModel when user makes a choice in the conflict resolution dialog
    func resolveConflict(with choice: RuleConflictChoice?) {
        pendingRuleConflict = nil
        conflictResolutionContinuation?.resume(returning: choice)
        conflictResolutionContinuation = nil
        notifyStateChanged()
    }

    // MARK: - Rule Collections (delegates to RuleCollectionsCoordinator)

    func replaceRuleCollections(_ collections: [RuleCollection]) async {
        await ruleCollectionsCoordinator.replaceRuleCollections(collections)
    }

    func enabledMappingsFromCollections() -> [KeyMapping] {
        ruleCollectionsCoordinator.enabledMappings()
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

    // MARK: - Configuration File Watching (delegates to ConfigHotReloadService)

    private let configHotReloadService = ConfigHotReloadService.shared

    /// Start watching the configuration file for external changes
    func startConfigFileWatching() {
        guard let fileWatcher = configFileWatcher else {
            AppLogger.shared.warn("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
            return
        }

        // Configure the hot reload service
        configHotReloadService.configure(
            configurationService: configurationService,
            reloadHandler: { [weak self] in
                guard let self else { return false }
                let result = await triggerConfigReload()
                return result.isSuccess
            },
            configParser: { [weak self] content in
                guard let self else { return [] }
                let parsed = try configurationService.parseConfigurationFromString(content)
                return parsed.keyMappings
            }
        )

        // Set up UI callbacks
        configHotReloadService.callbacks = ConfigHotReloadService.Callbacks(
            onDetected: {
                SoundManager.shared.playTinkSound()
            },
            onValidating: { [weak self] in
                self?.saveStatus = .saving
            },
            onSuccess: { [weak self] content in
                SoundManager.shared.playGlassSound()
                self?.saveStatus = .success
                // Update in-memory config
                if let mappings = self?.configHotReloadService.parseKeyMappings(from: content) {
                    self?.applyKeyMappings(mappings)
                }
            },
            onFailure: { [weak self] message in
                SoundManager.shared.playErrorSound()
                self?.saveStatus = .failed(message)
            },
            onReset: { [weak self] in
                self?.saveStatus = .idle
            }
        )

        let configPath = configPath
        AppLogger.shared.log("📁 [FileWatcher] Starting to watch config file: \(configPath)")

        fileWatcher.startWatching(path: configPath) { [weak self] in
            guard let self else { return }
            _ = await configHotReloadService.handleExternalChange(configPath: configPath)
        }
    }

    /// Stop watching the configuration file
    func stopConfigFileWatching() {
        configFileWatcher?.stopWatching()
        AppLogger.shared.log("📁 [FileWatcher] Stopped watching config file")
    }

    /// Attempts to recover from zombie keyboard capture when VirtualHID connection fails

    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        await recoveryCoordinator.startKanataWithValidation(
            isKarabinerDaemonRunning: { await isKarabinerDaemonRunning() },
            startKanata: { await startKanata(reason: "VirtualHID validation start") },
            onError: { [weak self] error in
                self?.lastError = error
                self?.notifyStateChanged()
            }
        )
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
            case let .reloadFailed(message):
                "Config reload failed: \(message)"
            case let .validationFailed(errors):
                "Config validation failed: \(errors.joined(separator: ", "))"
            case let .postSaveValidationFailed(errors):
                "Post-save validation failed: \(errors.joined(separator: ", "))"
            }
        }
    }

    /// Backup current working config before making changes
    private func backupCurrentConfig() async {
        let config = await configurationService.current()
        saveCoordinator.backupCurrentConfig(config.content)
    }

    /// Restore last known good config in case of validation failure
    private func restoreLastGoodConfig() async throws {
        try await saveCoordinator.restoreLastGoodConfig()
    }

    func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
        let diagnostics = diagnosticsManager.diagnoseFailure(exitCode: exitCode, output: output)

        recoveryCoordinator.diagnoseKanataFailure(
            exitCode: exitCode,
            output: output,
            diagnostics: diagnostics,
            addDiagnostic: { [weak self] diagnostic in
                self?.addDiagnostic(diagnostic)
            },
            attemptRecovery: { [weak self] in
                await self?.attemptKeyboardRecovery()
            }
        )
    }

    // MARK: - Auto-Fix Capabilities

    func autoFixDiagnostic(_ diagnostic: KanataDiagnostic) async -> Bool {
        guard let action = recoveryCoordinator.autoFixActionType(diagnostic) else {
            return false
        }

        var success = false
        switch action {
        case .resetConfig:
            do {
                try await resetToDefaultConfig()
                success = true
            } catch {
                success = false
            }

        case .restartService:
            success = await restartServiceWithFallback(
                reason: "AutoFix diagnostic: \(diagnostic.title)"
            )
        }

        recoveryCoordinator.logAutoFixResult(action, success: success)
        return success
    }

    // MARK: - Service Management Helpers

    @discardableResult
    func startKanata(reason: String = "Manual start") async -> Bool {
        AppLogger.shared.log("🚀 [Service] Starting Kanata (\(reason))")

        // CRITICAL: Check VHID daemon health before starting Kanata
        // If Kanata starts without a healthy VHID daemon, it will grab keyboard input
        // but have nowhere to output keystrokes, freezing the keyboard
        if await !isKarabinerDaemonRunning() {
            AppLogger.shared.error("❌ [Service] Cannot start Kanata - VirtualHID daemon is not running")
            lastError = "Cannot start: Karabiner VirtualHID daemon is not running. Please complete the setup wizard."
            notifyStateChanged()
            return false
        }

        do {
            try await kanataService.start()
            await kanataService.refreshStatus()

            // Start the app context service for per-app keymaps
            // This monitors frontmost app and activates virtual keys via TCP
            await AppContextService.shared.start()

            lastError = nil
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Start failed: \(message)")
            lastError = "Start failed: \(message)"
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func stopKanata(reason: String = "Manual stop") async -> Bool {
        AppLogger.shared.log("🛑 [Service] Stopping Kanata (\(reason))")

        // Stop the app context service first
        await AppContextService.shared.stop()

        do {
            try await kanataService.stop()
            await kanataService.refreshStatus()
            notifyStateChanged()
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLogger.shared.error("❌ [Service] Stop failed: \(message)")
            lastError = "Stop failed: \(message)"
            notifyStateChanged()
            return false
        }
    }

    @discardableResult
    func restartKanata(reason: String = "Manual restart") async -> Bool {
        await restartServiceWithFallback(reason: reason)
    }

    func currentServiceState() async -> KanataService.ServiceState {
        await kanataService.refreshStatus()
    }

    @discardableResult
    func restartServiceWithFallback(reason: String) async -> Bool {
        AppLogger.shared.log("🔄 [ServiceRestart] \(reason) - delegating to ProcessCoordinator")
        let restarted = await processCoordinator.restartService()

        let state = await kanataService.refreshStatus()
        let isRunning = state.isRunning

        if restarted, isRunning {
            AppLogger.shared.log("✅ [ServiceRestart] Kanata is running (state=\(state.description))")
            notifyStateChanged()
            return true
        }

        if !restarted {
            AppLogger.shared.warn("⚠️ [ServiceRestart] ProcessCoordinator restart failed")
        } else {
            AppLogger.shared.warn("⚠️ [ServiceRestart] Restart finished but state=\(state.description)")
        }
        notifyStateChanged()
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

    // MARK: - UI-Focused Lifecycle Methods (from SimpleRuntimeCoordinator)

    /// Check if this is a fresh install (no Kanata binary or config)
    private func isFirstTimeInstall() -> Bool {
        installationCoordinator.isFirstTimeInstall(configPath: KeyPathConstants.Config.mainConfigPath)
    }

    // Removed: checkLaunchDaemonStatus, killProcess

    /// Save a complete generated configuration (for Claude API generated configs)
    func saveGeneratedConfiguration(_ configContent: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving generated configuration")

        let result = await saveCoordinator.saveGeneratedConfig(
            content: configContent,
            reloadHandler: { [weak self] in
                guard let self else { return (false, "Coordinator deallocated") }
                let reloadResult = await triggerConfigReload()
                return (reloadResult.isSuccess, reloadResult.errorMessage)
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            lastConfigUpdate = Date()
            applyKeyMappings(mappings)
            notifyStateChanged()
        } else if let error = result.error {
            notifyStateChanged()
            throw error
        }
    }

    // MARK: - Rule Collections (delegates to RuleCollectionsCoordinator)

    func toggleRuleCollection(id: UUID, isEnabled: Bool) async {
        await ruleCollectionsCoordinator.toggleRuleCollection(id: id, isEnabled: isEnabled)
    }

    func addRuleCollection(_ collection: RuleCollection) async {
        await ruleCollectionsCoordinator.addRuleCollection(collection)
    }

    func updateCollectionOutput(id: UUID, output: String) async {
        await ruleCollectionsCoordinator.updateCollectionOutput(id: id, output: output)
    }

    func updateCollectionTapOutput(id: UUID, tapOutput: String) async {
        await ruleCollectionsCoordinator.updateCollectionTapOutput(id: id, tapOutput: tapOutput)
    }

    func updateCollectionHoldOutput(id: UUID, holdOutput: String) async {
        await ruleCollectionsCoordinator.updateCollectionHoldOutput(id: id, holdOutput: holdOutput)
    }

    func updateCollectionLayerPreset(_ id: UUID, presetId: String) async {
        await ruleCollectionsCoordinator.updateCollectionLayerPreset(id: id, presetId: presetId)
    }

    func updateWindowKeyConvention(_ id: UUID, convention: WindowKeyConvention) async {
        await ruleCollectionsCoordinator.updateWindowKeyConvention(id: id, convention: convention)
    }

    func updateFunctionKeyMode(_ id: UUID, mode: FunctionKeyMode) async {
        await ruleCollectionsCoordinator.updateFunctionKeyMode(id: id, mode: mode)
    }

    func updateHomeRowModsConfig(collectionId: UUID, config: HomeRowModsConfig) async {
        await ruleCollectionsCoordinator.updateHomeRowModsConfig(id: collectionId, config: config)
    }

    func updateHomeRowLayerTogglesConfig(collectionId: UUID, config: HomeRowLayerTogglesConfig) async {
        await ruleCollectionsCoordinator.updateHomeRowLayerTogglesConfig(id: collectionId, config: config)
    }

    func updateChordGroupsConfig(collectionId: UUID, config: ChordGroupsConfig) async {
        await ruleCollectionsCoordinator.updateChordGroupsConfig(id: collectionId, config: config)
    }

    func updateSequencesConfig(collectionId: UUID, config: SequencesConfig) async {
        await ruleCollectionsCoordinator.updateSequencesConfig(id: collectionId, config: config)
    }

    func updateLauncherConfig(collectionId: UUID, config: LauncherGridConfig) async {
        await ruleCollectionsCoordinator.updateLauncherConfig(id: collectionId, config: config)
    }

    func updateLeaderKey(_ newKey: String) async {
        await ruleCollectionsCoordinator.updateLeaderKey(newKey)
    }

    @discardableResult
    func saveCustomRule(_ rule: CustomRule, skipReload: Bool = false) async -> Bool {
        await ruleCollectionsCoordinator.saveCustomRule(rule, skipReload: skipReload)
    }

    func toggleCustomRule(id: UUID, isEnabled: Bool) async {
        await ruleCollectionsCoordinator.toggleCustomRule(id: id, isEnabled: isEnabled)
    }

    func removeCustomRule(withID id: UUID) async {
        await ruleCollectionsCoordinator.removeCustomRule(withID: id)
    }

    /// Clear all custom rules without affecting rule collections
    func clearAllCustomRules() async {
        await ruleCollectionsCoordinator.clearAllCustomRules()
    }

    private func makeCustomRuleForSave(input: String, output: String) -> CustomRule {
        ruleCollectionsCoordinator.makeCustomRule(input: input, output: output)
    }

    /// Creates or returns an existing custom rule for the given input key.
    /// If a rule already exists with the same input, returns a copy with the same ID but updated output.
    /// This prevents duplicate keys in the generated Kanata config.
    func makeCustomRule(input: String, output: String) -> CustomRule {
        ruleCollectionsCoordinator.makeCustomRule(input: input, output: output)
    }

    /// Get existing custom rule for the given input key, if any
    func getCustomRule(forInput input: String) -> CustomRule? {
        ruleCollectionsCoordinator.getCustomRule(forInput: input)
    }

    /// Fetch layer names reported by Kanata over TCP.
    /// Falls back to empty list if the service is unavailable.
    func fetchLayerNamesFromKanata() async -> [String] {
        let port = PreferencesService.shared.tcpServerPort
        let client = KanataTCPClient(port: port, timeout: 3.0)

        let serverUp = await client.checkServerStatus()
        guard serverUp else {
            await client.cancelInflightAndCloseConnection()
            return []
        }

        do {
            let names = try await client.requestLayerNames()
            await client.cancelInflightAndCloseConnection()
            return names.map { $0.lowercased() }
        } catch {
            AppLogger.shared.warn("❌ [RuntimeCoordinator] Failed to fetch layer names: \(error)")
            await client.cancelInflightAndCloseConnection()
            return []
        }
    }

    /// Switch to a different layer via Kanata TCP command.
    /// Returns true if the layer was changed successfully.
    func changeLayer(_ layerName: String) async -> Bool {
        let port = PreferencesService.shared.tcpServerPort
        let client = KanataTCPClient(port: port, timeout: 3.0)

        let serverUp = await client.checkServerStatus()
        guard serverUp else {
            AppLogger.shared.warn("❌ [RuntimeCoordinator] Cannot change layer - TCP server not available")
            await client.cancelInflightAndCloseConnection()
            return false
        }

        let result = await client.changeLayer(layerName)
        await client.cancelInflightAndCloseConnection()

        switch result {
        case .success:
            AppLogger.shared.log("✅ [RuntimeCoordinator] Layer changed to: \(layerName)")
            return true
        case let .error(msg):
            AppLogger.shared.warn("❌ [RuntimeCoordinator] Failed to change layer: \(msg)")
            return false
        case let .networkError(msg):
            AppLogger.shared.warn("❌ [RuntimeCoordinator] Network error changing layer: \(msg)")
            return false
        }
    }

    func saveConfiguration(input: String, output: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving configuration mapping")

        let result = await saveCoordinator.saveMapping(
            input: input,
            output: output,
            ruleCollectionsManager: ruleCollectionsManager,
            reloadHandler: { [weak self] in
                guard let self else { return (false, "Coordinator deallocated") }
                let tcpResult = await triggerTCPReload()
                return (tcpResult.isSuccess, tcpResult.errorMessage)
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            applyKeyMappings(mappings, persistCollections: false)
            notifyStateChanged()
            AppLogger.shared.log("⚡ [Config] Validation-on-demand save completed")
        } else if let error = result.error {
            notifyStateChanged()
            throw error
        }
    }

    func updateStatus() async {
        notifyStateChanged()
    }

    func inspectSystemContext() async -> SystemContext {
        await installerEngine.inspectSystem()
    }

    func uninstall(deleteConfig: Bool) async -> InstallerReport {
        await installerEngine.uninstall(deleteConfig: deleteConfig, using: privilegeBroker)
    }

    func runFullRepair(reason: String = "RuntimeCoordinator repair request") async -> InstallerReport {
        AppLogger.shared.log("🛠️ [RuntimeCoordinator] runFullRepair invoked (\(reason))")
        return await installerEngine.run(intent: .repair, using: privilegeBroker)
    }

    /// Run full installation via InstallerEngine façade.
    /// This replaces direct calls to PrivilegedOperationsCoordinator.installAllLaunchDaemonServices().
    func runFullInstall(reason: String = "RuntimeCoordinator install request") async -> InstallerReport {
        AppLogger.shared.log("🔧 [RuntimeCoordinator] runFullInstall invoked (\(reason))")
        return await installerEngine.run(intent: .install, using: privilegeBroker)
    }

    private func captureRecentKanataErrorMessage() -> String? {
        let stderrPath = KeyPathConstants.Logs.kanataStderr
        let contents: String
        do {
            contents = try String(contentsOfFile: stderrPath, encoding: .utf8)
        } catch {
            AppLogger.shared.debug("⚠️ [RuntimeCoordinator] Could not read stderr log at \(stderrPath): \(error.localizedDescription)")
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
        do {
            try await kanataService.stop()
        } catch {
            AppLogger.shared.warn("⚠️ [RuntimeCoordinator] Failed to stop Kanata during cleanup: \(error.localizedDescription)")
        }
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

    // MARK: - Installation and Permissions (delegates to SystemRequirementsChecker)

    func isInstalled() -> Bool {
        systemRequirementsChecker.isInstalled()
    }

    func isCompletelyInstalled() -> Bool {
        systemRequirementsChecker.isCompletelyInstalled(isServiceInstalled: isServiceInstalled)
    }

    func hasInputMonitoringPermission() async -> Bool {
        await systemRequirementsChecker.hasInputMonitoringPermission()
    }

    func hasAccessibilityPermission() async -> Bool {
        await systemRequirementsChecker.hasAccessibilityPermission()
    }

    func checkBothAppsHavePermissions() async -> (
        keyPathHasPermission: Bool, kanataHasPermission: Bool, permissionDetails: String
    ) {
        await systemRequirementsChecker.checkBothAppsHavePermissions()
    }

    func hasAllRequiredPermissions() async -> Bool {
        await systemRequirementsChecker.hasAllRequiredPermissions()
    }

    func hasAllSystemRequirements() async -> Bool {
        await systemRequirementsChecker.hasAllSystemRequirements(isServiceInstalled: isServiceInstalled)
    }

    func getSystemRequirementsStatus() async -> (
        installed: Bool, permissions: Bool, driver: Bool, daemon: Bool
    ) {
        await systemRequirementsChecker.getSystemRequirementsStatus(isServiceInstalled: isServiceInstalled)
    }

    func openInputMonitoringSettings() {
        systemRequirementsChecker.openInputMonitoringSettings()
    }

    func openAccessibilitySettings() {
        systemRequirementsChecker.openAccessibilitySettings()
    }

    func revealKanataInFinder() {
        systemRequirementsChecker.revealKanataInFinder(onRevealed: nil)
    }

    func isKarabinerDriverInstalled() -> Bool {
        systemRequirementsChecker.isKarabinerDriverInstalled()
    }

    func isKarabinerDriverExtensionEnabled() async -> Bool {
        await systemRequirementsChecker.isKarabinerDriverExtensionEnabled()
    }

    func areKarabinerBackgroundServicesEnabled() async -> Bool {
        await systemRequirementsChecker.areKarabinerBackgroundServicesEnabled()
    }

    func isKarabinerElementsRunning() async -> Bool {
        await systemRequirementsChecker.isKarabinerElementsRunning()
    }

    func disableKarabinerElementsPermanently() async -> Bool {
        await systemRequirementsChecker.disableKarabinerElementsPermanently()
    }

    func killKarabinerGrabber() async -> Bool {
        await systemRequirementsChecker.killKarabinerGrabber()
    }

    func isKarabinerDaemonRunning() async -> Bool {
        await systemRequirementsChecker.isKarabinerDaemonRunning()
    }

    func startKarabinerDaemon() async -> Bool {
        await systemRequirementsChecker.startKarabinerDaemon()
    }

    func restartKarabinerDaemon() async -> Bool {
        await systemRequirementsChecker.restartKarabinerDaemon()
    }

    func getVirtualHIDBreakageSummary() async -> String {
        let summary = await systemRequirementsChecker.getVirtualHIDBreakageSummary(
            diagnosticsService: diagnosticsService
        )
        AppLogger.shared.log("🔎 [VHID-DIAG] Diagnostic summary:\n\(summary)")
        return summary
    }

    func getInstallationStatus() -> String {
        systemRequirementsChecker.getInstallationStatus(isServiceInstalled: isServiceInstalled)
    }

    func performTransparentInstallation() async -> Bool {
        AppLogger.shared.log("🔧 [Installation] Starting transparent installation...")

        var stepsCompleted = 0
        var stepsFailed = 0
        let totalSteps = 5

        // 1. Check Kanata binary
        let step1 = installationCoordinator.checkKanataBinary(stepNumber: 1, totalSteps: totalSteps)
        if step1.success {
            stepsCompleted += 1
        } else {
            stepsFailed += 1
        }

        // 2. Check Karabiner driver
        _ = installationCoordinator.checkKarabinerDriver(stepNumber: 2, totalSteps: totalSteps)
        stepsCompleted += 1 // Always counts as completed (warning-only)

        // 3. Prepare daemon directories
        installationCoordinator.logDaemonDirectoriesStep(stepNumber: 3, totalSteps: totalSteps)
        await installationCoordinator.prepareDaemonDirectories()
        installationCoordinator.logDaemonDirectoriesSuccess(stepNumber: 3, totalSteps: totalSteps)
        stepsCompleted += 1

        // 4. Create initial config
        await createInitialConfigIfNeeded()
        let step4 = installationCoordinator.checkConfigFile(configPath: configPath, stepNumber: 4, totalSteps: totalSteps)
        if step4.success {
            stepsCompleted += 1
        } else {
            stepsFailed += 1
        }

        // 5. System config step (skipped in new architecture)
        installationCoordinator.logSystemConfigSkipped(stepNumber: 5, totalSteps: totalSteps)
        stepsCompleted += 1

        return installationCoordinator.logInstallationResult(
            stepsCompleted: stepsCompleted,
            stepsFailed: stepsFailed,
            totalSteps: totalSteps
        )
    }

    private func prepareDaemonDirectories() async {
        await installationCoordinator.prepareDaemonDirectories()
    }

    // MARK: - Configuration Management

    // Logic moved to ConfigurationManager

    func clearValidationError() {
        validationError = nil
        notifyStateChanged()
    }

    // MARK: - Methods Expected by Tests

    func isServiceInstalled() -> Bool {
        let state = KanataDaemonManager.shared.currentManagementState
        switch state {
        case .uninstalled:
            return false
        case .unknown:
            // State is .unknown when process is running but SMAppService not fully registered yet.
            // This happens during the startup window where SMAppService.status lags behind actual process state.
            // Since .unknown specifically means "process running but unclear management" (see KanataDaemonManager:154),
            // treat it as installed to allow recording during this transient state.
            return true
        default:
            return true
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

        // Get ALL collections from catalog, then disable everything except macOS Function Keys
        // This ensures the UI shows all collections with correct enabled/disabled state after reset
        let catalog = RuleCollectionCatalog()
        let allCollections = catalog.defaultCollections().map { collection -> RuleCollection in
            var modified = collection
            // Only enable macOS Function Keys - everything else is OFF
            modified.isEnabled = (collection.id == RuleCollectionIdentifier.macFunctionKeys)
            return modified
        }

        // Generate config from only enabled collections (just macOS Function Keys)
        let enabledCollections = allCollections.filter(\.isEnabled)
        let defaultConfig = KanataConfiguration.generateFromCollections(enabledCollections)
        let configURL = URL(fileURLWithPath: configPath)

        // Ensure config directory exists
        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Write the default config (unconditionally)
        try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        AppLogger.shared.log("💾 [Config] Reset to default configuration (macOS Function Keys only)")

        // Update the stores with ALL collections (so UI shows correct enabled/disabled state)
        try await RuleCollectionStore.shared.saveCollections(allCollections)
        try await CustomRulesStore.shared.saveRules([]) // Clear custom rules

        // Re-bootstrap the manager to pick up the changes
        await ruleCollectionsManager.bootstrap()

        AppLogger.shared.log("🔄 [Reset] Updated stores and manager properties to match default state")

        // Notify ViewModel of state change so UI updates
        notifyStateChanged()

        // Skip TCP/service operations in test environment to avoid timeouts
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🧪 [Reset] Test environment - skipping TCP reload")
            return
        }

        // Apply changes immediately via TCP reload if service is running
        let serviceState = await kanataService.refreshStatus()
        if serviceState.isRunning {
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
                _ = await restartServiceWithFallback(reason: "Default config reload fallback")
            }

            // Reset to idle after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.saveStatus = .idle
            }
        }
    }

    // MARK: - Pause/Resume Mappings for Recording (delegates to RecoveryCoordinator)

    /// Temporarily pause mappings (for raw key capture during recording)
    func pauseMappings() async -> Bool {
        await recoveryCoordinator.pauseMappings()
    }

    /// Resume mappings after recording
    func resumeMappings() async -> Bool {
        await recoveryCoordinator.resumeMappings()
    }

    func convertToKanataKey(_ key: String) -> String {
        KanataKeyConverter.convertToKanataKey(key)
    }

    func convertToKanataSequence(_ sequence: String) -> String {
        KanataKeyConverter.convertToKanataSequence(sequence)
    }

    // MARK: - Real-Time VirtualHID Connection Monitoring

    // startLogMonitoring/stopLogMonitoring moved to RuntimeCoordinator+Output.swif

    /// Analyze new log content for VirtualHID connection issues (delegates parsing to DiagnosticsService)
    func analyzeLogContent(_ content: String) async {
        let events = diagnosticsService.analyzeKanataLogChunk(content)
        for event in events {
            switch event {
            case .virtualHIDConnectionFailed:
                let shouldTriggerRecovery = await kanataService.recordConnectionFailure()
                if shouldTriggerRecovery {
                    AppLogger.shared.log(
                        "🚨 [LogMonitor] Maximum connection failures reached - triggering recovery")
                    await triggerVirtualHIDRecovery()
                }
            case .virtualHIDConnected:
                await kanataService.recordConnectionSuccess()
            }
        }
    }

    // MARK: - One-click Service Regeneration

    /// Regenerate LaunchDaemon services (rewrite plists, bootstrap, kickstart) using current settings.
    /// Returns true on success.
    func regenerateServices() async -> Bool {
        AppLogger.shared.log("🔧 [Services] One-click regenerate services initiated")
        let report = await installerEngine
            .runSingleAction(.regenerateServiceConfiguration, using: privilegeBroker)
        if report.success {
            // Refresh status after regeneration to update UI promptly
            await updateStatus()
            AppLogger.shared.info("✅ [Services] Regenerate services completed")
            return true
        }

        let failureReason = report.failureReason ?? "Unknown error"
        AppLogger.shared.error("❌ [Services] Regenerate services failed: \(failureReason)")
        lastError = "Regenerate services failed: \(failureReason)"
        return false
    }

    /// Trigger VirtualHID recovery when connection failures are detected
    private func triggerVirtualHIDRecovery() async {
        await recoveryCoordinator.triggerVirtualHIDRecovery(
            addDiagnostic: { [weak self] diagnostic in
                self?.addDiagnostic(diagnostic)
            },
            attemptRecovery: { [weak self] in
                await self?.attemptKeyboardRecovery()
            }
        )
    }

    // MARK: - Enhanced Config Validation and Recovery

    // Logic moved to ConfigurationManager

    /// Opens a file in Zed editor with fallback options
    func openFileInZed(_ filePath: String) async {
        await configurationManager.openInEditor(filePath)
    }

    // MARK: - Kanata Arguments Builder

    // Logic moved to ConfigurationManager

    // MARK: - AI Configuration Repair

    /// Attempt to repair a broken config using the AI service
    /// - Parameters:
    ///   - config: The broken config content
    ///   - errors: Validation error messages from Kanata
    /// - Returns: Repaired config string if successful
    /// - Throws: KeyPathError if repair fails or no API key configured
    func attemptAIRepair(config: String, errors: [String]) async throws -> String {
        AppLogger.shared.log("🤖 [RuntimeCoordinator] Starting AI config repair")

        // Check API key availability
        guard KeychainService.shared.hasClaudeAPIKey else {
            throw KeyPathError.configuration(.repairFailed(reason: "No Claude API key configured. Add one in Settings → Experimental → AI Config Generation."))
        }

        // Get current mappings for context (helps AI understand intent)
        let mappings = keyMappings

        AppLogger.shared.log("🤖 [RuntimeCoordinator] Calling AI service with \(errors.count) errors and \(mappings.count) mappings")

        // Call AI service
        let repairedConfig = try await configRepairService.repairConfig(
            config: config,
            errors: errors,
            mappings: mappings
        )

        AppLogger.shared.log("✅ [RuntimeCoordinator] AI repair completed")
        return repairedConfig
    }
}
