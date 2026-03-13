import Darwin
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
import ServiceManagement

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
public class KanataDaemonManager {
    // MARK: - SMAppService indirection for testability

    // Allows unit tests to inject a fake SMAppService and simulate states like `.notFound`.
    // Default implementation wraps Apple's `SMAppService`.
    #if DEBUG
        nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
        }

        nonisolated(unsafe) static var registeredButNotLoadedOverride: (() async -> Bool)?
    #else
        nonisolated(unsafe) static let smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
            NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
        }
    #endif

    // MARK: - Singleton

    static let shared = KanataDaemonManager()

    // MARK: - Dependencies

    private let subprocessRunner: SubprocessRunner

    // MARK: - Constants

    /// Service identifier for Kanata LaunchDaemon
    nonisolated static let kanataServiceID = "com.keypath.kanata"

    /// LaunchDaemon plist name packaged inside the app bundle for SMAppService
    nonisolated static let kanataPlistName = "com.keypath.kanata.plist"

    /// Path to legacy LaunchDaemon plist
    nonisolated static var legacyPlistPath: String {
        WizardSystemPaths.remapSystemPath("/Library/LaunchDaemons/\(kanataServiceID).plist")
    }

    // MARK: - Initialization

    init(subprocessRunner: SubprocessRunner = .shared) {
        self.subprocessRunner = subprocessRunner
        AppLogger.shared.log("🔧 [KanataDaemonManager] Initialized")
        Task { await refreshManagementStateInternal() }
    }

    // MARK: - Service Management State (Single Source of Truth)

    /// Represents the current state of service management for Kanata daemon
    /// This is the single source of truth for determining which management method is active
    enum ServiceManagementState: Equatable {
        case legacyActive // Legacy plist exists, launchctl managing
        case smappserviceActive // No legacy plist, SMAppService .enabled
        case smappservicePending // No legacy plist, SMAppService .requiresApproval
        case uninstalled // No legacy plist, SMAppService .notFound, process not running
        case conflicted // Both legacy plist AND SMAppService active (error state)
        case unknown // Ambiguous state requiring investigation

        var description: String {
            switch self {
            case .legacyActive: "Legacy launchctl"
            case .smappserviceActive: "SMAppService (active)"
            case .smappservicePending: "SMAppService (pending approval)"
            case .uninstalled: "Uninstalled"
            case .conflicted: "Conflicted (both methods active)"
            case .unknown: "Unknown"
            }
        }

        /// Returns true if SMAppService is the active management method
        var isSMAppServiceManaged: Bool {
            self == .smappserviceActive || self == .smappservicePending
        }

        /// Returns true if legacy launchctl is the active management method
        var isLegacyManaged: Bool {
            self == .legacyActive
        }

        /// Returns true if installation is needed
        var needsInstallation: Bool {
            self == .uninstalled
        }

        /// Returns true if migration is needed (legacy exists - we always use SMAppService now)
        func needsMigration() -> Bool {
            self == .legacyActive || self == .conflicted
        }
    }

    @MainActor private var cachedManagementState: ServiceManagementState = .unknown

    /// Synchronous access to cached state for UI usage
    @MainActor var currentManagementState: ServiceManagementState {
        cachedManagementState
    }

    /// Determines the current service management state (Async, updates cache)
    /// This is the SINGLE SOURCE OF TRUTH for determining which management method is active
    /// Priority order (most reliable first):
    /// 1. Legacy plist existence (most reliable indicator)
    /// 2. SMAppService status
    /// 3. Process running state (for ambiguous cases - only checked when needed)
    ///
    /// - Returns: The current ServiceManagementState
    @discardableResult
    nonisolated func refreshManagementStateInternal() async -> ServiceManagementState {
        let hasLegacy = Foundation.FileManager().fileExists(atPath: Self.legacyPlistPath)
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        let smStatus = svc.status

        AppLogger.shared.log("🔍 [KanataDaemonManager] State determination:")
        AppLogger.shared.log("  - Legacy plist exists: \(hasLegacy)")
        AppLogger.shared.log(
            "  - SMAppService status: \(smStatus.rawValue) (\(String(describing: smStatus)))"
        )

        let newState: ServiceManagementState = await {
            // Check for conflicts first (both methods active - error state)
            if hasLegacy, smStatus == .enabled {
                AppLogger.shared.log(
                    "⚠️ [KanataDaemonManager] CONFLICTED STATE: Both legacy plist and SMAppService active"
                )
                return .conflicted
            }

            // Priority 1: Legacy plist existence (most reliable check)
            if hasLegacy {
                AppLogger.shared.log("✅ [KanataDaemonManager] State: LEGACY_ACTIVE (plist exists)")
                return .legacyActive
            }

            // Priority 2: SMAppService status
            switch smStatus {
            case .enabled:
                AppLogger.shared.log("✅ [KanataDaemonManager] State: SMAPPSERVICE_ACTIVE")
                return .smappserviceActive
            case .requiresApproval:
                AppLogger.shared.log("⏳ [KanataDaemonManager] State: SMAPPSERVICE_PENDING (approval needed)")
                return .smappservicePending
            case .notFound, .notRegistered:
                if TestEnvironment.isTestMode {
                    AppLogger.shared.log(
                        "🧪 [KanataDaemonManager] Test mode - treating missing plist as uninstalled"
                    )
                    return .uninstalled
                }
                // No legacy plist and SMAppService not registered
                // Only check process when state is ambiguous (lazy evaluation for performance)
                let isProcessRunning = await pgrepKanataProcessAsync()
                AppLogger.shared.log("  - Process running: \(isProcessRunning)")
                if isProcessRunning {
                    // Process running but unclear management - investigate
                    AppLogger.shared.log(
                        "❓ [KanataDaemonManager] State: UNKNOWN (process running but no clear management)"
                    )
                    return .unknown
                }
                AppLogger.shared.log("❌ [KanataDaemonManager] State: UNINSTALLED")
                return .uninstalled
            @unknown default:
                AppLogger.shared.log(
                    "❓ [KanataDaemonManager] State: UNKNOWN (unexpected SMAppService status)"
                )
                return .unknown
            }
        }()

        await MainActor.run {
            self.cachedManagementState = newState
        }
        return newState
    }

    /// Legacy static method alias for compatibility (deprecated)
    @available(*, unavailable, message: "Use shared.refreshManagementStateInternal()")
    nonisolated static func determineServiceManagementState() async -> ServiceManagementState {
        await shared.refreshManagementStateInternal()
    }

    /// Helper function to check if Kanata process is running
    /// This is used as a fallback when state is ambiguous
    private nonisolated func pgrepKanataProcessAsync() async -> Bool {
        let pids = await subprocessRunner.pgrep("kanata.*--cfg")
        return !pids.isEmpty
    }

    /// Legacy synchronous helper (deprecated)
    @available(*, unavailable, message: "Use async version")
    private nonisolated static func pgrepKanataProcess() -> Bool {
        false
    }

    // MARK: - Status Checking (Legacy - kept for compatibility)

    /// Check if Kanata daemon is installed and registered via SMAppService
    /// - Returns: true if SMAppService reports `.enabled` OR launchctl has the job
    nonisolated func isInstalled() async -> Bool {
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        if svc.status == .enabled { return true }

        // Best-effort check: does launchd know about the job?
        do {
            let result = try await subprocessRunner.launchctl("print", ["system/\(Self.kanataServiceID)"])
            if result.exitCode == 0 {
                let s = result.stdout
                if s.contains("program") || s.contains("state =") || s.contains("pid =") {
                    AppLogger.shared.log(
                        "ℹ️ [KanataDaemonManager] launchctl reports daemon present while SMAppService status=\(svc.status)"
                    )
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
    nonisolated static func isRegisteredViaSMAppService() -> Bool {
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        return svc.status == .enabled
    }

    /// Check if legacy launchctl installation exists
    /// - Returns: true if plist exists at /Library/LaunchDaemons/com.keypath.kanata.plist
    nonisolated func hasLegacyInstallation() -> Bool {
        Foundation.FileManager().fileExists(atPath: Self.legacyPlistPath)
    }

    /// Check if SMAppService is currently being used for Kanata daemon management
    /// - Returns: true if SMAppService is registered
    nonisolated static var isUsingSMAppService: Bool {
        isRegisteredViaSMAppService()
    }

    /// Get the active plist path for Kanata service
    /// - Returns: SMAppService plist path (always uses SMAppService now)
    nonisolated static func getActivePlistPath() -> String {
        // Always use SMAppService path
        let bundlePath = Bundle.main.bundlePath
        return "\(bundlePath)/Contents/Library/LaunchDaemons/\(kanataServiceID).plist"
    }

    /// Detect if service is in a broken state requiring re-registration
    /// This can happen after clean uninstall when SMAppService/launchd caching causes issues
    ///
    /// Detects two failure modes:
    /// 1. Registered but not loaded - launchd can't find the service
    /// 2. Spawn failed state - launchd finds service but it crashes immediately (exit code 78)
    ///
    /// - Returns: true if service needs unregister/re-register cycle to fix
    public nonisolated func isRegisteredButNotLoaded() async -> Bool {
        #if DEBUG
            if let override = Self.registeredButNotLoadedOverride {
                return await override()
            }
        #endif

        let svc = Self.smServiceFactory(Self.kanataPlistName)

        // 1. Check if SMAppService thinks it's registered
        guard svc.status == .enabled else {
            return false
        }

        // Run expensive checks async
        return await Task.detached { [self] in
            let launchctlOutputs = await readLaunchctlOutputs(for: .smappserviceActive)

            // 3. Check if process is running
            let processIsRunning = await pgrepKanataProcessAsync()

            // 4. Analyze the state
            let launchctlCanFindService = launchctlOutputs.contains { !$0.output.isEmpty }
            let isSpawnFailed = launchctlOutputs.contains { entry in
                entry.output.contains("spawn failed") || entry.output.contains("last exit code = 78")
            }

            // Issue detected if:
            // - Service registered but launchd can't find it, OR
            // - Service in spawn failed state with exit code 78
            // AND process is not actually running
            let hasIssue = (!launchctlCanFindService || isSpawnFailed) && !processIsRunning

            if hasIssue {
                AppLogger.shared.log(
                    "⚠️ [KanataDaemonManager] Detected SMAppService broken state requiring re-registration:"
                )
                AppLogger.shared.log("  - SMAppService status: .enabled")
                AppLogger.shared.log("  - launchctl can find service: \(launchctlCanFindService)")
                AppLogger.shared.log("  - Spawn failed state: \(isSpawnFailed)")
                AppLogger.shared.log("  - Process running: \(processIsRunning)")
                AppLogger.shared.log(
                    "💡 [KanataDaemonManager] This is a known macOS bug after clean uninstall"
                )
                AppLogger.shared.log(
                    "💡 [KanataDaemonManager] BundleProgram path caching issue - will fix via unregister/re-register"
                )
            }

            return hasIssue
        }.value
    }

    nonisolated static func preferredLaunchctlTargets(
        for managementState: ServiceManagementState,
        userID: uid_t = getuid()
    ) -> [String] {
        let guiTarget = "gui/\(userID)/\(kanataServiceID)"
        let systemTarget = "system/\(kanataServiceID)"

        switch managementState {
        case .legacyActive:
            return [systemTarget]
        case .smappserviceActive, .smappservicePending, .conflicted, .unknown, .uninstalled:
            return [guiTarget, systemTarget]
        }
    }

    nonisolated private func readLaunchctlOutputs(for managementState: ServiceManagementState)
        async -> [(target: String, output: String, exitCode: Int32?)]
    {
        var outputs: [(target: String, output: String, exitCode: Int32?)] = []
        for target in Self.preferredLaunchctlTargets(for: managementState) {
            do {
                let result = try await subprocessRunner.launchctl("print", [target])
                outputs.append((
                    target: target,
                    output: result.exitCode == 0 ? result.stdout : "",
                    exitCode: result.exitCode
                ))
            } catch {
                outputs.append((target: target, output: "", exitCode: nil))
            }
        }
        return outputs
    }

    // MARK: - Registration

    /// Register Kanata daemon via SMAppService
    /// - Throws: KanataDaemonError if registration fails
    public func register() async throws {
        AppLogger.shared.log(
            "🔐 [SMAPPSERVICE-TRIGGER] *** ENTRY POINT *** Registering Kanata daemon via SMAppService"
        )
        AppLogger.shared.log("🔐 [SMAPPSERVICE-TRIGGER] Caller stack unavailable in this build")
        AppLogger.shared.log(
            "🔍 [KanataDaemonManager] macOS version check: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
        guard #available(macOS 13, *) else {
            AppLogger.shared.log("❌ [KanataDaemonManager] macOS version too old for SMAppService")
            throw KanataDaemonError.registrationFailed("Requires macOS 13+ for SMAppService")
        }
        AppLogger.shared.log("✅ [KanataDaemonManager] macOS version OK for SMAppService")

        let svc = Self.smServiceFactory(Self.kanataPlistName)
        if TestEnvironment.isTestMode {
            AppLogger.shared.log(
                "🧪 [KanataDaemonManager] Test mode detected – skipping bundle validation checks"
            )
        } else {
            // Validate plist exists in app bundle
            // Check both the expected location (for build scripts) and bundle resources (for SPM builds)
            let bundlePath = Bundle.main.bundlePath
            let expectedPlistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/\(Self.kanataPlistName)"
            AppLogger.shared.log("🔍 [KanataDaemonManager] Bundle path: \(bundlePath)")
            AppLogger.shared.log("🔍 [KanataDaemonManager] Checking for plist at: \(expectedPlistPath)")

            // First check the expected location (build scripts place it here)
            if Foundation.FileManager().fileExists(atPath: expectedPlistPath) {
                AppLogger.shared.log(
                    "✅ [KanataDaemonManager] Found plist at expected location: \(expectedPlistPath)"
                )
                if let plist = NSDictionary(contentsOfFile: expectedPlistPath) as? [String: Any],
                   let args = plist["ProgramArguments"] as? [String],
                   let first = args.first,
                   !first.contains("kanata-launcher")
                {
                    AppLogger.shared.log(
                        "❌ [KanataDaemonManager] Plist ProgramArguments missing kanata-launcher wrapper (found: \(first))"
                    )
                    throw KanataDaemonError.registrationFailed(
                        "Bundled Kanata plist not updated to use kanata-launcher. Rebuild KeyPath before registering."
                    )
                }
            } else if let resourcePath = Bundle.main.path(
                forResource: "com.keypath.kanata", ofType: "plist"
            ) {
                // Found in bundle resources (SPM build) - this is acceptable
                AppLogger.shared.log(
                    "ℹ️ [KanataDaemonManager] Found plist in bundle resources: \(resourcePath)"
                )
                if let plist = NSDictionary(contentsOfFile: resourcePath) as? [String: Any],
                   let args = plist["ProgramArguments"] as? [String],
                   let first = args.first,
                   !first.contains("kanata-launcher")
                {
                    AppLogger.shared.log(
                        "❌ [KanataDaemonManager] Resource plist missing kanata-launcher wrapper (found: \(first))"
                    )
                    throw KanataDaemonError.registrationFailed(
                        "Bundled Kanata plist not updated to use kanata-launcher. Rebuild KeyPath before registering."
                    )
                }
            } else {
                AppLogger.shared.log(
                    "❌ [KanataDaemonManager] Plist not found in app bundle (checked: \(expectedPlistPath) and bundle resources)"
                )
                throw KanataDaemonError.registrationFailed(
                    "Plist not found in app bundle (checked: \(expectedPlistPath) and bundle resources)"
                )
            }

            // Validate runtime host exists in app bundle
            let launcherPath = WizardSystemPaths.bundledKanataLauncherPath
            AppLogger.shared.log("🔍 [KanataDaemonManager] Checking for Kanata launcher at: \(launcherPath)")
            guard Foundation.FileManager().fileExists(atPath: launcherPath) else {
                AppLogger.shared.log("❌ [KanataDaemonManager] Kanata launcher not found at: \(launcherPath)")
                throw KanataDaemonError.registrationFailed(
                    "Kanata launcher not found in app bundle: \(launcherPath)"
                )
            }
            AppLogger.shared.log("✅ [KanataDaemonManager] Kanata launcher found")

            // Validate kanata core binary exists in app bundle
            let kanataPath = WizardSystemPaths.bundledKanataPath
            AppLogger.shared.log("🔍 [KanataDaemonManager] Checking for Kanata binary at: \(kanataPath)")
            guard Foundation.FileManager().fileExists(atPath: kanataPath) else {
                AppLogger.shared.log("❌ [KanataDaemonManager] Kanata binary not found at: \(kanataPath)")
                throw KanataDaemonError.registrationFailed(
                    "Kanata binary not found in app bundle: \(kanataPath)"
                )
            }
            AppLogger.shared.log("✅ [KanataDaemonManager] Kanata binary found")
        }

        let initialStatus = svc.status
        AppLogger.shared.log(
            "🔍 [KanataDaemonManager] SMAppService created with plist name: \(Self.kanataPlistName)"
        )
        AppLogger.shared.log(
            "🔍 [KanataDaemonManager] Initial SMAppService status: \(initialStatus.rawValue) (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)"
        )
        AppLogger.shared.log(
            "🔍 [KanataDaemonManager] Initial SMAppService status description: \(String(describing: initialStatus))"
        )

        switch initialStatus {
        case .enabled:
            if await isRegisteredButNotLoaded() {
                AppLogger.shared.log(
                    "⚠️ [KanataDaemonManager] Status is .enabled but service is not loaded/running. Attempting unregister/re-register recovery."
                )
                try await recoverEnabledServiceRegistration(using: svc)
                AppLogger.shared.info(
                    "✅ [KanataDaemonManager] Recovered stale .enabled registration via re-registration"
                )
            } else {
                AppLogger.shared.info(
                    "✅ [KanataDaemonManager] Daemon already enabled via SMAppService - keeping existing registration"
                )
            }
            return

        case .requiresApproval:
            AppLogger.shared.log(
                "⚠️ [KanataDaemonManager] Status is .requiresApproval - user needs to approve in System Settings"
            )
            notifyBackgroundApprovalRequired()
            throw KanataDaemonError.registrationFailed(
                "Approval required in System Settings → Login Items."
            )

        case .notRegistered:
            AppLogger.shared.log(
                "📝 [KanataDaemonManager] Status is .notRegistered - attempting registration..."
            )
            do {
                AppLogger.shared.log("🔧 [KanataDaemonManager] Calling svc.register()...")
                try svc.register()
                let newStatus = svc.status
                AppLogger.shared.log(
                    "🔍 [KanataDaemonManager] After register(), status changed to: \(newStatus.rawValue) (\(String(describing: newStatus)))"
                )
                try await recoverIfStaleAfterRegistration(using: svc, context: "Registration")
                AppLogger.shared.info("✅ [KanataDaemonManager] Daemon registered successfully")
                return
            } catch {
                let errorStatus = svc.status
                AppLogger.shared.log("❌ [KanataDaemonManager] Registration failed with error: \(error)")
                AppLogger.shared.log(
                    "🔍 [KanataDaemonManager] Status after error: \(errorStatus.rawValue) (\(String(describing: errorStatus)))"
                )

                // If another thread already registered or approval raced, treat Enabled as success
                if errorStatus == .enabled {
                    AppLogger.shared.info(
                        "✅ [KanataDaemonManager] Daemon became Enabled during registration race; treating as success"
                    )
                    return
                }
                if errorStatus == .requiresApproval {
                    AppLogger.shared.log(
                        "⚠️ [KanataDaemonManager] Status changed to .requiresApproval after error"
                    )
                    notifyBackgroundApprovalRequired()
                    throw KanataDaemonError.registrationFailed(
                        "Approval required in System Settings → Login Items."
                    )
                }
                AppLogger.shared.log(
                    "❌ [KanataDaemonManager] Registration failed with final status: \(errorStatus)"
                )
                throw KanataDaemonError.registrationFailed(
                    "SMAppService register failed: \(error.localizedDescription)"
                )
            }

        case .notFound:
            // .notFound means the system hasn't seen the daemon yet, but registration might still work
            AppLogger.shared.log(
                "⚠️ [KanataDaemonManager] Status is .notFound - attempting registration anyway to get detailed error"
            )
            do {
                AppLogger.shared.log(
                    "🔧 [KanataDaemonManager] Calling svc.register() despite .notFound status..."
                )
                try svc.register()
                let newStatus = svc.status
                AppLogger.shared.log(
                    "🔍 [KanataDaemonManager] After register(), status changed to: \(newStatus.rawValue) (\(String(describing: newStatus)))"
                )
                try await recoverIfStaleAfterRegistration(using: svc, context: "Registration from .notFound")
                AppLogger.shared.info(
                    "✅ [KanataDaemonManager] Daemon registered successfully despite initial .notFound status"
                )
                return
            } catch {
                let errorStatus = svc.status
                AppLogger.shared.log(
                    "❌ [KanataDaemonManager] Registration failed with detailed error: \(error)"
                )
                AppLogger.shared.log(
                    "🔍 [KanataDaemonManager] Status after error: \(errorStatus.rawValue) (\(String(describing: errorStatus)))"
                )
                if errorStatus == .requiresApproval {
                    notifyBackgroundApprovalRequired()
                }
                throw KanataDaemonError.registrationFailed(
                    "SMAppService register failed: \(error.localizedDescription)"
                )
            }

        @unknown default:
            AppLogger.shared.log(
                "⚠️ [KanataDaemonManager] Unknown status case: \(initialStatus.rawValue) - attempting registration anyway"
            )
            do {
                try svc.register()
                AppLogger.shared.info(
                    "✅ [KanataDaemonManager] Registration succeeded for unknown status case"
                )
                return
            } catch {
                AppLogger.shared.log(
                    "❌ [KanataDaemonManager] Registration failed for unknown status case: \(error)"
                )
                throw KanataDaemonError.registrationFailed(
                    "SMAppService register failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Check for stale registration after a successful `svc.register()` and recover if needed.
    private func recoverIfStaleAfterRegistration(using svc: SMAppServiceProtocol, context: String) async throws {
        if await isRegisteredButNotLoaded() {
            AppLogger.shared.log(
                "⚠️ [KanataDaemonManager] \(context) reached .enabled but launchd still cannot load service. Attempting recovery."
            )
            try await recoverEnabledServiceRegistration(using: svc)
        }
    }

    private func recoverEnabledServiceRegistration(using svc: SMAppServiceProtocol) async throws {
        do {
            try await svc.unregister()
        } catch {
            throw KanataDaemonError.registrationFailed(
                "Failed to unregister stale SMAppService registration: \(error.localizedDescription)"
            )
        }

        do {
            try svc.register()
        } catch {
            throw KanataDaemonError.registrationFailed(
                "Failed to re-register daemon after stale SMAppService state: \(error.localizedDescription)"
            )
        }

        if await isRegisteredButNotLoaded() {
            throw KanataDaemonError.registrationFailed(
                "SMAppService remained enabled but not loaded after unregister/re-register recovery."
            )
        }
    }

    /// Unregister Kanata daemon via SMAppService
    /// - Throws: KanataDaemonError if unregistration fails
    public func unregister() async throws {
        AppLogger.shared.log("🗑️ [KanataDaemonManager] Unregistering Kanata daemon via SMAppService")
        guard #available(macOS 13, *) else {
            throw KanataDaemonError.operationFailed("Requires macOS 13+ for SMAppService")
        }
        let svc = Self.smServiceFactory(Self.kanataPlistName)
        do {
            try await svc.unregister()
            AppLogger.shared.info("✅ [KanataDaemonManager] Daemon unregistered successfully")
        } catch {
            throw KanataDaemonError.operationFailed(
                "SMAppService unregister failed: \(error.localizedDescription)"
            )
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

        // 2. Stop legacy service and remove plist (requires admin)
        AppLogger.shared.log("🛑 [KanataDaemonManager] Stopping legacy service and removing plist...")
        let legacyPlistPath = Self.legacyPlistPath

        // Routing via InstallerEngine per AGENTS.md
        let command = """
        /bin/launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true && \
        /bin/rm -f '\(legacyPlistPath)' || true
        """

        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        try await engine.sudoExecuteCommand(
            command,
            description: "Stop legacy service and remove plist",
            using: broker
        )

        // 3. Register via SMAppService
        AppLogger.shared.log("📝 [KanataDaemonManager] Registering via SMAppService...")
        do {
            try await register()
            AppLogger.shared.log("✅ [KanataDaemonManager] SMAppService registration call succeeded")
        } catch {
            // Check if error is just "requires approval" - this is OK, user can approve later
            if let kanataError = error as? KanataDaemonError,
               case let .registrationFailed(reason) = kanataError,
               reason.contains("Approval required")
            {
                AppLogger.shared.log(
                    "⚠️ [KanataDaemonManager] Registration requires user approval - this is OK"
                )
                AppLogger.shared.log(
                    "💡 [KanataDaemonManager] User needs to approve in System Settings → Login Items"
                )
                AppLogger.shared.log(
                    "💡 [KanataDaemonManager] Legacy plist removed - migration will complete once approved"
                )
                // Don't throw - migration is successful, just needs approval
            } else {
                // Other errors - rethrow
                AppLogger.shared.log("❌ [KanataDaemonManager] Registration failed with error: \(error)")
                throw error
            }
        }

        // 4. Verify service started OR is pending approval
        // Give it a moment to start or transition to requiresApproval
        try await Task.sleep(for: .seconds(2)) // 2 seconds

        let finalStatus = getStatus()
        let isRegistered = Self.isRegisteredViaSMAppService()
        let hasLegacyAfterMigration = hasLegacyInstallation()

        AppLogger.shared.log("🔍 [KanataDaemonManager] Post-migration verification:")
        AppLogger.shared.log(
            "  - SMAppService status: \(finalStatus.rawValue) (\(String(describing: finalStatus)))"
        )
        AppLogger.shared.log("  - isRegisteredViaSMAppService(): \(isRegistered)")
        AppLogger.shared.log("  - Legacy plist still exists: \(hasLegacyAfterMigration)")

        // Success criteria:
        // 1. Legacy plist is gone (migration cleanup succeeded)
        // 2. SMAppService status is .enabled OR .requiresApproval (registration succeeded or pending)
        // 3. Process is running OR will start after approval
        if hasLegacyAfterMigration {
            AppLogger.shared.log(
                "❌ [KanataDaemonManager] Legacy plist still exists after migration - migration may have failed"
            )
            throw KanataDaemonError.migrationFailed("Legacy plist still exists after migration")
        }

        if finalStatus == .enabled || finalStatus == .requiresApproval {
            AppLogger.shared.info("✅ [KanataDaemonManager] Migration completed successfully")
            AppLogger.shared.log(
                "💡 [KanataDaemonManager] SMAppService status: \(finalStatus == .enabled ? "Enabled" : "Requires Approval")"
            )
            if finalStatus == .requiresApproval {
                AppLogger.shared.log(
                    "💡 [KanataDaemonManager] User needs to approve in System Settings → Login Items → Background Items"
                )
            }
            return
        }

        // If status is .notFound or .notRegistered, check if process is running anyway
        if await isInstalled() {
            AppLogger.shared.log(
                "⚠️ [KanataDaemonManager] SMAppService status is \(finalStatus) but service is running"
            )
            AppLogger.shared.log(
                "💡 [KanataDaemonManager] This might be a timing issue - migration may still succeed"
            )
            AppLogger.shared.info(
                "✅ [KanataDaemonManager] Migration completed (service running despite status)"
            )
            return
        }

        AppLogger.shared.log("❌ [KanataDaemonManager] Service did not start after migration")
        throw KanataDaemonError.migrationFailed(
            "Service did not start after migration (status: \(finalStatus))"
        )
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

private extension KanataDaemonManager {
    func notifyBackgroundApprovalRequired() {
        NotificationCenter.default.post(name: .smAppServiceApprovalRequired, object: nil)
    }
}
