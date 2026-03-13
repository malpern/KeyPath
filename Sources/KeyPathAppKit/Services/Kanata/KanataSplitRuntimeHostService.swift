import Foundation
import KeyPathCore

@MainActor
struct KanataSplitRuntimeHostLaunchReport: Sendable, Equatable {
    let exitCode: Int32
    let stderr: String
    let launcherPath: String
    let sessionID: String
    let socketPath: String
}

@MainActor
struct KanataSplitRuntimeCompanionRecoveryResult: Sendable, Equatable {
    let companionRunningAfterRestart: Bool
    let recoveredHostPID: pid_t?
}

enum SplitRuntimeIdentity {
    static let hostTitle = "Split Runtime Host"
    static let hostDetailPrefix = "Bundled user-session host active"
}

enum KanataSplitRuntimeHostExitInfo {
    static let pidUserInfoKey = "pid"
    static let exitCodeUserInfoKey = "exitCode"
    static let terminationReasonUserInfoKey = "terminationReason"
    static let expectedUserInfoKey = "expected"
    static let stderrLogPathUserInfoKey = "stderrLogPath"
}

@MainActor
public final class KanataSplitRuntimeHostService {
    static let shared = KanataSplitRuntimeHostService()

    #if DEBUG
        nonisolated(unsafe) static var testPersistentHostPID: pid_t?
        nonisolated(unsafe) static var testStartPersistentError: Error?
    #endif

    private static let inProcessRuntimeEnvKey = "KEYPATH_EXPERIMENTAL_HOST_RUNTIME"
    private static let passthruRuntimeEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_RUNTIME"
    private static let passthruForwardEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_FORWARD"
    private static let passthruOnlyEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_ONLY"
    private static let passthruInjectEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_INJECT"
    private static let passthruCaptureEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_CAPTURE"
    private static let passthruPersistEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_PERSIST"
    private static let passthruPollEnvKey = "KEYPATH_EXPERIMENTAL_HOST_PASSTHRU_POLL_MS"

    private let companionManager: KanataOutputBridgeCompanionManager
    private var activeHostProcess: Process?
    private var expectedPersistentHostTermination = false
    private var activePersistentHostIncludesCapture = true
    private var activePersistentHostPollMilliseconds = 1000

    init(companionManager: KanataOutputBridgeCompanionManager = .shared) {
        self.companionManager = companionManager
    }

