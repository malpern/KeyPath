import ApplicationServices
import Foundation
import IOKit.hidsystem
import Network
import SwiftUI

/// Actor for process synchronization to prevent multiple concurrent Kanata starts
actor ProcessSynchronizationActor {
    func synchronize<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        try await operation()
    }
}

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

/// Simple UI-focused state model (from SimpleKanataManager)
enum SimpleKanataState: String, CaseIterable {
    case starting // App launched, attempting auto-start
    case running // Kanata is running successfully
    case needsHelp = "needs_help" // Auto-start failed, user intervention required
    case stopped // User manually stopped

    var displayName: String {
        switch self {
        case .starting: "Starting..."
        case .running: "Running"
        case .needsHelp: "Needs Help"
        case .stopped: "Stopped"
        }
    }

    var isWorking: Bool {
        self == .running
    }

    var needsUserAction: Bool {
        self == .needsHelp
    }
}

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
/// - Core initialization and state management
/// - UI state snapshots and ViewModel interface
/// - Health monitoring and auto-start logic
/// - Diagnostics and error handling
///
/// **KanataManager+Lifecycle.swift** (~400 lines)
/// - Process start/stop/restart operations
/// - LaunchDaemon service management
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
/// - Config reload and layer management
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
        case let .failed(error): "❌ Config Invalid: \(error)"
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
    var isRunning = false
    var lastError: String?
    var keyMappings: [KeyMapping] = []
    var diagnostics: [KanataDiagnostic] = []
    var lastProcessExitCode: Int32?
    var lastConfigUpdate: Date = .init()

    // UI state properties (from SimpleKanataManager)
    var currentState: SimpleKanataState = .starting {
        didSet {
            if oldValue != currentState {
                Task { @MainActor in
                    UserNotificationService.shared.notifyStatusChange(currentState)
                }
            }
        }
    }

    var errorReason: String?
    var showWizard: Bool = false
    var launchFailureStatus: LaunchFailureStatus? {
        didSet {
            if let status = launchFailureStatus {
                Task { @MainActor in
                    UserNotificationService.shared.notifyLaunchFailure(status)
                }
            }
        }
    }

    var autoStartAttempts: Int = 0
    var lastHealthCheck: Date?
    var retryCount: Int = 0
    var isRetryingAfterFix: Bool = false

    // Lifecycle state properties (from KanataLifecycleManager)
    var lifecycleState: LifecycleStateMachine.KanataState = .uninitialized
    var lifecycleErrorMessage: String?
    var isBusy: Bool = false
    var canPerformActions: Bool = true
    var autoStartAttempted: Bool = false
    var autoStartSucceeded: Bool = false
    var autoStartFailureReason: String?
    var shouldShowWizard: Bool = false

    // Validation-specific UI state
    var showingValidationAlert = false
    var validationAlertTitle = ""
    var validationAlertMessage = ""
    var validationAlertActions: [ValidationAlertAction] = []

    // Save progress feedback
    var saveStatus: SaveStatus = .idle

    // MARK: - UI State Snapshot (Phase 4: MVVM)

    /// Returns a snapshot of current UI state for ViewModel synchronization
    /// This method allows KanataViewModel to read UI state without @Published properties
    func getCurrentUIState() -> KanataUIState {
        // Sync diagnostics from DiagnosticsManager
        diagnostics = diagnosticsManager.getDiagnostics()
        
        return KanataUIState(
            isRunning: isRunning,
            lastError: lastError,
            keyMappings: keyMappings,
            diagnostics: diagnostics,
            lastProcessExitCode: lastProcessExitCode,
            lastConfigUpdate: lastConfigUpdate,
            currentState: currentState,
            errorReason: errorReason,
            showWizard: showWizard,
            launchFailureStatus: launchFailureStatus,
            autoStartAttempts: autoStartAttempts,
            lastHealthCheck: lastHealthCheck,
            retryCount: retryCount,
            isRetryingAfterFix: isRetryingAfterFix,
            lifecycleState: lifecycleState,
            lifecycleErrorMessage: lifecycleErrorMessage,
            isBusy: isBusy,
            canPerformActions: canPerformActions,
            autoStartAttempted: autoStartAttempted,
            autoStartSucceeded: autoStartSucceeded,
            autoStartFailureReason: autoStartFailureReason,
            shouldShowWizard: shouldShowWizard,
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
    private let karabinerConflictService: KarabinerConflictManaging
    private let configBackupManager: ConfigBackupManager
    
    private var isStartingKanata = false
    var isInitializing = false
    private let isHeadlessMode: Bool

    // MARK: - UI State Management Properties (from SimpleKanataManager)

    private var healthTimer: Timer?
    private var statusTimer: Timer?
    private let maxAutoStartAttempts = 2
    private let maxRetryAttempts = 3
    private var lastPermissionState: (input: Bool, accessibility: Bool) = (false, false)

    // MARK: - Lifecycle State Machine (from KanataLifecycleManager)

    // Note: Removed stateMachine to avoid MainActor isolation issues
    // Lifecycle management is now handled directly in this class

    // MARK: - Process Synchronization (Phase 1)

    private static let startupActor = ProcessSynchronizationActor()
    private var lastStartAttempt: Date? // Still used for backward compatibility
    private var lastServiceKickstart: Date? // Still used for grace period tracking

    // Configuration file watching for hot reload
    private var configFileWatcher: ConfigFileWatcher?

    var configPath: String {
        configurationManager.configPath
    }

    init(engineClient: EngineClient? = nil) {
        // Check if running in headless mode
        isHeadlessMode =
            ProcessInfo.processInfo.arguments.contains("--headless")
                || ProcessInfo.processInfo.environment["KEYPATH_HEADLESS"] == "1"

        // Initialize TCP server grace period timestamp at app startup
        // This prevents immediate admin requests on launch
        lastServiceKickstart = Date()

        // Initialize legacy service dependencies (for backward compatibility)
        configurationService = ConfigurationService(configDirectory: "\(NSHomeDirectory())/.config/keypath")
        processLifecycleManager = ProcessLifecycleManager(kanataManager: nil)
        
        // Initialize configuration file watcher for hot reload
        configFileWatcher = ConfigFileWatcher()
        
        // Initialize configuration backup manager
        let configBackupManager = ConfigBackupManager(configPath: "\(NSHomeDirectory())/.config/keypath/keypath.kbd")
        
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
        
        // Initialize EngineClient
        self.engineClient = engineClient ?? TCPEngineClient()

        // Dispatch heavy initialization work to background thread (skip during unit tests)
        // Use Task.detached to ensure this runs off the main thread even with @MainActor
        if !TestEnvironment.isRunningTests {
            Task.detached { [weak self] in
                // Clean up any orphaned processes first
                await self?.processLifecycleManager.cleanupOrphanedProcesses()
                await self?.performInitialization()
            }
        } else {
            AppLogger.shared.log("🧪 [KanataManager] Skipping background initialization in test environment")
        }

        if isHeadlessMode {
            AppLogger.shared.log("🤖 [KanataManager] Initialized in headless mode")
        }
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
            AppLogger.shared.log("⚠️ [FileWatcher] ConfigFileWatcher not initialized")
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
            AppLogger.shared.log("❌ [FileWatcher] Config file no longer exists: \(configPath)")
            Task { @MainActor in SoundManager.shared.playErrorSound() }
            await MainActor.run {
                saveStatus = .failed("Config file was deleted")
            }
            return
        }

        do {
            let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log("📁 [FileWatcher] Read \(configContent.count) characters from external file")

            // Validate the configuration via CLI
            let validationResult = await configurationService.validateConfiguration(configContent)
            if !validationResult.isValid {
                AppLogger.shared.log("❌ [FileWatcher] External config validation failed: \(validationResult.errors.joined(separator: ", "))")
                Task { @MainActor in SoundManager.shared.playErrorSound() }

                await MainActor.run {
                    saveStatus = .failed("Invalid config from external edit: \(validationResult.errors.first ?? "Unknown error")")
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
                AppLogger.shared.log("✅ [FileWatcher] External config successfully reloaded")
                Task { @MainActor in SoundManager.shared.playGlassSound() }

                // Update configuration service with the new content
                await updateInMemoryConfig(configContent)

                await MainActor.run {
                    saveStatus = .success
                }

                AppLogger.shared.log("📝 [FileWatcher] Configuration updated from external file")
            } else {
                let errorMessage = reloadResult.errorMessage ?? "Unknown error"
                AppLogger.shared.log("❌ [FileWatcher] External config reload failed: \(errorMessage)")
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
            AppLogger.shared.log("❌ [FileWatcher] Failed to read external config: \(error)")
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
                keyMappings = parsedConfig.keyMappings
                lastConfigUpdate = Date()
            }
        } catch {
            AppLogger.shared.log("⚠️ [FileWatcher] Failed to parse config for in-memory update: \(error)")
        }
    }

    /// Attempts to recover from zombie keyboard capture when VirtualHID connection fails

    /// Starts Kanata with VirtualHID connection validation
    func startKanataWithValidation() async {
        // Check if VirtualHID daemon is running first
        if !isKarabinerDaemonRunning() {
            AppLogger.shared.log("⚠️ [Recovery] Karabiner daemon not running - recovery failed")
            updateInternalState(
                isRunning: isRunning,
                lastProcessExitCode: lastProcessExitCode,
                lastError: "Recovery failed: Karabiner daemon not available"
            )
            return
        }

        // Try starting Kanata normally
        await startKanata()
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

    /// Config backup for rollback capability
    private var lastGoodConfig: String?

    /// Backup current working config before making changes
    private func backupCurrentConfig() async {
        do {
            let currentConfig = try String(contentsOfFile: configPath, encoding: .utf8)
            lastGoodConfig = currentConfig
            AppLogger.shared.log("💾 [Backup] Current config backed up successfully")
        } catch {
            AppLogger.shared.log("⚠️ [Backup] Failed to backup current config: \(error)")
        }
    }

    /// Restore last known good config in case of validation failure
    private func restoreLastGoodConfig() async throws {
        guard let backup = lastGoodConfig else {
            throw KeyPathError.configuration(.backupNotFound)
        }

        try backup.write(toFile: configPath, atomically: true, encoding: .utf8)
        AppLogger.shared.log("🔄 [Restore] Restored last good config successfully")
    }

    func diagnoseKanataFailure(_ exitCode: Int32, _ output: String) {
        let diagnostics = diagnosticsManager.diagnoseFailure(exitCode: exitCode, output: output)

        // Check for zombie keyboard capture bug (exit code 6 with VirtualHID connection failure)
        if exitCode == 6,
           output.contains("connect_failed asio.system:61") || output.contains("connect_failed asio.system:2") {
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

    func getSystemDiagnostics() async -> [KanataDiagnostic] {
        await diagnosticsManager.getSystemDiagnostics()
    }

    // Check if permission issues should trigger the wizard
    func shouldShowWizardForPermissions() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.blockingIssue != nil
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
            await performStartKanata()
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
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds

                // Check if Kanata is still running and stop it
                guard let self else { return }

                if await MainActor.run(resultType: Bool.self, body: { self.isRunning }) {
                    AppLogger.shared.log(
                        "⚠️ [Safety] 30-second timeout reached - automatically stopping Kanata for safety")
                    await stopKanata()

                    // Show safety notification (skip in tests)
                    await MainActor.run {
                        if TestEnvironment.isRunningTests {
                            AppLogger.shared.log("🧪 [Safety] Suppressing NSAlert in test environment")
                        } else {
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
    }

    private func performStartKanata() async {
        let startTime = Date()
        AppLogger.shared.log("🚀 [Start] ========== KANATA START ATTEMPT ==========")
        AppLogger.shared.log("🚀 [Start] Time: \(startTime)")
        AppLogger.shared.log("🚀 [Start] Starting Kanata with synchronization lock...")

        // Check restart cooldown
        let cooldownState = await diagnosticsManager.canRestartService()
        if !cooldownState.canRestart {
            AppLogger.shared.log("⚠️ [Start] Restart cooldown active: \(String(format: "%.1f", cooldownState.remainingCooldown))s remaining")
            return
        }

        // Record this start attempt
        await diagnosticsManager.recordStartAttempt(timestamp: Date())
        lastStartAttempt = Date()

        // Check if already starting (prevent concurrent operations)
        if isStartingKanata {
            AppLogger.shared.log("⚠️ [Start] Kanata is already starting - skipping concurrent start")
            return
        }

        // If Kanata is already running, check if it's healthy before restarting
        if isRunning {
            AppLogger.shared.log("🔍 [Start] Kanata is already running - checking health before restart")

            // Check health via DiagnosticsManager
            let launchDaemonStatus = await checkLaunchDaemonStatus()
            let processStatus = ProcessHealthStatus(
                isRunning: launchDaemonStatus.isRunning,
                pid: launchDaemonStatus.pid
            )
            let tcpPort = PreferencesService.shared.tcpServerPort
            let healthStatus = await diagnosticsManager.checkHealth(
                processStatus: processStatus,
                tcpPort: tcpPort
            )

            if healthStatus.isHealthy, !healthStatus.shouldRestart {
                AppLogger.shared.log("✅ [Start] Kanata is healthy - no restart needed")
                return
            }

            if !healthStatus.shouldRestart {
                AppLogger.shared.log("⏳ [Start] Service not ready but should wait - skipping restart")
                return
            }

            AppLogger.shared.log("🔄 [Start] Service unhealthy: \(healthStatus.reason ?? "unknown") - proceeding with restart")

            AppLogger.shared.log("🔄 [Start] Performing necessary restart via kickstart")
            isStartingKanata = true
            defer { isStartingKanata = false }

            // Record when we're triggering a service kickstart for grace period tracking
            lastServiceKickstart = Date()

            let success = await startLaunchDaemonService() // Already uses kickstart -k

            if success {
                AppLogger.shared.log("✅ [Start] Kanata service restarted successfully via kickstart")
                await diagnosticsManager.recordStartSuccess()
                // Update service status after restart
                let serviceStatus = await checkLaunchDaemonStatus()
                if let pid = serviceStatus.pid {
                    AppLogger.shared.log("📝 [Start] Service restarted with PID: \(pid)")
                    let command = buildKanataArguments(configPath: configPath).joined(separator: " ")
                    await processLifecycleManager.registerStartedProcess(pid: Int32(pid), command: "launchd: \(command)")
                }
            } else {
                AppLogger.shared.log("❌ [Start] Kickstart restart failed - will fall through to full startup")
                // Don't return - let it fall through to full startup sequence
            }

            if success {
                return // Successfully restarted, we're done
            }
        }

        // Set flag to prevent concurrent starts
        isStartingKanata = true
        defer { isStartingKanata = false }

        // Pre-flight checks
        let validation = await validateConfigFile()
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
            updateInternalState(
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
                updateInternalState(
                    isRunning: isRunning,
                    lastProcessExitCode: lastProcessExitCode,
                    lastError: "Conflict: karabiner_grabber is running"
                )
                return
            }
        }

        // Check for and resolve any existing conflicting processes
        AppLogger.shared.log("🔍 [Start] Checking for conflicting Kanata processes...")
        await resolveProcessConflicts()

        // Check if config file exists and is readable
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: configPath) {
            AppLogger.shared.log("⚠️ [DEBUG] Config file does NOT exist at: \(configPath)")
            updateInternalState(
                isRunning: false,
                lastProcessExitCode: 1,
                lastError: "Configuration file not found: \(configPath)"
            )
            return
        } else {
            AppLogger.shared.log("✅ [DEBUG] Config file exists at: \(configPath)")
            if !fileManager.isReadableFile(atPath: configPath) {
                AppLogger.shared.log("⚠️ [DEBUG] Config file is NOT readable")
                updateInternalState(
                    isRunning: false,
                    lastProcessExitCode: 1,
                    lastError: "Configuration file not readable: \(configPath)"
                )
                return
            }
        }

        // Use LaunchDaemon service management exclusively
        AppLogger.shared.log("🚀 [Start] Starting Kanata via LaunchDaemon service...")
        AppLogger.shared.log("🔍 [DEBUG] Config path: \(configPath)")
        AppLogger.shared.log("🔍 [DEBUG] Kanata binary: \(WizardSystemPaths.kanataActiveBinary)")

        // Start the LaunchDaemon service
        // Record when we're triggering a service start for grace period tracking
        lastServiceKickstart = Date()
        let success = await startLaunchDaemonService()

        if success {
            // Wait a moment for service to initialize
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Verify service started successfully
            let serviceStatus = await checkLaunchDaemonStatus()
            if let pid = serviceStatus.pid {
                AppLogger.shared.log("📝 [Start] LaunchDaemon service started with PID: \(pid)")

                // Register with lifecycle manager
                let command = buildKanataArguments(configPath: configPath).joined(separator: " ")
                await processLifecycleManager.registerStartedProcess(pid: Int32(pid), command: "launchd: \(command)")

                // Start real-time log monitoring for VirtualHID connection issues
                startLogMonitoring()

                // Check for process conflicts after starting
                await verifyNoProcessConflicts()

                // Update state and clear old diagnostics when successfully starting
                updateInternalState(
                    isRunning: true,
                    lastProcessExitCode: nil,
                    lastError: nil,
                    shouldClearDiagnostics: true
                )

                AppLogger.shared.log("✅ [Start] Successfully started Kanata LaunchDaemon service (PID: \(pid))")
                AppLogger.shared.log("✅ [Start] ========== KANATA START SUCCESS ==========")
                await diagnosticsManager.recordStartSuccess()

            } else {
                // Service started but no PID found - may still be initializing
                AppLogger.shared.log("⚠️ [Start] LaunchDaemon service started but PID not yet available")

                // Update state to indicate running
                updateInternalState(
                    isRunning: true,
                    lastProcessExitCode: nil,
                    lastError: nil,
                    shouldClearDiagnostics: true
                )

                AppLogger.shared.log("✅ [Start] LaunchDaemon service started successfully")
                AppLogger.shared.log("✅ [Start] ========== KANATA START SUCCESS ==========")
                await healthMonitor.recordStartSuccess()
            }
        } else {
            // Failed to start LaunchDaemon service
            updateInternalState(
                isRunning: false,
                lastProcessExitCode: 1,
                lastError: "Failed to start LaunchDaemon service"
            )
            AppLogger.shared.log("❌ [Start] Failed to start LaunchDaemon service")

            let diagnostic = KanataDiagnostic(
                timestamp: Date(),
                severity: .error,
                category: .process,
                title: "LaunchDaemon Start Failed",
                description: "Failed to start Kanata LaunchDaemon service.",
                technicalDetails: "launchctl kickstart command failed",
                suggestedAction: "Check LaunchDaemon installation and permissions",
                canAutoFix: true
            )
            addDiagnostic(diagnostic)
        }

        await updateStatus()
    }

    // MARK: - UI-Focused Lifecycle Methods (from SimpleKanataManager)

    /// Check if this is a fresh install (no Kanata binary or config)
    private func isFirstTimeInstall() -> Bool {
        // Check for system-installed Kanata binary (bundled-only doesn't count as installed)
        let status = KanataBinaryDetector.shared.detectCurrentStatus().status
        let hasSystemKanataBinary = switch status {
        case .systemInstalled:
            true
        default:
            false
        }

        if !hasSystemKanataBinary {
            AppLogger.shared.log("🆕 [FreshInstall] No system Kanata binary found - fresh install detected")
            return true
        }

        // Check for user config file
        let configPath = NSHomeDirectory() + "/Library/Application Support/KeyPath/keypath.kbd"
        let hasUserConfig = FileManager.default.fileExists(atPath: configPath)

        if !hasUserConfig {
            AppLogger.shared.log("🆕 [FreshInstall] No user config found at \(configPath) - fresh install detected")
            return true
        }

        AppLogger.shared.log("✅ [FreshInstall] Both Kanata binary and user config exist - returning user")
        return false
    }

    /// Start the automatic Kanata launch sequence
    func startAutoLaunch(presentWizardOnFailure: Bool = true) async {
        AppLogger.shared.log("🚀 [KanataManager] ========== AUTO-LAUNCH START ==========")

        // Check if this is a fresh install first
        let isFreshInstall = isFirstTimeInstall()
        let hasShownWizardBefore = UserDefaults.standard.bool(forKey: "KeyPath.HasShownWizard")

        AppLogger.shared.log(
            "🔍 [KanataManager] Fresh install: \(isFreshInstall), HasShownWizard: \(hasShownWizardBefore)")

        if isFreshInstall {
            // Fresh install - show wizard immediately without trying to start (unless quiet mode)
            AppLogger.shared.log("🆕 [KanataManager] Fresh install detected")
            await MainActor.run {
                currentState = .needsHelp
                errorReason = "Welcome! Let's set up KeyPath on your Mac."
                if presentWizardOnFailure {
                    showWizard = true
                    AppLogger.shared.log("🆕 [KanataManager] Showing wizard for fresh install")
                } else {
                    AppLogger.shared.log("🕊️ [KanataManager] Quiet mode: not presenting wizard on fresh install")
                }
            }
        } else if hasShownWizardBefore {
            AppLogger.shared.log(
                "ℹ️ [KanataManager] Returning user - attempting quiet start"
            )
            // Try to start silently without showing wizard
            await attemptQuietStart(presentWizardOnFailure: presentWizardOnFailure)
        } else {
            AppLogger.shared.log(
                "🆕 [KanataManager] First launch on existing system - proceeding with normal auto-launch")
            AppLogger.shared.log(
                "🆕 [KanataManager] This means wizard MAY auto-show if system needs help")
            currentState = .starting
            errorReason = nil
            showWizard = false
            autoStartAttempts = 0
            await attemptAutoStart(presentWizardOnFailure: presentWizardOnFailure)
        }

        AppLogger.shared.log("🚀 [KanataManager] ========== AUTO-LAUNCH COMPLETE ==========")
    }

    /// Attempt to start quietly without showing wizard (for subsequent app launches)
    private func attemptQuietStart(presentWizardOnFailure: Bool = true) async {
        AppLogger.shared.log("🤫 [KanataManager] ========== QUIET START ATTEMPT ==========")
        await MainActor.run {
            currentState = .starting
            errorReason = nil
            showWizard = false // Never show wizard on quiet starts
        }
        await MainActor.run {
            autoStartAttempts = 0
        }

        // Try to start, but if it fails, just show error state without wizard
        await attemptAutoStart(presentWizardOnFailure: presentWizardOnFailure)

        // If we ended up in needsHelp state, don't show wizard - just stay in error state
        if currentState == .needsHelp {
            AppLogger.shared.log(
                "🤫 [KanataManager] Quiet start failed - staying in error state without wizard")
            await MainActor.run {
                showWizard = false // Explicitly ensure wizard doesn't show
            }
        }

        AppLogger.shared.log("🤫 [KanataManager] ========== QUIET START COMPLETE ==========")
    }

    /// Show wizard specifically for input monitoring permissions
    func showWizardForInputMonitoring() async {
        AppLogger.shared.log("🧙‍♂️ [KanataManager] Showing wizard for input monitoring permissions")

        await MainActor.run {
            showWizard = true
            currentState = .needsHelp
            errorReason = "Input monitoring permission required"
            launchFailureStatus = .permissionDenied("Input monitoring permission required")
        }
    }

    /// Manual start triggered by user action
    func manualStart() async {
        AppLogger.shared.log("👆 [KanataManager] Manual start requested")
        await startKanata()
        await refreshStatus()
    }

    /// Manual stop triggered by user action
    func manualStop() async {
        AppLogger.shared.log("👆 [KanataManager] Manual stop requested")
        await stopKanata()
        await MainActor.run {
            currentState = .stopped
        }
    }

    /// Force refresh the current status
    func forceRefreshStatus() async {
        AppLogger.shared.log("🔄 [KanataManager] Force refresh status requested")
        await refreshStatus()
    }

    /// Refresh status and update UI state
    private func refreshStatus() async {
        await updateStatus()

        // Update currentState based on isRunning
        await MainActor.run {
            if isRunning {
                currentState = .running
                errorReason = nil
                launchFailureStatus = nil
            } else if !isRunning, currentState == .running {
                currentState = .stopped
            }
        }
    }

    /// Attempt auto-start with retry logic
    private func attemptAutoStart(presentWizardOnFailure: Bool = true) async {
        autoStartAttempts += 1
        AppLogger.shared.log(
            "🔄 [KanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) ==========")

        // Try to start Kanata
        await startKanata()
        await refreshStatus()

        // Check if start was successful
        if isRunning {
            AppLogger.shared.log("✅ [KanataManager] Auto-start successful!")
            await MainActor.run {
                currentState = .running
                errorReason = nil
                launchFailureStatus = nil
            }
        } else {
            AppLogger.shared.log("❌ [KanataManager] Auto-start failed")
            await handleAutoStartFailure(presentWizardOnFailure: presentWizardOnFailure)
        }

        AppLogger.shared.log(
            "🔄 [KanataManager] ========== AUTO-START ATTEMPT #\(autoStartAttempts) COMPLETE ==========")
    }

    /// Handle auto-start failure with retry logic
    private func handleAutoStartFailure(presentWizardOnFailure: Bool = true) async {
        // Check if we should retry
        if autoStartAttempts < maxAutoStartAttempts {
            AppLogger.shared.log("🔄 [KanataManager] Retrying auto-start...")
            try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds
            await attemptAutoStart(presentWizardOnFailure: presentWizardOnFailure)
            return
        }

        // Max attempts reached - show help
        await MainActor.run {
            currentState = .needsHelp
            errorReason = "Failed to start Kanata after \(maxAutoStartAttempts) attempts"
            if presentWizardOnFailure {
                showWizard = true
                AppLogger.shared.log("❌ [KanataManager] Max attempts reached - showing wizard")
            } else {
                AppLogger.shared.log("🕊️ [KanataManager] Quiet mode: not presenting wizard on max attempts failure")
            }
        }
    }

    /// Retry after manual fix (from SimpleKanataManager)
    func retryAfterFix(_ feedbackMessage: String) async {
        AppLogger.shared.log("🔄 [KanataManager] Retry after fix requested: \(feedbackMessage)")

        await MainActor.run {
            isRetryingAfterFix = true
            retryCount += 1
            currentState = .starting
            errorReason = nil
            showWizard = false
        }

        // Try to start Kanata
        await startKanata()
        await refreshStatus()

        await MainActor.run {
            isRetryingAfterFix = false
        }

        AppLogger.shared.log("🔄 [KanataManager] Retry after fix completed")
    }

    /// Request wizard presentation from any UI component
    @MainActor
    func requestWizardPresentation(initialPage _: WizardPage? = nil) {
        AppLogger.shared.log("🧭 [KanataManager] Wizard presentation requested")
        showWizard = true
        shouldShowWizard = true
    }

    /// Called when wizard is closed (from SimpleKanataManager)
    func onWizardClosed() async {
        AppLogger.shared.log("🧙‍♂️ [KanataManager] Wizard closed - attempting retry")

        await MainActor.run {
            showWizard = false
        }

        // Try to refresh status and start if needed
        await refreshStatus()

        // Notify any UI components (e.g., main page validator) that the wizard closed
        NotificationCenter.default.post(name: .wizardClosed, object: nil)

        // If Kanata is now running successfully, mark wizard as completed
        if isRunning {
            AppLogger.shared.log("✅ [KanataManager] Wizard completed successfully - Kanata is running")
            UserDefaults.standard.set(true, forKey: "KeyPath.HasShownWizard")
            UserDefaults.standard.synchronize()
            AppLogger.shared.log("✅ [KanataManager] Set KeyPath.HasShownWizard = true for future launches")
        } else {
            AppLogger.shared.log("⚠️ [KanataManager] Wizard closed but Kanata is not running - will retry setup on next launch")
        }

        if !isRunning {
            await startKanata()
            await refreshStatus()
        }

        AppLogger.shared.log("🧙‍♂️ [KanataManager] Wizard closed handling completed")
    }

    // MARK: - LaunchDaemon Service Management

    /// Start the Kanata LaunchDaemon service via privileged operations facade
    private func startLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🚀 [LaunchDaemon] Starting Kanata service via PrivilegedOperations...")
        return await PrivilegedOperationsProvider.shared.startKanataService()
    }

    /// Check the status of the LaunchDaemon service
    private func checkLaunchDaemonStatus() async -> (isRunning: Bool, pid: Int?) {
        await processManager.status()
    }

    /// Resolve any conflicting Kanata processes before starting
    private func resolveProcessConflicts() async {
        await processManager.resolveConflicts()
    }

    /// Verify no process conflicts exist after starting
    private func verifyNoProcessConflicts() async {
        await processManager.verifyNoConflicts()
    }

    /// Stop the Kanata LaunchDaemon service via privileged operations facade
    private func stopLaunchDaemonService() async -> Bool {
        AppLogger.shared.log("🛑 [LaunchDaemon] Stopping Kanata service via PrivilegedOperations...")
        let ok = await PrivilegedOperationsProvider.shared.stopKanataService()
        if ok {
            // Wait a moment for graceful shutdown
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return ok
    }

    /// Kill a specific process by PID
    private func killProcess(pid: Int) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["kill", "-TERM", String(pid)]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [Kill] Successfully killed process \(pid)")
            } else {
                AppLogger.shared.log("⚠️ [Kill] Failed to kill process \(pid) (may have already exited)")
            }
        } catch {
            AppLogger.shared.log("❌ [Kill] Exception killing process \(pid): \(error)")
        }
    }

    // Removed monitorKanataProcess() - no longer needed with LaunchDaemon service management

    func stopKanata() async {
        AppLogger.shared.log("🛑 [Stop] Stopping Kanata LaunchDaemon service...")

        // Stop the service via ProcessManager
        let success = await processManager.stopService()

        if success {
            AppLogger.shared.log("✅ [Stop] Successfully stopped Kanata LaunchDaemon service")

            // Stop log monitoring when Kanata stops
            diagnosticsManager.stopLogMonitoring()

            updateInternalState(
                isRunning: false,
                lastProcessExitCode: nil,
                lastError: nil
            )
        } else {
            AppLogger.shared.log("⚠️ [Stop] Failed to stop Kanata LaunchDaemon service")

            // Still update status to reflect current state
            await updateStatus()
        }
    }

    func restartKanata() async {
        AppLogger.shared.log("🔄 [Restart] Restarting Kanata...")
        let configPath = configurationManager.configPath
        let arguments = configurationManager.buildKanataArguments(checkOnly: false)
        let success = await processManager.restartService(configPath: configPath, arguments: arguments)
        
        if success {
            // Start log monitoring
            diagnosticsManager.startLogMonitoring()
            
            // Update state
            updateInternalState(
                isRunning: true,
                lastProcessExitCode: nil,
                lastError: nil,
                shouldClearDiagnostics: true
            )
        }
    }

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
            AppLogger.shared.log("🔍 [KanataManager] Validating generated config before save...")
            let validation = await configurationService.validateConfiguration(configContent)

            if !validation.isValid {
                AppLogger.shared.log("❌ [KanataManager] Generated config validation failed: \(validation.errors.joined(separator: ", "))")
                await MainActor.run {
                    saveStatus = .failed("Invalid config: \(validation.errors.first ?? "Unknown error")")
                }
                throw KeyPathError.configuration(.validationFailed(errors: validation.errors))
            }

            AppLogger.shared.log("✅ [KanataManager] Generated config validation passed")

            // Backup current config before making changes
            await backupCurrentConfig()

            // Ensure config directory exists
            let configDirectoryURL = URL(fileURLWithPath: configDirectory)
            try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

            // Write the configuration file
            let configURL = URL(fileURLWithPath: configPath)
            try configContent.write(to: configURL, atomically: true, encoding: .utf8)

            AppLogger.shared.log("✅ [KanataManager] Generated configuration saved to \(configPath)")

            // Update last config update timestamp
            lastConfigUpdate = Date()

            // Parse the saved config to update key mappings (for UI display)
            let parsedMappings = parseKanataConfig(configContent)
            await MainActor.run {
                keyMappings = parsedMappings
            }

            // Play tink sound asynchronously to avoid blocking save pipeline
            Task { @MainActor in SoundManager.shared.playTinkSound() }

            // Trigger hot reload via TCP
            let reloadResult = await triggerConfigReload()
            if reloadResult.isSuccess {
                AppLogger.shared.log("✅ [KanataManager] TCP reload successful, config is active")
                // Play glass sound asynchronously to avoid blocking completion
                Task { @MainActor in SoundManager.shared.playGlassSound() }
                await MainActor.run {
                    saveStatus = .success
                }
            } else {
                // TCP reload failed - this is a critical error for validation-on-demand
                let errorMessage = reloadResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.log("❌ [KanataManager] TCP reload FAILED: \(errorMessage)")
                AppLogger.shared.log("❌ [KanataManager] Restoring backup since config couldn't be verified")

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
                saveStatus = .failed("Failed to save generated configuration: \(error.localizedDescription)")
            }
            throw error
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
            // Parse existing mappings from config file
            await loadExistingMappings()

            // Create new mapping
            let newMapping = KeyMapping(input: input, output: output)

            // Remove any existing mapping with the same input
            keyMappings.removeAll { $0.input == input }

            // Add the new mapping
            keyMappings.append(newMapping)

            // Backup current config before making changes
            await backupCurrentConfig()

            // Delegate to ConfigurationService for saving
            try await configurationService.saveConfiguration(keyMappings: keyMappings)
            AppLogger.shared.log("💾 [Config] Config saved with \(keyMappings.count) mappings via ConfigurationService")

            // Play tink sound asynchronously to avoid blocking save pipeline
            Task { @MainActor in SoundManager.shared.playTinkSound() }

            // Attempt TCP reload to validate config
            AppLogger.shared.log("📡 [Config] Triggering TCP reload for validation")
            let tcpResult = await triggerTCPReload()

            if tcpResult.isSuccess {
                // Reload succeeded - config is valid
                AppLogger.shared.log("✅ [Config] Reload successful, config is valid")

                // Play glass sound asynchronously to avoid blocking completion
                Task { @MainActor in SoundManager.shared.playGlassSound() }

                await MainActor.run {
                    saveStatus = .success
                }
            } else {
                // TCP reload failed - this is a critical error for validation-on-demand
                let errorMessage = tcpResult.errorMessage ?? "TCP server unresponsive"
                AppLogger.shared.log("❌ [Config] TCP reload FAILED: \(errorMessage)")
                AppLogger.shared.log("❌ [Config] TCP server is required for validation-on-demand - restoring backup")

                // Play error sound asynchronously
                Task { @MainActor in SoundManager.shared.playErrorSound() }

                // Restore backup since we can't verify the config was applied
                try await restoreLastGoodConfig()

                // Set error status
                await MainActor.run {
                    saveStatus = .failed("TCP server reload failed: \(errorMessage)")
                }
                throw KeyPathError.configuration(.loadFailed(reason: "TCP server required for validation-on-demand failed: \(errorMessage)"))
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
        // Synchronize status updates to prevent concurrent access to internal state
        await KanataManager.startupActor.synchronize { [self] in
            await performUpdateStatus()
        }
    }

    /// Wait for the kanata service to be ready and fully started
    /// Returns true if service becomes ready within timeout, false otherwise
    func waitForServiceReady(timeout: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()

        AppLogger.shared.log("⏳ [KanataManager] Waiting for service to be ready (timeout: \(timeout)s)")

        // Fast path - already running
        await updateStatus()
        if await MainActor.run(body: { currentState == .running }) {
            AppLogger.shared.log("✅ [KanataManager] Service already ready")
            return true
        }

        // Poll until ready or timeout
        while Date().timeIntervalSince(startTime) < timeout {
            // Wait a bit before checking again
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await updateStatus()

            let state = await MainActor.run { currentState }

            if state == .running {
                let elapsed = Date().timeIntervalSince(startTime)
                AppLogger.shared.log("✅ [KanataManager] Service became ready after \(String(format: "%.1f", elapsed))s")
                return true
            }

            if state == .needsHelp || state == .stopped {
                AppLogger.shared.log("❌ [KanataManager] Service failed to start (state: \(state.rawValue))")
                return false
            }

            // Still starting, keep waiting
        }

        AppLogger.shared.log("⏱️ [KanataManager] Service ready timeout after \(timeout)s")
        return false
    }

    /// Main actor function to safely update internal state properties
    @MainActor
    private func updateInternalState(
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
        // Check LaunchDaemon service status instead of direct process
        let serviceStatus = await checkLaunchDaemonStatus()
        let serviceRunning = serviceStatus.isRunning

        if isRunning != serviceRunning {
            AppLogger.shared.log("⚠️ [Status] LaunchDaemon service state changed: \(serviceRunning)")

            if serviceRunning {
                // Service is running - clear any stale errors
                updateInternalState(
                    isRunning: serviceRunning,
                    lastProcessExitCode: nil,
                    lastError: nil,
                    shouldClearDiagnostics: true
                )
                AppLogger.shared.log("🔄 [Status] LaunchDaemon service running - cleared stale diagnostics")

                if let pid = serviceStatus.pid {
                    AppLogger.shared.log("✅ [Status] LaunchDaemon service PID: \(pid)")

                    // Update lifecycle manager with current service PID
                    let command = buildKanataArguments(configPath: configPath).joined(separator: " ")
                    await processLifecycleManager.registerStartedProcess(pid: Int32(pid), command: "launchd: \(command)")
                }
            } else {
                // Service is not running
                updateInternalState(
                    isRunning: serviceRunning,
                    lastProcessExitCode: lastProcessExitCode,
                    lastError: lastError
                )
                AppLogger.shared.log("⚠️ [Status] LaunchDaemon service is not running")

                // Clean up lifecycle manager
                await processLifecycleManager.unregisterProcess()
            }
        }

        // Check for any conflicting processes
        await verifyNoProcessConflicts()
    }

    /// Stop Kanata when the app is terminating (async version).
    func cleanup() async {
        await stopKanata()
    }

    /// Synchronous cleanup for app termination - blocks until process is killed
    func cleanupSync() {
        AppLogger.shared.log("🛝 [Cleanup] Performing synchronous cleanup...")

        // LaunchDaemon service management - synchronous cleanup not directly supported
        // The LaunchDaemon service will handle process lifecycle automatically
        AppLogger.shared.log("ℹ️ [Cleanup] LaunchDaemon service will handle process cleanup automatically")

        // Clean up PID file
        try? PIDFileManager.removePID()
        AppLogger.shared.log("✅ [Cleanup] Synchronous cleanup complete")
    }

    private func checkExternalKanataProcess() async -> Bool {
        // Delegate to ProcessLifecycleManager for conflict detection
        let conflicts = await processLifecycleManager.detectConflicts()
        return !conflicts.externalProcesses.isEmpty
    }

    // MARK: - Installation and Permissions

    func isInstalled() -> Bool {
        // Fast, non-blocking check for UI gating during startup.
        // Avoids kicking off binary signature detection on the main thread.
        FileManager.default.fileExists(atPath: WizardSystemPaths.kanataSystemInstallPath)
    }

    func isCompletelyInstalled() -> Bool {
        isInstalled()
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
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
                AppLogger.shared.log("❌ [Finder] AppleScript error revealing kanata: \(error)")
            } else {
                AppLogger.shared.log("✅ [Finder] Revealed kanata in Finder: \(kanataPath)")
                // Show guide bubble slightly below the icon (fallback if we cannot resolve exact AX position)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.showDragAndDropHelpBubble()
                }
            }
        } else {
            AppLogger.shared.log("❌ [Finder] Could not create AppleScript to reveal kanata.")
        }
    }

    /// Show floating help bubble near the Finder selection, with fallback positioning
    private func showDragAndDropHelpBubble() {
        // TODO: Post notification for UI layer to show help bubble
        // Core library cannot directly call UI components
        AppLogger.shared.log("ℹ️ [Bubble] Help bubble would be shown here (needs notification-based implementation)")
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

    func getKillKarabinerCommand() -> String {
        karabinerConflictService.getKillKarabinerCommand()
    }

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

        var lines: [String] = []
        if status.pids.count > 1 {
            lines.append("Reason: Multiple VirtualHID daemons detected (\(status.pids.count)).")
            lines.append("PIDs: \(status.pids.joined(separator: ", "))")
            if !status.owners.isEmpty { lines.append("Owners:\n\(status.owners.joined(separator: "\n"))") }
        } else if status.pids.isEmpty {
            lines.append("Reason: VirtualHID daemon not running.")
        } else {
            lines.append("Reason: Daemon unhealthy.")
            if !status.owners.isEmpty { lines.append("Owner:\n\(status.owners.joined(separator: "\n"))") }
        }
        lines.append("LaunchDaemon: \(status.serviceInstalled ? "installed" : "not installed")\(status.serviceInstalled ? ", \(status.serviceState)" : "")")
        lines.append("Driver extension: \(driverEnabled ? "enabled" : "disabled")")
        lines.append("Driver version: \(installedVersion)\(hasMismatch ? " (incompatible with current Kanata)" : "")")
        let summary = lines.joined(separator: "\n")
        AppLogger.shared.log("🔎 [VHID-DIAG] Diagnostic summary:\n\(summary)")
        AppLogger.shared.log("🔎 [RestartOutcome] \(status.pids.count == 1 ? "single-owner" : (status.pids.isEmpty ? "not-running" : "duplicate")) PIDs=\(status.pids.joined(separator: ", "))")
        return summary
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
        let detectionResult = detector.detectCurrentStatus()

        if detectionResult.status != .systemInstalled {
            AppLogger.shared.log(
                "⚠️ [Installation] Kanata binary needs installation - status: \(detectionResult.status)")

            // Install bundled kanata binary to system location
            AppLogger.shared.log("🔧 [Installation] Installing bundled Kanata binary to system location...")

            do {
                try await PrivilegedOperationsCoordinator.shared.installBundledKanata()
                AppLogger.shared.log("✅ [Installation] Successfully installed bundled Kanata binary")
                AppLogger.shared.log("✅ [Installation] Step 1 SUCCESS: Kanata binary installed and verified")
                stepsCompleted += 1
            } catch {
                AppLogger.shared.log("❌ [Installation] Step 1 FAILED: Failed to install bundled Kanata binary: \(error)")
                AppLogger.shared.log("💡 [Installation] Check system permissions and try running KeyPath with administrator privileges")
                stepsFailed += 1
            }
        } else {
            AppLogger.shared.log(
                "✅ [Installation] Step 1 SUCCESS: Kanata binary already exists at \(detectionResult.path ?? "unknown")")
            stepsCompleted += 1
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
        AppLogger.shared.log("✅ [Installation] Step 3 SUCCESS: Daemon directories prepared")
        stepsCompleted += 1

        // 4. Create initial config if needed
        AppLogger.shared.log("🔧 [Installation] Step 4/\(totalSteps): Creating user configuration...")
        await createInitialConfigIfNeeded()
        if FileManager.default.fileExists(atPath: configPath) {
            AppLogger.shared.log(
                "✅ [Installation] Step 4 SUCCESS: User config available at \(configPath)")
            stepsCompleted += 1
        } else {
            AppLogger.shared.log("❌ [Installation] Step 4 FAILED: User config missing at \(configPath)")
            stepsFailed += 1
        }

        // 5. No longer needed - LaunchDaemon reads user config directly
        AppLogger.shared.log(
            "🔧 [Installation] Step 5/\(totalSteps): System config step skipped - LaunchDaemon uses user config directly"
        )
        AppLogger.shared.log("✅ [Installation] Step 5 SUCCESS: Using ~/.config/keypath path directly")
        stepsCompleted += 1

        let success = stepsCompleted >= 4 // Require at least user config + binary + directories
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
        do shell script "mkdir -p '\(rootOnlyPath)' && chown -R \(NSUserName()) '\(tmpPath)' && chmod -R 755 '\(tmpPath)'" \
        with administrator privileges \
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

    /// Load and strictly validate existing configuration with fallback to default
    private func loadExistingMappings() async {
        AppLogger.shared.log("📂 [Validation] ========== STARTUP CONFIG VALIDATION BEGIN ==========")
        keyMappings.removeAll()

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
                keyMappings = config.keyMappings
                AppLogger.shared.log("✅ [Validation] Successfully loaded \(keyMappings.count) existing mappings")
            } else {
                AppLogger.shared.log("❌ [Validation] CLI validation FAILED with \(cli.errors.count) errors")
                await handleInvalidStartupConfig(configContent: configContent, errors: cli.errors)
            }
        } catch {
            AppLogger.shared.log("❌ [Validation] Failed to load existing config: \(error)")
            AppLogger.shared.log("❌ [Validation] Error type: \(type(of: error))")
            keyMappings = []
        }

        AppLogger.shared.log("📂 [Validation] ========== STARTUP CONFIG VALIDATION END ==========")
    }

    /// Handle invalid startup configuration with backup and fallback
    private func handleInvalidStartupConfig(configContent: String, errors: [String]) async {
        AppLogger.shared.log("🛡️ [Validation] Handling invalid startup configuration...")

        // Create backup of invalid config
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(configDirectory)/invalid-config-backup-\(timestamp).kbd"

        AppLogger.shared.log("💾 [Validation] Creating backup of invalid config...")
        do {
            try configContent.write(toFile: backupPath, atomically: true, encoding: .utf8)
            AppLogger.shared.log("💾 [Validation] Successfully backed up invalid config to: \(backupPath)")
            AppLogger.shared.log("💾 [Validation] Backup file size: \(configContent.count) characters")
        } catch {
            AppLogger.shared.log("❌ [Validation] Failed to backup invalid config: \(error)")
            AppLogger.shared.log("❌ [Validation] Backup path attempted: \(backupPath)")
        }

        // Generate default configuration
        AppLogger.shared.log("🔧 [Validation] Generating default fallback configuration...")
        let defaultMapping = KeyMapping(input: "caps", output: "esc")
        let defaultConfig = generateKanataConfigWithMappings([defaultMapping])
        AppLogger.shared.log("🔧 [Validation] Default config generated with mapping: caps → esc")

        do {
            AppLogger.shared.log("📝 [Validation] Writing default config to: \(configPath)")
            try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            keyMappings = [defaultMapping]
            AppLogger.shared.log("✅ [Validation] Successfully replaced invalid config with default")
            AppLogger.shared.log("✅ [Validation] New config has \(keyMappings.count) mapping(s)")

            // Schedule user notification about the fallback
            AppLogger.shared.log("📢 [Validation] Scheduling user notification about config fallback...")
            await scheduleConfigValidationNotification(originalErrors: errors, backupPath: backupPath)
        } catch {
            AppLogger.shared.log("❌ [Validation] Failed to write default config: \(error)")
            AppLogger.shared.log("❌ [Validation] Config path: \(configPath)")
            keyMappings = []
        }

        AppLogger.shared.log("🛡️ [Validation] Invalid startup config handling complete")
    }

    /// Schedule notification to inform user about config validation issues
    private func scheduleConfigValidationNotification(originalErrors: [String], backupPath: String) async {
        AppLogger.shared.log("📢 [Config] Showing validation error dialog to user")

        await MainActor.run {
            if TestEnvironment.isRunningTests {
                AppLogger.shared.log("🧪 [Config] Suppressing validation alert in test environment")
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
                        AppLogger.shared.log("🧪 [Config] Suppressing NSWorkspace file viewer in test environment")
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backupPath)])
                    }
                    self?.showingValidationAlert = false
                }
            ]

            showingValidationAlert = true
        }
    }

    /// Show validation error dialog with options to cancel or revert to default
    private func showValidationErrorDialog(title: String, errors: [String], config _: String? = nil) async {
        await MainActor.run {
            validationAlertTitle = title
            validationAlertMessage = """
            KeyPath found errors in the configuration:

            \(errors.joined(separator: "\n• "))

            What would you like to do?
            """

            var actions: [ValidationAlertAction] = []

            // Cancel option
            actions.append(ValidationAlertAction(title: "Cancel", style: .cancel) { [weak self] in
                self?.showingValidationAlert = false
            })

            // Revert to default option
            actions.append(ValidationAlertAction(title: "Use Default Config", style: .destructive) { [weak self] in
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
        AppLogger.shared.log("🔄 [Config] Reverting to default configuration")

        let defaultMapping = KeyMapping(input: "caps", output: "esc")
        let defaultConfig = generateKanataConfigWithMappings([defaultMapping])

        do {
            try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            await MainActor.run {
                keyMappings = [defaultMapping]
                lastConfigUpdate = Date()
            }
            AppLogger.shared.log("✅ [Config] Successfully reverted to default configuration")
        } catch {
            AppLogger.shared.log("❌ [Config] Failed to revert to default configuration: \(error)")
        }
    }

    private func parseKanataConfig(_ configContent: String) -> [KeyMapping] {
        // Delegate to ConfigurationService for parsing
        do {
            let config = try configurationService.parseConfigurationFromString(configContent)
            return config.keyMappings
        } catch {
            AppLogger.shared.log("⚠️ [Parse] Failed to parse config: \(error)")
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
        true // No service needed - kanata runs directly
    }

    func getInstallationStatus() -> String {
        let detection = KanataBinaryDetector.shared.detectCurrentStatus()
        let driverInstalled = isKarabinerDriverInstalled()

        switch detection.status {
        case .systemInstalled:
            return driverInstalled ? "✅ Fully installed" : "⚠️ Driver missing"
        case .bundledAvailable:
            return "⚠️ Bundled Kanata available (install to system required)"
        case .bundledUnsigned:
            return "⚠️ Bundled Kanata unsigned (needs Developer ID signature)"
        case .missing:
            return "❌ Kanata not found"
        }
    }

    // MARK: - Configuration Backup Management

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
        AppLogger.shared.log("🔄 [Reset] Forcing reset to default config (no validation - recovery mode)")

        let defaultMapping = KeyMapping(input: "caps", output: "escape")
        let defaultConfig = KanataConfiguration.generateFromMappings([defaultMapping])
        let configURL = URL(fileURLWithPath: configPath)

        // Ensure config directory exists
        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Write the default config (unconditionally)
        try defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)

        AppLogger.shared.log("💾 [Config] Reset to default configuration (caps → esc)")

        // Apply changes immediately via TCP reload if service is running
        if isRunning {
            AppLogger.shared.log("🔄 [Reset] Triggering immediate config reload via TCP...")
            let reloadResult = await triggerConfigReload()

            if reloadResult.isSuccess {
                let response = reloadResult.response ?? "Success"
                AppLogger.shared.log("✅ [Reset] Default config applied successfully via TCP: \(response)")
                // Play happy chime on successful reset
                await MainActor.run {
                    SoundManager.shared.playGlassSound()
                }
            } else {
                let error = reloadResult.errorMessage ?? "Unknown error"
                let response = reloadResult.response ?? "No response"
                AppLogger.shared.log("⚠️ [Reset] TCP reload failed (\(error)), fallback restart initiated")
                AppLogger.shared.log("📝 [Reset] TCP response: \(response)")
                // If TCP reload fails, fall back to service restart
                await restartKanata()
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
            // Small settle to ensure processes exit
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            AppLogger.shared.log("🛑 [Mappings] Paused by killing Kanata processes via helper")
            return true
        } catch {
            AppLogger.shared.log("⚠️ [Mappings] Helper killAllKanataProcesses failed: \(error)")
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
            AppLogger.shared.log("🚀 [Mappings] Resumed by restarting unhealthy services via helper")
            return true
        } catch {
            AppLogger.shared.log("⚠️ [Mappings] Helper restartUnhealthyServices failed: \(error)")
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

    // startLogMonitoring/stopLogMonitoring moved to KanataManager+Output.swift

    /// Analyze new log content for VirtualHID connection issues (delegates parsing to DiagnosticsService)
    func analyzeLogContent(_ content: String) async {
        let events = diagnosticsService.analyzeKanataLogChunk(content)
        for event in events {
            switch event {
            case .virtualHIDConnectionFailed:
                let shouldTriggerRecovery = await healthMonitor.recordConnectionFailure()
                if shouldTriggerRecovery {
                    AppLogger.shared.log("🚨 [LogMonitor] Maximum connection failures reached - triggering recovery")
                    await triggerVirtualHIDRecovery()
                }
            case .virtualHIDConnected:
                await healthMonitor.recordConnectionSuccess()
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
    private func validateGeneratedConfig(_ config: String) async -> (isValid: Bool, errors: [String]) {
        // Delegate to ConfigurationService for combined TCP+CLI validation
        await configurationService.validateConfiguration(config)
    }

    /// Uses Claude to repair a corrupted Kanata config
    private func repairConfigWithClaude(config: String, errors: [String], mappings: [KeyMapping])
        async throws -> String {
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
            AppLogger.shared.log("⚠️ [KanataManager] Claude API failed: \(error), falling back to rule-based repair")
            // For now, use rule-based repair as fallback
            return try await performRuleBasedRepair(config: config, errors: errors, mappings: mappings)
        }
    }

    /// Fallback rule-based repair when Claude is not available
    private func performRuleBasedRepair(config: String, errors: [String], mappings: [KeyMapping])
        async throws -> String {
        // Delegate to ConfigurationService for rule-based repair
        try await configurationService.repairConfiguration(config: config, errors: errors, mappings: mappings)
    }

    /// Saves a validated config to disk
    private func saveValidatedConfig(_ config: String) async throws {
        // DEBUG: Log detailed file save information
        AppLogger.shared.log("🔍 [DEBUG] saveValidatedConfig called")
        AppLogger.shared.log("🔍 [DEBUG] Target config path: \(configPath)")
        AppLogger.shared.log("🔍 [DEBUG] Config size: \(config.count) characters")

        // Config validation is performed by caller before reaching here
        AppLogger.shared.log("📡 [SaveConfig] Saving validated config (TCP-only mode)")

        let configDir = URL(fileURLWithPath: configDirectory)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        AppLogger.shared.log("🔍 [DEBUG] Config directory created/verified: \(configDirectory)")

        let configURL = URL(fileURLWithPath: configPath)

        // Check if file exists before writing
        let fileExists = FileManager.default.fileExists(atPath: configPath)
        AppLogger.shared.log("🔍 [DEBUG] Config file exists before write: \(fileExists)")

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
        AppLogger.shared.log("✅ [DEBUG] Config written to file successfully")

        // Note: File watcher delay removed - we use TCP reload commands instead of --watch

        // Get modification time after write
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: configPath)
        let afterModTime = afterAttributes[.modificationDate] as? Date
        let fileSize = afterAttributes[.size] as? Int ?? 0

        AppLogger.shared.log(
            "🔍 [DEBUG] Modification time after write: \(afterModTime?.description ?? "unknown")")
        AppLogger.shared.log("🔍 [DEBUG] File size after write: \(fileSize) bytes")

        // Calculate time difference if we have both times
        if let before = beforeModTime, let after = afterModTime {
            let timeDiff = after.timeIntervalSince(before)
            AppLogger.shared.log("🔍 [DEBUG] File modification time changed by: \(timeDiff) seconds")
        }

        // Post-save validation: verify the file was saved correctly
        await MainActor.run {
            saveStatus = .validating
        }

        AppLogger.shared.log("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION BEGIN ==========")
        AppLogger.shared.log("🔍 [Validation-PostSave] Validating saved config at: \(configPath)")
        do {
            let savedContent = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log("📖 [Validation-PostSave] Successfully read saved file (\(savedContent.count) characters)")

            let postSaveStart = Date()
            let postSaveValidation = await validateGeneratedConfig(savedContent)
            let postSaveDuration = Date().timeIntervalSince(postSaveStart)
            AppLogger.shared.log("⏱️ [Validation-PostSave] Validation completed in \(String(format: "%.3f", postSaveDuration)) seconds")

            if postSaveValidation.isValid {
                AppLogger.shared.log("✅ [Validation-PostSave] Post-save validation PASSED")
                AppLogger.shared.log("✅ [Validation-PostSave] Config saved and verified successfully")
            } else {
                AppLogger.shared.log("❌ [Validation-PostSave] Post-save validation FAILED")
                AppLogger.shared.log("❌ [Validation-PostSave] Found \(postSaveValidation.errors.count) errors:")
                for (index, error) in postSaveValidation.errors.enumerated() {
                    AppLogger.shared.log("   Error \(index + 1): \(error)")
                }
                AppLogger.shared.log("🎭 [Validation-PostSave] Showing error dialog to user...")
                await showValidationErrorDialog(title: "Save Verification Failed", errors: postSaveValidation.errors)
                AppLogger.shared.log("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
                throw KeyPathError.configuration(.validationFailed(errors: postSaveValidation.errors))
            }
        } catch {
            AppLogger.shared.log("❌ [Validation-PostSave] Failed to read saved config: \(error)")
            AppLogger.shared.log("❌ [Validation-PostSave] Error type: \(type(of: error))")
            AppLogger.shared.log("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")
            throw error
        }

        AppLogger.shared.log("🔍 [Validation-PostSave] ========== POST-SAVE VALIDATION END ==========")

        // Notify UI that config was updated
        lastConfigUpdate = Date()
        AppLogger.shared.log("🔍 [DEBUG] lastConfigUpdate timestamp set to: \(lastConfigUpdate)")
    }

    /// Synchronize config to system path for Kanata --watch compatibility
    // synchronizeConfigToSystemPath removed - no longer needed since LaunchDaemon reads user config directly

    /// Backs up a failed config and applies safe default, returning backup path
    func backupFailedConfigAndApplySafe(failedConfig: String, mappings: [KeyMapping]) async throws
        -> String {
        // Delegate to ConfigurationService for backup and safe config application
        let backupPath = try await configurationService.backupFailedConfigAndApplySafe(
            failedConfig: failedConfig,
            mappings: mappings
        )

        // Update in-memory mappings to reflect the safe state
        keyMappings = [KeyMapping(input: "caps", output: "escape")]

        return backupPath
    }

    /// Opens a file in Zed editor with fallback options
    func openFileInZed(_ filePath: String) {
        configurationManager.openInEditor(filePath)
    }

    // MARK: - Kanata Arguments Builder

    /// Builds Kanata command line arguments including TCP port when enabled
    func buildKanataArguments(configPath: String, checkOnly: Bool = false) -> [String] {
        // Delegate to ConfigurationManager
        return configurationManager.buildKanataArguments(checkOnly: checkOnly)
    }

    // MARK: - Claude API Integration

    /// Call Claude API to repair configuration
    private func callClaudeAPI(prompt: String) async throws -> String {
        // Check for API key in environment or keychain
        guard let apiKey = getClaudeAPIKey() else {
            throw NSError(domain: "ClaudeAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Claude API key not found. Set ANTHROPIC_API_KEY environment variable or store in Keychain."])
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw NSError(domain: "ClaudeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Claude API URL"])
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
                    "content": prompt
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ClaudeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ClaudeAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API request failed (\(httpResponse.statusCode)): \(errorMessage)"])
        }

        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = jsonResponse["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String
        else {
            throw NSError(domain: "ClaudeAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Claude API response"])
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
            kSecMatchLimit as String: kSecMatchLimitOne
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
