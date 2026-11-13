import AppKit
import ApplicationServices
import Foundation
import IOKit.hidsystem
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathRulesCore
import KeyPathWizardCore
import Network
import Observation

// Thin orchestrator for Kanata process management and configuration.
//
// # Architecture: Orchestrator + Focused Types
//
// RuntimeCoordinator delegates real work to focused coordinator types:
//
// ## Extracted Coordinators (each owns a single responsibility):
//
// - **ServiceLifecycleCoordinator**: start/stop/restart Kanata, runtime status
// - **ConfigReloadCoordinator**: TCP-based config reload, safety checks
// - **SaveCoordinator**: Save operations with rollback
// - **RecoveryCoordinator**: recording pause/resume, diagnostic auto-fix
// - **RuleCollectionsManager**: Rule collection CRUD and persistence
// - **ConfigurationManager**: Config file management (create, validate, backup)
// - **DiagnosticsManager**: System diagnostics and health checks
// - **ServiceHealthMonitor**: Health monitoring and restart cooldown
//
// ## File Organization:
//
// **RuntimeCoordinator.swift** (this file)
// - Core initialization, dependency wiring, and callback plumbing
// - All delegation methods (state, configuration, lifecycle, service management,
//   config hot reload, config maintenance, conflict resolution, diagnostics)
//
// **RuntimeCoordinator+RuleCollections.swift** (separate extension)
// - Rule collection operations and runtime mapping refresh
//
// ## Public API (Views → ViewModel → Manager)
// The UI should call ONLY the following methods via `KanataViewModel`:
// - Lifecycle
//   - `startAutoLaunch(presentWizardOnFailure:)`
//   - `manualStart()` / `manualStop()`
//   - `startKanata()` / `stopKanata()`
// - Wizard
//   - `requestWizardPresentation(initialPage:)`
//   - `onWizardClosed()`
// - Configuration (UI-level operations)
//   - `createDefaultUserConfigIfMissing()`
//   - `backupFailedConfigAndApplySafe(failedConfig:mappings:)`
//   - `validateConfigFile()`
//   - `resetToDefaultConfig()`
//
// All other methods are internal implementation details and may change.

/// UI reads runtime-owned status and requests through Swift Observation.
@MainActor
@Observable
public class RuntimeCoordinator: SaveCoordinatorDelegate {
    // MARK: - Internal State Properties

    // Note: These are internal (not private) to allow extensions to access them

    /// Core status tracking
    struct ReportedError: Equatable {
        let message: String
        private let id = UUID()
    }

    private(set) var reportedError: ReportedError?
    public var lastError: String? {
        get { reportedError?.message }
        // A retry can fail with the same message and still needs a new alert.
        set { reportedError = newValue.map(ReportedError.init(message:)) }
    }

    @ObservationIgnored private(set) var lastWarning: String? {
        didSet {
            if let lastWarning, lastWarning != oldValue {
                onWarning?(lastWarning)
            }
        }
    }

    /// Delivers transient warnings to the app's presentation layer.
    @ObservationIgnored var onWarning: ((String) -> Void)?

    /// Legacy single-flight guard for grab-failure recovery (#625).
    /// W3 keeps grab-failure detection passive, but the guard remains until the
    /// deletion pass removes the old recovery state machine.
    private var isRecoveringGrab = false
    /// True while `lastError` holds the grab-failure message (#625), so a
    /// later authoritative grab success can clear exactly that error without
    /// stomping an unrelated error someone else set in the meantime.
    private var grabGiveUpErrorActive = false
    private var warningExpiryTask: Task<Void, Never>?
    var keyMappings: [KeyMapping] = []
    var currentLayerName: String = RuleCollectionLayer.base.displayName

    // Conflict resolution state
    var pendingRuleConflict: RuleConflictContext?
    var conflictResolutionContinuation: CheckedContinuation<RuleConflictChoice?, Never>?

    // Save-time mapping conflict resolution state (#460)
    var pendingMappingConflict: MappingConflictContext?
    var mappingConflictContinuation: CheckedContinuation<UUID?, Never>?

    // Forward prerequisite resolution state (#869)
    var pendingRuleSetup: RuleSetupSession?
    var pendingPrerequisiteResolution: RulePrerequisiteDialogModel?
    var prerequisiteResolutionContinuation:
        CheckedContinuation<RulePrerequisiteResolutionChoice?, Never>?

    // Reverse dependent resolution state (#868)
    var pendingDependentResolution: RuleDependentResolutionDialogModel?
    var dependentResolutionContinuation:
        CheckedContinuation<RuleDependentResolutionChoice?, Never>?

    var ruleCollections: [RuleCollection] {
        get { ruleCollectionsManager.ruleCollections }
        set { /* Write access via coordinator methods only */ }
    }

    var customRules: [CustomRule] {
        get { ruleCollectionsManager.customRules }
        set { /* Write access via coordinator methods only */ }
    }

    var diagnostics: [KanataDiagnostic] {
        diagnosticsManager.getDiagnostics()
    }

    /// Save progress feedback
    var saveStatus: SaveStatus = .idle

    let configDirectory = KeyPathConstants.Config.directory

    let configFileName = "keypath.kbd"

    // MARK: - Manager Dependencies (Refactored Architecture)

    let configurationManager: ConfigurationManager
    let diagnosticsManager: DiagnosticsManager
    let configRepairService: ConfigRepairService

    let configurationService: ConfigurationService

    // Additional dependencies needed by extensions
    let installerEngine: InstallerEngine
    let reloadSafetyMonitor = ReloadSafetyMonitor() // internal for use by extensions
    let configBackupManager: ConfigBackupManager
    let ruleCollectionsManager: RuleCollectionsManager

