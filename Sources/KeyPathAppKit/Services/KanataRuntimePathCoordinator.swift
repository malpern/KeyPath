import Foundation
import KeyPathCore

@MainActor
enum KanataRuntimePathCoordinator {
    static let experimentalOutputBridgeSessionEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SESSION"
    static let experimentalOutputBridgeSocketEnvKey = "KEYPATH_EXPERIMENTAL_OUTPUT_BRIDGE_SOCKET"

#if DEBUG
    nonisolated(unsafe) static var testDecision: KanataRuntimePathDecision?
#endif

    static func evaluateCurrentPath(
        configPath: String = KeyPathConstants.Config.mainConfigPath,
        runtimeHost: KanataRuntimeHost = .current(),
        fileManager: FileManager = .default,
        helperManager: HelperManager = .shared
    ) async -> KanataRuntimePathDecision {
#if DEBUG
        if TestEnvironment.isRunningTests, let testDecision {
            return testDecision
        }
#endif
        let bridgeProbe = KanataHostBridge.probe(runtimeHost: runtimeHost, fileManager: fileManager)
        let configValidation = KanataHostBridge.validateConfig(
            runtimeHost: runtimeHost,
            configPath: configPath,
            fileManager: fileManager
        )
        let runtimeCreation = KanataHostBridge.createRuntime(
            runtimeHost: runtimeHost,
            configPath: configPath,
            fileManager: fileManager
        )

        let helperReady = await helperManager.testHelperFunctionality()
        let outputBridgeStatus = try? await helperManager.getKanataOutputBridgeStatus()
        let inputs = KanataRuntimePathInputs(
            hostBridgeLoaded: {
                if case .loaded = bridgeProbe { return true }
                return false
            }(),
            hostConfigValid: configValidation == .valid,
            hostRuntimeConstructible: {
                if case .created = runtimeCreation { return true }
                return false
            }(),
            helperReady: helperReady,
            outputBridgeStatus: outputBridgeStatus,
            legacySystemBinaryAvailable: fileManager.isExecutableFile(atPath: runtimeHost.systemCorePath)
        )

        return KanataRuntimePathEvaluator.decide(inputs)
    }

    static func prepareOutputBridgeSession(
        hostPID: Int32,
        helperManager: HelperManager = .shared
    ) async throws -> KanataOutputBridgeSession {
        try await helperManager.prepareKanataOutputBridgeSession(hostPID: hostPID)
    }

    static func activateOutputBridgeSession(
        sessionID: String,
        helperManager: HelperManager = .shared
    ) async throws {
        try await helperManager.activateKanataOutputBridgeSession(sessionID: sessionID)
    }

    static func prepareExperimentalOutputBridgeEnvironment(
        hostPID: Int32,
        helperManager: HelperManager = .shared
    ) async throws -> [String: String] {
        if helperManager === HelperManager.shared {
            return try await KanataOutputBridgeCompanionManager.shared.prepareEnvironment(hostPID: hostPID)
        }

        let companionManager = KanataOutputBridgeCompanionManager(helperManager: helperManager)
        return try await companionManager.prepareEnvironment(hostPID: hostPID)
    }
}