    private actor ProcessExitLatch {
        private var didExit = false
        private var continuation: CheckedContinuation<Void, Never>?

        func markExited() {
            didExit = true
            continuation?.resume()
            continuation = nil
        }

        func wait() async {
            if didExit {
                return
            }

            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    private func waitForPersistentHostExit(
        process: Process,
        timeoutSeconds: TimeInterval = 5
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func launcherArguments(configPath: String) -> [String] {
        [
            "--cfg",
            configPath,
            "--port",
            "\(PreferencesService.shared.tcpServerPort)",
            "--log-layer-changes"
        ]
    }

    private func buildPassthruEnvironment(
        session: KanataOutputBridgeSession,
        includeCapture: Bool,
        pollMilliseconds: Int,
        persist: Bool
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[KanataRuntimePathCoordinator.experimentalOutputBridgeSessionEnvKey] = session.sessionID
        environment[KanataRuntimePathCoordinator.experimentalOutputBridgeSocketEnvKey] = session.socketPath
        environment[Self.inProcessRuntimeEnvKey] = "1"
        environment[Self.passthruRuntimeEnvKey] = "1"
        environment[Self.passthruForwardEnvKey] = "1"
        environment[Self.passthruOnlyEnvKey] = "1"
        if persist {
            environment[Self.passthruPersistEnvKey] = "1"
        } else {
            environment.removeValue(forKey: Self.passthruPersistEnvKey)
        }
        if includeCapture {
            environment[Self.passthruCaptureEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruInjectEnvKey)
        } else {
            environment[Self.passthruInjectEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruCaptureEnvKey)
        }
        environment[Self.passthruPollEnvKey] = "\(pollMilliseconds)"
        environment["HOME"] = NSHomeDirectory()
        return environment
    }

    public var isPersistentPassthruHostRunning: Bool {
        #if DEBUG
            if TestEnvironment.isRunningTests, let testPersistentHostPID = Self.testPersistentHostPID {
                return testPersistentHostPID > 0
            }
        #endif
        return activeHostProcess?.isRunning == true
    }

    // Int instead of pid_t for Sendable compatibility across module boundary
    public var activePersistentHostPID: Int? {
        #if DEBUG
            if TestEnvironment.isRunningTests,
               let testPersistentHostPID = Self.testPersistentHostPID,
               testPersistentHostPID > 0
            {
                return Int(testPersistentHostPID)
            }
        #endif
        guard activeHostProcess?.isRunning == true else { return nil }
        return activeHostProcess.map { Int($0.processIdentifier) }
    }

    func launchPassthruHost(
        includeCapture: Bool,
        timeout: TimeInterval = 8,
        pollMilliseconds: Int = 1000
    ) async throws -> KanataSplitRuntimeHostLaunchReport {
        let runtimeHost = KanataRuntimeHost.current()
        let launcherPath = runtimeHost.launcherPath
        let configPath = KeyPathConstants.Config.mainConfigPath

        AppLogger.shared.info("🧪 [HostService] Preparing split-runtime host environment")
        let session = try await companionManager.prepareEnvironmentAndPersist(hostPID: getpid())
        AppLogger.shared.info(
            "🧪 [HostService] Prepared split-runtime host environment session=\(session.sessionID) socket=\(session.socketPath)"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launcherPath)
        process.arguments = launcherArguments(configPath: configPath)
        process.environment = buildPassthruEnvironment(
            session: session,
            includeCapture: includeCapture,
            pollMilliseconds: pollMilliseconds,
            persist: false
        )
        process.currentDirectoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)

        let stderrLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-host-passthru-child-stderr.log")
        Foundation.FileManager().createFile(atPath: stderrLogURL.path, contents: Data())
        let stderrHandle = try FileHandle(forWritingTo: stderrLogURL)
        process.standardError = stderrHandle
        process.standardOutput = Pipe()
        let exitLatch = ProcessExitLatch()
        process.terminationHandler = { _ in
            Task {
                await exitLatch.markExited()
            }
        }

        AppLogger.shared.info("🧪 [HostService] Launching split-runtime host child: \(launcherPath)")
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        if process.isRunning {
            AppLogger.shared.warn("⚠️ [HostService] Split-runtime host child exceeded timeout; terminating")
            process.terminate()
            try await Task.sleep(for: .milliseconds(200))
            if process.isRunning {
                process.interrupt()
                try await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning {
                AppLogger.shared.warn("⚠️ [HostService] Split-runtime host child ignored terminate/interrupt; sending SIGKILL")
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        await exitLatch.wait()
        try? stderrHandle.close()
        let terminationReason = switch process.terminationReason {
        case .exit:
            "exit"
        case .uncaughtSignal:
            "uncaughtSignal"
        @unknown default:
            "unknown"
        }
        AppLogger.shared.info(
            "🧪 [HostService] Split-runtime host child exited with code \(process.terminationStatus) reason=\(terminationReason)"
        )

        let stderrData = (try? Data(contentsOf: stderrLogURL)) ?? Data()
        let stderr = String(decoding: stderrData, as: UTF8.self)
        if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.shared.info(
                "🧪 [HostService] Split-runtime host child stderr was empty (file: \(stderrLogURL.path))"
            )
        } else {
            AppLogger.shared.info(
                "🧪 [HostService] Split-runtime host child stderr from \(stderrLogURL.path):\n\(stderr)"
            )
        }

        return KanataSplitRuntimeHostLaunchReport(
            exitCode: process.terminationStatus,
            stderr: stderr,
            launcherPath: launcherPath,
            sessionID: session.sessionID,
            socketPath: session.socketPath
        )
    }

    func startPersistentPassthruHost(
        includeCapture: Bool,
        pollMilliseconds: Int = 1000
    ) async throws -> pid_t {
        #if DEBUG
            if TestEnvironment.isRunningTests {
                if let testStartPersistentError = Self.testStartPersistentError {
                    throw testStartPersistentError
                }
                if let testPersistentHostPID = Self.testPersistentHostPID, testPersistentHostPID > 0 {
                    return testPersistentHostPID
                }
                let pid: pid_t = 4242
                Self.testPersistentHostPID = pid
                return pid
            }
        #endif
        if let activeHostProcess, activeHostProcess.isRunning {
            return activeHostProcess.processIdentifier
        }

        // Kill orphaned kanata-launcher processes from a previous app instance.
        // After build.sh deploys, the old app's child kanata-launcher survives and
        // holds the TCP port, causing the new instance to crash with SIGABRT.
        await killOrphanedKanataLaunchers()

        let runtimeHost = KanataRuntimeHost.current()
        let launcherPath = runtimeHost.launcherPath
        let configPath = KeyPathConstants.Config.mainConfigPath
        let session = try await companionManager.prepareEnvironmentAndPersist(hostPID: getpid())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launcherPath)
        process.arguments = launcherArguments(configPath: configPath)
        process.environment = buildPassthruEnvironment(
            session: session,
            includeCapture: includeCapture,
            pollMilliseconds: pollMilliseconds,
            persist: true
        )
        process.currentDirectoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)

        let stderrLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-host-passthru-live-stderr.log")
        Foundation.FileManager().createFile(atPath: stderrLogURL.path, contents: Data())
        process.standardError = try FileHandle(forWritingTo: stderrLogURL)
        process.standardOutput = Pipe()
        expectedPersistentHostTermination = false
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                let expected = self.expectedPersistentHostTermination
                let terminationReason = switch process.terminationReason {
                case .exit:
                    "exit"
                case .uncaughtSignal:
                    "uncaughtSignal"
                @unknown default:
                    "unknown"
                }

                Foundation.NotificationCenter.default.post(
                    name: .splitRuntimeHostExited,
                    object: nil,
                    userInfo: [
                        KanataSplitRuntimeHostExitInfo.pidUserInfoKey: process.processIdentifier,
                        KanataSplitRuntimeHostExitInfo.exitCodeUserInfoKey: process.terminationStatus,
                        KanataSplitRuntimeHostExitInfo.terminationReasonUserInfoKey: terminationReason,
                        KanataSplitRuntimeHostExitInfo.expectedUserInfoKey: expected,
                        KanataSplitRuntimeHostExitInfo.stderrLogPathUserInfoKey: stderrLogURL.path
                    ]
                )

                if self.activeHostProcess?.processIdentifier == process.processIdentifier {
                    self.activeHostProcess = nil
                }
                self.expectedPersistentHostTermination = false
            }
        }

        AppLogger.shared.info(
            "🧪 [HostService] Starting persistent split-runtime host child: \(launcherPath) session=\(session.sessionID)"
        )
        try process.run()
        activeHostProcess = process
        activePersistentHostIncludesCapture = includeCapture
        activePersistentHostPollMilliseconds = pollMilliseconds
        return process.processIdentifier
    }

