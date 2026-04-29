import Foundation
import KeyPathCore

private final class HelperXPCCallCompletionState: @unchecked Sendable {
    private var completed = false
    private let lock = NSLock()

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return false }
        completed = true
        return true
    }
}

extension HelperManager {
    // MARK: - XPC Protocol Wrappers

    /// Get the remote object proxy with a per-call error handler so callers can resume awaits
    func getRemoteProxy(errorHandler: @escaping (Error) -> Void) async throws -> HelperProtocol {
        let connection = try await getConnection()
        guard
            let proxy = connection.remoteObjectProxyWithErrorHandler({ (err: Error) in
                AppLogger.shared.log("❌ [HelperManager] XPC proxy error: \(err.localizedDescription)")

                // Detect signature validation failures (common when app updated but not restarted)
                let nsError = err as NSError
                if nsError.domain == NSCocoaErrorDomain, nsError.code == 4097 {
                    // NSXPCConnectionInterrupted - often caused by signature mismatch
                    AppLogger.shared.log("⚠️ [HelperManager] XPC connection interrupted - this may indicate:")
                    AppLogger.shared.log(
                        "   1. Helper signature validation failed (app updated but not restarted)"
                    )
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
        timeout: TimeInterval = 30.0,
        _ call: @escaping @Sendable (HelperProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) async throws {
        // Detect concurrent XPC calls (indicates a bug in caller logic)
        if activeXPCCalls.contains(name) {
            AppLogger.shared.log("⚠️ [HelperManager] CONCURRENT XPC CALL DETECTED: \(name)")
            AppLogger.shared.log("   → This may cause race conditions or hangs")
            AppLogger.shared.log("   → Active calls: \(activeXPCCalls.joined(separator: ", "))")
        }

        activeXPCCalls.insert(name)
        defer { activeXPCCalls.remove(name) }

        AppLogger.shared.log("📤 [HelperManager] Calling \(name)")

        let proxy = try await getRemoteProxy { _ in }

        // Execute with timeout to prevent infinite hangs when XPC connection is interrupted
        // Use a class with lock for thread-safe completion tracking
        let completionState = HelperXPCCallCompletionState()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Set up timeout
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard completionState.tryComplete() else { return } // Already completed by XPC callback
                AppLogger.shared.log("⏱️ [HelperManager] \(name) timed out after \(Int(timeout))s")
                continuation.resume(throwing: HelperManagerError.operationFailed("XPC call '\(name)' timed out after \(Int(timeout))s"))
            }

            // Execute the XPC call
            call(proxy) { success, errorMessage in
                guard completionState.tryComplete() else { return } // Already timed out

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

    /// Execute an XPC call that returns a value, with the same timeout and duplicate-call guard
    /// used by the void-returning helper operations.
    private func executeValueXPCCall<T: Sendable>(
        _ name: String,
        timeout: TimeInterval = 30.0,
        _ call: @escaping @Sendable (
            HelperProtocol,
            @escaping @Sendable (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
        if activeXPCCalls.contains(name) {
            AppLogger.shared.log("⚠️ [HelperManager] CONCURRENT XPC CALL DETECTED: \(name)")
            AppLogger.shared.log("   → This may cause race conditions or hangs")
            AppLogger.shared.log("   → Active calls: \(activeXPCCalls.joined(separator: ", "))")
        }

        activeXPCCalls.insert(name)
        defer { activeXPCCalls.remove(name) }

        AppLogger.shared.log("📤 [HelperManager] Calling \(name)")

        let completionState = HelperXPCCallCompletionState()

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard completionState.tryComplete() else { return }
                AppLogger.shared.log("⏱️ [HelperManager] \(name) timed out after \(Int(timeout))s")
                continuation.resume(throwing: HelperManagerError.operationFailed("XPC call '\(name)' timed out after \(Int(timeout))s"))
            }

            Task {
                do {
                    let proxy = try await self.getRemoteProxy { error in
                        guard completionState.tryComplete() else { return }
                        continuation.resume(throwing: error)
                    }

                    call(proxy) { result in
                        guard completionState.tryComplete() else { return }

                        switch result {
                        case let .success(value):
                            AppLogger.shared.info("✅ [HelperManager] \(name) succeeded")
                            continuation.resume(returning: value)
                        case let .failure(error):
                            AppLogger.shared.log("❌ [HelperManager] \(name) failed: \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    guard completionState.tryComplete() else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func recoverRequiredRuntimeServices() async throws {
        try await executeXPCCall("recoverRequiredRuntimeServices") { proxy, reply in
            proxy.recoverRequiredRuntimeServices(reply: reply)
        }
    }

    func regenerateServiceConfiguration() async throws {
        try await executeXPCCall("regenerateServiceConfiguration") { proxy, reply in
            proxy.regenerateServiceConfiguration(reply: reply)
        }
    }

    func installNewsyslogConfig() async throws {
        try await executeXPCCall("installNewsyslogConfig") { proxy, reply in
            proxy.installNewsyslogConfig(reply: reply)
        }
    }

    func repairVHIDDaemonServices() async throws {
        try await executeXPCCall("repairVHIDDaemonServices") { proxy, reply in
            proxy.repairVHIDDaemonServices(reply: reply)
        }
    }

    func installRequiredRuntimeServices() async throws {
        try await executeXPCCall("installRequiredRuntimeServices") { proxy, reply in
            proxy.installRequiredRuntimeServices(reply: reply)
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
        let bundledPkgPath = WizardSystemPaths.bundledVHIDDriverPkgPath
        guard WizardSystemPaths.bundledVHIDDriverPkgExists else {
            throw HelperManagerError.operationFailed(
                "Bundled VHID driver package not found at: \(bundledPkgPath)"
            )
        }
        try await installBundledVHIDDriver(pkgPath: bundledPkgPath)
    }

    func installBundledVHIDDriver(pkgPath: String) async throws {
        try await executeXPCCall("installBundledVHIDDriver") { proxy, reply in
            proxy.installBundledVHIDDriver(pkgPath: pkgPath, reply: reply)
        }
    }

    // MARK: - Process Management

    func terminateProcess(_ pid: Int32) async throws {
        try await executeValueXPCCall("terminateProcess") { proxy, reply in
            proxy.terminateProcess(pid) { success, errorMessage in
                if success {
                    reply(.success(()))
                } else {
                    let error = errorMessage ?? "Unknown error"
                    reply(.failure(HelperManagerError.operationFailed(error)))
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

    // MARK: - Uninstall Operations

    /// Uninstall KeyPath completely using the privileged helper
    /// - Parameter deleteConfig: If true, also removes user configuration at ~/.config/keypath
    /// - Throws: HelperManagerError if the operation fails
    func uninstallKeyPath(deleteConfig: Bool) async throws {
        // Use shorter timeout for uninstall - if it hangs, we want to fallback quickly
        try await executeXPCCall("uninstallKeyPath", timeout: 10.0) { proxy, reply in
            proxy.uninstallKeyPath(deleteConfig: deleteConfig, reply: reply)
        }
    }
}
