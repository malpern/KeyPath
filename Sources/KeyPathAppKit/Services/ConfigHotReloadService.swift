import Foundation
import KeyPathCore

/// Coordinates configuration hot-reload when external file changes are detected.
///
/// This service handles:
/// - Validating externally-modified config files
/// - Triggering hot reload via TCP to running Kanata
/// - Providing callbacks for UI feedback (sounds, status updates)
/// - Parsing updated config for in-memory state sync
///
/// Works in conjunction with `ConfigFileWatcher` which monitors the filesystem.
@MainActor
final class ConfigHotReloadService {
    // MARK: - Types

    /// Result of an external config change handling
    struct ReloadResult: Sendable {
        let success: Bool
        let message: String
        let newContent: String?

        static func success(content: String) -> ReloadResult {
            ReloadResult(success: true, message: "Configuration reloaded", newContent: content)
        }

        static func failure(_ message: String) -> ReloadResult {
            ReloadResult(success: false, message: message, newContent: nil)
        }
    }

    /// Callbacks for UI feedback during reload
    struct Callbacks {
        var onDetected: (() -> Void)?
        var onValidating: (() -> Void)?
        var onSuccess: ((String) -> Void)?
        var onFailure: ((String) -> Void)?
        var onReset: (() -> Void)?
    }

    // MARK: - Properties

    private var configurationService: ConfigurationService?
    private var reloadHandler: (() async -> Bool)?
    private var configParser: ((String) throws -> [KeyMapping])?

    /// UI feedback callbacks
    var callbacks = Callbacks()

    /// Delay before auto-resetting status
    var statusResetDelay: TimeInterval = 2.0

    // MARK: - Singleton

    static let shared = ConfigHotReloadService()

    private init() {}

    // MARK: - Configuration

    /// Configure the service with required dependencies
    ///
    /// - Parameters:
    ///   - configurationService: Service for validating config content
    ///   - reloadHandler: Async handler to trigger TCP reload (returns success)
    ///   - configParser: Parser to extract key mappings from config content
    func configure(
        configurationService: ConfigurationService,
        reloadHandler: @escaping () async -> Bool,
        configParser: @escaping (String) throws -> [KeyMapping]
    ) {
        self.configurationService = configurationService
        self.reloadHandler = reloadHandler
        self.configParser = configParser
    }

    // MARK: - External Change Handling

    /// Handle an external configuration file change
    ///
    /// This method:
    /// 1. Reads the updated file
    /// 2. Validates the configuration
    /// 3. Triggers hot reload via TCP
    /// 4. Parses and returns new key mappings
    ///
    /// - Parameter configPath: Path to the config file that changed
    /// - Returns: Result with success status and optional new content/mappings
    func handleExternalChange(configPath: String) async -> ReloadResult {
        AppLogger.shared.log("📝 [ConfigHotReload] External config file change detected")

        // Notify detection
        callbacks.onDetected?()
        callbacks.onValidating?()

        // Check file exists
        guard FileManager.default.fileExists(atPath: configPath) else {
            AppLogger.shared.error("❌ [ConfigHotReload] Config file no longer exists: \(configPath)")
            let result = ReloadResult.failure("Config file was deleted")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }

        // Read file content
        let configContent: String
        do {
            configContent = try String(contentsOfFile: configPath, encoding: .utf8)
            AppLogger.shared.log(
                "📁 [ConfigHotReload] Read \(configContent.count) characters from external file")
        } catch {
            AppLogger.shared.error("❌ [ConfigHotReload] Failed to read external config: \(error)")
            let result = ReloadResult.failure("Failed to read config: \(error.localizedDescription)")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }

        // Validate configuration
        guard let configService = configurationService else {
            AppLogger.shared.error("❌ [ConfigHotReload] ConfigurationService not configured")
            let result = ReloadResult.failure("Service not configured")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }

        let validationResult = await configService.validateConfiguration(configContent)
        if !validationResult.isValid {
            let errorMsg = validationResult.errors.first ?? "Unknown validation error"
            AppLogger.shared.error(
                "❌ [ConfigHotReload] Validation failed: \(validationResult.errors.joined(separator: ", "))"
            )
            let result = ReloadResult.failure("Invalid config: \(errorMsg)")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }

        // Trigger hot reload via TCP
        guard let handler = reloadHandler else {
            AppLogger.shared.error("❌ [ConfigHotReload] Reload handler not configured")
            let result = ReloadResult.failure("Reload handler not configured")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }

        let reloadSuccess = await handler()

        if reloadSuccess {
            AppLogger.shared.info("✅ [ConfigHotReload] External config successfully reloaded")
            callbacks.onSuccess?(configContent)
            scheduleStatusReset()
            return .success(content: configContent)
        } else {
            // Check if service is simply unavailable (SMAppService pending, service not running, or process not started)
            // In this case, don't show error to user - config is valid, just can't reload yet
            let smState = await KanataDaemonManager.shared.refreshManagementState()

            // Also check if Kanata process is actually running - if service is "active" but
            // process isn't running yet, we shouldn't show an error.
            // IMPORTANT: Run this off MainActor to avoid blocking UI - InstallerEngine spawns subprocesses.
            let isProcessRunning = await Task.detached {
                await InstallerEngine().checkKanataServiceHealth().isRunning
            }.value

            if smState == .smappservicePending || smState.needsInstallation || !isProcessRunning {
                let reason = !isProcessRunning ? "process not running" :
                    (smState == .smappservicePending ? "pending approval" : "needs installation")
                AppLogger.shared.info("ℹ️ [ConfigHotReload] Reload skipped - service not available (\(reason)), config is valid")
                // Don't call onFailure - this isn't a real error, just service unavailability
                // Reset status after a brief delay so UI doesn't show stale "validating" state
                callbacks.onReset?()
                return ReloadResult(success: true, message: "Config valid (service starting)", newContent: configContent)
            }

            AppLogger.shared.error("❌ [ConfigHotReload] Hot reload failed")
            let result = ReloadResult.failure("Hot reload failed")
            callbacks.onFailure?(result.message)
            scheduleStatusReset()
            return result
        }
    }

    /// Parse config content to extract key mappings
    ///
    /// - Parameter configContent: Raw config file content
    /// - Returns: Parsed key mappings, or nil if parsing fails
    func parseKeyMappings(from configContent: String) -> [KeyMapping]? {
        guard let parser = configParser else {
            AppLogger.shared.warn("⚠️ [ConfigHotReload] Config parser not configured")
            return nil
        }

        do {
            return try parser(configContent)
        } catch {
            AppLogger.shared.warn("⚠️ [ConfigHotReload] Failed to parse config: \(error)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func scheduleStatusReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + statusResetDelay) { [weak self] in
            self?.callbacks.onReset?()
        }
    }
}
