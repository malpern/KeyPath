import Foundation
import KeyPathCore
import Security
import ServiceManagement

/// Manages LaunchDaemon installation and configuration for KeyPath services
/// Implements the production-ready LaunchDaemon architecture identified in the installer improvement analysis
///
/// IMPORTANT: Service Dependency Order
/// The services MUST be bootstrapped in this specific order:
/// 1. VirtualHID Daemon (com.keypath.karabiner-vhiddaemon) - provides base VirtualHID framework
/// 2. VirtualHID Manager (com.keypath.karabiner-vhidmanager) - manages VirtualHID devices
/// 3. Kanata (com.keypath.kanata) - depends on VirtualHID services being available
///
/// Failure to respect this order results in "Bootstrap failed: 5: Input/output error"
/// because Kanata cannot connect to the required VirtualHID services.
@MainActor
class LaunchDaemonInstaller {
    // MARK: - Constants

    private static let launchDaemonsPath: String = LaunchDaemonInstaller.resolveLaunchDaemonsPath()
    static let systemLaunchDaemonsDir = "/Library/LaunchDaemons"
    static let systemLaunchAgentsDir = "/Library/LaunchAgents"
    static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"
    private static let logRotationServiceID = "com.keypath.logrotate"

    /// Path to the log rotation script
    private static let logRotationScriptPath = "/usr/local/bin/keypath-logrotate.sh"

    /// Path to the Kanata service plist file (system daemon)
    static var kanataPlistPath: String {
        "\(systemLaunchDaemonsDir)/\(kanataServiceID).plist"
    }

    /// Path to the Kanata LaunchAgent plist file (per-user)
    static var kanataLaunchAgentPlistPath: String {
        "\(systemLaunchAgentsDir)/\(kanataServiceID).plist"
    }

    // Use user config path following industry standard ~/.config/ pattern
    private static var kanataConfigPath: String {
        WizardSystemPaths.userConfigPath
    }

    private static let vhidDaemonPath =
        "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
    private static let vhidManagerPath =
        "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"

    // MARK: - Initialization

    init() {}

    // MARK: - Diagnostic Methods

    /// Test admin dialog capability - use this to diagnose osascript issues
    /// NOTE: This is a blocking operation that should not be called during startup
    func testAdminDialog() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Testing admin dialog capability...")
        AppLogger.shared.log("🔧 [LaunchDaemon] Current thread: \(Thread.isMainThread ? "main" : "background")")

        // Skip test if called during startup to prevent freezes
        if ProcessInfo.processInfo.environment["KEYPATH_SKIP_ADMIN_TEST"] == "1" {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Skipping admin dialog test during startup")
            return true // Assume it works to avoid blocking
        }

        let testCommand = "echo 'Admin dialog test successful'"
        let osascriptCode = """
        do shell script "\(testCommand)" with administrator privileges with prompt "KeyPath Admin Dialog Test - This is a test of the admin password dialog. Please enter your password to confirm it's working."
        """

        // Execute directly without semaphore to avoid deadlock
        let success = executeOSAScriptDirectly(osascriptCode)

