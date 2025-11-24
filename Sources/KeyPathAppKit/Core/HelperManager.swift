import Darwin
import Foundation
import KeyPathCore
import ServiceManagement

/// Manager for XPC communication with the privileged helper
///
/// This manager handles the XPC connection lifecycle and provides async/await wrappers
/// around the helper's XPC protocol methods.
///
/// Design:
/// - Actor to serialize connection state without @unchecked Sendable.
/// - SMJobBless calls hop to MainActor for Authorization UI safety.
actor HelperManager {
    // MARK: - Helper Health State

    enum HealthState: Equatable {
        case notInstalled
        case requiresApproval(String?)
        case registeredButUnresponsive(String?)
        case healthy(version: String?)
    }

    // MARK: - SMAppService indirection for testability

    // Allows unit tests to inject a fake SMAppService and simulate states like `.notFound`.
    // Default implementation wraps Apple's `SMAppService`.
    nonisolated(unsafe) static var smServiceFactory: (String) -> SMAppServiceProtocol = { plistName in
        NativeSMAppService(wrapped: ServiceManagement.SMAppService.daemon(plistName: plistName))
    }

    nonisolated(unsafe) static var testHelperFunctionalityOverride: (() async -> Bool)?
    nonisolated(unsafe) static var testInstallHelperOverride: (() async throws -> Void)?

    // MARK: - Singleton

    static let shared = HelperManager()

    // MARK: - Properties

    /// XPC connection to the privileged helper
    private var connection: NSXPCConnection?

    /// Mach service name for the helper (type-level constant)
    static let helperMachServiceName = "com.keypath.helper"

    /// Bundle identifier / label for the helper (type-level constant)
    static let helperBundleIdentifier = "com.keypath.helper"

    /// LaunchDaemon plist name packaged inside the app bundle for SMAppService
    static let helperPlistName = "com.keypath.helper.plist"

    /// Expected helper version (should match HelperService.version)
    static let expectedHelperVersion = "1.0.0"

    /// Cached helper version (lazy loaded)
    private var cachedHelperVersion: String?

    /// Active XPC call tracking for detecting concurrency issues
    private var activeXPCCalls: Set<String> = []

    // MARK: - Initialization

    private init() {
        AppLogger.shared.log("🔧 [HelperManager] Initialized")
    }

    deinit {
        // Note: Cannot safely access MainActor-isolated connection from deinit
        // Connection will be invalidated when the XPC connection is deallocated
    }

    // MARK: - Connection Management

    /// Get or create the XPC connection to the helper
    /// - Returns: The active XPC connection
    /// - Throws: HelperError if connection cannot be established
    private func getConnection() throws -> NSXPCConnection {
        // Check if existing connection is still valid
        if let existingConnection = connection {
            // Verify connection is still alive by checking if we can get process identifier
            // If connection is invalidated, processIdentifier will be 0 or connection will be nil
            let pid = existingConnection.processIdentifier
            if pid > 0 {
                // Connection appears valid - but verify helper process is still running
                // This catches cases where helper restarted but connection wasn't invalidated
                if isHelperProcessRunning(pid: pid) {
                    AppLogger.shared.log("♻️ [HelperManager] Reusing existing XPC connection (PID: \(pid))")
                    return existingConnection
                } else {
                    AppLogger.shared.log(
                        "⚠️ [HelperManager] Cached connection points to dead helper process (PID: \(pid)) - clearing"
                    )
                    connection = nil
                }
            } else {
                AppLogger.shared.log("⚠️ [HelperManager] Cached connection has invalid PID - clearing")
                connection = nil
            }
        }

        // Best-effort: verify embedded helper signature/requirement before connecting
        verifyEmbeddedHelperSignature()

        // Create new connection
        AppLogger.shared.log(
            "🔗 [HelperManager] Creating XPC connection to \(Self.helperMachServiceName)")

        let newConnection = NSXPCConnection(
            machServiceName: Self.helperMachServiceName, options: .privileged
        )

        // Set up the interface
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        // Handle connection lifecycle
        newConnection.invalidationHandler = {
            AppLogger.shared.log("❌ [HelperManager] XPC connection invalidated")
            Task { await HelperManager.shared.clearConnection() }
        }

        newConnection.interruptionHandler = {
            AppLogger.shared.log("⚠️ [HelperManager] XPC connection interrupted - will reconnect")
            Task { await HelperManager.shared.clearConnection() }
        }

        // Start the connection
        newConnection.resume()

        connection = newConnection
        AppLogger.shared.info(
            "✅ [HelperManager] XPC connection established (PID: \(newConnection.processIdentifier))")

        return newConnection
    }

    /// Check if helper process is still running
    /// - Parameter pid: Process ID to check
    /// - Returns: true if process exists, false otherwise
    private func isHelperProcessRunning(pid: Int32) -> Bool {
        // Use kill(pid, 0) to check if process exists (doesn't actually kill, just checks)
        // Returns 0 if process exists, -1 with errno set if it doesn't
        // EPERM means process exists but we don't have permission (still means it's running)
        let result = kill(pid, 0)
        if result == 0 {
            return true
        }
        // Check errno - EPERM means process exists but we can't signal it (still running)
        // ESRCH means process doesn't exist
        let error = errno
        return error == EPERM
    }

    /// Close the XPC connection
    func disconnect() {
        AppLogger.shared.log("🔌 [HelperManager] Disconnecting XPC connection")
        connection?.invalidate()
        connection = nil
    }

    func clearConnection() {
        AppLogger.shared.log("🧹 [HelperManager] Clearing XPC connection cache")
        connection?.invalidate()
        connection = nil
        // Clear cached version when connection is cleared (might be stale)
        cachedHelperVersion = nil
    }

    // MARK: - Helper Status

    /// Check if the privileged helper is installed and registered (SMAppService path)
    /// - Returns: true if SMAppService reports `.enabled` OR launchctl has the job
    ///
    /// On macOS 13+, the helper binary remains embedded inside the app bundle and is
    /// invoked via `BundleProgram` in the plist; there is no binary at
    /// `/Library/PrivilegedHelperTools` as with legacy SMJobBless.
    nonisolated func isHelperInstalled() -> Bool {
        let svc = Self.smServiceFactory(Self.helperPlistName)
        if svc.status == .enabled { return true }

        // Best-effort check: does launchd know about the job?
        do {
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["print", "system/\(Self.helperBundleIdentifier)"]
            let out = Pipe()
            p.standardOutput = out
            let err = Pipe()
            p.standardError = err
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let s = String(data: data, encoding: .utf8) ?? ""
                if s.contains("program") || s.contains("state =") || s.contains("pid =") {
                    AppLogger.shared.log(
                        "ℹ️ [HelperManager] launchctl reports helper present while SMAppService status=\(svc.status)"
                    )
                    return true
                }
            }
        } catch {
            // Ignore; treated as not installed
        }
        return false
    }

    /// Get the version of the installed helper
    /// - Returns: Version string, or nil if helper not installed or version check fails
    func getHelperVersion() async -> String? {
        // Return cached version if available
        if let cached = cachedHelperVersion {
            return cached
        }

        // Bypass XPC call in tests
        if TestEnvironment.isRunningTests {
            AppLogger.shared.log("🧪 [HelperManager] Test mode - returning mock version")
            return Self.expectedHelperVersion
        }

        // Query version from helper
        guard isHelperInstalled() else {
            AppLogger.shared.log("⚠️ [HelperManager] Helper not installed, cannot get version")
            return nil
        }

        do {
            let proxy = try getRemoteProxy { _ in /* proxy error handled by timeout path */ }
            return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let sema = DispatchSemaphore(value: 0)
                final class VersionHolder: @unchecked Sendable {
                    var value: String?
                }
                let versionHolder = VersionHolder()
                AppLogger.shared.log("📤 [HelperManager] Calling proxy.getVersion()")
                proxy.getVersion { version, error in
                    let threadName = Thread.current.isMainThread ? "main" : "background"
                    AppLogger.shared.log(
                        "📥 [HelperManager] getVersion callback received on \(threadName) thread")
                    if let version {
                        AppLogger.shared.log("✅ [HelperManager] getVersion callback: version=\(version)")
                        versionHolder.value = version
                    } else {
                        let msg = error ?? "Unknown error"
                        AppLogger.shared.log("❌ [HelperManager] getVersion callback error: \(msg)")
                    }
                    AppLogger.shared.log("📥 [HelperManager] Signaling semaphore")
                    sema.signal()
                }
                AppLogger.shared.log(
                    "📤 [HelperManager] proxy.getVersion() call dispatched, waiting for callback")
                DispatchQueue.global(qos: .utility).async {
                    let waited = sema.wait(timeout: .now() + 3)
                    if waited == .timedOut {
                        AppLogger.shared.log(
                            "⚠️ [HelperManager] getVersion timed out - clearing connection cache")
                        // Clear connection on timeout - it's likely stale
                        Task { await HelperManager.shared.clearConnection() }
                        continuation.resume(returning: nil)
                    } else {
                        if let v = versionHolder.value {
                            AppLogger.shared.info("✅ [HelperManager] Helper version: \(v)")
                            continuation.resume(returning: v)
                        } else {
                            AppLogger.shared.log(
                                "⚠️ [HelperManager] getVersion callback completed but no version received - clearing connection cache"
                            )
                            // Clear connection if callback completed but no version (connection issue)
                            Task { await HelperManager.shared.clearConnection() }
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
        } catch {
            AppLogger.shared.log(
                "❌ [HelperManager] Failed to connect to helper for version check: \(error)")
            return nil
        }
    }

    /// Check if the helper version matches the expected version
    /// - Returns: true if versions match, false otherwise
    func isHelperVersionCompatible() async -> Bool {
        guard let helperVersion = await getHelperVersion() else {
            return false
        }

        let compatible = helperVersion == Self.expectedHelperVersion
        if !compatible {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Version mismatch - expected: \(Self.expectedHelperVersion), got: \(helperVersion)"
            )
        }
        return compatible
    }

    /// Test if the helper is actually functional (can communicate via XPC)
    /// - Returns: true if helper responds to XPC calls, false otherwise
    ///
    /// **Use Case:** This is the definitive test for helper functionality.
    /// - Returns true ONLY if XPC connection succeeds AND helper responds
    /// - Returns false for phantom registrations, connection failures, timeouts
    /// - Should be used by wizard to verify helper is truly working
    func testHelperFunctionality() async -> Bool {
        if let override = Self.testHelperFunctionalityOverride {
            return await override()
        }
        AppLogger.shared.log("🧪 [HelperManager] Testing helper functionality via XPC ping")

        // Pre-flight check: Must be installed first
        guard isHelperInstalled() else {
            AppLogger.shared.log("❌ [HelperManager] Functionality test failed: Not installed")
            return false
        }

        // Test actual XPC communication by getting version
        // This tests: XPC connection, helper process, message handling
        guard let version = await getHelperVersion() else {
            AppLogger.shared.log("❌ [HelperManager] Functionality test failed: XPC communication failed")
            return false
        }

        AppLogger.shared.info(
            "✅ [HelperManager] Functionality test passed: Helper v\(version) responding")
        return true
    }

    // MARK: - Diagnostics

    nonisolated func runBlessDiagnostics() -> String {
        let report = BlessDiagnostics.run()
        return report.summarizedText()
    }

    // MARK: - Helper log surface (for UX when XPC fails)

    /// Fetch the last N helper log messages (message text only)
    /// Uses `log show` with a tight window to avoid heavy queries.
    nonisolated func lastHelperLogs(count: Int = 3, windowSeconds: Int = 300) -> [String] {
        // First: if launchctl has no record of the job, surface that clearly.
        do {
            let p = Process()
            p.launchPath = "/bin/launchctl"
            p.arguments = ["print", "system/com.keypath.helper"]
            let out = Pipe()
            p.standardOutput = out
            let err = Pipe()
            p.standardError = err
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                if errStr.contains("Could not find service") || errStr.contains("Bad request") {
                    return [
                        "Helper not registered: launchctl has no job 'system/com.keypath.helper'",
                        "Click ‘Install Helper’, then Test XPC again."
                    ]
                }
            }
        } catch {
            // Ignore; fall through to unified-log path
        }
        func fetch(_ seconds: Int) -> [String] {
            let p = Process()
            p.launchPath = "/usr/bin/log"
            p.arguments = [
                "show",
                "--last", "\(seconds)s",
                "--style", "syslog",
                "--predicate",
                "process == 'KeyPathHelper' OR processImagePath CONTAINS[c] 'KeyPathHelper'"
            ]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do { try p.run() } catch { return [] }
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return [] }
            return s.split(separator: "\n").map(String.init)
        }
        // Try progressively larger windows
        let windows = [max(60, windowSeconds), 1800, 86400]
        var collected: [String] = []
        for w in windows {
            let lines = fetch(w)
            // Extract message part after the first ': '
            let messages = lines.compactMap { line -> String? in
                guard let range = line.range(of: ": ") else { return nil }
                let msg = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return msg.isEmpty ? nil : msg
            }
            collected.append(contentsOf: messages)
            if collected.count >= count { break }
        }
        if !collected.isEmpty {
            return Array(collected.suffix(count))
        }
        // Fallback: check file logs if present
        let fileCandidates = [
            "/var/log/com.keypath.helper.stdout.log",
            "/var/log/com.keypath.helper.stderr.log"
        ]
        for path in fileCandidates {
            if FileManager.default.fileExists(atPath: path),
               let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) {
                let data = try? handle.readToEnd()
                let s = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let lines = s.split(separator: "\n").map(String.init)
                if !lines.isEmpty { return Array(lines.suffix(count)) }
            }
        }
        return []
    }

    /// Check if helper needs upgrade (installed but wrong version)
    /// - Returns: true if upgrade needed, false otherwise
    func needsHelperUpgrade() async -> Bool {
        guard isHelperInstalled() else {
            return false // Not installed, not an upgrade case
        }

        return await !isHelperVersionCompatible()
    }

    // MARK: - Helper Installation

    /// Install the privileged helper using SMJobBless
    /// - Throws: HelperManagerError if installation fails
    func installHelper() async throws {
        if let override = Self.testInstallHelperOverride {
            try await override()
            return
        }
        AppLogger.shared.log("🔧 [HelperManager] Registering privileged helper via SMAppService")
        guard #available(macOS 13, *) else {
            throw HelperManagerError.installationFailed("Requires macOS 13+ for SMAppService")
        }

        // Diagnostic logging
        if let bundlePath = Bundle.main.bundlePath as String? {
            AppLogger.shared.log("📦 [HelperManager] App bundle: \(bundlePath)")
            let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
            if let infoDict = NSDictionary(contentsOfFile: infoPlistPath) {
                let hasSMPrivileged = infoDict["SMPrivilegedExecutables"] != nil
                AppLogger.shared.log(
                    "📋 [HelperManager] Info.plist has SMPrivilegedExecutables: \(hasSMPrivileged)")
            } else {
                AppLogger.shared.log("⚠️ [HelperManager] Could not read Info.plist")
            }
        }

        let svc = Self.smServiceFactory(Self.helperPlistName)
        AppLogger.shared.log(
            "🔍 [HelperManager] SMAppService status: \(svc.status.rawValue) (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)"
        )
        switch svc.status {
        case .enabled:
            // Enabled means the app has background-item approval, not necessarily that
            // the daemon is registered. Attempt an idempotent register to ensure the
            // system copies are installed. Treat enabled-after-call as success.
            do {
                try svc.register()
                AppLogger.shared.info("✅ [HelperManager] Helper registered (was Enabled prior)")
                return
            } catch {
                if svc.status == .enabled {
                    AppLogger.shared.log("ℹ️ [HelperManager] Helper already Enabled; proceeding")
                    return
                }
                throw HelperManagerError.installationFailed(
                    "SMAppService register (enabled path) failed: \(error.localizedDescription)")
            }
        case .requiresApproval:
            throw HelperManagerError.installationFailed(
                "Approval required in System Settings → Login Items.")
        case .notRegistered:
            do {
                try svc.register()
                AppLogger.shared.info("✅ [HelperManager] Helper registered (status: \(svc.status))")
                return
            } catch {
                // If another thread already registered or approval raced, treat Enabled as success
                if svc.status == .enabled {
                    AppLogger.shared.info(
                        "✅ [HelperManager] Helper became Enabled during registration race; treating as success")
                    return
                }
                if svc.status == .requiresApproval {
                    throw HelperManagerError.installationFailed(
                        "Approval required in System Settings → Login Items.")
                }
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(error.localizedDescription)")
            }
        case .notFound:
            // .notFound means the system hasn't seen the helper yet, but registration might still work
            // Try to register to get the actual error message
            AppLogger.shared.log(
                "⚠️ [HelperManager] Helper status is .notFound - attempting registration anyway to get detailed error"
            )
            do {
                try svc.register()
                AppLogger.shared.info(
                    "✅ [HelperManager] Helper registered successfully despite initial .notFound status")
                return
            } catch {
                // Now we have the real error from SMAppService
                let detail = HelperManager.formatSMError(error)
                AppLogger.shared.log("❌ [HelperManager] Registration failed with detailed error: \(detail)")
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(detail)")
            }
        @unknown default:
            do {
                try svc.register()
                return
            } catch {
                throw HelperManagerError.installationFailed(
                    "SMAppService register failed: \(error.localizedDescription)")
            }
        }
    }

    /// Uninstall the privileged helper
    /// - Throws: HelperManagerError if uninstallation fails
    func uninstallHelper() async throws {
        AppLogger.shared.log("🗑️ [HelperManager] Unregistering privileged helper via SMAppService")
        guard #available(macOS 13, *) else {
            throw HelperManagerError.operationFailed("Requires macOS 13+ for SMAppService")
        }
        let svc = Self.smServiceFactory(Self.helperPlistName)
        do { try await svc.unregister() } catch {
            throw HelperManagerError.operationFailed(
                "SMAppService unregister failed: \(error.localizedDescription)")
        }
    }

    /// Determine helper health state using SMAppService, launchctl, and XPC
    func getHelperHealth() async -> HealthState {
        let svc = Self.smServiceFactory(Self.helperPlistName)
        let smStatus = svc.status

        // Approval explicitly required
        if smStatus == .requiresApproval {
            return .requiresApproval("Approval required in System Settings → Login Items.")
        }

        let installed = isHelperInstalled()
        if !installed {
            return .notInstalled
        }

        // Fast path: if XPC responds, we are healthy
        if let version = await getHelperVersion(), await testHelperFunctionality() {
            return .healthy(version: version)
        }

        // Installed but XPC failing
        return .registeredButUnresponsive("Helper registered but XPC communication failed")
    }

    // MARK: - Error helpers

    static func formatSMError(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = []
        parts.append(ns.localizedDescription)
        parts.append("[\(ns.domain):\(ns.code)]")
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain):\(underlying.code) \(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - XPC Protocol Wrappers

    /// Get the remote object proxy with a per-call error handler so callers can resume awaits
    private func getRemoteProxy(errorHandler: @escaping (Error) -> Void) throws -> HelperProtocol {
        let connection = try getConnection()
        guard
            let proxy = connection.remoteObjectProxyWithErrorHandler({ err in
                AppLogger.shared.log("❌ [HelperManager] XPC proxy error: \(err.localizedDescription)")

                // Detect signature validation failures (common when app updated but not restarted)
                let nsError = err as NSError
                if nsError.domain == NSCocoaErrorDomain, nsError.code == 4097 {
                    // NSXPCConnectionInterrupted - often caused by signature mismatch
                    AppLogger.shared.log("⚠️ [HelperManager] XPC connection interrupted - this may indicate:")
                    AppLogger.shared.log(
                        "   1. Helper signature validation failed (app updated but not restarted)")
                    AppLogger.shared.log("   2. Helper process crashed")
                    AppLogger.shared.log("   3. Helper was killed by the system")
                    AppLogger.shared.log("💡 If you just updated KeyPath, try restarting the app")
                } else if nsError.code == -67050 {
                    // errSecCSReqFailed - explicit signature validation failure
                    AppLogger.shared.log("❌ [HelperManager] SIGNATURE VALIDATION FAILED (errSecCSReqFailed)")
                    AppLogger.shared.log("   → Running app signature doesn't match helper's requirements")
                    AppLogger.shared.log("   → This happens when app is updated but not restarted")
                    AppLogger.shared.log("💡 SOLUTION: Restart KeyPath to load the new signature")

                    // Try to trigger signature health check alert
                    Task { @MainActor in
                        SignatureHealthCheck.showRestartAlertIfNeeded()
                    }
                }

                errorHandler(err)
            }) as? HelperProtocol
        else {
            throw HelperManagerError.connectionFailed("Failed to create remote proxy")
        }
        return proxy
    }

    /// Execute an XPC call with async/await conversion
    /// - Parameters:
    ///   - name: Operation name for logging
    ///   - call: The XPC call to execute
    /// - Throws: HelperError if the operation fails
    private func executeXPCCall(
        _ name: String,
        _ call: @escaping @Sendable (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) async throws {
        // Detect concurrent XPC calls (indicates a bug in caller logic)
        if activeXPCCalls.contains(name) {
            AppLogger.shared.log("⚠️ [HelperManager] CONCURRENT XPC CALL DETECTED: \(name)")
            AppLogger.shared.log("   → This may cause race conditions or hangs")
            AppLogger.shared.log("   → Active calls: \(activeXPCCalls.joined(separator: ", "))")
            assertionFailure("Concurrent XPC call to \(name) - check caller logic")
        }

        activeXPCCalls.insert(name)
        defer { activeXPCCalls.remove(name) }

        AppLogger.shared.log("📤 [HelperManager] Calling \(name)")

        let proxy = try getRemoteProxy { _ in }

        return try await withCheckedThrowingContinuation { continuation in
            call(proxy) { success, errorMessage in
                if success {
                    AppLogger.shared.info("✅ [HelperManager] \(name) succeeded")
                    continuation.resume()
                } else {
                    let error = errorMessage ?? "Unknown error"
                    AppLogger.shared.log("❌ [HelperManager] \(name) failed: \(error)")
                    continuation.resume(throwing: HelperManagerError.operationFailed(error))
                }
            }
        }
    }

    // MARK: - LaunchDaemon Operations

    func installLaunchDaemon(plistPath: String, serviceID: String) async throws {
        try await executeXPCCall("installLaunchDaemon") { proxy, reply in
            proxy.installLaunchDaemon(plistPath: plistPath, serviceID: serviceID, reply: reply)
        }
    }

    func restartUnhealthyServices() async throws {
        try await executeXPCCall("restartUnhealthyServices") { proxy, reply in
            proxy.restartUnhealthyServices(reply: reply)
        }
    }

    func regenerateServiceConfiguration() async throws {
        try await executeXPCCall("regenerateServiceConfiguration") { proxy, reply in
            proxy.regenerateServiceConfiguration(reply: reply)
        }
    }

    func installLogRotation() async throws {
        try await executeXPCCall("installLogRotation") { proxy, reply in
            proxy.installLogRotation(reply: reply)
        }
    }

    func repairVHIDDaemonServices() async throws {
        try await executeXPCCall("repairVHIDDaemonServices") { proxy, reply in
            proxy.repairVHIDDaemonServices(reply: reply)
        }
    }

    func installLaunchDaemonServicesWithoutLoading() async throws {
        try await executeXPCCall("installLaunchDaemonServicesWithoutLoading") { proxy, reply in
            proxy.installLaunchDaemonServicesWithoutLoading(reply: reply)
        }
    }

    // MARK: - VirtualHID Operations

    func activateVirtualHIDManager() async throws {
        try await executeXPCCall("activateVirtualHIDManager") { proxy, reply in
            proxy.activateVirtualHIDManager(reply: reply)
        }
    }

    func uninstallVirtualHIDDrivers() async throws {
        try await executeXPCCall("uninstallVirtualHIDDrivers") { proxy, reply in
            proxy.uninstallVirtualHIDDrivers(reply: reply)
        }
    }

    func installVirtualHIDDriver(version: String, downloadURL: String) async throws {
        try await executeXPCCall("installVirtualHIDDriver") { proxy, reply in
            proxy.installVirtualHIDDriver(version: version, downloadURL: downloadURL, reply: reply)
        }
    }

    func downloadAndInstallCorrectVHIDDriver() async throws {
        try await executeXPCCall("downloadAndInstallCorrectVHIDDriver") { proxy, reply in
            proxy.downloadAndInstallCorrectVHIDDriver(reply: reply)
        }
    }

    // MARK: - Process Management

    func terminateProcess(_ pid: Int32) async throws {
        AppLogger.shared.log("📤 [HelperManager] Calling terminateProcess(\(pid))")

        let proxy = try getRemoteProxy { _ in }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.terminateProcess(pid) { success, errorMessage in
                if success {
                    AppLogger.shared.info("✅ [HelperManager] terminateProcess succeeded")
                    continuation.resume()
                } else {
                    let error = errorMessage ?? "Unknown error"
                    AppLogger.shared.log("❌ [HelperManager] terminateProcess failed: \(error)")
                    continuation.resume(throwing: HelperManagerError.operationFailed(error))
                }
            }
        }
    }

    func killAllKanataProcesses() async throws {
        try await executeXPCCall("killAllKanataProcesses") { proxy, reply in
            proxy.killAllKanataProcesses(reply: reply)
        }
    }

    func restartKarabinerDaemon() async throws {
        try await executeXPCCall("restartKarabinerDaemon") { proxy, reply in
            proxy.restartKarabinerDaemon(reply: reply)
        }
    }

    func disableKarabinerGrabber() async throws {
        try await executeXPCCall("disableKarabinerGrabber") { proxy, reply in
            proxy.disableKarabinerGrabber(reply: reply)
        }
    }

    // Note: executeCommand removed for security. Use explicit operations only.

    // MARK: - Bundled Kanata Installation

    func installBundledKanataBinaryOnly() async throws {
        try await executeXPCCall("installBundledKanataBinaryOnly") { proxy, reply in
            proxy.installBundledKanataBinaryOnly(reply: reply)
        }
    }
}

