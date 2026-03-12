import Foundation
import KeyPathCore

protocol KanataOutputBridgeSmokeHelping: AnyObject, Sendable {
    func prepareKanataOutputBridgeSession(hostPID: Int32) async throws -> KanataOutputBridgeSession
    func activateKanataOutputBridgeSession(sessionID: String) async throws
}

extension HelperManager: KanataOutputBridgeSmokeHelping {}

struct KanataOutputBridgeSmokeReport: Equatable, Sendable {
    let session: KanataOutputBridgeSession
    let handshake: KanataOutputBridgeResponse
    let ping: KanataOutputBridgeResponse
    let syncedModifiers: KanataOutputBridgeModifierState?
    let syncModifiers: KanataOutputBridgeResponse?
    let emittedKeyEvent: KanataOutputBridgeKeyEvent?
    let emitKey: KanataOutputBridgeResponse?
    let reset: KanataOutputBridgeResponse?
}

@MainActor
enum KanataOutputBridgeSmokeService {
    typealias HandshakeOperation = @Sendable (KanataOutputBridgeSession) throws -> KanataOutputBridgeResponse
    typealias PingOperation = @Sendable (KanataOutputBridgeSession) throws -> KanataOutputBridgeResponse
    typealias SyncModifiersOperation = @Sendable (
        KanataOutputBridgeModifierState,
        KanataOutputBridgeSession
    ) throws -> KanataOutputBridgeResponse
    typealias EmitKeyOperation = @Sendable (
        KanataOutputBridgeKeyEvent,
        KanataOutputBridgeSession
    ) throws -> KanataOutputBridgeResponse
    typealias ResetOperation = @Sendable (KanataOutputBridgeSession) throws -> KanataOutputBridgeResponse

    static let defaultEmitProbeEvent = KanataOutputBridgeKeyEvent(
        usagePage: 0x07,
        usage: 0x68,
        action: .keyDown,
        sequence: 1
    )
    static let defaultModifierProbeState = KanataOutputBridgeModifierState(leftShift: true)

    static func run(
        hostPID: Int32 = getpid(),
        syncModifierProbe: KanataOutputBridgeModifierState? = nil,
        emitProbeEvent: KanataOutputBridgeKeyEvent? = nil,
        includeReset: Bool = false,
        helper: KanataOutputBridgeSmokeHelping = HelperManager.shared,
        performHandshake: HandshakeOperation = KanataOutputBridgeClient.performHandshake(session:),
        performPing: PingOperation = KanataOutputBridgeClient.ping(session:),
        performSyncModifiers: SyncModifiersOperation = KanataOutputBridgeClient.syncModifiers(_:session:),
        performEmitKey: EmitKeyOperation = KanataOutputBridgeClient.emitKey(_:session:),
        performReset: ResetOperation = KanataOutputBridgeClient.reset(session:)
    ) async throws -> KanataOutputBridgeSmokeReport {
        let session = try await helper.prepareKanataOutputBridgeSession(hostPID: hostPID)
        try await helper.activateKanataOutputBridgeSession(sessionID: session.sessionID)

        let handshake = try performHandshake(session)
        let ping = try performPing(session)
        let syncModifiers: KanataOutputBridgeResponse? =
            if let syncModifierProbe {
                try performSyncModifiers(syncModifierProbe, session)
            } else {
                nil
            }
        let emitKey: KanataOutputBridgeResponse? =
            if let emitProbeEvent {
                try performEmitKey(emitProbeEvent, session)
            } else {
                nil
            }
        let reset: KanataOutputBridgeResponse? =
            if includeReset {
                try performReset(session)
            } else {
                nil
            }

        return KanataOutputBridgeSmokeReport(
            session: session,
            handshake: handshake,
            ping: ping,
            syncedModifiers: syncModifierProbe,
            syncModifiers: syncModifiers,
            emittedKeyEvent: emitProbeEvent,
            emitKey: emitKey,
            reset: reset
        )
    }
}
