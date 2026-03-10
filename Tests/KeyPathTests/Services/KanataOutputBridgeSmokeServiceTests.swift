@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class KanataOutputBridgeSmokeServiceTests: XCTestCase {
    func testRunPreparesActivatesAndExecutesHandshakeAndPing() async throws {
        let helper = MockKanataOutputBridgeSmokeHelper()
        let session = KanataOutputBridgeSession(
            sessionID: "session-123",
            socketPath: "/tmp/session-123.sock",
            socketDirectory: "/tmp",
            hostPID: 4242,
            hostUID: 501,
            hostGID: 20
        )
        helper.preparedSession = session

        let operations = SendableOperationRecorder()

        let report = try await KanataOutputBridgeSmokeService.run(
            hostPID: 4242,
            helper: helper,
            performHandshake: { smokeSession in
                operations.append("handshake:\(smokeSession.sessionID)")
                return .ready(version: 1)
            },
            performPing: { smokeSession in
                operations.append("ping:\(smokeSession.sessionID)")
                return .pong
            },
            performReset: { _ in
                XCTFail("reset should not run when includeReset is false")
                return .acknowledged(sequence: nil)
            }
        )

        XCTAssertEqual(helper.preparedHostPIDs, [4242])
        XCTAssertEqual(helper.activatedSessionIDs, ["session-123"])
        XCTAssertEqual(operations.values, ["handshake:session-123", "ping:session-123"])
        XCTAssertEqual(report.session, session)
        XCTAssertEqual(report.handshake, .ready(version: 1))
        XCTAssertEqual(report.ping, .pong)
        XCTAssertNil(report.syncedModifiers)
        XCTAssertNil(report.syncModifiers)
        XCTAssertNil(report.emittedKeyEvent)
        XCTAssertNil(report.emitKey)
        XCTAssertNil(report.reset)
    }

    func testRunIncludesResetWhenRequested() async throws {
        let helper = MockKanataOutputBridgeSmokeHelper()
        helper.preparedSession = KanataOutputBridgeSession(
            sessionID: "session-reset",
            socketPath: "/tmp/session-reset.sock",
            socketDirectory: "/tmp",
            hostPID: 777,
            hostUID: 501,
            hostGID: 20
        )

        let operations = SendableOperationRecorder()

        let report = try await KanataOutputBridgeSmokeService.run(
            hostPID: 777,
            includeReset: true,
            helper: helper,
            performHandshake: { smokeSession in
                operations.append("handshake:\(smokeSession.sessionID)")
                return .ready(version: 1)
            },
            performPing: { smokeSession in
                operations.append("ping:\(smokeSession.sessionID)")
                return .pong
            },
            performReset: { smokeSession in
                operations.append("reset:\(smokeSession.sessionID)")
                return .acknowledged(sequence: nil)
            }
        )

        XCTAssertEqual(
            operations.values,
            ["handshake:session-reset", "ping:session-reset", "reset:session-reset"]
        )
        XCTAssertEqual(report.reset, .acknowledged(sequence: nil))
    }

    func testRunIncludesEmitProbeWhenRequested() async throws {
        let helper = MockKanataOutputBridgeSmokeHelper()
        helper.preparedSession = KanataOutputBridgeSession(
            sessionID: "session-emit",
            socketPath: "/tmp/session-emit.sock",
            socketDirectory: "/tmp",
            hostPID: 909,
            hostUID: 501,
            hostGID: 20
        )

        let probeEvent = KanataOutputBridgeKeyEvent(
            usagePage: 0x07,
            usage: 0x04,
            action: .keyDown,
            sequence: 99
        )
        let operations = SendableOperationRecorder()

        let report = try await KanataOutputBridgeSmokeService.run(
            hostPID: 909,
            emitProbeEvent: probeEvent,
            helper: helper,
            performHandshake: { smokeSession in
                operations.append("handshake:\(smokeSession.sessionID)")
                return .ready(version: 1)
            },
            performPing: { smokeSession in
                operations.append("ping:\(smokeSession.sessionID)")
                return .pong
            },
            performEmitKey: { event, smokeSession in
                operations.append("emit:\(smokeSession.sessionID):\(event.usagePage):\(event.usage):\(event.sequence)")
                return .acknowledged(sequence: event.sequence)
            },
            performReset: { _ in
                XCTFail("reset should not run when includeReset is false")
                return .acknowledged(sequence: nil)
            }
        )

        XCTAssertEqual(
            operations.values,
            [
                "handshake:session-emit",
                "ping:session-emit",
                "emit:session-emit:7:4:99"
            ]
        )
        XCTAssertEqual(report.emittedKeyEvent, probeEvent)
        XCTAssertEqual(report.emitKey, .acknowledged(sequence: 99))
        XCTAssertNil(report.reset)
    }

    func testRunIncludesModifierSyncWhenRequested() async throws {
        let helper = MockKanataOutputBridgeSmokeHelper()
        helper.preparedSession = KanataOutputBridgeSession(
            sessionID: "session-modifiers",
            socketPath: "/tmp/session-modifiers.sock",
            socketDirectory: "/tmp",
            hostPID: 313,
            hostUID: 501,
            hostGID: 20
        )

        let probeState = KanataOutputBridgeModifierState(leftShift: true, rightCommand: true)
        let operations = SendableOperationRecorder()

        let report = try await KanataOutputBridgeSmokeService.run(
            hostPID: 313,
            syncModifierProbe: probeState,
            helper: helper,
            performHandshake: { smokeSession in
                operations.append("handshake:\(smokeSession.sessionID)")
                return .ready(version: 1)
            },
            performPing: { smokeSession in
                operations.append("ping:\(smokeSession.sessionID)")
                return .pong
            },
            performSyncModifiers: { modifiers, smokeSession in
                operations.append("sync:\(smokeSession.sessionID):\(modifiers.leftShift):\(modifiers.rightCommand)")
                return .acknowledged(sequence: nil)
            },
            performEmitKey: { _, _ in
                XCTFail("emitKey should not run when emitProbeEvent is nil")
                return .acknowledged(sequence: nil)
            },
            performReset: { _ in
                XCTFail("reset should not run when includeReset is false")
                return .acknowledged(sequence: nil)
            }
        )

        XCTAssertEqual(
            operations.values,
            ["handshake:session-modifiers", "ping:session-modifiers", "sync:session-modifiers:true:true"]
        )
        XCTAssertEqual(report.syncedModifiers, probeState)
        XCTAssertEqual(report.syncModifiers, .acknowledged(sequence: nil))
        XCTAssertNil(report.emittedKeyEvent)
        XCTAssertNil(report.emitKey)
        XCTAssertNil(report.reset)
    }
}

@MainActor
private final class MockKanataOutputBridgeSmokeHelper: KanataOutputBridgeSmokeHelping, @unchecked Sendable {
    var preparedSession = KanataOutputBridgeSession(
        sessionID: "default-session",
        socketPath: "/tmp/default-session.sock",
        socketDirectory: "/tmp",
        hostPID: 1,
        hostUID: 501,
        hostGID: 20
    )
    private(set) var preparedHostPIDs: [Int32] = []
    private(set) var activatedSessionIDs: [String] = []

    func prepareKanataOutputBridgeSession(hostPID: Int32) async throws -> KanataOutputBridgeSession {
        preparedHostPIDs.append(hostPID)
        return preparedSession
    }

    func activateKanataOutputBridgeSession(sessionID: String) async throws {
        activatedSessionIDs.append(sessionID)
    }
}

private final class SendableOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