    /// Provides access to the rule collections manager for keymap changes
    var rulesManager: RuleCollectionsManager {
        ruleCollectionsManager
    }

    // MARK: - Extracted Coordinators (Refactoring: Nov 2025)

    let saveCoordinator: SaveCoordinator
    let recoveryCoordinator: RecoveryCoordinator // internal for extension access
    let serviceHealthMonitor: ServiceHealthMonitor
    let serviceLifecycleCoordinator: ServiceLifecycleCoordinator
    let configReloadCoordinator: ConfigReloadCoordinator

    var isInitializing = false
    @ObservationIgnored private var grabStatusObserver: NotificationCenter.ObservationToken?
    let isHeadlessMode: Bool

    // MARK: - Process Synchronization (Phase 1)

    var lastStartAttempt: Date? // Still used for backward compatibility
    var lastServiceKickstart: Date? // Still used for grace period tracking

    // Configuration file watching for hot reload
    @ObservationIgnored var configFileWatcher: ConfigFileWatcher?
    let configHotReloadService = ConfigHotReloadService.shared

    var configPath: String {
        configurationManager.configPath
    }

    init(
        injectedConfigurationService: ConfigurationService? = nil,
        injectedRuleCollectionsManager: RuleCollectionsManager? = nil,
        configRepairService: ConfigRepairService? = nil
    ) {
        AppLogger.shared.log("🏗️ [RuntimeCoordinator] init() called")
        let isOneShotProbeMode = AppDelegate.isOneShotProbeEnvironment()

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
                configDirectory: KeyPathConstants.Config.directory
            )
        }

        // Initialize configuration file watcher for hot reload
        configFileWatcher = ConfigFileWatcher()

        // Initialize configuration backup manager
        let configBackupManager = ConfigBackupManager(
            configPath: KeyPathConstants.Config.mainConfigPath
        )

        // Initialize manager dependencies
        installerEngine = InstallerEngine()
        // Store for extensions
        self.configBackupManager = configBackupManager

        // Initialize RuleCollectionsManager
        ruleCollectionsManager = injectedRuleCollectionsManager ?? RuleCollectionsManager(
            configurationService: configurationService
        )

        // Initialize extracted coordinators
        saveCoordinator = SaveCoordinator(
            configurationService: configurationService,
            configFileWatcher: configFileWatcher
        )
        serviceHealthMonitor = ServiceHealthMonitor()

        // Initialize ConfigurationManager
        configurationManager = ConfigurationManager(configurationService: configurationService)

        recoveryCoordinator = RecoveryCoordinator()
        serviceLifecycleCoordinator = ServiceLifecycleCoordinator()

        // Initialize DiagnosticsManager
        diagnosticsManager = DiagnosticsManager(
            healthMonitor: serviceHealthMonitor,
            processStatusProvider: { [serviceLifecycleCoordinator] in
                let report = serviceLifecycleCoordinator.currentSessionReport()
                return ProcessHealthStatus(isRunning: report?.state == .running && report?.tapActive == true,
                                           pid: report.map { Int($0.pid) })
            }
        )

        // Initialize ConfigRepairService
        self.configRepairService = configRepairService ?? AnthropicConfigRepairService()

        // Initialize ConfigReloadCoordinator
        configReloadCoordinator = ConfigReloadCoordinator(
            reloadSafetyMonitor: reloadSafetyMonitor,
            healthStatusProvider: { [diagnosticsManager] in
                await diagnosticsManager.checkHealth()
            },
            isRuntimeTransitioning: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.isRuntimeTransitionInProgress
            },
            startRuntimeForExplicitApply: { [serviceLifecycleCoordinator] in
                await serviceLifecycleCoordinator.startKanata(reason: "Applying onboarding rules after interrupted startup")
            },
            runtimeWantsRunning: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.sessionWantsRunning
            },
            runtimeIntentGeneration: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.sessionIntentGeneration
            },
            currentManagedCaps: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.sessionManagedCapsActive
            },
            currentCapsIntermediate: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.sessionManagedCapsActive ? serviceLifecycleCoordinator.sessionCapsIntermediate : nil
            },
            currentCapsPaused: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.sessionCapsPaused != nil
            },
            capsNoLongerNeeded: { [serviceLifecycleCoordinator] in
                serviceLifecycleCoordinator.clearCapsPaused()
            },
            restartForManagedCapsChange: { [serviceLifecycleCoordinator] in
                await serviceLifecycleCoordinator.restartKanata(reason: "Caps runtime mode changed during config reload")
            }
        )

        // Dispatch heavy initialization work to background thread (skip during unit tests)
        // Prefer structured concurrency; a plain Task{} runs off the main actor by default
        if !TestEnvironment.isRunningTests, !isOneShotProbeMode {
            Task { [weak self] in
                await self?.performInitialization()
            }
        } else {
            AppLogger.shared.debug(
                "🧪 [RuntimeCoordinator] Skipping background initialization in \(isOneShotProbeMode ? "one-shot probe" : "test") mode"
            )
        }

        if isHeadlessMode {
            AppLogger.shared.log("🤖 [RuntimeCoordinator] Initialized in headless mode")
        }

        // Wire up SaveCoordinator delegate for status change notifications
        saveCoordinator.delegate = self

        // Wire up ServiceLifecycleCoordinator callbacks
        serviceLifecycleCoordinator.onError = { [weak self] error in
            self?.lastError = error
        }
        serviceLifecycleCoordinator.onWarning = { [weak self] warning in
            self?.lastWarning = warning
        }
        serviceLifecycleCoordinator.onAdmissionEnvironment = { [weak self] environment in
            self?.ruleCollectionsManager.admissionEnvironment = environment
        }
        // A refused start or save names the rule the engine blames (phase 4e).
        serviceLifecycleCoordinator.admissionAttribution = { [weak self] in
            self?.ruleCollectionsManager.blockingAdmissionSentences() ?? []
        }
        configurationService.sessionRefusalAttribution = { [weak self] in
            self?.ruleCollectionsManager.blockingAdmissionSentences() ?? []
        }
        StuckKeyRecoveryService.shared.sessionReportProvider = { [weak self] in
            self?.serviceLifecycleCoordinator.lastSessionReportForDiagnostics()
        }
        StuckKeyRecoveryService.shared.runtimeIsRemapping = { [weak self] in
            guard let report = self?.serviceLifecycleCoordinator.currentSessionReport() else { return false }
            return report.state == .running && report.tapActive
        }
        // Wire up ConfigReloadCoordinator callbacks
        configReloadCoordinator.onReloadSuccess = { [weak self] in
            self?.clearDiagnostics()
        }
        configReloadCoordinator.configurationOperationGate = configurationService.operationGate
        configReloadCoordinator.onDeferredReloadSuccess = {
            await AppContextService.shared.reloadMappings(afterRuntimeReload: true)
        }

        // Recording pause uses the same session owner; no process-wide termination.
        recoveryCoordinator.configure(
            killAllKanataProcesses: { [weak serviceLifecycleCoordinator] in
                guard await serviceLifecycleCoordinator?.stopKanata(reason: "Recording pause") == true else {
                    throw KeyPathError.process(.notRunning)
                }
            },
            restartService: { [weak serviceLifecycleCoordinator] reason in
                await serviceLifecycleCoordinator?.startKanata(reason: reason) ?? false
            }
        )

        // Wire up RuleCollectionsManager callbacks
        ruleCollectionsManager.onRulesChanged = { [weak self] in
            guard let self else {
                return ReloadResult(success: false, response: nil, errorMessage: "Runtime coordinator unavailable", protocol: nil, disposition: .failed)
            }
            return await applyPersistedRuleChanges()
        }
        ruleCollectionsManager.onLayerChanged = { [weak self] layerName in
            self?.currentLayerName = layerName
            NotificationCenter.default.post(KanataLayerChange(layerName: layerName, source: .kanata))
        }
        ruleCollectionsManager.onError = { [weak self] error in
            AppLogger.shared.debug("🚨 [RuntimeCoordinator] onError callback received: \(error)")
            self?.lastError = error
        }
        ruleCollectionsManager.onWarning = { [weak self] warning in
            self?.lastWarning = warning
            SoundManager.shared.playWarningSound()
            self?.warningExpiryTask?.cancel()
            self?.warningExpiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self?.lastWarning == warning else { return }
                self?.lastWarning = nil
            }
        }
        ruleCollectionsManager.onConflictResolution = { [weak self] context in
            await self?.promptForConflictResolution(context)
        }
        ruleCollectionsManager.onMappingConflictResolution = { [weak self] context in
            await self?.promptForMappingConflict(context)
        }
        ruleCollectionsManager.onPrerequisiteSetup = { [weak self] context, apply in
            guard let self else { return .failure(CancellationError()) }
            // The sheet lives in the Settings window, and this waits while holding
            // the rule-write gate. Bring Settings forward so a request made from the
            // overlay or a pack window is answerable, and never strand an older one.
            pendingRuleSetup?.finish(.failure(CancellationError()))
            return await withCheckedContinuation { continuation in
                self.pendingRuleSetup = RuleSetupSession(context: context, apply: apply) { [weak self] result in
                    self?.pendingRuleSetup = nil
                    continuation.resume(returning: result)
                }
                openPreferencesTab(.openSettingsRules)
            }
        }
        ruleCollectionsManager.onPrerequisiteResolution = { [weak self] context in
            await self?.promptForPrerequisiteResolution(context)
        }
        ruleCollectionsManager.onDependentResolution = { [weak self] context in
            await self?.promptForDependentResolution(context)
        }
        // Note: onActionURI callback not needed - RuleCollectionsManager.handleActionURI()
        // already dispatches to ActionDispatcher. Setting this would cause double dispatch.
        ruleCollectionsManager.onBeforeSave = nil

        if !isOneShotProbeMode, !TestEnvironment.isTestHostProcess {
            AppLogger.shared.log(
                "🏗️ [RuntimeCoordinator] About to call bootstrapRuleCollections and startEventMonitoring"
            )
            Task {
                await ruleCollectionsManager.bootstrap()
                do {
                    _ = try await configurationService.applyRecoveredDeviceRuntimeRestartIfNeeded(
                        mutationPermit: nil
                    ) { [weak self] in
                        guard let self else { return false }
                        return await restartKanata(reason: "Recovering device selection")
                    }
                } catch {
                    self.lastError = error.localizedDescription
                }
                ruleCollectionsManager.startEventMonitoring()
            }
            HrmObservabilityService.shared.startMonitoring()
            _ = KeystrokeHistoryService.shared
        } else {
            // #922: bootstrap() performs real disk I/O (config load/save), TCP reload
            // attempts, and posts notifications/sounds — unstubbed side effects that raced
            // with fixture assertions in unit tests (e.g. RecordingCoordinatorTests), causing
            // flaky failures on the self-hosted CI runner. Skip it in test-host processes;
            // explicit tests of bootstrap() call it directly on their own
            // RuleCollectionsManager instance. isTestHostProcess (not isRunningTests) so a
            // REAL app launched inside a CI job for smoke QA still bootstraps its rules.
            AppLogger.shared.log("🧪 [RuntimeCoordinator] One-shot probe mode or test host - skipping bootstrap and event monitoring")
        }

        if !isOneShotProbeMode {
            // Authoritative kanata grab status (#625): a grab failure means kanata
            // is up but not remapping. Drive bounded auto-recovery off this signal.
            grabStatusObserver = NotificationCenter.default.addObserver(for: KanataGrabStatus.self) { [weak self] status in
                Task { @MainActor [weak self] in
                    await self?.handleGrabStatusChanged(active: status.active, reason: status.reason)
                }
            }
        }

        AppLogger.shared.log("🏗️ [RuntimeCoordinator] init() completed")
    }

    // Note: RuleCollectionsManager handles its own cleanup in deinit

    // MARK: - Public Interface

    /// Fetch layer names reported by Kanata over TCP.
    /// Falls back to empty list if the service is unavailable.
    func fetchLayerNamesFromKanata() async -> [String] {
        let client = KanataTCPClient(timeout: 3.0)

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
        let client = KanataTCPClient(timeout: 3.0)

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

    private(set) var uninstallCleanupCompleted = false

    func uninstall(deleteConfig: Bool) async -> InstallerReport {
        // Telemetry has its own debounced writer, outside the config operation
        // gate. Drain it before backup and keep it closed through app termination.
        KindaVimTelemetryStore.shared.suspendForUninstall()
        let report = await installerEngine.uninstall(deleteConfig: deleteConfig)
        // Successful uninstall already verified runtime cleanup and intentionally
        // leaves configuration admission suspended until process exit.
        uninstallCleanupCompleted = report.success
        if !report.success {
            KindaVimTelemetryStore.shared.resumeAfterFailedUninstall()
        }
        return report
    }

    /// Persist exact-device Caps consent only after admitted runtime restoration.
    /// The change stops the runtime to release the Caps lease; if it was running,
    /// it is started again afterwards, whether the change committed or was refused.
    func setCapsSelection(_ selection: SessionCapsSelection?, automaticSetupDisabled: Bool? = nil,
                          selectedKeyboardOnly: Bool? = nil) async -> Bool
    {
        let wasRunning = serviceLifecycleCoordinator.sessionWantsRunning
        let changed: Bool
        do {
            changed = try await configurationService.operationGate.withOperation { [serviceLifecycleCoordinator] _ in
                await serviceLifecycleCoordinator.changeCapsSelection(verify: {
                    guard let selection else { return }
                    try await Task.detached {
                        try selection.verifyConnected(devices: SessionCapsHIDUtilTransport.backend().enumerate(),
                                                      currentBoot: SessionCapsRuntimeSupport.bootSessionUUID())
                        try SessionCapsRuntimeSupport.requirePhysicalAllUp()
                    }.value
                }, commit: {
                    try SessionCapsSelectionStore.save(selection)
                    // Before any restart: start-up reads this to decide automatic Caps setup.
                    if let automaticSetupDisabled {
                        UserDefaults.standard.set(automaticSetupDisabled, forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
                    }
                    if let selectedKeyboardOnly {
                        UserDefaults.standard.set(selectedKeyboardOnly, forKey: SessionCapsRuntimeSupport.selectedKeyboardOnlyKey)
                    }
                })
            }
        } catch { changed = false }
        await serviceLifecycleCoordinator.resumeAfterCapsSelectionChange(wasRunning: wasRunning)
        return changed
    }

    /// Apply keyboard exceptions only after the current leases were restored.
    /// A failed stop leaves both the preference and live mappings unchanged.
    func setCapsExcludedKeyboardIDs(_ ids: Set<String>) async -> Bool {
        guard ids.count <= 128, ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }) else { return false }
        let wasRunning = serviceLifecycleCoordinator.sessionWantsRunning
        let changed: Bool
        do {
            changed = try await configurationService.operationGate.withOperation { [serviceLifecycleCoordinator] _ in
                await serviceLifecycleCoordinator.changeCapsSelection(verify: {}, commit: {
                    UserDefaults.standard.set(ids.sorted(), forKey: SessionCapsRuntimeSupport.excludedKeyboardsKey)
                })
            }
        } catch { changed = false }
        await serviceLifecycleCoordinator.resumeAfterCapsSelectionChange(wasRunning: wasRunning)
        return changed
    }

    /// Stop Kanata when the app is terminating (async version).
    func cleanup() async {
        let stopped = await stopKanata(reason: "App termination cleanup")
        if !stopped {
            AppLogger.shared.warn("⚠️ [RuntimeCoordinator] Failed to stop runtime during cleanup")
        }
    }

    // MARK: - Installation and Permissions

    func isInstalled() -> Bool {
        isServiceInstalled()
    }

    func isCompletelyInstalled() -> Bool {
        isServiceInstalled()
    }

    func hasAccessibilityPermission() async -> Bool {
        await SystemStateProvider.shared.currentPermissionSnapshot().accessibility.isReady
    }

    func hasAllRequiredPermissions() async -> Bool {
        await SystemStateProvider.shared.currentPermissionSnapshot().isSystemReady
    }

    func hasAllSystemRequirements() async -> Bool {
        let snapshot = await installerEngine.inspectSystem()
        return snapshot.isReady
    }

    func getSystemRequirementsStatus() async -> (
        installed: Bool, permissions: Bool, driver: Bool, daemon: Bool
    ) {
        let snapshot = await installerEngine.inspectSystem()
        // Historical tuple fields describe satisfied prerequisites: the session
        // backend has no driver or privileged daemon prerequisite.
        return (installed: snapshot.components.kanataBinaryInstalled,
                permissions: snapshot.permissions.isSystemReady, driver: true, daemon: true)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: KeyPathConstants.URLs.accessibilityPrivacy) {
            NSWorkspace.shared.open(url)
        }
    }

    func getInstallationStatus() -> String {
        isServiceInstalled() ? "✅ Session runtime installed" : "❌ Session runtime missing"
    }

    func performTransparentInstallation() async -> Bool {
        await createInitialConfigIfNeeded()
        let snapshot = await installerEngine.inspectSystem()
        return snapshot.isReady
    }

    // MARK: - Methods Expected by Tests

    func isServiceInstalled() -> Bool {
        Foundation.FileManager.default.fileExists(atPath: WizardSystemPaths.bundledKanataPath)
    }

    // MARK: - Configuration Backup Managemen

    /// Create a backup before opening config for editing
    /// Returns true if backup was created successfully
    func createPreEditBackup() -> Bool {
        configBackupManager.createPreEditBackup(generationPreferences: RuleBackupPreferences(defaults: ruleCollectionsManager.preferencesService.persistenceDefaults))
    }

    /// Get list of available configuration backups
    func getAvailableBackups() -> [BackupInfo] {
        configBackupManager.getAvailableBackups()
    }

    /// Restore configuration from a specific backup
    func restoreFromBackup(_ backup: BackupInfo) async -> SaveResult {
        await ruleCollectionsManager.restoreConfigurationBackup(backup)
    }

    func resetToDefaultConfig() async throws {
        // IMPORTANT: Reset should ALWAYS work - it's a recovery mechanism for broken configs
        // Intentionally bypass validation here: force-write a known-good default config (enforced by tests)
        AppLogger.shared.log(
            "🔄 [Reset] Forcing reset to default config (no validation - recovery mode)"
        )

        // Create a safety backup of the current config (if valid) before resetting
        let backupCreated = configBackupManager.createPreEditBackup(generationPreferences: RuleBackupPreferences(defaults: ruleCollectionsManager.preferencesService.persistenceDefaults))
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
        try Foundation.FileManager().createDirectory(at: configDir, withIntermediateDirectories: true)

        // Write the default config (unconditionally)
        try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        AppLogger.shared.log("💾 [Config] Reset to default configuration (macOS Function Keys only)")

        // Update the stores with ALL collections (so UI shows correct enabled/disabled state)
        try await RuleCollectionStore.shared.saveCollections(allCollections)
        try await CustomRulesStore.shared.saveRules([]) // Clear custom rules

        // Re-bootstrap the manager to pick up the changes
        await ruleCollectionsManager.bootstrap()

        AppLogger.shared.log("🔄 [Reset] Updated stores and manager properties to match default state")

        // Skip TCP/service operations in test environment to avoid timeouts
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🧪 [Reset] Test environment - skipping TCP reload")
            return
        }

        // Apply changes immediately via TCP reload if the real runtime is running
        let runtimeStatus = await currentRuntimeStatusInternal()
        if runtimeStatus.isRunning {
            AppLogger.shared.info("🔄 [Reset] Triggering immediate config reload via TCP...")
            let reloadResult = await triggerConfigReload()

            if reloadResult.disposition == .applied {
                let response = reloadResult.response ?? "Success"
                AppLogger.shared.info("✅ [Reset] Default config applied successfully via TCP: \(response)")
                // Play happy chime on successful reset
                await MainActor.run {
                    SoundManager.shared.playGlassSound()
                    saveStatus = .success
                }
            } else if reloadResult.disposition == .pending {
                let reason = reloadResult.errorMessage ?? "reload pending"
                AppLogger.shared.info("ℹ️ [Reset] Default config saved; reload pending: \(reason)")
                await MainActor.run {
                    saveStatus = .success
                }
            } else {
                let error = reloadResult.errorMessage ?? "Unknown error"
                let response = reloadResult.response ?? "No response"
                AppLogger.shared.warn("⚠️ [Reset] TCP reload failed (\(error)), fallback restart initiated")
                AppLogger.shared.log("📝 [Reset] TCP response: \(response)")
                await MainActor.run {
                    saveStatus = .failed(String(localized: "Reset reload failed: \(error)"))
                }
                // If TCP reload fails, fall back to service restart
                _ = await restartKanata(reason: "Default config reload fallback")
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

    // MARK: - Enhanced Config Validation and Recovery

    /// Opens a file in Zed editor with fallback options
    func openFileInZed(_ filePath: String) async {
        await configurationManager.openInEditor(filePath)
    }

    // MARK: - Kanata Arguments Builder

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
            throw KeyPathError.configuration(.repairFailed(reason: String(localized: "No Claude API key configured. Add one in Settings → Experimental → AI Config Generation.")))
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

    // MARK: - SaveCoordinatorDelegate

    func saveStatusDidChange(_ status: SaveStatus) {
        saveStatus = status
    }

    func configDidUpdate(mappings: [KeyMapping]) {
        applyKeyMappings(mappings)
    }

    // MARK: - Configuration Initialization

    func createInitialConfigIfNeeded() async {
        do {
            try await configurationService.createInitialConfigIfNeeded()
        } catch {
            AppLogger.shared.error(
                "❌ [Config] Failed to create initial config via ConfigurationService: \(error)"
            )
        }
    }

    /// Public wrapper to ensure a default user config exists.
    /// Returns true if the config exists after this call.
    func createDefaultUserConfigIfMissing() async -> Bool {
        await configurationManager.createDefaultIfMissing()
    }

    // MARK: - Configuration Validation

    func validateConfigFile() async -> (isValid: Bool, errors: [String]) {
        await configurationManager.validateConfigFile()
    }

    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String
    {
        try await configurationManager.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )
    }

    // MARK: - Hot Reload via TCP (delegates to ConfigReloadCoordinator)

    /// Main reload method using TCP protocol
    func triggerConfigReload() async -> ReloadResult {
        await configReloadCoordinator.triggerConfigReload()
    }

    /// Apply rule changes that have already been validated and persisted.
    ///
    /// Most rule saves reach this through `onRulesChanged`. Transactions that
    /// deliberately suppress that callback so they can verify the live result
    /// use this same path explicitly, keeping state and overlay notifications
    /// consistent without issuing a duplicate reload.
    func applyPersistedRuleChanges(recoverStoppedRuntime: Bool = false) async -> ReloadResult {
        let result = await configReloadCoordinator.triggerConfigReload(recoverStoppedRuntime: recoverStoppedRuntime)
        AppLogger.shared.debug(
            "🔔 [RuntimeCoordinator] Posting kanataConfigChanged notification"
        )
        NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
        return result
    }

    /// TCP-based config reload (no authentication required - see ADR-013)
    func triggerTCPReload() async -> TCPReloadResult {
        await configReloadCoordinator.triggerTCPReload()
    }

    /// Main reload method that should be used by new code
    func triggerReload() async {
        await configReloadCoordinator.triggerReload()
    }

    // MARK: - Lifecycle Initialization

    func performInitialization() async {
        if isInitializing {
            AppLogger.shared.warn("⚠️ [Init] Already initializing - skipping duplicate initialization")
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        let engine = InstallerEngine()

        let ensuredConfig = await createDefaultUserConfigIfMissing()
        if ensuredConfig {
            AppLogger.shared.log("✅ [Init] Verified user config exists at \(configPath)")
        }

        await saveCoordinator.ensureBackupExists()

        await MainActor.run {
            startConfigFileWatching()
        }

        let context = await engine.inspectSystem()

        if context.services.kanataRunning {
            AppLogger.shared.info("✅ [Init] Kanata is already running - skipping initialization")
            return
        }

        AppLogger.shared.log(
            "🔍 [Init] System Context: installed=\(context.components.kanataBinaryInstalled), permissions=\(context.permissions.isSystemReady)"
        )
    }

    // MARK: - Recovery Operations (delegates to RecoveryCoordinator)

    /// Pre-guard gate for a grab-status event (#625). Pure function so the
    /// suppression rules are unit-testable without touching the real recovery action.
    enum GrabRecoveryGate: Equatable, Sendable {
        /// `active == true` — authoritative healthy grab; reset the recovery budget.
        case recordSuccess
        /// Benign `active=false` during an intentional stop — do nothing.
        case suppressedDuringTransition
        /// A recovery is already in flight — do nothing (single-flight).
        case suppressedRecoveryInFlight
        /// Genuine grab failure — consult the bounded guard and maybe recover.
        case evaluate
    }

    nonisolated static func decideGrabRecoveryGate(
        active: Bool,
        isIntentionalTransition: Bool,
        isRecovering: Bool
    ) -> GrabRecoveryGate {
        if active {
            return .recordSuccess
        }
        if isIntentionalTransition {
            return .suppressedDuringTransition
        }
        if isRecovering {
            return .suppressedRecoveryInFlight
        }
        return .evaluate
    }

    /// React to an authoritative kanata `InputGrab` status (#625).
    ///
    /// `active == false` means kanata is up (process + TCP) but failed to seize the
    /// keyboard — remapping is silently dead. W3 keeps this passive: record/surface
    /// the degraded state, but do not mutate services from this background signal.
    /// `active == true` clears the failure budget.
    func handleGrabStatusChanged(active: Bool, reason: String?) async {
        switch Self.decideGrabRecoveryGate(
            active: active,
            isIntentionalTransition: serviceLifecycleCoordinator.isIntentionalTransitionInProgress,
            isRecovering: isRecoveringGrab
        ) {
        case .recordSuccess:
            // Authoritative healthy grab → reset the episode budget so a future
            // failure gets a fresh set of attempts.
            await diagnosticsManager.recordGrabSuccess()
            // If we'd previously given up and surfaced a persistent error, the grab
            // is working again now — clear that stale message so the UI recovers.
            if grabGiveUpErrorActive {
                grabGiveUpErrorActive = false
                lastError = nil
            }

        case .suppressedDuringTransition:
            AppLogger.shared.log(
                "🎛️ [RuntimeCoordinator] Grab inactive during an intentional transition — suppressing recovery (reason: \(reason ?? "none"))"
            )

        case .suppressedRecoveryInFlight:
            AppLogger.shared.log("🎛️ [RuntimeCoordinator] Grab recovery already in flight — ignoring")

        case .evaluate:
            // Note (#625): kanata only emits InputGrab on a transition or in reply to
            // RequestInputGrab at connect — it does not re-emit a steady failure. The
            // post-restart grab status from a freshly started kanata is no longer masked
            // by the stop-grace (startKanata clears it), so a restart that lands degraded
            // does reach here. The one residual window is single-flight: a failure event
            // arriving while a recovery is still in flight is suppressed; in practice the
            // new kanata's InputGrab arrives after the recovery call returns, so the
            // bounded loop re-fires and advances toward give-up.
            switch await diagnosticsManager.recordGrabFailureAndDecideRecovery() {
            case let .recover(attempt):
                AppLogger.shared.info(
                    "🚨 [RuntimeCoordinator] kanata failed to grab the keyboard (reason: \(reason ?? "unknown")) — surfacing degraded state (observation \(attempt))"
                )
                lastError = String(localized: "Keyboard remapping is not active: kanata could not capture the keyboard. Try quitting other keyboard tools, then restart KeyPath.")
                grabGiveUpErrorActive = true
            case let .giveUp(attempts):
                AppLogger.shared.error(
                    "❌ [RuntimeCoordinator] kanata still not grabbing the keyboard after \(attempts) observations — manual intervention / reboot may be needed"
                )
                lastError = String(localized: "Keyboard remapping is not active: kanata could not capture the keyboard after repeated checks. Try quitting other keyboard tools, then restart KeyPath.")
                grabGiveUpErrorActive = true
            }
        }
    }

    func attemptKeyboardRecovery() async {
        _ = await restartKanata(reason: "Session keyboard recovery")
    }

    // MARK: - Service Management

    @discardableResult
    public func startKanata(reason: String = "Manual start") async -> Bool {
        await serviceLifecycleCoordinator.startKanata(reason: reason)
    }

    @discardableResult
    public func stopKanata(reason: String = "Manual stop") async -> Bool {
        await serviceLifecycleCoordinator.stopKanata(reason: reason)
    }

    @discardableResult
    public func restartKanata(reason: String = "Manual restart") async -> Bool {
        await serviceLifecycleCoordinator.restartKanata(reason: reason)
    }

    func currentRuntimeStatusInternal() async -> RuntimeStatus {
        await serviceLifecycleCoordinator.currentRuntimeStatus()
    }

    // MARK: - Configuration File Watching (delegates to ConfigHotReloadService)

    /// Start watching the configuration file for external changes
    func startConfigFileWatching() {
        guard let fileWatcher = configFileWatcher else {
            AppLogger.shared.warn("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
            return
        }

        configurationService.onWillStageConfigurationWrite = { [weak fileWatcher] content in
            fileWatcher?.claimInternalContent(content)
        }

        // Configure the hot reload service
        configHotReloadService.configure(
            configurationService: configurationService,
            reloadHandler: { [weak self] in
                guard let self else { return .failed("Coordinator deallocated") }
                let result = await triggerConfigReload()
                return ConfigHotReloadService.ReloadOutcome(
                    disposition: result.disposition,
                    message: result.errorMessage
                )
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

    // MARK: - Config Maintenance

    /// Backup current working config before making changes
    func backupCurrentConfig() async {
        let config = await configurationService.current()
        saveCoordinator.backupCurrentConfig(config.content)
    }

    /// Restore last known good config in case of validation failure
    func restoreLastGoodConfig() async throws {
        try await saveCoordinator.restoreLastGoodConfig()
    }

    /// Shared app-specific edit path used by mapper, settings, and overlay.
    func mutateAppKeymaps(
        store: AppKeymapStore = .shared,
        _ mutate: @escaping @MainActor @Sendable (inout [AppKeymap]) throws -> Void
    ) async throws {
        let result = await saveCoordinator.saveAppKeymaps(store: store, mutate: mutate, runtimeDidApply: {
            await AppContextService.shared.reloadMappings(afterRuntimeReload: true)
        }) { [weak self] in
            guard let self else {
                return ReloadResult(success: false, response: nil, errorMessage: "Coordinator deallocated", protocol: nil, disposition: .failed)
            }
            return await triggerConfigReload()
        }
        saveStatus = saveCoordinator.saveStatus
        guard result.success else {
            throw result.error ?? AppConfigError.validationUnavailable
        }
        if let mappings = result.mappings {
            applyKeyMappings(mappings)
        }
    }

    func removeAppRule(bundleIdentifier: String, overrideID: UUID, store: AppKeymapStore = .shared) async throws {
        try await mutateAppKeymaps(store: store) { keymaps in
            guard let index = keymaps.firstIndex(where: { $0.mapping.bundleIdentifier == bundleIdentifier }) else { return }
            keymaps[index].overrides.removeAll { $0.id == overrideID }
            if keymaps[index].overrides.isEmpty {
                keymaps.remove(at: index)
            }
        }
    }

    func editConfiguration(at path: String, transform: @escaping @MainActor @Sendable (String) throws -> String) async -> SaveResult {
        guard URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            == URL(fileURLWithPath: configurationService.configurationPath).standardizedFileURL.resolvingSymlinksInPath()
        else {
            return .failure(KeyPathError.configuration(.loadFailed(reason: String(localized: "This editor is not connected to the requested configuration file."))))
        }
        let result = await saveCoordinator.editConfiguration(transform: transform, runtimeDidApply: {
            await AppContextService.shared.reloadMappings(afterRuntimeReload: true)
        }) { [weak self] in
            guard let self else { return ReloadResult(success: false, response: nil, errorMessage: "Coordinator unavailable", protocol: nil, disposition: .failed) }
            return await triggerConfigReload()
        }
        saveStatus = saveCoordinator.saveStatus
        if result.success, let mappings = result.mappings {
            applyKeyMappings(mappings)
        }
        return result
    }

    /// Save a complete generated configuration (for Claude API generated configs)
    func saveGeneratedConfiguration(_ configContent: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving generated configuration")

        let result = await saveCoordinator.saveGeneratedConfig(
            content: configContent,
            runtimeDidApply: { await AppContextService.shared.reloadMappings(afterRuntimeReload: true) },
            reloadHandler: { [weak self] in
                guard let self else {
                    return ReloadResult(success: false, response: nil, errorMessage: "Coordinator deallocated", protocol: nil, disposition: .failed)
                }
                return await triggerConfigReload()
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            applyKeyMappings(mappings)
        } else if let error = result.error {
            throw error
        }
    }

    func saveConfiguration(input: String, output: String) async throws {
        AppLogger.shared.log("💾 [RuntimeCoordinator] Saving configuration mapping")

        let result = await saveCoordinator.saveMapping(
            input: input,
            output: output,
            ruleCollectionsManager: ruleCollectionsManager,
            reloadHandler: { [weak self] in
                guard let self else {
                    return ReloadResult(success: false, response: nil, errorMessage: "Coordinator deallocated", protocol: nil, disposition: .failed)
                }
                return await triggerConfigReload()
            }
        )

        // Sync coordinator state to RuntimeCoordinator
        saveStatus = saveCoordinator.saveStatus

        if result.success, let mappings = result.mappings {
            applyKeyMappings(mappings)
            AppLogger.shared.log("⚡ [Config] Validation-on-demand save completed")
        } else if let error = result.error {
            throw error
        }
    }

    // MARK: - Conflict Resolution

    /// Prompt the user to resolve a rule conflict via the UI
    @MainActor
    func promptForConflictResolution(_ context: RuleConflictContext) async -> RuleConflictChoice? {
        // Cancel any pending resolution to avoid continuation leak
        conflictResolutionContinuation?.resume(returning: nil)
        conflictResolutionContinuation = nil

        pendingRuleConflict = context

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                conflictResolutionContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.conflictResolutionContinuation?.resume(returning: nil)
                self.conflictResolutionContinuation = nil
                self.pendingRuleConflict = nil
            }
        }
    }

    /// Called by ViewModel when user makes a choice in the conflict resolution dialog
    func resolveConflict(with choice: RuleConflictChoice?) {
        pendingRuleConflict = nil
        conflictResolutionContinuation?.resume(returning: choice)
        conflictResolutionContinuation = nil
    }

    /// Prompt the user to resolve a save-time mapping conflict by disabling a
    /// collection (#460). Returns the collection id to disable, or nil to cancel.
    @MainActor
    func promptForMappingConflict(_ context: MappingConflictContext) async -> UUID? {
        // Cancel any pending resolution to avoid continuation leak
        mappingConflictContinuation?.resume(returning: nil)
        mappingConflictContinuation = nil

        pendingMappingConflict = context

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                mappingConflictContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.mappingConflictContinuation?.resume(returning: nil)
                self.mappingConflictContinuation = nil
                self.pendingMappingConflict = nil
            }
        }
    }

    /// Called by ViewModel when the user resolves (or dismisses) a mapping conflict.
    func resolveMappingConflict(disabling collectionID: UUID?) {
        pendingMappingConflict = nil
        mappingConflictContinuation?.resume(returning: collectionID)
        mappingConflictContinuation = nil
    }

    /// Prompts before applying an enable or save that introduces an unmet
    /// requirement. The dialog receives a prepared presentation snapshot.
    @MainActor
    func promptForPrerequisiteResolution(
        _ context: RulePrerequisiteResolutionContext
    ) async -> RulePrerequisiteResolutionChoice? {
        prerequisiteResolutionContinuation?.resume(returning: nil)
        prerequisiteResolutionContinuation = nil

        pendingPrerequisiteResolution = RulePrerequisiteDialogModel(context: context)
        openPreferencesTab(.openSettingsRules)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                prerequisiteResolutionContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.prerequisiteResolutionContinuation?.resume(returning: nil)
                self.prerequisiteResolutionContinuation = nil
                self.pendingPrerequisiteResolution = nil
            }
        }
    }

    func resolvePrerequisiteResolution(
        with choice: RulePrerequisiteResolutionChoice?
    ) {
        pendingPrerequisiteResolution = nil
        prerequisiteResolutionContinuation?.resume(returning: choice)
        prerequisiteResolutionContinuation = nil
    }

    /// Prompts before disabling a provider that is still required by enabled rules.
    @MainActor
    func promptForDependentResolution(
        _ context: RuleDependentResolutionContext
    ) async -> RuleDependentResolutionChoice? {
        dependentResolutionContinuation?.resume(returning: nil)
        dependentResolutionContinuation = nil

        pendingDependentResolution = RuleDependentResolutionDialogModel(
            context: context
        )
        openPreferencesTab(.openSettingsRules)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                dependentResolutionContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.dependentResolutionContinuation?.resume(returning: nil)
                self.dependentResolutionContinuation = nil
                self.pendingDependentResolution = nil
            }
        }
    }

    func resolveDependentResolution(
        with choice: RuleDependentResolutionChoice?
    ) {
        pendingDependentResolution = nil
        dependentResolutionContinuation?.resume(returning: choice)
        dependentResolutionContinuation = nil
    }

    // MARK: - Diagnostics

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnosticsManager.addDiagnostic(diagnostic)
    }

    func clearDiagnostics() {
        diagnosticsManager.clearDiagnostics()
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
            success = await restartKanata(
                reason: "AutoFix diagnostic: \(diagnostic.title)"
            )
        }

        recoveryCoordinator.logAutoFixResult(action, success: success)
        return success
    }
}

// MARK: - Result Types

enum ReloadDisposition: Sendable, Equatable {
    case applied
    case pending
    case rejected
    case failed
}

/// TCP reload result
struct ReloadResult {
    let success: Bool
    let response: String?
    let errorMessage: String?
    let `protocol`: CommunicationProtocol?
    let disposition: ReloadDisposition

    var isSuccess: Bool {
        disposition == .applied
    }

    init(
        success: Bool,
        response: String?,
        errorMessage: String?,
        protocol: CommunicationProtocol?,
        disposition: ReloadDisposition? = nil
    ) {
        self.success = success
        self.response = response
        self.errorMessage = errorMessage
        self.protocol = `protocol`
        self.disposition = disposition ?? (success ? .applied : .failed)
    }
}

/// Sendable is already required of this type: the wizard protocol it conforms to
/// in WizardProtocolConformances.swift inherits Sendable, so the conformance has
/// been in force all along. Swift 6 requires it to be declared alongside the
/// class rather than in the conformance file, so state it here. This records the
/// existing guarantee where the compiler wants it; it is not a new claim about
/// this type's thread safety.
extension RuntimeCoordinator: @unchecked Sendable {}
