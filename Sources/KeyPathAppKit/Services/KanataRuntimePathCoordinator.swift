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
        fileManager: FileManager = Foundation.FileManager(),
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
        let hostBridgeLoaded: Bool = {
            if case .loaded = bridgeProbe { return true }
            return false
        }()
        let hostRuntimeConstructible: Bool = {
            if case .created = runtimeCreation { return true }
            return false
        }()
        // Check actual legacy system path, NOT the deprecated systemCorePath alias
        // which now returns the bundled path and would always report "available"
        let legacyAvailable = fileManager.isExecutableFile(atPath: WizardSystemPaths.legacySystemBinaryPath)

        AppLogger.shared.log("🧭 [RuntimePath] Evaluating split runtime decision:")
        AppLogger.shared.log("  bridgeProbe=\(bridgeProbe), hostBridgeLoaded=\(hostBridgeLoaded)")
        AppLogger.shared.log("  configValidation=\(configValidation), hostConfigValid=\(configValidation == .valid)")
        AppLogger.shared.log("  runtimeCreation=\(runtimeCreation), hostRuntimeConstructible=\(hostRuntimeConstructible)")
        AppLogger.shared.log("  helperReady=\(helperReady)")
        AppLogger.shared.log("  outputBridgeStatus=\(String(describing: outputBridgeStatus))")
        AppLogger.shared.log("  legacySystemBinaryAvailable=\(legacyAvailable)")

        let inputs = KanataRuntimePathInputs(
            hostBridgeLoaded: hostBridgeLoaded,
            hostConfigValid: configValidation == .valid,
            hostRuntimeConstructible: hostRuntimeConstructible,
            helperReady: helperReady,
            outputBridgeStatus: outputBridgeStatus,
            legacySystemBinaryAvailable: legacyAvailable
        )

        let decision = KanataRuntimePathEvaluator.decide(inputs)
        AppLogger.shared.log("🧭 [RuntimePath] Decision: \(decision)")
        return decision
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
        helperManager _: HelperManager = .shared
    ) async throws -> [String: String] {
        try await KanataOutputBridgeCompanionManager.shared.prepareEnvironment(hostPID: hostPID)
    }
}