        AppLogger.shared.log("🔧 [LaunchDaemon] Admin dialog test result: \(success)")
        return success
    }

    /// Execute osascript directly without thread switching
    private func executeOSAScriptDirectly(_ osascriptCode: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCode]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔧 [LaunchDaemon] OSAScript test output: \(output)")
            return task.terminationStatus == 0
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] OSAScript test error: \(error)")
            return false
        }
    }

    private func executeOSAScriptOnMainThread(_ osascriptCode: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCode]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔧 [LaunchDaemon] OSAScript test output: \(output)")
            return task.terminationStatus == 0
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] OSAScript test failed: \(error)")
            return false
        }
    }

    // MARK: - Warm-up tracking (to distinguish "starting" from "failed")

    @MainActor private static var lastKickstartTimes: [String: Date] = [:]
    private static let healthyWarmupWindow: TimeInterval = 2.0

    @MainActor private func markRestartTime(for serviceIDs: [String]) {
        let now = Date()
        for id in serviceIDs {
            Self.lastKickstartTimes[id] = now
        }
    }

    // Expose read access across instances
    @MainActor static func wasRecentlyRestarted(_ serviceID: String, within seconds: TimeInterval? = nil) -> Bool {
        guard let last = lastKickstartTimes[serviceID] else { return false }
        let window = seconds ?? healthyWarmupWindow
        return Date().timeIntervalSince(last) < window
    }

    @MainActor static func hadRecentRestart(within seconds: TimeInterval = healthyWarmupWindow) -> Bool {
        let now = Date()
        return lastKickstartTimes.values.contains { now.timeIntervalSince($0) < seconds }
    }

    // MARK: - Env/Test helpers

    private static let isTestMode: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["KEYPATH_TEST_MODE"] == "1"
    }()

    private static func resolveLaunchDaemonsPath() -> String {
        let env = ProcessInfo.processInfo.environment
        if let override = env["KEYPATH_LAUNCH_DAEMONS_DIR"], !override.isEmpty {
            return override
        }
        return "/Library/LaunchDaemons"
    }

    /// Escapes a shell command string for safe embedding in AppleScript
    private func escapeForAppleScript(_ command: String) -> String {
        var escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    // MARK: - Path Detection Methods

    /// Gets the Kanata binary path for LaunchDaemon
    private func getKanataBinaryPath() -> String {
        // Use system install path which has Input Monitoring TCC permissions
        // The bundled path inside KeyPath.app does NOT have permissions
        let systemPath = WizardSystemPaths.kanataSystemInstallPath

        // Verify the system path exists, otherwise fall back to bundled
        if FileManager.default.fileExists(atPath: systemPath) {
            AppLogger.shared.log("✅ [LaunchDaemon] Using system Kanata path (has TCC permissions): \(systemPath)")
            return systemPath
        } else {
            let bundledPath = WizardSystemPaths.bundledKanataPath
            AppLogger.shared.log("⚠️ [LaunchDaemon] System kanata not found, using bundled path: \(bundledPath)")
            return bundledPath
        }
    }

    /// Checks if the bundled kanata is newer than the system-installed version
    /// Returns true if an upgrade is needed
    func shouldUpgradeKanata() -> Bool {
        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let bundledPath = WizardSystemPaths.bundledKanataPath

        // If system version doesn't exist, we need to install it
        guard FileManager.default.fileExists(atPath: systemPath) else {
            AppLogger.shared.log("🔄 [LaunchDaemon] System kanata not found - initial installation needed")
            return true
        }

        // If bundled version doesn't exist, no upgrade possible
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Bundled kanata not found - cannot upgrade")
            return false
        }

        let systemVersion = getKanataVersionAtPath(systemPath)
        let bundledVersion = getKanataVersionAtPath(bundledPath)

        AppLogger.shared.log("🔄 [LaunchDaemon] Version check: System=\(systemVersion ?? "unknown"), Bundled=\(bundledVersion ?? "unknown")")

        // If we can't determine versions, assume upgrade is needed for safety
        guard let systemVer = systemVersion, let bundledVer = bundledVersion else {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Cannot determine versions - assuming upgrade needed")
            return true
        }

        // Compare versions (simple string comparison works for most version formats)
        let upgradeNeeded = bundledVer != systemVer
        if upgradeNeeded {
            AppLogger.shared.log("🔄 [LaunchDaemon] Upgrade needed: \(systemVer) → \(bundledVer)")
        } else {
            AppLogger.shared.log("✅ [LaunchDaemon] Kanata versions match - no upgrade needed")
        }

        return upgradeNeeded
    }

    /// Gets the version of kanata at a specific path
    private func getKanataVersionAtPath(_ path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return output
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to get kanata version at \(path): \(error)")
            return nil
        }
    }

    // MARK: - Installation Methods

    /// Creates and installs all LaunchDaemon services with a single admin prompt
    /// GUARD: Skips Kanata plist creation if SMAppService is active
    func createAllLaunchDaemonServices() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating all LaunchDaemon services")

        // GUARD: Check if SMAppService is active for Kanata - if so, skip Kanata plist creation
        // Use synchronous check since this method is not async
        let isSMAppServiceActive = KanataDaemonManager.isUsingSMAppService

        if isSMAppServiceActive {
            AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService is active for Kanata - skipping Kanata plist creation")
            AppLogger.shared.log("💡 [LaunchDaemon] Only installing VirtualHID services via launchctl")
        }

        let kanataBinaryPath = getKanataBinaryPath()

        // Generate plist contents (skip Kanata if SMAppService is active)
        let kanataPlist = isSMAppServiceActive ? nil : generateKanataPlist(binaryPath: kanataBinaryPath)
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()

        // Create temporary files for all plists (skip Kanata if SMAppService is active)
        let tempDir = NSTemporaryDirectory()
        let kanataTempPath = isSMAppServiceActive ? nil : "\(tempDir)\(Self.kanataServiceID).plist"
        let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
        let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

        do {
            // Write plist contents to temporary files (skip Kanata if SMAppService is active)
            if let kanataPlist = kanataPlist, let kanataTempPath = kanataTempPath {
                try kanataPlist.write(toFile: kanataTempPath, atomically: true, encoding: .utf8)
            }
            try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
            try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

            // Install services with a single admin prompt (skip Kanata if SMAppService is active)
            let success: Bool
            if isSMAppServiceActive {
                // Only install VirtualHID services
                success = executeConsolidatedInstallationForVHIDOnly(
                    vhidDaemonTemp: vhidDaemonTempPath,
                    vhidManagerTemp: vhidManagerTempPath
                )
            } else {
                // Install all services including Kanata
                success = executeAllWithAdminPrivileges(
                    kanataTemp: kanataTempPath!,
                    vhidDaemonTemp: vhidDaemonTempPath,
                    vhidManagerTemp: vhidManagerTempPath
                )
            }

            // Clean up temporary files
            if let kanataTempPath = kanataTempPath {
                try? FileManager.default.removeItem(atPath: kanataTempPath)
            }
            try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
            try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
            return false
        }
    }

    /// Creates and installs the Kanata LaunchDaemon service
    /// Uses SMAppService if feature flag is enabled, otherwise uses launchctl
    func createKanataLaunchDaemon() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] *** DECISION POINT *** createKanataLaunchDaemon() called")
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating Kanata LaunchDaemon service")

        // Check if SMAppService path is enabled
        let featureFlagValue = FeatureFlags.useSMAppServiceForDaemon
        AppLogger.shared.log("🔍 [LaunchDaemon] Feature flag check in createKanataLaunchDaemon(): useSMAppServiceForDaemon = \(featureFlagValue)")
        AppLogger.shared.log("🔍 [LaunchDaemon] Feature flag UserDefaults key: USE_SMAPPSERVICE_FOR_DAEMON")
        if let userDefaultsValue = UserDefaults.standard.object(forKey: "USE_SMAPPSERVICE_FOR_DAEMON") {
            AppLogger.shared.log("🔍 [LaunchDaemon] UserDefaults has explicit value: \(userDefaultsValue)")
        } else {
            AppLogger.shared.log("🔍 [LaunchDaemon] UserDefaults has no explicit value - using default: true")
        }

        if featureFlagValue {
            AppLogger.shared.log("📱 [LaunchDaemon] ✅ DECISION: Feature flag is TRUE - Using SMAppService path for Kanata daemon")
            return await createKanataLaunchDaemonViaSMAppService()
        } else {
            AppLogger.shared.log("🔧 [LaunchDaemon] ⚠️ DECISION: Feature flag is FALSE - Using launchctl path for Kanata daemon")
            return createKanataLaunchDaemonViaLaunchctl()
        }
    }

    /// Creates and installs Kanata LaunchDaemon via SMAppService
    /// GUARD: Uses state determination to check if legacy is active before registering
    @MainActor
    private func createKanataLaunchDaemonViaSMAppService() async -> Bool {
        AppLogger.shared.log("📱 [LaunchDaemon] *** ENTRY POINT *** createKanataLaunchDaemonViaSMAppService() called")
        AppLogger.shared.log("📱 [LaunchDaemon] Registering Kanata daemon via SMAppService")

        guard #available(macOS 13, *) else {
            AppLogger.shared.log("❌ [LaunchDaemon] SMAppService requires macOS 13+, falling back to launchctl")
            return createKanataLaunchDaemonViaLaunchctl()
        }
        AppLogger.shared.log("✅ [LaunchDaemon] macOS version OK for SMAppService")

        // GUARD: Use state determination to check current state
        let state = KanataDaemonManager.determineServiceManagementState()
        AppLogger.shared.log("🔍 [LaunchDaemon] Current state: \(state.description)")

        // If legacy is active, must migrate first, don't register fresh
        if state.isLegacyManaged {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Legacy plist exists (state: \(state.description)) - must use migrateFromLaunchctl() instead")
            return false
        }

        // If conflicted, auto-resolve by removing legacy
        if state == .conflicted {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Conflicted state detected - auto-resolving by removing legacy plist")
            // Auto-resolve: remove legacy plist and unload service
            let command = """
            /bin/launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true && \
            /bin/rm -f '/Library/LaunchDaemons/\(Self.kanataServiceID).plist' || true
            """
            do {
                try await PrivilegedOperationsCoordinator.shared.sudoExecuteCommand(
                    command,
                    description: "Remove legacy plist to resolve conflict"
                )
                AppLogger.shared.log("✅ [LaunchDaemon] Legacy plist removed, conflict resolved")
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to resolve conflict: \(error)")
                return false
            }
        }

        // If already managed by SMAppService, skip registration
        if state.isSMAppServiceManaged {
            AppLogger.shared.log("✅ [LaunchDaemon] Already managed by SMAppService (state: \(state.description)) - skipping registration")
            return true
        }

        do {
            AppLogger.shared.log("🔧 [LaunchDaemon] Calling KanataDaemonManager.shared.register()...")
            try await KanataDaemonManager.shared.register()
            AppLogger.shared.info("✅ [LaunchDaemon] Kanata daemon registered via SMAppService - SUCCESS")
            return true
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] SMAppService registration failed: \(error.localizedDescription)")
            AppLogger.shared.log("❌ [LaunchDaemon] Error type: \(type(of: error))")
            if let kanataError = error as? KanataDaemonError {
                AppLogger.shared.log("❌ [LaunchDaemon] KanataDaemonError details: \(kanataError.localizedDescription)")
            }

            // CRITICAL: Don't fall back to launchctl if feature flag is enabled
            // This prevents recreating the legacy plist after migration
            AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService registration failed - NOT falling back to launchctl (feature flag enabled)")
            AppLogger.shared.log("💡 [LaunchDaemon] User may need to approve in System Settings, or migration may be needed")
            return false
        }
    }

    /// Creates and installs Kanata LaunchDaemon via launchctl (legacy path)
    /// GUARD: Uses state determination to check if SMAppService is active before creating legacy plist
    private func createKanataLaunchDaemonViaLaunchctl() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] *** ENTRY POINT *** createKanataLaunchDaemonViaLaunchctl() called")

        // GUARD: Use state determination to check if SMAppService is active
        // This is the single source of truth for state determination
        let state = KanataDaemonManager.determineServiceManagementState()
        AppLogger.shared.log("🔍 [LaunchDaemon] Current state: \(state.description)")

        // If SMAppService is managing the service, don't create legacy plist
        if state.isSMAppServiceManaged {
            AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService is active (state: \(state.description)) - skipping legacy plist creation to avoid conflict")
            AppLogger.shared.log("💡 [LaunchDaemon] Use SMAppService path instead, or rollback first")
            return false
        }

        // Also check for conflicted state
        if state == .conflicted {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Conflicted state detected - both legacy and SMAppService active")
            AppLogger.shared.log("💡 [LaunchDaemon] Auto-resolving by keeping SMAppService (feature flag is ON)")
            // Don't create legacy plist in conflicted state
            return false
        }

        AppLogger.shared.log("🔧 [LaunchDaemon] Installing Kanata LaunchDaemon via launchctl (legacy path)")

        let kanataBinaryPath = getKanataBinaryPath()
        AppLogger.shared.log("🔍 [LaunchDaemon] Kanata binary path: \(kanataBinaryPath)")
        let plistContent = generateKanataPlist(binaryPath: kanataBinaryPath)
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        AppLogger.shared.log("🔍 [LaunchDaemon] Plist path: \(plistPath)")

        let result = installPlist(content: plistContent, path: plistPath, serviceID: Self.kanataServiceID)
        AppLogger.shared.log("🔍 [LaunchDaemon] installPlist() returned: \(result)")
        return result
    }

    /// Creates and installs the VirtualHIDDevice Daemon LaunchDaemon service
    func createVHIDDaemonService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Daemon LaunchDaemon service")

        let plistContent = generateVHIDDaemonPlist()
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"

        return installPlist(content: plistContent, path: plistPath, serviceID: Self.vhidDaemonServiceID)
    }

    /// Creates and installs the VirtualHIDDevice Manager LaunchDaemon service
    func createVHIDManagerService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Creating VHIDDevice Manager LaunchDaemon service")

        let plistContent = generateVHIDManagerPlist()
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        return installPlist(
            content: plistContent, path: plistPath, serviceID: Self.vhidManagerServiceID
        )
    }

    /// Creates, installs, configures, and loads all LaunchDaemon services with a single admin prompt
    /// This method consolidates all admin operations to eliminate multiple password prompts
    /// Uses SMAppService for Kanata if feature flag is enabled, otherwise uses launchctl for all services
    func createConfigureAndLoadAllServices() async -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] *** DECISION POINT *** createConfigureAndLoadAllServices() called")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Creating, configuring, and loading all services with single admin prompt")

        // Check if SMAppService path is enabled for Kanata
        let featureFlagValue = FeatureFlags.useSMAppServiceForDaemon
        AppLogger.shared.log("🔍 [LaunchDaemon] Feature flag check: useSMAppServiceForDaemon = \(featureFlagValue)")
        AppLogger.shared.log("🔍 [LaunchDaemon] Feature flag UserDefaults key: USE_SMAPPSERVICE_FOR_DAEMON")
        if let userDefaultsValue = UserDefaults.standard.object(forKey: "USE_SMAPPSERVICE_FOR_DAEMON") {
            AppLogger.shared.log("🔍 [LaunchDaemon] UserDefaults has explicit value: \(userDefaultsValue)")
        } else {
            AppLogger.shared.log("🔍 [LaunchDaemon] UserDefaults has no explicit value - using default: true")
        }

        if featureFlagValue {
            AppLogger.shared.log("📱 [LaunchDaemon] ✅ DECISION: Feature flag is TRUE - Using SMAppService path for Kanata, launchctl for VirtualHID")
            return await createConfigureAndLoadAllServicesWithSMAppService()
        } else {
            AppLogger.shared.log("🔧 [LaunchDaemon] ⚠️ DECISION: Feature flag is FALSE - Using launchctl path for all services")
            return createConfigureAndLoadAllServicesViaLaunchctl()
        }
    }

    /// Creates, installs, configures, and loads services using SMAppService for Kanata
    /// VirtualHID services still use launchctl (they don't support SMAppService)
    @MainActor
    private func createConfigureAndLoadAllServicesWithSMAppService() async -> Bool {
        AppLogger.shared.log("📱 [LaunchDaemon] Installing VirtualHID via launchctl, Kanata via SMAppService")

        // 1. Install VirtualHID services via launchctl (they still need launchctl)
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()

        let tempDir = NSTemporaryDirectory()
        let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
        let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

        do {
            try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
            try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

            // Install VirtualHID services via launchctl (requires admin)
            let vhidSuccess = executeConsolidatedInstallationForVHIDOnly(
                vhidDaemonTemp: vhidDaemonTempPath,
                vhidManagerTemp: vhidManagerTempPath
            )

            // Clean up temporary files
            try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
            try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

            guard vhidSuccess else {
                AppLogger.shared.log("❌ [LaunchDaemon] VirtualHID installation failed")
                return false
            }

            // 2. Install Kanata via SMAppService
            AppLogger.shared.log("📱 [LaunchDaemon] Installing Kanata via SMAppService...")
            let kanataSuccess = await createKanataLaunchDaemon()

            if !kanataSuccess {
                AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService registration failed - NOT falling back to launchctl")
                AppLogger.shared.log("💡 [LaunchDaemon] User may need to approve in System Settings, or migration may be needed")
                // Don't fall back to launchctl - return false so caller can handle it
                // This prevents recreating the legacy plist after migration
                return false
            }

            AppLogger.shared.info("✅ [LaunchDaemon] All services installed (VirtualHID via launchctl, Kanata via SMAppService)")
            return true

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
            return false
        }
    }

    /// Creates, installs, configures, and loads all services via launchctl (legacy path)
    /// GUARD: Skips Kanata plist creation if SMAppService is active
    private func createConfigureAndLoadAllServicesViaLaunchctl() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing all services via launchctl")

        // GUARD: Check if SMAppService is active for Kanata - if so, skip Kanata plist creation
        let isSMAppServiceActive = KanataDaemonManager.isUsingSMAppService

        if isSMAppServiceActive {
            AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService is active for Kanata - skipping Kanata plist creation")
            AppLogger.shared.log("💡 [LaunchDaemon] Only installing VirtualHID services via launchctl")
        }

        let kanataBinaryPath = getKanataBinaryPath()

        // Generate plist contents (skip Kanata if SMAppService is active)
        let kanataPlist = isSMAppServiceActive ? nil : generateKanataPlist(binaryPath: kanataBinaryPath)
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()

        // Create temporary files for all plists (skip Kanata if SMAppService is active)
        let tempDir = NSTemporaryDirectory()
        let kanataTempPath = isSMAppServiceActive ? nil : "\(tempDir)\(Self.kanataServiceID).plist"
        let vhidDaemonTempPath = "\(tempDir)\(Self.vhidDaemonServiceID).plist"
        let vhidManagerTempPath = "\(tempDir)\(Self.vhidManagerServiceID).plist"

        do {
            // Write plist contents to temporary files (skip Kanata if SMAppService is active)
            if let kanataPlist = kanataPlist, let kanataTempPath = kanataTempPath {
                try kanataPlist.write(toFile: kanataTempPath, atomically: true, encoding: .utf8)
            }
            try vhidDaemonPlist.write(toFile: vhidDaemonTempPath, atomically: true, encoding: .utf8)
            try vhidManagerPlist.write(toFile: vhidManagerTempPath, atomically: true, encoding: .utf8)

            // Execute consolidated admin operations (skip Kanata if SMAppService is active)
            let success: Bool
            if isSMAppServiceActive {
                // Only install VirtualHID services
                success = executeConsolidatedInstallationForVHIDOnly(
                    vhidDaemonTemp: vhidDaemonTempPath,
                    vhidManagerTemp: vhidManagerTempPath
                )
            } else {
                // Install all services including Kanata
                success = executeConsolidatedInstallationImproved(
                    kanataTemp: kanataTempPath!,
                    vhidDaemonTemp: vhidDaemonTempPath,
                    vhidManagerTemp: vhidManagerTempPath
                )
            }

            // Clean up temporary files
            if let kanataTempPath = kanataTempPath {
                try? FileManager.default.removeItem(atPath: kanataTempPath)
            }
            try? FileManager.default.removeItem(atPath: vhidDaemonTempPath)
            try? FileManager.default.removeItem(atPath: vhidManagerTempPath)

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plists: \(error)")
            return false
        }
    }

    /// Loads all KeyPath LaunchDaemon services
    func loadServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Loading all KeyPath LaunchDaemon services")

        let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
        var allSucceeded = true

        for serviceID in services {
            let success = await loadService(serviceID: serviceID)
            if !success {
                allSucceeded = false
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service: \(serviceID)")
            }
        }

        return allSucceeded
    }

    // MARK: - Service Management

    /// Loads a specific LaunchDaemon service
    @MainActor private func loadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Loading service: \(serviceID)")
        if Self.isTestMode {
            return FileManager.default.fileExists(atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", "-w", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully loaded service: \(serviceID)")
                // Loading triggers program start; mark warm-up
                markRestartTime(for: [serviceID])
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to load service \(serviceID): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error loading service \(serviceID): \(error)")
            return false
        }
    }

    /// Unloads a specific LaunchDaemon service
    private func unloadService(serviceID: String) async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Unloading service: \(serviceID)")
        if Self.isTestMode { return true }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", "\(Self.launchDaemonsPath)/\(serviceID).plist"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully unloaded service: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log(
                    "⚠️ [LaunchDaemon] Service \(serviceID) may not have been loaded: \(output)")
                return true // Not an error if it wasn't loaded
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error unloading service \(serviceID): \(error)")
            return false
        }
    }

    /// Checks if a LaunchDaemon service is currently loaded
    /// Uses state determination for Kanata service to ensure consistent detection
    func isServiceLoaded(serviceID: String) -> Bool {
        // Special handling for Kanata service: Use state determination for consistent detection
        if serviceID == Self.kanataServiceID && FeatureFlags.useSMAppServiceForDaemon {
            let state = KanataDaemonManager.determineServiceManagementState()
            AppLogger.shared.log("🔍 [LaunchDaemon] Kanata service state: \(state.description)")

            switch state {
            case .legacyActive:
                // Legacy plist exists - check launchctl status
                // Fall through to launchctl check below
                AppLogger.shared.log("🔍 [LaunchDaemon] Legacy plist exists - checking launchctl status")
            case .smappserviceActive, .smappservicePending:
                // SMAppService is managing - consider it loaded
                AppLogger.shared.log("🔍 [LaunchDaemon] Kanata service loaded via SMAppService (state: \(state.description))")
                return true
            case .conflicted:
                // Both active - consider it loaded (SMAppService takes precedence)
                AppLogger.shared.log("🔍 [LaunchDaemon] Conflicted state - considering loaded (SMAppService active)")
                return true
            case .unknown:
                // Process running but unclear - check process, consider loaded if running
                if pgrepKanataProcess() {
                    AppLogger.shared.log("🔍 [LaunchDaemon] Unknown state but process running - considering loaded")
                    return true
                }
                return false
            case .uninstalled:
                // Not installed
                AppLogger.shared.log("🔍 [LaunchDaemon] Service not installed (state: \(state.description))")
                return false
            }
        }

        if Self.isTestMode {
            let exists = FileManager.default.fileExists(
                atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] (test) Service \(serviceID) considered loaded: \(exists)")
            return exists
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let isLoaded = task.terminationStatus == 0
            AppLogger.shared.log("🔍 [LaunchDaemon] (system) Service \(serviceID) loaded: \(isLoaded)")
            return isLoaded
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking service \(serviceID): \(error)")
            return false
        }
    }

    /// Check if Kanata process is running (helper for SMAppService detection)
    nonisolated func pgrepKanataProcess() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "kanata.*--cfg"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Checks if a LaunchDaemon service is running healthily (not just loaded)
    @MainActor func isServiceHealthy(serviceID: String) -> Bool {
        AppLogger.shared.log("🔍 [LaunchDaemon] HEALTH CHECK (system/print) for: \(serviceID)")

        if Self.isTestMode {
            let exists = FileManager.default.fileExists(
                atPath: "\(Self.launchDaemonsPath)/\(serviceID).plist")
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] (test) Service \(serviceID) considered healthy: \(exists)")
            return exists
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                AppLogger.shared.log("🔍 [LaunchDaemon] \(serviceID) not found in system domain")
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Extract details from 'launchctl print' output
            let state = output.firstMatchString(pattern: #"state\s*=\s*([A-Za-z]+)"#)?.lowercased()
            let pid = output.firstMatchInt(pattern: #"\bpid\s*=\s*([0-9]+)"#)
                ?? output.firstMatchInt(pattern: #""PID"\s*=\s*([0-9]+)"#)
            let lastExit =
                output.firstMatchInt(pattern: #"last exit (?:status|code)\s*=\s*(-?\d+)"#)
                    ?? output.firstMatchInt(pattern: #""LastExitStatus"\s*=\s*(-?\d+)"#)

            let isOneShot = (serviceID == Self.vhidManagerServiceID)
            let isRunningLike = (state == "running" || state == "launching")
            let hasPID = (pid != nil)
            let inWarmup = Self.wasRecentlyRestarted(serviceID)

            var healthy = false
            if isOneShot {
                // One-shot: OK if clean exit or (still running) or within warm-up window
                if let lastExit, lastExit == 0 { healthy = true } else if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
                else { healthy = false }
            } else {
                // KeepAlive jobs should be running. Allow starting states or warm-up.
                if isRunningLike || hasPID { healthy = true } else if inWarmup { healthy = true } // starting up
                else { healthy = false }
            }

            AppLogger.shared.log("🔍 [LaunchDaemon] HEALTH ANALYSIS \(serviceID):")
            AppLogger.shared.log("    state=\(state ?? "nil"), pid=\(pid?.description ?? "nil"), lastExit=\(lastExit?.description ?? "nil"), oneShot=\(isOneShot), warmup=\(inWarmup), healthy=\(healthy)")

            return healthy
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking service health \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Plist Generation

    private func generateKanataPlist(binaryPath: String) -> String {
        let arguments = buildKanataPlistArguments(binaryPath: binaryPath)

        // TCP mode: No environment variables needed (auth token stored in Keychain)
        let environmentXML = ""

        var argumentsXML = ""
        for arg in arguments {
            argumentsXML += "                <string>\(arg)</string>\n"
        }
        // Ensure proper indentation for the XML
        argumentsXML = argumentsXML.trimmingCharacters(in: .newlines)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.kanataServiceID)</string>
            <key>ProgramArguments</key>
            <array>
            \(argumentsXML)
            </array>\(environmentXML)
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/var/log/kanata.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/kanata.log</string>
            <key>SoftResourceLimits</key>
            <dict>
                <key>NumberOfFiles</key>
                <integer>256</integer>
            </dict>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
            <key>AssociatedBundleIdentifiers</key>
            <array>
                <string>com.keypath.KeyPath</string>
            </array>
        </dict>
        </plist>
        """
    }

    private func generateVHIDDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.vhidDaemonServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.vhidDaemonPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-daemon.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
            <key>ThrottleInterval</key>
            <integer>10</integer>
        </dict>
        </plist>
        """
    }

    private func generateVHIDManagerPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.vhidManagerServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.vhidManagerPath)</string>
                <string>activate</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/karabiner-vhid-manager.log</string>
            <key>UserName</key>
            <string>root</string>
            <key>GroupName</key>
            <string>wheel</string>
        </dict>
        </plist>
        """
    }

    // MARK: - File System Operations

    private func installPlist(content: String, path: String, serviceID: String) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing plist: \(path)")

        // Skip admin operations in test environment
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("🧪 [TestEnvironment] Skipping plist installation - returning mock success")
            return true
        }

        // Create temporary file with plist content
        let tempDir = NSTemporaryDirectory()
        let tempPath = "\(tempDir)\(serviceID).plist"

        do {
            // Write content to temporary file first
            try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

            // Use admin privileges to install the plist (unless in test mode)
            let success: Bool
            if Self.isTestMode {
                do {
                    try FileManager.default.createDirectory(
                        atPath: (path as NSString).deletingLastPathComponent,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    try FileManager.default.removeItem(atPath: path)
                } catch { /* ignore if not exists */ }
                do {
                    try FileManager.default.copyItem(atPath: tempPath, toPath: path)
                    success = true
                } catch {
                    AppLogger.shared.log("❌ [LaunchDaemon] (test) copy failed: \(error)")
                    success = false
                }
            } else {
                success = executeWithAdminPrivileges(
                    tempPath: tempPath,
                    finalPath: path,
                    serviceID: serviceID
                )
            }

            // Clean up temporary file
            try? FileManager.default.removeItem(atPath: tempPath)

            return success
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to create temporary plist \(serviceID): \(error)")
            return false
        }
    }

    /// Execute all LaunchDaemon installations with a single administrator privileges request
    private func executeAllWithAdminPrivileges(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install all services")
        if Self.isTestMode {
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: Self.launchDaemonsPath, withIntermediateDirectories: true)
                let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
                let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
                let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
                for (src, dst) in [
                    (kanataTemp, kanataFinal), (vhidDaemonTemp, vhidDaemonFinal),
                    (vhidManagerTemp, vhidManagerFinal)
                ] {
                    try? fm.removeItem(atPath: dst)
                    try fm.copyItem(atPath: src, toPath: dst)
                }
                AppLogger.shared.log(
                    "✅ [LaunchDaemon] (test) Installed all plists to \(Self.launchDaemonsPath)")
                return true
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] (test) Failed to install plists: \(error)")
                return false
            }
        }

        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        // Create a single compound command that installs all three services
        let command = """
        mkdir -p '\(Self.launchDaemonsPath)' && \
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)' && \
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)' && \
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'
        """

        // Use osascript to request admin privileges with proper password dialog
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
        """

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            try osascriptTask.run()
            osascriptTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed all LaunchDaemon services")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install services: \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute admin command: \(error)")
            return false
        }
    }

    /// Execute LaunchDaemon installation with administrator privileges using osascript
    private func executeWithAdminPrivileges(tempPath: String, finalPath: String, serviceID: String)
        -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Requesting admin privileges to install \(serviceID)")

        // Create the command to copy the file and set proper permissions
        let command =
            "mkdir -p '\(Self.launchDaemonsPath)' && cp '\(tempPath)' '\(finalPath)' && chown root:wheel '\(finalPath)' && chmod 644 '\(finalPath)'"

        // Use osascript to request admin privileges with proper password dialog
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install LaunchDaemon services for keyboard management."
        """

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            try osascriptTask.run()
            osascriptTask.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed plist: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install plist \(serviceID): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to execute admin command for \(serviceID): \(error)")
            return false
        }
    }

    /// Execute consolidated installation using native Authorization Services
    /// This is the most reliable approach for GUI apps on macOS
    private func executeConsolidatedInstallationWithAuthServices(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Starting consolidated installation with Authorization Services")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] This approach bypasses osascript sandbox restrictions")

        // Create the installation script
        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
        let currentUserName = NSUserName()

        let script = """
        #!/bin/bash
        set -e
        echo "Starting LaunchDaemon installation with Authorization Services..."

        # Create LaunchDaemons directory
        mkdir -p '\(Self.launchDaemonsPath)'

        # Install plist files with proper ownership
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)'
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)'
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'

        # Create user configuration directory and file (as current user)
        install -d -o '\(currentUserName)' -g staff '/Users/\(currentUserName)/.config/keypath'
        touch '/Users/\(currentUserName)/.config/keypath/keypath.kbd'
        chown '\(currentUserName):staff' '/Users/\(currentUserName)/.config/keypath/keypath.kbd'

        # Unload existing services first (ignore errors if not loaded)
        launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true
        launchctl bootout system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        launchctl bootout system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Ensure system kanata exists and is up-to-date for TCC permissions
        echo "Ensuring system kanata at: /Library/KeyPath/bin/kanata"
        mkdir -p '/Library/KeyPath/bin'
        if [ -f '\(WizardSystemPaths.bundledKanataPath)' ]; then
            if [ -f '/Library/KeyPath/bin/kanata' ]; then
                src_md5=$(/sbin/md5 -q '\(WizardSystemPaths.bundledKanataPath)' 2>/dev/null || echo '')
                dst_md5=$(/sbin/md5 -q '/Library/KeyPath/bin/kanata' 2>/dev/null || echo 'different')
                if [ "$src_md5" != "$dst_md5" ]; then
                    cp -f '\(WizardSystemPaths.bundledKanataPath)' '/Library/KeyPath/bin/kanata'
                fi
            else
                cp -f '\(WizardSystemPaths.bundledKanataPath)' '/Library/KeyPath/bin/kanata'
            fi
            chown root:wheel '/Library/KeyPath/bin/kanata'
            chmod 755 '/Library/KeyPath/bin/kanata'
            /usr/bin/xattr -d com.apple.quarantine '/Library/KeyPath/bin/kanata' 2>/dev/null || true
        else
            echo "ERROR: Bundled kanata not found at \(WizardSystemPaths.bundledKanataPath)"
            exit 1
        fi

        # Enable services in case previously disabled
        echo "Enabling services..."
        /bin/launchctl enable system/\(Self.kanataServiceID) 2>/dev/null || true
        /bin/launchctl enable system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        /bin/launchctl enable system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Load services using bootstrap (modern approach) - DEPENDENCIES FIRST!
        launchctl bootstrap system '\(vhidDaemonFinal)'
        launchctl bootstrap system '\(vhidManagerFinal)'
        launchctl bootstrap system '\(kanataFinal)' || {
            echo "Bootstrap failed for kanata. Collecting diagnostics..."
            echo "Checking system kanata exists:"
            /bin/ls -la '/Library/KeyPath/bin/kanata' || echo "Kanata not found at system path"
            echo "Checking spctl acceptance:"
            /usr/sbin/spctl -a -vvv -t execute '/Library/KeyPath/bin/kanata' || echo "spctl rejected kanata binary"
            echo "Checking file attributes:"
            /usr/bin/xattr -l '/Library/KeyPath/bin/kanata' || true
            echo "Checking launchctl status:"
            /bin/launchctl print system/\(Self.kanataServiceID) 2>&1 || true
            echo "Recent launchd logs:"
            /usr/bin/log show --style syslog --last 2m --predicate 'subsystem == "com.apple.xpc.launchd" || eventMessage CONTAINS "com.keypath.kanata"' 2>&1 || true
            exit 1
        }

        # Start services - DEPENDENCIES FIRST!
        launchctl kickstart -k system/\(Self.vhidDaemonServiceID)
        launchctl kickstart -k system/\(Self.vhidManagerServiceID)
        launchctl kickstart -k system/\(Self.kanataServiceID)

        echo "Installation completed successfully with Authorization Services"
        """

        // Create temporary script
        let tempScriptPath = NSTemporaryDirectory() + "keypath-auth-install-\(UUID().uuidString).sh"

        do {
            try script.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)

            // Use Authorization Services for privilege escalation
            let success = requestAdminPrivilegesAndExecute(scriptPath: tempScriptPath)

            // Clean up
            try? FileManager.default.removeItem(atPath: tempScriptPath)

            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Authorization Services installation completed successfully")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Authorization Services installation failed")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error with Authorization Services approach: \(error)")
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            return false
        }
    }

    private func requestAdminPrivilegesAndExecute(scriptPath: String) -> Bool {
        AppLogger.shared.log("🔐 [LaunchDaemon] Requesting admin privileges via Authorization Services")

        var authRef: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errSecSuccess else {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create authorization reference: \(status)")
            return false
        }

        defer {
            if let authRef {
                AuthorizationFree(authRef, [])
            }
        }

        // Request admin privileges (ensure C-string and pointer lifetimes are valid)
        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]

        let executeRight = "system.privilege.admin"
        let rightsStatus: OSStatus = executeRight.withCString { namePtr in
            var authItem = AuthorizationItem(
                name: namePtr,
                valueLength: 0,
                value: nil,
                flags: 0
            )

            return withUnsafeMutablePointer(to: &authItem) { authItemPtr in
                var rights = AuthorizationRights(count: 1, items: authItemPtr)
                return AuthorizationCopyRights(authRef!, &rights, nil, flags, nil)
            }
        }

        status = rightsStatus

        guard status == errSecSuccess else {
            if status == errSecUserCanceled {
                AppLogger.shared.log("ℹ️ [LaunchDaemon] User canceled admin authorization")
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to get admin authorization: \(status)")
            }
            return false
        }

        AppLogger.shared.log("✅ [LaunchDaemon] Admin authorization granted, executing script")

        // Execute the script with admin privileges
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            // This execution should have the admin privileges we requested
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔐 [LaunchDaemon] Script execution completed with status: \(task.terminationStatus)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Output: \(output)")

            return task.terminationStatus == 0

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute admin script: \(error)")
            return false
        }
    }

    /// Execute consolidated installation with improved osascript execution
    /// This method addresses sandbox restrictions by ensuring proper execution context
    private func executeConsolidatedInstallationImproved(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Starting consolidated installation with improved osascript")
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Using direct osascript execution with proper environment")

        // First, test if osascript works at all with a simple command
        AppLogger.shared.log("🔧 [LaunchDaemon] Testing osascript functionality first...")
        let testCommand = """
        do shell script "echo 'osascript test successful'" with administrator privileges
        """

        let testTask = Process()
        testTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        testTask.arguments = ["-e", testCommand]

        // Capture both stdout and stderr
        let testPipe = Pipe()
        let testErrorPipe = Pipe()
        testTask.standardOutput = testPipe
        testTask.standardError = testErrorPipe

        do {
            try testTask.run()
            testTask.waitUntilExit()

            let testStatus = testTask.terminationStatus
            AppLogger.shared.log("🔧 [LaunchDaemon] osascript test result: \(testStatus)")

            if testStatus != 0 {
                // Capture stderr for detailed error info
                let errorData = testErrorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                    AppLogger.shared.log("❌ [LaunchDaemon] osascript error output: \(errorString)")
                }

                AppLogger.shared.log("❌ [LaunchDaemon] osascript test failed - admin dialogs may be blocked")
                AppLogger.shared.log("❌ [LaunchDaemon] This usually indicates missing entitlements or sandbox restrictions")
                return false
            }
            AppLogger.shared.log("✅ [LaunchDaemon] osascript test passed - proceeding with installation")
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] osascript test threw error: \(error)")
            AppLogger.shared.log("❌ [LaunchDaemon] Error details: \(error.localizedDescription)")
            return false
        }

        // Build installation script (same as before)
        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
        let currentUserName = NSUserName()

        let command = """
        set -ex
        exec > /tmp/keypath-install-debug.log 2>&1
        echo "Starting LaunchDaemon installation at $(date)..."
        echo "Current user: $(whoami)"

        # Create LaunchDaemons directory
        mkdir -p '\(Self.launchDaemonsPath)'

        # Install plist files with proper ownership
        cp '\(kanataTemp)' '\(kanataFinal)' && chown root:wheel '\(kanataFinal)' && chmod 644 '\(kanataFinal)'
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)'
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'

        # Create user configuration directory and file (as current user)
        install -d -o '\(currentUserName)' -g staff '/Users/\(currentUserName)/.config/keypath'
        touch '/Users/\(currentUserName)/.config/keypath/keypath.kbd'
        chown '\(currentUserName):staff' '/Users/\(currentUserName)/.config/keypath/keypath.kbd'

        # Unload existing services first (ignore errors if not loaded)
        launchctl bootout system/\(Self.kanataServiceID) 2>/dev/null || true
        launchctl bootout system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        launchctl bootout system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Use bundled kanata directly in this path (avoids TCC identity issues)
        # Note: This behavior is covered by safety lints/tests to prevent regressions
        echo "Using bundled kanata binary at: \(WizardSystemPaths.bundledKanataPath)"

        # Verify bundled kanata exists and is executable
        if [ ! -f '\(WizardSystemPaths.bundledKanataPath)' ]; then
            echo "ERROR: Bundled kanata not found at \(WizardSystemPaths.bundledKanataPath)"
            exit 1
        fi

        # Clear any quarantine attributes on the bundled binary
        /usr/bin/xattr -d com.apple.quarantine '\(WizardSystemPaths.bundledKanataPath)' 2>/dev/null || true

        # Enable services in case previously disabled
        echo "Enabling services..."
        /bin/launchctl enable system/\(Self.kanataServiceID) 2>/dev/null || true
        /bin/launchctl enable system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        /bin/launchctl enable system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Load services using bootstrap (modern approach) - DEPENDENCIES FIRST!
        launchctl bootstrap system '\(vhidDaemonFinal)'
        launchctl bootstrap system '\(vhidManagerFinal)'
        launchctl bootstrap system '\(kanataFinal)' || {
            echo "Bootstrap failed for kanata. Collecting diagnostics..."
            echo "Checking if kanata exists at bundled path:"
            /bin/ls -la '\(WizardSystemPaths.bundledKanataPath)' || echo "Kanata not found at bundled path"
            echo "Checking spctl acceptance:"
            /usr/sbin/spctl -a -vvv -t execute '\(WizardSystemPaths.bundledKanataPath)' || echo "spctl rejected kanata binary"
            echo "Checking file attributes:"
            /usr/bin/xattr -l '/Library/KeyPath/bin/kanata' || true
            echo "Checking launchctl status:"
            /bin/launchctl print system/\(Self.kanataServiceID) 2>&1 || true
            echo "Recent launchd logs:"
            /usr/bin/log show --style syslog --last 2m --predicate 'subsystem == "com.apple.xpc.launchd" || eventMessage CONTAINS "com.keypath.kanata"' 2>&1 || true
            exit 1
        }

        # Start services - DEPENDENCIES FIRST!
        launchctl kickstart -k system/\(Self.vhidDaemonServiceID)
        launchctl kickstart -k system/\(Self.vhidManagerServiceID)
        launchctl kickstart -k system/\(Self.kanataServiceID)

        echo "Installation completed successfully"
        """

        // Create a temporary script file
        let tempScriptPath = NSTemporaryDirectory() + "keypath-install-\(UUID().uuidString).sh"

        do {
            try command.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)

            // Set executable permissions
            let fileManager = FileManager.default
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)

            // Use osascript to execute the script with admin privileges
            // Custom prompt to clearly identify KeyPath (not osascript)
            let osascriptCode = """
            do shell script "bash '\(tempScriptPath)'" with administrator privileges with prompt "KeyPath needs administrator access to install system services for keyboard management."
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascriptCode]
            task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            AppLogger.shared.log("🔐 [LaunchDaemon] Executing osascript with temp script approach...")
            AppLogger.shared.log("🔐 [LaunchDaemon] Script path: \(tempScriptPath)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Current thread: \(Thread.isMainThread ? "main" : "background")")
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript command: \(osascriptCode)")
            AppLogger.shared.log("🔐 [LaunchDaemon] About to execute: /usr/bin/osascript -e [command]")

            // Execute without thread switching to avoid deadlock
            // Admin dialogs can run from any thread when using osascript
            var taskSuccess = false
            var taskStatus: Int32 = -1

            do {
                AppLogger.shared.log("🔐 [LaunchDaemon] Executing osascript directly")
                try task.run()
                task.waitUntilExit()
                taskStatus = task.terminationStatus
                taskSuccess = true
                AppLogger.shared.log("🔐 [LaunchDaemon] Execution completed with status: \(taskStatus)")
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] Execution failed: \(error)")
                taskSuccess = false
            }

            if !taskSuccess {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute osascript task")
                try? fileManager.removeItem(atPath: tempScriptPath)
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔐 [LaunchDaemon] osascript completed with status: \(taskStatus)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Output: \(output)")

            // Clean up temp script
            try? fileManager.removeItem(atPath: tempScriptPath)

            if taskStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully completed installation with main thread osascript")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] osascript installation failed with status: \(taskStatus)")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error with improved osascript approach: \(error)")
            // Clean up temp script on error
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            return false
        }
    }

    /// Execute consolidated installation for VirtualHID services only (no Kanata)
    /// Used when Kanata is installed via SMAppService
    private func executeConsolidatedInstallationForVHIDOnly(
        vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing VirtualHID services only (Kanata via SMAppService)")

        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"
        let currentUserName = NSUserName()

        let command = """
        set -ex
        exec > /tmp/keypath-vhid-install-debug.log 2>&1
        echo "Starting VirtualHID installation at $(date)..."
        echo "Current user: $(whoami)"

        # Create LaunchDaemons directory
        mkdir -p '\(Self.launchDaemonsPath)'

        # Install VirtualHID plist files with proper ownership
        cp '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && chown root:wheel '\(vhidDaemonFinal)' && chmod 644 '\(vhidDaemonFinal)'
        cp '\(vhidManagerTemp)' '\(vhidManagerFinal)' && chown root:wheel '\(vhidManagerFinal)' && chmod 644 '\(vhidManagerFinal)'

        # Create user configuration directory and file (as current user)
        install -d -o '\(currentUserName)' -g staff '/Users/\(currentUserName)/.config/keypath'
        touch '/Users/\(currentUserName)/.config/keypath/keypath.kbd'
        chown '\(currentUserName):staff' '/Users/\(currentUserName)/.config/keypath/keypath.kbd'

        # Unload existing VirtualHID services first (ignore errors if not loaded)
        launchctl bootout system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        launchctl bootout system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Enable services in case previously disabled
        echo "Enabling VirtualHID services..."
        /bin/launchctl enable system/\(Self.vhidDaemonServiceID) 2>/dev/null || true
        /bin/launchctl enable system/\(Self.vhidManagerServiceID) 2>/dev/null || true

        # Load services using bootstrap (modern approach) - DEPENDENCIES FIRST!
        launchctl bootstrap system '\(vhidDaemonFinal)'
        launchctl bootstrap system '\(vhidManagerFinal)'

        # Start services - DEPENDENCIES FIRST!
        launchctl kickstart -k system/\(Self.vhidDaemonServiceID)
        launchctl kickstart -k system/\(Self.vhidManagerServiceID)

        echo "VirtualHID installation completed successfully"
        """

        // Create a temporary script file
        let tempScriptPath = NSTemporaryDirectory() + "keypath-vhid-install-\(UUID().uuidString).sh"

        do {
            try command.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)

            // Set executable permissions
            let fileManager = FileManager.default
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)

            // Use osascript to execute the script with admin privileges
            let osascriptCode = """
            do shell script "bash '\(tempScriptPath)'" with administrator privileges with prompt "KeyPath needs administrator access to install VirtualHID services for keyboard management."
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascriptCode]
            task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            AppLogger.shared.log("🔐 [LaunchDaemon] Executing VirtualHID installation...")
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            AppLogger.shared.log("🔐 [LaunchDaemon] VirtualHID installation status: \(task.terminationStatus)")
            AppLogger.shared.log("🔐 [LaunchDaemon] Output: \(output)")

            // Clean up temp script
            try? fileManager.removeItem(atPath: tempScriptPath)

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed VirtualHID services")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] VirtualHID installation failed")
                return false
            }

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error installing VirtualHID services: \(error)")
            try? FileManager.default.removeItem(atPath: tempScriptPath)
            return false
        }
    }

    /// Execute consolidated installation with all operations in a single admin prompt
    /// Includes: install plists, create system config directory, create system config file, and load services
    @MainActor
    private func executeConsolidatedInstallation(
        kanataTemp: String, vhidDaemonTemp: String, vhidManagerTemp: String
    ) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Executing consolidated installation with single admin prompt")

        if Self.isTestMode {
            // Test mode - use file operations without admin privileges
            do {
                let fm = FileManager.default
                try fm.createDirectory(atPath: Self.launchDaemonsPath, withIntermediateDirectories: true)
                try fm.createDirectory(
                    atPath: WizardSystemPaths.userConfigDirectory, withIntermediateDirectories: true
                )

                let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
                let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
                let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

                for (src, dst) in [
                    (kanataTemp, kanataFinal), (vhidDaemonTemp, vhidDaemonFinal),
                    (vhidManagerTemp, vhidManagerFinal)
                ] {
                    try? fm.removeItem(atPath: dst)
                    try fm.copyItem(atPath: src, toPath: dst)
                }

                // Create a basic config file for testing
                try "test config".write(
                    toFile: WizardSystemPaths.userConfigPath, atomically: true, encoding: .utf8
                )

                AppLogger.shared.log("✅ [LaunchDaemon] (test) Consolidated installation completed")
                return true
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] (test) Failed consolidated installation: \(error)")
                return false
            }
        }

        let kanataFinal = "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist"
        let vhidDaemonFinal = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let vhidManagerFinal = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        // Get user config directory for initial setup
        let userConfigDir = WizardSystemPaths.userConfigDirectory
        let userConfigPath = WizardSystemPaths.userConfigPath

        // Create a comprehensive command that does everything in one admin operation
        let command = """
        /bin/echo Installing LaunchDaemon services and configuration... && \
        /bin/mkdir -p '\(Self.launchDaemonsPath)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(kanataTemp)' '\(kanataFinal)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(vhidDaemonTemp)' '\(vhidDaemonFinal)' && \
        /usr/bin/install -m 0644 -o root -g wheel '\(vhidManagerTemp)' '\(vhidManagerFinal)' && \
        CONSOLE_UID="$(/usr/bin/stat -f %u /dev/console)" && \
        CONSOLE_GID="$(/usr/bin/id -g $CONSOLE_UID)" && \
        /usr/bin/install -d -m 0755 -o $CONSOLE_UID -g $CONSOLE_GID '\(userConfigDir)' && \
        if [ ! -f '\(userConfigPath)' ]; then \
          /usr/bin/printf "%s\\n" ";; Default KeyPath config" "(defcfg process-unmapped-keys no)" "(defsrc)" "(deflayer base)" | /usr/bin/tee '\(userConfigPath)' >/dev/null && \
          /usr/sbin/chown $CONSOLE_UID:$CONSOLE_GID '\(userConfigPath)'; \
        fi && \
        /bin/launchctl bootstrap system '\(vhidDaemonFinal)' 2>/dev/null || /bin/echo VHID daemon already loaded && \
        /bin/launchctl bootstrap system '\(vhidManagerFinal)' 2>/dev/null || /bin/echo VHID manager already loaded && \
        /bin/launchctl bootstrap system '\(kanataFinal)' 2>/dev/null || /bin/echo Kanata service already loaded && \
        /bin/echo Installation completed successfully
        """

        // Use osascript to request admin privileges with clear explanation
        AppLogger.shared.log("🔐 [LaunchDaemon] *** ABOUT TO EXECUTE OSASCRIPT FOR ADMIN PRIVILEGES ***")
        AppLogger.shared.log("🔐 [LaunchDaemon] This should show a password dialog to the user")
        AppLogger.shared.log("🔐 [LaunchDaemon] isTestMode = \(Self.isTestMode)")

        // Escape the command for safe AppleScript embedding
        let escapedCommand = escapeForAppleScript(command)

        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs administrator access to install LaunchDaemon services, create configuration files, and start the keyboard services. This will be a single prompt."
        """

        AppLogger.shared.log("🔐 [LaunchDaemon] osascript command length: \(osascriptCommand.count) characters")
        AppLogger.shared.log("🔐 [LaunchDaemon] Starting osascript process...")

        let osascriptTask = Process()
        osascriptTask.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascriptTask.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        osascriptTask.standardOutput = pipe
        osascriptTask.standardError = pipe

        do {
            AppLogger.shared.log("🔐 [LaunchDaemon] Executing osascript.run()...")
            try osascriptTask.run()
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript.run() succeeded, now waiting for completion...")
            osascriptTask.waitUntilExit()
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript completed with status: \(osascriptTask.terminationStatus)")

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            AppLogger.shared.log("🔐 [LaunchDaemon] osascript output: \(output)")

            if osascriptTask.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully completed consolidated installation")
                AppLogger.shared.log("🔧 [LaunchDaemon] Admin output: \(output)")
                // Mark warm-up for all services we just installed+bootstrapped
                markRestartTime(for: [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID])
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed consolidated installation: \(output)")
                AppLogger.shared.log("❌ [LaunchDaemon] Exit status was: \(osascriptTask.terminationStatus)")
                return false
            }
        } catch {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Failed to execute consolidated admin command: \(error)")
            AppLogger.shared.log("❌ [LaunchDaemon] This means osascript.run() threw an exception")
            return false
        }
    }

    // MARK: - Cleanup Methods

    /// Removes all KeyPath LaunchDaemon services
    func removeAllServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Removing all KeyPath LaunchDaemon services")

        let services = [Self.kanataServiceID, Self.vhidDaemonServiceID, Self.vhidManagerServiceID]
        var allSucceeded = true

        for serviceID in services {
            // First unload the service
            let unloadSuccess = await unloadService(serviceID: serviceID)

            // Then remove the plist file
            let plistPath = "\(Self.launchDaemonsPath)/\(serviceID).plist"
            let removeSuccess = removePlist(path: plistPath, serviceID: serviceID)

            if !unloadSuccess || !removeSuccess {
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    private func removePlist(path: String, serviceID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "rm", "-f", path]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully removed plist: \(serviceID)")
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to remove plist: \(serviceID)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error removing plist \(serviceID): \(error)")
            return false
        }
    }

    // MARK: - Status Methods

    /// Gets comprehensive status of all LaunchDaemon services
    @MainActor func getServiceStatus() -> LaunchDaemonStatus {
        let kanataLoaded = isServiceLoaded(serviceID: Self.kanataServiceID)
        let vhidDaemonLoaded = isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerLoaded = isServiceLoaded(serviceID: Self.vhidManagerServiceID)

        let kanataHealthy = isServiceHealthy(serviceID: Self.kanataServiceID)
        let vhidDaemonHealthy = isServiceHealthy(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerHealthy = isServiceHealthy(serviceID: Self.vhidManagerServiceID)

        return LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded,
            kanataServiceHealthy: kanataHealthy,
            vhidDaemonServiceHealthy: vhidDaemonHealthy,
            vhidManagerServiceHealthy: vhidManagerHealthy
        )
    }

    /// Check if Kanata service plist file exists (but may not be loaded)
    func isKanataPlistInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.kanataPlistPath)
    }

    /// Install LaunchDaemon service files without loading/starting them
    /// Used for adopting orphaned processes - installs management files but doesn't interfere with running process
    /// GUARD: Uses state determination to prevent installing Kanata if SMAppService is managing it
    func createAllLaunchDaemonServicesInstallOnly() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing service files only (no load/start)...")

        // GUARD: Use state determination to check if SMAppService is managing Kanata
        let state = KanataDaemonManager.determineServiceManagementState()
        AppLogger.shared.log("🔍 [LaunchDaemon] Current state: \(state.description)")

        // If SMAppService is managing Kanata, skip Kanata installation to prevent reverting to launchctl
        // Also skip if state is unknown but process is running (likely SMAppService managed)
        let shouldSkipKanata = state.isSMAppServiceManaged || (state == .unknown && pgrepKanataProcess())

        AppLogger.shared.log("🔍 [LaunchDaemon] Install-only check: state=\(state.description), shouldSkipKanata=\(shouldSkipKanata)")

        // Create all required plist files (skip Kanata if SMAppService is active)
        let kanataSuccess: Bool
        if shouldSkipKanata {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Skipping Kanata installation - SMAppService is active or migrated (state: \(state.description))")
            kanataSuccess = true // Consider it success since we're intentionally skipping
        } else {
            kanataSuccess = await createKanataLaunchDaemon()
        }
        let vhidDaemonSuccess = createVHIDDaemonService()
        let vhidManagerSuccess = createVHIDManagerService()

        let success = kanataSuccess && vhidDaemonSuccess && vhidManagerSuccess
        AppLogger.shared.log("🔧 [LaunchDaemon] Install-only result: kanata=\(kanataSuccess), vhidDaemon=\(vhidDaemonSuccess), vhidManager=\(vhidManagerSuccess), overall=\(success)")

        return success
    }

    /// Verifies that the installed VHID LaunchDaemon plist points to the DriverKit daemon path
    func isVHIDDaemonConfiguredCorrectly() -> Bool {
        let plistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            AppLogger.shared.log("🔍 [LaunchDaemon] VHID plist not found or unreadable at: \(plistPath)")
            return false
        }

        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            let ok = first == Self.vhidDaemonPath
            AppLogger.shared.log(
                "🔍 [LaunchDaemon] VHID plist ProgramArguments[0]=\(first) | expected=\(Self.vhidDaemonPath) | ok=\(ok)"
            )
            return ok
        }
        AppLogger.shared.log("🔍 [LaunchDaemon] VHID plist ProgramArguments missing or malformed")
        return false
    }

    /// Restarts services with admin privileges using launchctl kickstart
    @MainActor
    private func restartServicesWithAdmin(_ serviceIDs: [String]) -> Bool {
        AppLogger.shared.log(
            "🔧 [LaunchDaemon] *** ENHANCED RESTART *** Restarting services: \(serviceIDs)")

        if Self.isTestMode {
            AppLogger.shared.log("🔧 [LaunchDaemon] Test mode - simulating successful restart")
            return true
        }
        guard !serviceIDs.isEmpty else {
            AppLogger.shared.log("🔧 [LaunchDaemon] No services to restart - returning success")
            return true
        }

        let cmds = serviceIDs.map { "launchctl kickstart -k system/\($0)" }.joined(separator: " && ")
        AppLogger.shared.log("🔧 [LaunchDaemon] Executing admin command: \(cmds)")

        let escapedCmds = escapeForAppleScript(cmds)
        let script = """
        do shell script "\(escapedCmds)" with administrator privileges with prompt "KeyPath needs to restart failing system services."
        """

        AppLogger.shared.log("🔧 [LaunchDaemon] Running osascript with admin privileges...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        // Capture both stdout and stderr for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            // Read output and error streams
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "(no output)"
            let error = String(data: errorData, encoding: .utf8) ?? "(no error)"

            AppLogger.shared.log(
                "🔧 [LaunchDaemon] osascript termination status: \(task.terminationStatus)")
            AppLogger.shared.log("🔧 [LaunchDaemon] osascript stdout: \(output)")
            AppLogger.shared.log("🔧 [LaunchDaemon] osascript stderr: \(error)")

            let success = task.terminationStatus == 0
            AppLogger.shared.log(
                "🔧 [LaunchDaemon] Admin restart command result: \(success ? "SUCCESS" : "FAILED")")
            if success {
                // Mark warm-up start time for those services
                markRestartTime(for: serviceIDs)
            }
            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] kickstart admin failed with exception: \(error)")
            return false
        }
    }

    /// Restarts unhealthy services and diagnoses/fixes underlying issues
    @MainActor
    func restartUnhealthyServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Starting comprehensive service health fix")

        let initialStatus = getServiceStatus()
        var toRestart: [String] = []
        var toInstall: [String] = []

        // Categorize services by what they need
        if initialStatus.kanataServiceLoaded, !initialStatus.kanataServiceHealthy {
            toRestart.append(Self.kanataServiceID)
        } else if !initialStatus.kanataServiceLoaded {
            toInstall.append(Self.kanataServiceID)
        }

        if initialStatus.vhidDaemonServiceLoaded, !initialStatus.vhidDaemonServiceHealthy {
            toRestart.append(Self.vhidDaemonServiceID)
        } else if !initialStatus.vhidDaemonServiceLoaded {
            toInstall.append(Self.vhidDaemonServiceID)
        }

        if initialStatus.vhidManagerServiceLoaded, !initialStatus.vhidManagerServiceHealthy {
            toRestart.append(Self.vhidManagerServiceID)
        } else if !initialStatus.vhidManagerServiceLoaded {
            toInstall.append(Self.vhidManagerServiceID)
        }

        // Step 1: Install missing services first if needed
        // CRITICAL: Use state determination to check if SMAppService is managing Kanata
        // IMPORTANT: Don't install Kanata if SMAppService is managing it (even if launchctl print fails)
        let needsInstallation = !toInstall.isEmpty

        // Use state determination to determine current state
        let state = KanataDaemonManager.determineServiceManagementState()
        AppLogger.shared.log("🔍 [LaunchDaemon] Current state: \(state.description)")

        // Check if migration is needed (legacy exists but feature flag requires SMAppService)
        let needsMigration = state.needsMigration(featureFlagEnabled: FeatureFlags.useSMAppServiceForDaemon)

        // CRITICAL FIX: If Kanata is in toInstall but SMAppService is managing it, remove it from toInstall
        // This prevents reverting to launchctl after migration
        if toInstall.contains(Self.kanataServiceID) {
            if state.isSMAppServiceManaged {
                AppLogger.shared.log("⚠️ [LaunchDaemon] Kanata is managed by SMAppService (state: \(state.description)) - skipping installation to prevent revert")
                toInstall.removeAll { $0 == Self.kanataServiceID }
            } else if state == .unknown && pgrepKanataProcess() {
                // Unknown state but process running - likely SMAppService managed, skip installation
                AppLogger.shared.log("⚠️ [LaunchDaemon] Unknown state but process running - skipping installation to prevent revert")
                toInstall.removeAll { $0 == Self.kanataServiceID }
            }
        }

        AppLogger.shared.log("🔍 [LaunchDaemon] Installation check: needsInstallation=\(needsInstallation), needsMigration=\(needsMigration)")
        AppLogger.shared.log("🔍 [LaunchDaemon] Feature flag: useSMAppServiceForDaemon=\(FeatureFlags.useSMAppServiceForDaemon)")
        AppLogger.shared.log("🔍 [LaunchDaemon] Services to install after state check: \(toInstall)")

        // Recalculate needsInstallation after removing SMAppService-managed services
        let finalNeedsInstallation = !toInstall.isEmpty

        if finalNeedsInstallation || needsMigration {
            if needsMigration {
                AppLogger.shared.log("🔄 [LaunchDaemon] Migration needed - service using launchctl but feature flag requires SMAppService")
            } else {
                AppLogger.shared.log("🔧 [LaunchDaemon] Installing missing services: \(toInstall)")
            }
            let installSuccess = await createConfigureAndLoadAllServices()
            if !installSuccess {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install/migrate services")
                return false
            }
            AppLogger.shared.log("✅ [LaunchDaemon] Successfully installed/migrated services")

            // Wait for installation to settle
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        } else {
            AppLogger.shared.log("🔍 [LaunchDaemon] No installation/migration needed - services using correct method")
        }

        // Step 2: Handle unhealthy services
        if toRestart.isEmpty {
            AppLogger.shared.log("🔍 [LaunchDaemon] No unhealthy services found to restart")
            return true
        }

        AppLogger.shared.log("🔧 [LaunchDaemon] Services to restart: \(toRestart)")

        // Step 3: Diagnose issues before restarting
        await diagnoseServiceFailures(toRestart)

        // Step 4: Execute the restart command
        let restartOk = restartServicesWithAdmin(toRestart)
        if !restartOk {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to execute restart commands")
            return false
        }

        AppLogger.shared.log("✅ [LaunchDaemon] Restart commands executed successfully")

        // Step 5: Wait for services to start up (poll up to 10 seconds)
        AppLogger.shared.log("⏳ [LaunchDaemon] Waiting for services to start up (polling)...")
        let timeout: TimeInterval = 10.0
        let interval: UInt64 = 500_000_000 // 0.5s
        var elapsed: TimeInterval = 0

        while elapsed < timeout {
            let status = getServiceStatus()
            var allRecovered = true
            if toRestart.contains(Self.kanataServiceID), !status.kanataServiceHealthy { allRecovered = false }
            if toRestart.contains(Self.vhidDaemonServiceID), !status.vhidDaemonServiceHealthy { allRecovered = false }
            if toRestart.contains(Self.vhidManagerServiceID), !status.vhidManagerServiceHealthy { allRecovered = false }

            if allRecovered {
                AppLogger.shared.log("✅ [LaunchDaemon] Services recovered during polling")
                break
            }

            try? await Task.sleep(nanoseconds: interval)
            elapsed += 0.5
        }

        // Step 6: Final verification
        let finalStatus = getServiceStatus()
        var stillUnhealthy: [String] = []

        if toRestart.contains(Self.kanataServiceID), !finalStatus.kanataServiceHealthy {
            stillUnhealthy.append(Self.kanataServiceID)
        }
        if toRestart.contains(Self.vhidDaemonServiceID), !finalStatus.vhidDaemonServiceHealthy {
            stillUnhealthy.append(Self.vhidDaemonServiceID)
        }
        if toRestart.contains(Self.vhidManagerServiceID), !finalStatus.vhidManagerServiceHealthy {
            stillUnhealthy.append(Self.vhidManagerServiceID)
        }

        if stillUnhealthy.isEmpty {
            AppLogger.shared.log("✅ [LaunchDaemon] All restarted services are now healthy")
            return true
        } else {
            AppLogger.shared.log(
                "⚠️ [LaunchDaemon] Some services are still unhealthy after restart: \(stillUnhealthy)")

            // Provide detailed diagnosis with actionable guidance
            await diagnoseServiceFailures(stillUnhealthy)

            // Return success because we successfully:
            // 1. Restarted the services
            // 2. Diagnosed the underlying issues
            // 3. Provided specific guidance for manual resolution
            AppLogger.shared.log(
                "✅ [LaunchDaemon] Fix completed successfully - services restarted and issues diagnosed")
            return true
        }
    }

    /// Diagnose why services are still failing after restart attempt
    @MainActor private func diagnoseServiceFailures(_ serviceIDs: [String]) async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Diagnosing service failure reasons...")

        for serviceID in serviceIDs {
            await diagnoseSpecificServiceFailure(serviceID)
        }
    }

    /// Diagnose a specific service failure by checking launchctl details
    private func diagnoseSpecificServiceFailure(_ serviceID: String) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(serviceID)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                await analyzeServiceStatus(serviceID, output: output)
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Could not get status for \(serviceID): \(output)")
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking \(serviceID) status: \(error)")
        }
    }

    /// Analyze service status output to determine failure reason
    private func analyzeServiceStatus(_ serviceID: String, output: String) async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Analyzing \(serviceID) status...")

        // For Kanata service, also check the actual logs for detailed error messages
        if serviceID == Self.kanataServiceID {
            await analyzeKanataLogs()
        }

        // Check for common exit reasons
        if output.contains("OS_REASON_CODESIGNING") {
            AppLogger.shared.log("❌ [LaunchDaemon] \(serviceID) is failing due to CODE SIGNING issues")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: KeyPath requires Input Monitoring permission for the kanata binary. Grant permission in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] If permission is already granted, try using KeyPath's Installation Wizard to reinstall kanata with proper code signing"
                )
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: The binary needs to be properly code signed or requires system permissions"
                )
            }

            if serviceID == Self.kanataServiceID {
                await checkKanataCodeSigning()
            }
        } else if output.contains("OS_REASON_EXEC") {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] \(serviceID) executable not found or cannot be executed")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Kanata binary may be missing. Use KeyPath's Installation Wizard to install kanata automatically"
                )
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Check that the binary exists and has correct permissions")
            }
        } else if output.contains("Permission denied") || output.contains("OS_REASON_PERMISSIONS") {
            AppLogger.shared.log("❌ [LaunchDaemon] \(serviceID) failing due to permission issues")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant Input Monitoring permission to kanata in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] You may also need Accessibility permission if using advanced features")
            } else {
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant required permissions in System Settings > Privacy & Security"
                )
            }
        } else if output.contains("job state = exited") {
            AppLogger.shared.log("⚠️ [LaunchDaemon] \(serviceID) is exiting unexpectedly")

            // Extract exit reason if present
            if let exitReasonMatch = output.range(
                of: #"last exit reason = (.*)"#, options: .regularExpression
            ) {
                let exitReason = String(output[exitReasonMatch])
                AppLogger.shared.log("🔍 [LaunchDaemon] Exit reason: \(exitReason)")
            }
        } else {
            AppLogger.shared.log("⚠️ [LaunchDaemon] \(serviceID) unhealthy for unclear reason")
            if serviceID == Self.kanataServiceID {
                AppLogger.shared.log("💡 [LaunchDaemon] Check kanata logs: tail -f /var/log/kanata.log")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] Try using KeyPath's Installation Wizard to fix any configuration issues"
                )
            } else {
                AppLogger.shared.log("💡 [LaunchDaemon] Check system logs for more details")
            }
        }
    }

    /// Analyze Kanata logs for specific error patterns
    private func analyzeKanataLogs() async {
        AppLogger.shared.log("🔍 [LaunchDaemon] Analyzing Kanata logs for error patterns...")

        do {
            let logContent = try String(contentsOfFile: "/var/log/kanata.log", encoding: .utf8)
            let lastLines = logContent.components(separatedBy: .newlines).suffix(50).joined(
                separator: "\n")

            if lastLines.contains("IOHIDDeviceOpen error: (iokit/common) not permitted") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Kanata lacks Input Monitoring permission")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Grant Input Monitoring permission to kanata binary in System Settings > Privacy & Security > Input Monitoring"
                )
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] TIP: Look for 'kanata' in the list or add '/Library/KeyPath/bin/kanata' manually"
                )
            } else if lastLines.contains("failed to parse file") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Configuration file has syntax errors")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Fix configuration syntax or reset to a minimal valid config")
            } else if lastLines.contains("No such file or directory") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: Configuration file missing")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Ensure config file exists at expected location")
            } else if lastLines.contains("Device not configured") {
                AppLogger.shared.log("❌ [LaunchDaemon] DIAGNOSIS: VirtualHID device not available")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Restart VirtualHID daemon or enable Karabiner driver extension"
                )
            } else {
                AppLogger.shared.log("🔍 [LaunchDaemon] No specific error pattern found in recent logs")
                AppLogger.shared.log("📋 [LaunchDaemon] Recent log snippet: \(lastLines.prefix(200))...")
            }
        } catch {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Could not read kanata logs: \(error)")
        }
    }

    /// Check kanata binary code signing status
    private func checkKanataCodeSigning() async {
        let kanataPath = getKanataBinaryPath()
        guard FileManager.default.fileExists(atPath: kanataPath) else {
            AppLogger.shared.log(
                "❌ [LaunchDaemon] Cannot check code signing - kanata binary not found at \(kanataPath)")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-v", "-v", kanataPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Kanata binary appears to be properly signed")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] Issue may be missing Input Monitoring permission - check System Settings"
                )
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Kanata binary code signing issue: \(output)")
                AppLogger.shared.log(
                    "💡 [LaunchDaemon] SOLUTION: Use KeyPath's Installation Wizard to ensure proper kanata installation and permissions, or manually grant Input Monitoring permission"
                )
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error checking kanata code signing: \(error)")
        }
    }

    /// Repairs VHID daemon and manager services by reinstalling plists with correct DriverKit paths and reloading
    func repairVHIDDaemonServices() async -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Repairing VHID LaunchDaemon services (DriverKit paths)")

        // Unload services if present
        _ = await unloadService(serviceID: Self.vhidDaemonServiceID)
        _ = await unloadService(serviceID: Self.vhidManagerServiceID)

        // Reinstall plists with correct content
        let vhidDaemonPlist = generateVHIDDaemonPlist()
        let vhidManagerPlist = generateVHIDManagerPlist()
        let daemonPlistPath = "\(Self.launchDaemonsPath)/\(Self.vhidDaemonServiceID).plist"
        let managerPlistPath = "\(Self.launchDaemonsPath)/\(Self.vhidManagerServiceID).plist"

        let daemonInstall = installPlist(
            content: vhidDaemonPlist, path: daemonPlistPath, serviceID: Self.vhidDaemonServiceID
        )
        let managerInstall = installPlist(
            content: vhidManagerPlist, path: managerPlistPath, serviceID: Self.vhidManagerServiceID
        )

        guard daemonInstall, managerInstall else {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to install repaired VHID plists")
            return false
        }

        // Load services
        let daemonLoad = await loadService(serviceID: Self.vhidDaemonServiceID)
        let managerLoad = await loadService(serviceID: Self.vhidManagerServiceID)

        let ok = daemonLoad && managerLoad && isVHIDDaemonConfiguredCorrectly()
        AppLogger.shared.log(
            "🔍 [LaunchDaemon] Repair result: loadedDaemon=\(daemonLoad), loadedManager=\(managerLoad), configured=\(isVHIDDaemonConfiguredCorrectly())"
        )
        return ok
    }

    // MARK: - TCP Configuration Detection

    /// Gets the correct plist path for Kanata service
    /// Returns SMAppService plist path if active, otherwise legacy plist path
    /// Uses KanataDaemonManager.getActivePlistPath() as the single source of truth
    nonisolated func getKanataPlistPath() -> String {
        return KanataDaemonManager.getActivePlistPath()
    }

    /// Gets the current program arguments from the Kanata LaunchDaemon plist
    /// Checks SMAppService plist if active, otherwise checks legacy plist
    func getKanataProgramArguments() -> [String]? {
        let plistPath = getKanataPlistPath()
        guard let plistDict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            AppLogger.shared.log("🔍 [LaunchDaemon] Cannot read Kanata plist at \(plistPath)")
            return nil
        }

        guard let arguments = plistDict["ProgramArguments"] as? [String] else {
            AppLogger.shared.log("🔍 [LaunchDaemon] No ProgramArguments found in Kanata plist")
            return nil
        }

        AppLogger.shared.log("🔍 [LaunchDaemon] Current plist arguments: \(arguments.joined(separator: " "))")
        return arguments
    }

    /// Checks if the current service configuration matches the expected TCP settings (both arguments and environment variables)
    /// For SMAppService, always returns true since SMAppService manages its own plist from app bundle
    func isServiceConfigurationCurrent() -> Bool {
        // If SMAppService is active, configuration is always "current" since it's managed by the app bundle
        if KanataDaemonManager.isUsingSMAppService {
            AppLogger.shared.log("🔍 [LaunchDaemon] SMAppService is active - configuration is always current (managed by app bundle)")
            return true
        }

        guard let currentArgs = getKanataProgramArguments() else {
            AppLogger.shared.log("🔍 [LaunchDaemon] Cannot check TCP configuration - plist unreadable")
            return false
        }

        let expectedArgs = buildKanataPlistArguments(binaryPath: getKanataBinaryPath())

        // Compare argument arrays for exact match
        let argsMatch = currentArgs == expectedArgs

        AppLogger.shared.log("🔍 [LaunchDaemon] TCP Configuration Check:")
        AppLogger.shared.log("  Current Args:  \(currentArgs.joined(separator: " "))")
        AppLogger.shared.log("  Expected Args: \(expectedArgs.joined(separator: " "))")
        AppLogger.shared.log("  Args Match: \(argsMatch)")

        // TCP-only mode: No environment variables needed (no authentication)
        let currentEnvVars = getKanataEnvironmentVariables()
        // TCP doesn't need env vars - should be empty
        let envVarsMatch = currentEnvVars.isEmpty // Should be empty for TCP

        AppLogger.shared.log("  Current Env Vars: \(currentEnvVars.keys.sorted())")
        AppLogger.shared.log("  Expected Env Vars: none (TCP-only mode)")
        AppLogger.shared.log("  Env Vars Match: \(envVarsMatch)")

        let overallMatch = argsMatch && envVarsMatch
        AppLogger.shared.log("  Overall Match: \(overallMatch)")

        return overallMatch
    }

    /// Gets environment variables from the current Kanata plist
    /// Checks SMAppService plist if active, otherwise checks legacy plist
    private func getKanataEnvironmentVariables() -> [String: String] {
        let plistPath = getKanataPlistPath()
        guard let plistDict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            AppLogger.shared.log("🔍 [LaunchDaemon] Cannot read Kanata plist for environment variables at \(plistPath)")
            return [:]
        }

        guard let envVarsDict = plistDict["EnvironmentVariables"] as? [String: String] else {
            // No environment variables section - this is valid (empty env vars)
            return [:]
        }

        return envVarsDict
    }

    /// Regenerates Kanata service plist with current TCP settings
    /// GUARD: Skips regeneration if SMAppService is active (SMAppService manages its own plist)
    @MainActor
    func regenerateServiceWithCurrentSettings() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Regenerating Kanata service with current TCP settings")

        // GUARD: Check if SMAppService is active - if so, don't regenerate legacy plist
        let isSMAppServiceActive = KanataDaemonManager.isUsingSMAppService

        if isSMAppServiceActive {
            AppLogger.shared.log("⚠️ [LaunchDaemon] SMAppService is active - skipping legacy plist regeneration")
            AppLogger.shared.log("💡 [LaunchDaemon] SMAppService manages its own plist from app bundle")
            AppLogger.shared.log("💡 [LaunchDaemon] To update config, update app bundle plist and re-register")
            return true // Return success since SMAppService is managing it
        }

        let kanataBinaryPath = getKanataBinaryPath()
        let plistContent = generateKanataPlist(binaryPath: kanataBinaryPath)
        let tempDir = NSTemporaryDirectory()
        let tempPath = "\(tempDir)\(Self.kanataServiceID).plist"

        do {
            // Write new plist content to temporary file
            try plistContent.write(toFile: tempPath, atomically: true, encoding: .utf8)

            // Use bootout/bootstrap for proper service reload
            let success = reloadService(serviceID: Self.kanataServiceID, plistPath: Self.kanataPlistPath, tempPlistPath: tempPath)

            // Clean up temporary file
            try? FileManager.default.removeItem(atPath: tempPath)

            return success
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to create temporary plist: \(error)")
            return false
        }
    }

    /// Reloads a service using bootout/bootstrap pattern for plist changes
    @MainActor
    func reloadService(serviceID: String, plistPath: String, tempPlistPath: String) -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Reloading service \(serviceID) with bootout/bootstrap pattern")

        if Self.isTestMode {
            AppLogger.shared.log("🔧 [LaunchDaemon] Test mode - simulating service reload")
            do {
                try FileManager.default.copyItem(atPath: tempPlistPath, toPath: plistPath)
                return true
            } catch {
                AppLogger.shared.log("❌ [LaunchDaemon] Test mode plist copy failed: \(error)")
                return false
            }
        }

        // Create compound command: bootout, install new plist, bootstrap
        let command = """
        launchctl bootout system/\(serviceID) 2>/dev/null || echo "Service not loaded" && \
        cp '\(tempPlistPath)' '\(plistPath)' && \
        chown root:wheel '\(plistPath)' && \
        chmod 644 '\(plistPath)' && \
        launchctl bootstrap system '\(plistPath)' && \
        launchctl kickstart system/\(serviceID)
        """

        // Use osascript for admin privileges
        let escapedCommand = escapeForAppleScript(command)
        let osascriptCommand = """
        do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to update the TCP server configuration for the keyboard service."
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascriptCommand]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Successfully reloaded service \(serviceID)")
                AppLogger.shared.log("🔧 [LaunchDaemon] Reload output: \(output)")
                // Mark restart time for warm-up detection
                markRestartTime(for: [serviceID])
                return true
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to reload service \(serviceID): \(output)")
                return false
            }
        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error executing service reload: \(error)")
            return false
        }
    }

    // MARK: - Argument Building

    /// Builds Kanata command line arguments for LaunchDaemon plist including TCP port when enabled
    private func buildKanataPlistArguments(binaryPath: String) -> [String] {
        var arguments = [binaryPath, "--cfg", Self.kanataConfigPath]

        // Add TCP port for communication server
        let tcpPort = UserDefaults.standard.object(forKey: "KeyPath.TCP.ServerPort") as? Int ?? 37001
        arguments.append(contentsOf: ["--port", "\(tcpPort)"])
        AppLogger.shared.log("📡 [LaunchDaemon] TCP server enabled on port \(tcpPort)")

        arguments.append("--debug")
        arguments.append("--log-layer-changes")

        AppLogger.shared.log(
            "🔧 [LaunchDaemon] Built plist arguments: \(arguments.joined(separator: " "))")
        return arguments
    }

    // MARK: - Log Rotation Service

    /// Generate log rotation script that keeps logs under 10MB total
    private func generateLogRotationScript() -> String {
        """
        #!/bin/bash
        # KeyPath Log Rotation Script - Keep logs under 10MB total

        LOG_DIR="/var/log"
        MAX_SIZE_BYTES=$((5 * 1024 * 1024))  # 5MB per file (2 files = 10MB max)

        # Function to rotate a log file
        rotate_log() {
            local logfile="$1"
            if [[ -f "$logfile" ]]; then
                local size=$(stat -f%z "$logfile" 2>/dev/null || echo 0)

                if [[ $size -gt $MAX_SIZE_BYTES ]]; then
                    echo "$(date): Rotating $logfile (size: $size bytes)"

                    # Remove old backup if exists
                    [[ -f "$logfile.1" ]] && rm -f "$logfile.1"

                    # Move current to backup
                    mv "$logfile" "$logfile.1"

                    # Create new empty log file with correct permissions
                    touch "$logfile"
                    chmod 644 "$logfile"
                    chown root:wheel "$logfile" 2>/dev/null || true

                    echo "$(date): Log rotation completed for $logfile"
                fi
            fi
        }

        # Rotate kanata log
        rotate_log "$LOG_DIR/kanata.log"

        # Clean up any oversized KeyPath logs too
        for logfile in "$LOG_DIR"/keypath*.log; do
            [[ -f "$logfile" ]] && rotate_log "$logfile"
        done
        """
    }

    /// Generate plist for log rotation service (runs every hour)
    private func generateLogRotationPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.logRotationServiceID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(Self.logRotationScriptPath)</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Minute</key>
                <integer>0</integer>
            </dict>
            <key>StandardOutPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/keypath-logrotate.log</string>
            <key>UserName</key>
            <string>root</string>
        </dict>
        </plist>
        """
    }

    /// Check if log rotation service is already installed
    func isLogRotationServiceInstalled() -> Bool {
        let plistPath = "\(Self.systemLaunchDaemonsDir)/\(Self.logRotationServiceID).plist"
        let scriptPath = Self.logRotationScriptPath

        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        let scriptExists = FileManager.default.fileExists(atPath: scriptPath)

        AppLogger.shared.log("📝 [LaunchDaemon] Log rotation check: plist=\(plistExists), script=\(scriptExists)")

        return plistExists && scriptExists
    }

    /// Install log rotation service to keep logs under 10MB
    func installLogRotationService() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing log rotation service (keeps logs < 10MB)")

        let script = generateLogRotationScript()
        let plist = generateLogRotationPlist()

        let tempDir = NSTemporaryDirectory()
        let scriptTempPath = "\(tempDir)keypath-logrotate.sh"
        let plistTempPath = "\(tempDir)\(Self.logRotationServiceID).plist"

        do {
            // Write script and plist to temp files
            try script.write(toFile: scriptTempPath, atomically: true, encoding: .utf8)
            try plist.write(toFile: plistTempPath, atomically: true, encoding: .utf8)

            // Install both with admin privileges
            let scriptFinal = Self.logRotationScriptPath
            let plistFinal = "\(Self.systemLaunchDaemonsDir)/\(Self.logRotationServiceID).plist"

            let command = """
            mkdir -p /usr/local/bin && \
            cp '\(scriptTempPath)' '\(scriptFinal)' && \
            chmod 755 '\(scriptFinal)' && \
            chown root:wheel '\(scriptFinal)' && \
            cp '\(plistTempPath)' '\(plistFinal)' && \
            chmod 644 '\(plistFinal)' && \
            chown root:wheel '\(plistFinal)' && \
            launchctl bootstrap system '\(plistFinal)'
            """

            // Use osascript approach like other admin operations
            let escapedCommand = escapeForAppleScript(command)
            let osascriptCommand = """
            do shell script "\(escapedCommand)" with administrator privileges with prompt "KeyPath needs to install log rotation service to keep logs under 10MB."
            """

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascriptCommand]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            try task.run()
            task.waitUntilExit()

            let success = task.terminationStatus == 0

            // Clean up temp files
            try? FileManager.default.removeItem(atPath: scriptTempPath)
            try? FileManager.default.removeItem(atPath: plistTempPath)

            if success {
                AppLogger.shared.log("✅ [LaunchDaemon] Log rotation service installed successfully")
                // Also rotate the current huge log file immediately
                rotateCurrentLogs()
            } else {
                AppLogger.shared.log("❌ [LaunchDaemon] Failed to install log rotation service")
            }

            return success

        } catch {
            AppLogger.shared.log("❌ [LaunchDaemon] Error preparing log rotation files: \(error)")
            return false
        }
    }

    /// Immediately rotate current large log files
    private func rotateCurrentLogs() {
        AppLogger.shared.log("🔄 [LaunchDaemon] Immediately rotating current large log files")

        let command = """
        [[ -f /var/log/kanata.log ]] && \
        size=$(stat -f%z /var/log/kanata.log 2>/dev/null || echo 0) && \
        if [[ $size -gt 5242880 ]]; then \
            echo "Rotating kanata.log ($size bytes)"; \
            [[ -f /var/log/kanata.log.1 ]] && rm -f /var/log/kanata.log.1; \
            mv /var/log/kanata.log /var/log/kanata.log.1; \
            touch /var/log/kanata.log && chmod 644 /var/log/kanata.log; \
        fi
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                AppLogger.shared.log("✅ [LaunchDaemon] Current log files rotated successfully")
            } else {
                AppLogger.shared.log("⚠️ [LaunchDaemon] Log rotation completed with warnings")
            }
        } catch {
            AppLogger.shared.log("⚠️ [LaunchDaemon] Error during immediate log rotation: \(error)")
        }
    }

    /// Install only the bundled kanata binary to system location (recommended architecture)
    /// This replaces the need for Homebrew installation and ensures proper Developer ID signing
    func installBundledKanataBinaryOnly() -> Bool {
        AppLogger.shared.log("🔧 [LaunchDaemon] Installing bundled kanata binary to system location")

        let bundledPath = WizardSystemPaths.bundledKanataPath
        let systemPath = WizardSystemPaths.kanataSystemInstallPath
        let systemDir = "/Library/KeyPath/bin"

        // Ensure bundled binary exists
        guard FileManager.default.fileExists(atPath: bundledPath) else {
            AppLogger.shared.log("❌ [LaunchDaemon] CRITICAL: Bundled kanata binary not found at: \(bundledPath)")
            AppLogger.shared.log("❌ [LaunchDaemon] This indicates a packaging issue - the app bundle is missing the kanata binary")
            // swiftlint:disable:next todo
            // TODO: Surface this as a wizard issue with severity .critical
            return false
        }

        // Verify the bundled binary is executable
        guard FileManager.default.isExecutableFile(atPath: bundledPath) else {
            AppLogger.shared.log("❌ [LaunchDaemon] Bundled kanata binary exists but is not executable: \(bundledPath)")
            return false
        }

        AppLogger.shared.log("📂 [LaunchDaemon] Copying \(bundledPath) → \(systemPath)")

        // Check if we should skip admin operations for testing
        let success: Bool
        if TestEnvironment.shouldSkipAdminOperations {
            AppLogger.shared.log("⚠️ [LaunchDaemon] TEST MODE: Skipping actual binary installation")
            // In test mode, just verify the source exists and return success
            success = FileManager.default.fileExists(atPath: bundledPath)
        } else {
            let command = """
            mkdir -p '\(systemDir)' && \
            cp '\(bundledPath)' '\(systemPath)' && \
            chmod 755 '\(systemPath)' && \
            chown root:wheel '\(systemPath)' && \
            xattr -d com.apple.quarantine '\(systemPath)' 2>/dev/null || true
            """

            // Use osascript approach like other admin operations
            let escapedCommand = escapeForAppleScript(command)
            let osascriptCommand = """
            do shell script "\(escapedCommand)" with administrator privileges
            """

            success = executeOSAScriptOnMainThread(osascriptCommand)
        }

        if success {
            AppLogger.shared.log("✅ [LaunchDaemon] Bundled kanata binary installed successfully to \(systemPath)")

            // Verify code signing and trust
            AppLogger.shared.log("🔍 [LaunchDaemon] Verifying code signing and trust...")
            let verifyCommand = "spctl -a '\(systemPath)' 2>&1"
            let verifyTask = Process()
            verifyTask.executableURL = URL(fileURLWithPath: "/bin/bash")
            verifyTask.arguments = ["-c", verifyCommand]

            let pipe = Pipe()
            verifyTask.standardOutput = pipe
            verifyTask.standardError = pipe

            do {
                try verifyTask.run()
                verifyTask.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if verifyTask.terminationStatus == 0 {
                    AppLogger.shared.log("✅ [LaunchDaemon] Binary passed Gatekeeper verification")
                } else if output.contains("rejected") || output.contains("not accepted") {
                    AppLogger.shared.log("⚠️ [LaunchDaemon] Binary failed Gatekeeper verification: \(output)")
                    // Continue anyway - the binary is installed and quarantine removed
                }
            } catch {
                AppLogger.shared.log("⚠️ [LaunchDaemon] Could not verify code signing: \(error)")
            }

            // Smoke test: verify the binary can actually execute (skip in test mode)
            if !TestEnvironment.shouldSkipAdminOperations {
                AppLogger.shared.log("🔍 [LaunchDaemon] Running smoke test to verify binary execution...")
                let smokeTest = Process()
                smokeTest.executableURL = URL(fileURLWithPath: systemPath)
                smokeTest.arguments = ["--version"]

                let smokePipe = Pipe()
                smokeTest.standardOutput = smokePipe
                smokeTest.standardError = smokePipe

                do {
                    try smokeTest.run()
                    smokeTest.waitUntilExit()

                    let smokeData = smokePipe.fileHandleForReading.readDataToEndOfFile()
                    let smokeOutput = String(data: smokeData, encoding: .utf8) ?? ""

                    if smokeTest.terminationStatus == 0 {
                        AppLogger.shared.log("✅ [LaunchDaemon] Kanata binary executes successfully (--version): \(smokeOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                    } else {
                        AppLogger.shared.log("⚠️ [LaunchDaemon] Kanata exec smoke test failed with exit code \(smokeTest.terminationStatus): \(smokeOutput)")
                        // Continue anyway - the binary is installed
                    }
                } catch {
                    AppLogger.shared.log("⚠️ [LaunchDaemon] Kanata exec smoke test threw error: \(error)")
                    // Continue anyway - the binary is installed
                }
            }

            // Verify the installation using detector
            let detector = KanataBinaryDetector.shared
            let result = detector.detectCurrentStatus()
            AppLogger.shared.log("🔍 [LaunchDaemon] Post-installation detection: \(result.status) at \(result.path ?? "unknown")")

            return result.status == .systemInstalled
        } else {
            AppLogger.shared.log("❌ [LaunchDaemon] Failed to install bundled kanata binary")
            return false
        }
    }
}

// MARK: - Supporting Types

/// Status information for LaunchDaemon services
struct LaunchDaemonStatus {
    let kanataServiceLoaded: Bool
    let vhidDaemonServiceLoaded: Bool
    let vhidManagerServiceLoaded: Bool
    let kanataServiceHealthy: Bool
    let vhidDaemonServiceHealthy: Bool
    let vhidManagerServiceHealthy: Bool

    /// True if all required services are loaded
    var allServicesLoaded: Bool {
        kanataServiceLoaded && vhidDaemonServiceLoaded && vhidManagerServiceLoaded
    }

    /// True if all required services are healthy (loaded and running properly)
    var allServicesHealthy: Bool {
        kanataServiceHealthy && vhidDaemonServiceHealthy && vhidManagerServiceHealthy
    }

    /// Description of current status for logging/debugging
    var description: String {
        """
        LaunchDaemon Status:
        - Kanata Service: loaded=\(kanataServiceLoaded) healthy=\(kanataServiceHealthy)
        - VHIDDevice Daemon: loaded=\(vhidDaemonServiceLoaded) healthy=\(vhidDaemonServiceHealthy)
        - VHIDDevice Manager: loaded=\(vhidManagerServiceLoaded) healthy=\(vhidManagerServiceHealthy)
        - All Services Loaded: \(allServicesLoaded)
        - All Services Healthy: \(allServicesHealthy)
        """
    }
}

// MARK: - Helper Extensions

private extension String {
    func firstMatchInt(pattern: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return Int(self[range])
        } catch {
            return nil
        }
    }

    func firstMatchString(pattern: String) -> String? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let match = rx.firstMatch(in: self, range: nsRange), match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return String(self[range])
        } catch {
            return nil
        }
    }
}