// MARK: - Helper signature verification (best-effort warnings only)

extension HelperManager {
    /// Verify the embedded helper's designated requirement roughly matches expectations.
    /// Logs warnings on mismatch; does not block connection (to avoid false positives during dev).
    private nonisolated func verifyEmbeddedHelperSignature() {
        let fm = FileManager.default
        // Use the production app path (like SignatureHealthCheck does)
        // Bundle.main.bundlePath can be wrong when launched via Xcode tools
        let bundlePath = "/Applications/KeyPath.app"
        let helperPath = bundlePath + "/Contents/Library/HelperTools/KeyPathHelper"
        guard fm.fileExists(atPath: helperPath) else {
            AppLogger.shared.log("⚠️ [HelperManager] Embedded helper not found at \(helperPath)")
            AppLogger.shared.log("   Bundle.main.bundlePath = \(Bundle.main.bundlePath)")
            return
        }

        // Extract designated requirement using codesign
        let cs = Process()
        cs.launchPath = "/usr/bin/codesign"
        cs.arguments = ["-d", "-r-", helperPath]
        let out = Pipe()
        let err = Pipe()
        cs.standardOutput = out
        cs.standardError = err
        do { try cs.run() } catch {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Could not run codesign: \(error.localizedDescription)")
            return
        }
        cs.waitUntilExit()
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = outStr + "\n" + errStr
        guard
            let req = combined.components(separatedBy: "designated =>").last?.trimmingCharacters(
                in: .whitespacesAndNewlines), !req.isEmpty
        else {
            AppLogger.shared.log("⚠️ [HelperManager] Could not parse helper designated requirement")
            return
        }

        // Minimal checks
        var warnings: [String] = []
        if !req.contains("identifier \"com.keypath.helper\"") {
            warnings.append("missing identifier 'com.keypath.helper'")
        }
        if !req.contains("1.2.840.113635.100.6.2.6") { // Developer ID CA
            warnings.append("missing Developer ID CA marker")
        }
        if !req.contains("1.2.840.113635.100.6.1.13") { // Developer ID Application
            warnings.append("missing Developer ID Application marker")
        }

        // Compare with SMPrivilegedExecutables requirement (if present)
        var plistRequirement: String?
        if let info = NSDictionary(contentsOfFile: bundlePath + "/Contents/Info.plist"),
           let sm = (info["SMPrivilegedExecutables"] as? NSDictionary)?[Self.helperBundleIdentifier]
           as? String {
            plistRequirement = sm
            if !req.contains("com.keypath.helper") {
                warnings.append(
                    "helper req does not show expected identifier, while Info.plist declares it")
            }
        }

        if warnings.isEmpty {
            AppLogger.shared.log("🔒 [HelperManager] Embedded helper signature looks valid")
        } else {
            AppLogger.shared.log(
                "⚠️ [HelperManager] Embedded helper signature warnings: \(warnings.joined(separator: "; "))")
            if let plistRequirement {
                AppLogger.shared.log(
                    "ℹ️ [HelperManager] App Info.plist SMPrivilegedExecutables[\(Self.helperBundleIdentifier)] = \(plistRequirement)"
                )
            }
            AppLogger.shared.log("ℹ️ [HelperManager] codesign designated => \(req)")
        }
    }
}

