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

enum KanataSplitRuntimeHostExitInfo {
    static let pidUserInfoKey = "pid"
    static let exitCodeUserInfoKey = "exitCode"
    static let terminationReasonUserInfoKey = "terminationReason"
    static let expectedUserInfoKey = "expected"
    static let stderrLogPathUserInfoKey = "stderrLogPath"
}

@MainActor
final class KanataSplitRuntimeHostService {
    static let shared = KanataSplitRuntimeHostService()

#if DEBUG
    nonisolated(unsafe) static var testPersistentHostPID: pid_t?
    nonisolated(unsafe) static var testStartPersistentError: Error?
#endif

    private static let outputBridgeSessionEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SESSION"
    private static let outputBridgeSocketEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SOCKET"
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

    private func launcherArguments(configPath: String) -> [String] {
        [
            "--cfg",
            configPath,
            "--port",
            "\(PreferencesService.shared.tcpServerPort)",
            "--log-layer-changes"
        ]
    }

    var isPersistentPassthruHostRunning: Bool {
#if DEBUG
        if TestEnvironment.isRunningTests, let testPersistentHostPID = Self.testPersistentHostPID {
            return testPersistentHostPID > 0
        }
#endif
        return activeHostProcess?.isRunning == true
    }

    var activePersistentHostPID: pid_t? {
#if DEBUG
        if TestEnvironment.isRunningTests,
           let testPersistentHostPID = Self.testPersistentHostPID,
           testPersistentHostPID > 0
        {
            return testPersistentHostPID
        }
#endif
        guard activeHostProcess?.isRunning == true else { return nil }
        return activeHostProcess?.processIdentifier
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

        var environment = ProcessInfo.processInfo.environment
        environment[Self.outputBridgeSessionEnvKey] = session.sessionID
        environment[Self.outputBridgeSocketEnvKey] = session.socketPath
        environment[Self.inProcessRuntimeEnvKey] = "1"
        environment[Self.passthruRuntimeEnvKey] = "1"
        environment[Self.passthruForwardEnvKey] = "1"
        environment[Self.passthruOnlyEnvKey] = "1"
        if includeCapture {
            environment[Self.passthruCaptureEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruInjectEnvKey)
        } else {
            environment[Self.passthruInjectEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruCaptureEnvKey)
        }
        environment[Self.passthruPollEnvKey] = "\(pollMilliseconds)"
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)

        let stderrLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-host-passthru-child-stderr.log")
        FileManager.default.createFile(atPath: stderrLogURL.path, contents: Data())
        let stderrHandle = try FileHandle(forWritingTo: stderrLogURL)
        process.standardError = stderrHandle
        process.standardOutput = Pipe()

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

        process.waitUntilExit()
        try? stderrHandle.close()
        let terminationReason: String = switch process.terminationReason {
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
        guard activeHostProcess?.isRunning != true else {
            return activeHostProcess?.processIdentifier ?? 0
        }

        let runtimeHost = KanataRuntimeHost.current()
        let launcherPath = runtimeHost.launcherPath
        let configPath = KeyPathConstants.Config.mainConfigPath
        let session = try await companionManager.prepareEnvironmentAndPersist(hostPID: getpid())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launcherPath)
        process.arguments = launcherArguments(configPath: configPath)

        var environment = ProcessInfo.processInfo.environment
        environment[Self.outputBridgeSessionEnvKey] = session.sessionID
        environment[Self.outputBridgeSocketEnvKey] = session.socketPath
        environment[Self.inProcessRuntimeEnvKey] = "1"
        environment[Self.passthruRuntimeEnvKey] = "1"
        environment[Self.passthruForwardEnvKey] = "1"
        environment[Self.passthruOnlyEnvKey] = "1"
        environment[Self.passthruPersistEnvKey] = "1"
        if includeCapture {
            environment[Self.passthruCaptureEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruInjectEnvKey)
        } else {
            environment[Self.passthruInjectEnvKey] = "1"
            environment.removeValue(forKey: Self.passthruCaptureEnvKey)
        }
        environment[Self.passthruPollEnvKey] = "\(pollMilliseconds)"
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: (configPath as NSString).deletingLastPathComponent)

        let stderrLogURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keypath-host-passthru-live-stderr.log")
        FileManager.default.createFile(atPath: stderrLogURL.path, contents: Data())
        process.standardError = try FileHandle(forWritingTo: stderrLogURL)
        process.standardOutput = Pipe()
        expectedPersistentHostTermination = false
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                let expected = self.expectedPersistentHostTermination
                let terminationReason: String = switch process.terminationReason {
                case .exit:
                    "exit"
                case .uncaughtSignal:
                    "uncaughtSignal"
                @unknown default:
                    "unknown"
                }

                NotificationCenter.default.post(
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
                    self.expectedPersistentHostTermination = false
                }
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
        stopPersistentPassthruHost()
        try await Task.sleep(for: .milliseconds(250))
        return try await startPersistentPassthruHost(
            includeCapture: includeCapture,
            pollMilliseconds: pollMilliseconds
        )
    }

    func restartCompanionAndRecoverPersistentHost() async throws -> KanataSplitRuntimeCompanionRecoveryResult {
        try await companionManager.restartCompanion()

        let companionRunningAfterRestart: Bool
        if let statusAfterRestart = try? await companionManager.outputBridgeStatus() {
            companionRunningAfterRestart = statusAfterRestart.companionRunning
        } else {
            companionRunningAfterRestart = false
        }

        let recoveredHostPID = try await restartPersistentPassthruHostAfterCompanionRestart()
        return KanataSplitRuntimeCompanionRecoveryResult(
            companionRunningAfterRestart: companionRunningAfterRestart,
            recoveredHostPID: recoveredHostPID
        )
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
        }
        activeHostProcess = nil
        activePersistentHostIncludesCapture = true
        activePersistentHostPollMilliseconds = 1000
    }
}
