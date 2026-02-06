import ApplicationServices
@preconcurrency import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
import Network

// KeyMapping is now in Models/KeyMapping.swift

/// Manages the Kanata process lifecycle and configuration directly.
///
/// # Architecture: Main Coordinator + Extension Files (~1,800 lines total)
///
/// RuntimeCoordinator is the main orchestrator for Kanata process management and configuration.
/// It's split across multiple extension files for maintainability:
///
/// ## Extension Files (organized by concern):
///
/// **RuntimeCoordinator.swift** (main file, ~960 lines)
/// - Core initialization and state management
/// - UI state snapshots and ViewModel interface
/// - Health monitoring and auto-start logic
/// - Diagnostics and error handling
///
/// **RuntimeCoordinator+Configuration.swift** (~184 lines)
/// - Config reload triggering and TCP communication
/// - Key mapping save operations
///
/// **RuntimeCoordinator+RuleCollections.swift** (~112 lines)
/// - Rule collection CRUD and persistence
///
/// **RuntimeCoordinator+ServiceManagement.swift** (~119 lines)
/// - LaunchDaemon service start/stop/restart
///
/// **RuntimeCoordinator+ConfigMaintenance.swift** (~89 lines)
/// - Config backup, repair, and safe-config fallback
///
/// **RuntimeCoordinator+Lifecycle.swift** (~77 lines)
/// - Process lifecycle state transitions
///
/// **RuntimeCoordinator+State.swift** (~73 lines)
/// - UI state snapshot building
///
/// **RuntimeCoordinator+ConfigHotReload.swift** (~68 lines)
/// - File-change-driven hot reload
///
/// **RuntimeCoordinator+Diagnostics.swift** (~64 lines)
/// - System analysis and failure diagnosis
///
/// **RuntimeCoordinator+ConflictResolution.swift** (~29 lines)
/// - Karabiner conflict detection helpers
///
/// **RuntimeCoordinator+Engine.swift** (~13 lines)
/// - Kanata engine communication (stub)
///
/// **RuntimeCoordinator+Output.swift** (~13 lines)
/// - Log parsing and monitoring (stub)
///
/// ## Key Dependencies (used by extensions):
///
/// - **ConfigurationService**: File I/O, parsing, validation (Configuration extension)
/// - **ProcessLifecycleManager**: PID tracking, daemon registration (Lifecycle extension)
/// - **ServiceHealthMonitor**: Restart cooldown, recovery (ServiceManagement extension)
/// - **DiagnosticsService**: System analysis, failure diagnosis (Diagnostics extension)
/// - **PermissionOracle**: Permission state (main file + Lifecycle)
///
/// ## Navigation Tips:
///
/// - Starting/stopping Kanata? → See `+ServiceManagement.swift` or `+Lifecycle.swift`
/// - Reading/writing config? → See `+Configuration.swift` or `+ConfigMaintenance.swift`
/// - Hot reload on file change? → See `+ConfigHotReload.swift`
/// - Rule collections? → See `+RuleCollections.swift`
/// - UI state snapshots? → See `+State.swift`
/// - System diagnostics? → See `+Diagnostics.swift`
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
    var conflictResolutionContinuation: CheckedContinuation<RuleConflictChoice?, Never>?

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

    /// State publisher for reactive ViewModel updates
    let statePublisher = StatePublisherService<KanataUIState>()

    /// Stream of UI state changes for reactive ViewModel updates
    nonisolated var stateChanges: AsyncStream<KanataUIState> {
        statePublisher.stateChanges
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
    let processCoordinator: ProcessCoordinating
    let installerEngine: InstallerEngine
    let privilegeBroker: PrivilegeBroker
    let kanataService: KanataService
    nonisolated let diagnosticsService: DiagnosticsServiceProtocol
    let reloadSafetyMonitor = ReloadSafetyMonitor() // internal for use by extensions
    let karabinerConflictService: KarabinerConflictManaging
    let configBackupManager: ConfigBackupManager
    let ruleCollectionsManager: RuleCollectionsManager
    let systemRequirementsChecker: SystemRequirementsChecker

    /// Provides access to the rule collections manager for keymap changes
    var rulesManager: RuleCollectionsManager { ruleCollectionsManager }

    // MARK: - Extracted Coordinators (Refactoring: Nov 2025)

    let saveCoordinator: SaveCoordinator
    let recoveryCoordinator: RecoveryCoordinator // internal for extension access
    let installationCoordinator: InstallationCoordinator
    let ruleCollectionsCoordinator: RuleCollectionsCoordinator

    var isStartingKanata = false
    var isInitializing = false
    let isHeadlessMode: Bool

    // MARK: - Process Synchronization (Phase 1)

    var lastStartAttempt: Date? // Still used for backward compatibility
    var lastServiceKickstart: Date? // Still used for grace period tracking

    // Configuration file watching for hot reload
    var configFileWatcher: ConfigFileWatcher?
    let configHotReloadService = ConfigHotReloadService.shared

    var configPath: String {
        configurationManager.configPath
    }

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
        // Prefer structured concurrency; a plain Task{} runs off the main actor by default
        if !TestEnvironment.isRunningTests {
            Task { [weak self] in
                // Clean up any orphaned processes first
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

    // Note: RuleCollectionsManager handles its own cleanup in deinit

    // MARK: - Public Interface

    // Removed: checkLaunchDaemonStatus, killProcess

    func updateStatus() async {
        notifyStateChanged()
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
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
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