// MARK: - SMAppService test seam

protocol SMAppServiceProtocol {
    var status: ServiceManagement.SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

struct NativeSMAppService: SMAppServiceProtocol {
    private let wrapped: ServiceManagement.SMAppService
    init(wrapped: ServiceManagement.SMAppService) { self.wrapped = wrapped }
    var status: ServiceManagement.SMAppService.Status { wrapped.status }
    func register() throws { try wrapped.register() }
    func unregister() async throws { if #available(macOS 13, *) { try await wrapped.unregister() } }
}

// MARK: - Error Types

/// Errors that can occur in HelperManager
enum HelperManagerError: Error, LocalizedError {
    case notInstalled
    case connectionFailed(String)
    case operationFailed(String)
    case installationFailed(String)
    case signatureMismatch

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Privileged helper is not installed"
        case let .connectionFailed(reason):
            "Failed to connect to helper: \(reason)"
        case let .operationFailed(reason):
            "Helper operation failed: \(reason)"
        case let .installationFailed(reason):
            "Failed to install helper: \(reason)"
        case .signatureMismatch:
            "App signature mismatch - restart required"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .signatureMismatch:
            "KeyPath was recently updated. Please restart the app to load the new version."
        case .connectionFailed:
            "Try restarting KeyPath. If the problem persists, reinstall the app."
        case .notInstalled:
            "Run the installation wizard to set up KeyPath."
        case .operationFailed, .installationFailed:
            "Check the logs for more details. You may need to restart KeyPath."
        }
    }
}