    func restartPersistentPassthruHostAfterCompanionRestart() async throws -> pid_t? {
        #if DEBUG
            if TestEnvironment.isRunningTests {
                guard let testPersistentHostPID = Self.testPersistentHostPID, testPersistentHostPID > 0 else {
                    return nil
                }
                if let testStartPersistentError = Self.testStartPersistentError {
                    throw testStartPersistentError
                }
                return testPersistentHostPID
            }
        #endif

        guard isPersistentPassthruHostRunning else {
            return nil
        }

        let includeCapture = activePersistentHostIncludesCapture
        let pollMilliseconds = activePersistentHostPollMilliseconds

        AppLogger.shared.info(
            "🧪 [HostService] Restarting persistent split-runtime host after output bridge companion restart"
        )
        let priorProcess = activeHostProcess
        stopPersistentPassthruHost()
        if let priorProcess {
            await waitForPersistentHostExit(process: priorProcess)
        }
        return try await startPersistentPassthruHost(
            includeCapture: includeCapture,
            pollMilliseconds: pollMilliseconds
        )
    }

    func restartCompanionAndRecoverPersistentHost() async throws -> KanataSplitRuntimeCompanionRecoveryResult {
        try await companionManager.restartCompanion()

        let companionRunningAfterRestart: Bool = if let statusAfterRestart = try? await companionManager.outputBridgeStatus() {
            statusAfterRestart.companionRunning
        } else {
            false
        }

        let recoveredHostPID = try await restartPersistentPassthruHostAfterCompanionRestart()
        return KanataSplitRuntimeCompanionRecoveryResult(
            companionRunningAfterRestart: companionRunningAfterRestart,
            recoveredHostPID: recoveredHostPID
        )
    }

    /// Kill orphaned kanata-launcher processes that survived a previous app instance.
    /// Uses pgrep to find kanata-launcher processes not owned by this app.
    private func killOrphanedKanataLaunchers() async {
        do {
            let result = try await SubprocessRunner.shared.run("/usr/bin/pgrep", args: ["-f", "kanata-launcher.*--cfg"])
            let pids = result.stdout.split(separator: "\n").compactMap { Int32(String($0).trimmingCharacters(in: CharacterSet.whitespaces)) }
            let myPID = getpid()
            var killedPIDs: [Int32] = []
            for pid in pids {
                // Don't kill our own children or ourselves
                if pid == myPID { continue }
                if let active = activeHostProcess, active.processIdentifier == pid { continue }
                AppLogger.shared.log("🧹 [HostService] Killing orphaned kanata-launcher (PID \(pid))")
                kill(pid, SIGTERM)
                killedPIDs.append(pid)
            }
            if !killedPIDs.isEmpty {
                // Brief pause to let orphans release ports
                try? await Task.sleep(for: .milliseconds(500))
                // SIGKILL any that ignored SIGTERM
                for pid in killedPIDs {
                    if kill(pid, 0) == 0 {
                        AppLogger.shared.log("🧹 [HostService] Orphan PID \(pid) ignored SIGTERM, sending SIGKILL")
                        kill(pid, SIGKILL)
                    }
                }
            } else {
                AppLogger.shared.log("🧹 [HostService] No orphaned kanata-launcher processes found")
            }
        } catch {
            // pgrep returns exit 1 if no matches — not an error for that case
            AppLogger.shared.log("🧹 [HostService] pgrep check: \(error.localizedDescription)")
        }
    }

    func stopPersistentPassthruHost() {
        #if DEBUG
            if TestEnvironment.isRunningTests {
                Self.testPersistentHostPID = nil
                Self.testStartPersistentError = nil
                return
            }
        #endif
        guard let process = activeHostProcess else { return }
        if process.isRunning {
            expectedPersistentHostTermination = true
            process.terminate()
            return
        }
        activeHostProcess = nil
        expectedPersistentHostTermination = false
        activePersistentHostIncludesCapture = true
        activePersistentHostPollMilliseconds = 1000
    }
}
