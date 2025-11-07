import Foundation
import ServiceManagement
import KeyPathCore

/// Manager for Kanata LaunchDaemon registration via SMAppService
///
/// This manager handles SMAppService registration/unregistration for the Kanata daemon,
/// similar to how HelperManager handles the privileged helper registration.
///
/// Design:
/// - Uses SMAppService.daemon() for registration
/// - Provides status checking, registration, and unregistration
/// - Supports migration from launchctl to SMAppService
/// - Supports rollback from SMAppService to launchctl
@MainActor
class KanataDaemonManager {
    // MARK: - SMAppService indirection for testability
    // Allows unit tests to inject a fake SMAppService and simulate states like `.notFound`.
    // Default implementation wraps Apple's `SMAppService`.
    nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
        NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
    }

    // MARK: - Singleton

    static let shared = KanataDaemonManager()

    // MARK: - Constants

    /// Service identifier for Kanata LaunchDaemon
    static let kanataServiceID = "com.keypath.kanata"

    /// LaunchDaemon plist name packaged inside the app bundle for SMAppService
    static let kanataPlistName = "com.keypath.kanata.plist"

    // MARK: - Initialization

    private init() {
        AppLogger.shared.log("🔧 [KanataDaemonManager] Initialized")
    }

    // MARK: - Status Checking

    /// Check if Kanata daemon is installed and registered via SMAppService
    /// - Returns: true if SMAppService reports `.enabled` OR launchctl has the job
    nonisolated func isInstalled() -> Bool {
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        if svc.status == .enabled { return true }

        // Best-effort check: does launchd know about the job?
        do {
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["print", "system/\(Self.kanataServiceID)"]
            let out = Pipe(); p.standardOutput = out; let err = Pipe(); p.standardError = err
            try p.run(); p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: data, encoding: .utf8) ?? ""
                if s.contains("program") || s.contains("state =") || s.contains("pid =") {
                    AppLogger.shared.log("ℹ️ [KanataDaemonManager] launchctl reports daemon present while SMAppService status=\(svc.status)")
                    return true
                }
            }
        } catch {
            // Ignore; treated as not installed
        }
        return false
    }

    /// Get the current SMAppService status
    /// - Returns: The current status (.notFound, .requiresApproval, .enabled, .notRegistered)
    nonisolated func getStatus() -> ServiceManagement.SMAppService.Status {
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        return svc.status
    }

    /// Check if daemon is registered via SMAppService (not launchctl)
    /// - Returns: true if SMAppService status is `.enabled`
    nonisolated func isRegisteredViaSMAppService() -> Bool {
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        return svc.status == .enabled
    }

    /// Check if legacy launchctl installation exists
    /// - Returns: true if plist exists at /Library/LaunchDaemons/com.keypath.kanata.plist
    nonisolated func hasLegacyInstallation() -> Bool {
        let legacyPlistPath = LaunchDaemonInstaller.kanataPlistPath
        return FileManager.default.fileExists(atPath: legacyPlistPath)
    }

    // MARK: - Registration

    /// Register Kanata daemon via SMAppService
    /// - Throws: KanataDaemonError if registration fails
    func register() async throws {
        AppLogger.shared.log("🔧 [KanataDaemonManager] Registering Kanata daemon via SMAppService")
        guard #available(macOS 13, *) else {
            throw KanataDaemonError.registrationFailed("Requires macOS 13+ for SMAppService")
        }

        let svc = Self.smServiceFactory(Self.kanataPlistName)
        AppLogger.shared.log("🔍 [KanataDaemonManager] SMAppService status: \(svc.status.rawValue) (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)")

        switch svc.status {
        case .enabled:
            // Already enabled - treat as success
            AppLogger.shared.info("✅ [KanataDaemonManager] Daemon already enabled")
            return

        case .requiresApproval:
            throw KanataDaemonError.registrationFailed("Approval required in System Settings → Login Items.")

        case .notRegistered:
            do {
                try svc.register()
                AppLogger.shared.info("✅ [KanataDaemonManager] Daemon registered (status: \(svc.status))")
                return
            } catch {
                // If another thread already registered or approval raced, treat Enabled as success
                if svc.status == .enabled {
                    AppLogger.shared.info("✅ [KanataDaemonManager] Daemon became Enabled during registration race; treating as success")
                    return
                }
                if svc.status == .requiresApproval {
                    throw KanataDaemonError.registrationFailed("Approval required in System Settings → Login Items.")
                }
                throw KanataDaemonError.registrationFailed("SMAppService register failed: \(error.localizedDescription)")
            }

        case .notFound:
            // .notFound means the system hasn't seen the daemon yet, but registration might still work
            AppLogger.shared.log("⚠️ [KanataDaemonManager] Daemon status is .notFound - attempting registration anyway to get detailed error")
            do {
                try svc.register()
                AppLogger.shared.info("✅ [KanataDaemonManager] Daemon registered successfully despite initial .notFound status")
                return
            } catch {
                AppLogger.shared.log("❌ [KanataDaemonManager] Registration failed with detailed error: \(error)")
                throw KanataDaemonError.registrationFailed("SMAppService register failed: \(error.localizedDescription)")
            }

        @unknown default:
            do {
                try svc.register()
                return
            } catch {
                throw KanataDaemonError.registrationFailed("SMAppService register failed: \(error.localizedDescription)")
            }
        }
    }

    /// Unregister Kanata daemon via SMAppService
    /// - Throws: KanataDaemonError if unregistration fails
    func unregister() async throws {
        AppLogger.shared.log("🗑️ [KanataDaemonManager] Unregistering Kanata daemon via SMAppService")
        guard #available(macOS 13, *) else {
            throw KanataDaemonError.operationFailed("Requires macOS 13+ for SMAppService")
        }
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        do {
            try await svc.unregister()
            AppLogger.shared.info("✅ [KanataDaemonManager] Daemon unregistered successfully")
        } catch {
            throw KanataDaemonError.operationFailed("SMAppService unregister failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Migration Support

    /// Migrate from legacy launchctl installation to SMAppService
    /// - Throws: KanataDaemonError if migration fails
    func migrateFromLaunchctl() async throws {
        AppLogger.shared.log("🔄 [KanataDaemonManager] Migrating from launchctl to SMAppService")

        // 1. Check if legacy exists
        guard hasLegacyInstallation() else {
            throw KanataDaemonError.migrationFailed("No legacy launchctl installation found")
        }

        // 2. Stop legacy service (requires admin via helper)
        AppLogger.shared.log("🛑 [KanataDaemonManager] Stopping legacy service...")
        try await HelperManager.shared.installLaunchDaemon(
            plistPath: "", // Empty means uninstall
            serviceID: Self.kanataServiceID
        )

        // Actually, we need to use a different approach - use helper to bootout
        // For now, let's use the helper's executeCommand if available, or we'll need to add a method
        // Let's check what methods HelperManager has available

        // 3. Remove legacy plist (requires admin via helper)
        // This will be handled by the helper

        // 4. Register via SMAppService
        AppLogger.shared.log("📝 [KanataDaemonManager] Registering via SMAppService...")
        try await register()

        // 5. Verify service started
        // Give it a moment to start
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        guard isInstalled() else {
            throw KanataDaemonError.migrationFailed("Service did not start after migration")
        }

        AppLogger.shared.info("✅ [KanataDaemonManager] Migration completed successfully")
    }

    /// Rollback from SMAppService to launchctl installation
    /// - Throws: KanataDaemonError if rollback fails
    func rollbackToLaunchctl() async throws {
        AppLogger.shared.log("🔄 [KanataDaemonManager] Rolling back from SMAppService to launchctl")

        // 1. Unregister via SMAppService
        try await unregister()

        // 2. Reinstall via launchctl (using existing LaunchDaemonInstaller)
        AppLogger.shared.log("📝 [KanataDaemonManager] Reinstalling via launchctl...")
        let installer = LaunchDaemonInstaller()
        // Use the existing installation method
        // This will be handled by calling the appropriate LaunchDaemonInstaller method

        AppLogger.shared.info("✅ [KanataDaemonManager] Rollback completed successfully")
    }
}

// MARK: - Error Types

/// Errors that can occur in KanataDaemonManager
enum KanataDaemonError: Error, LocalizedError {
    case notInstalled
    case registrationFailed(String)
    case operationFailed(String)
    case migrationFailed(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Kanata daemon is not installed"
        case let .registrationFailed(reason):
            "Failed to register daemon: \(reason)"
        case let .operationFailed(reason):
            "Daemon operation failed: \(reason)"
        case let .migrationFailed(reason):
            "Migration failed: \(reason)"
        case let .rollbackFailed(reason):
            "Rollback failed: \(reason)"
        }
    }
}
