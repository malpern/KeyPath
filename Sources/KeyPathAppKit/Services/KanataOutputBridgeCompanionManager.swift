import Foundation
import KeyPathCore

@MainActor
final class KanataOutputBridgeCompanionManager {
    static let shared = KanataOutputBridgeCompanionManager()
    static let bridgeEnvironmentOutputPath = "/var/tmp/keypath-host-passthru-bridge-env.txt"

    private let helperManager: HelperManager

    init(helperManager: HelperManager = .shared) {
        self.helperManager = helperManager
    }

    func outputBridgeStatus() async throws -> KanataOutputBridgeStatus {
        try await helperManager.getKanataOutputBridgeStatus()
    }

    func prepareSession(hostPID: Int32) async throws -> KanataOutputBridgeSession {
        try await helperManager.prepareKanataOutputBridgeSession(hostPID: hostPID)
    }

    func activateSession(sessionID: String) async throws {
        try await helperManager.activateKanataOutputBridgeSession(sessionID: sessionID)
    }

    func restartCompanion() async throws {
        try await helperManager.restartKanataOutputBridgeCompanion()
    }

    func prepareEnvironment(hostPID: Int32) async throws -> [String: String] {
        let session = try await prepareSession(hostPID: hostPID)
        try await activateSession(sessionID: session.sessionID)
        return [
            KanataRuntimePathCoordinator.experimentalOutputBridgeSessionEnvKey: session.sessionID,
            KanataRuntimePathCoordinator.experimentalOutputBridgeSocketEnvKey: session.socketPath
        ]
    }

    @discardableResult
    func prepareEnvironmentAndPersist(
        hostPID: Int32,
        outputPath: String = bridgeEnvironmentOutputPath
    ) async throws -> KanataOutputBridgeSession {
        let session = try await prepareSession(hostPID: hostPID)
        try await activateSession(sessionID: session.sessionID)

        let payload = """
        session=\(session.sessionID)
        socket=\(session.socketPath)
        """
        try payload.write(toFile: outputPath, atomically: true, encoding: .utf8)
        return session
    }
}
