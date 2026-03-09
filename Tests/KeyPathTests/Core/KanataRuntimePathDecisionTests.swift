@testable import KeyPathCore
import XCTest

final class KanataRuntimePathDecisionTests: XCTestCase {
    func testEvaluatorPrefersSplitRuntimeWhenHostAndOutputBridgeAreReady() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: true,
                hostConfigValid: true,
                hostRuntimeConstructible: true,
                helperReady: true,
                outputBridgeStatus: KanataOutputBridgeStatus(
                    available: true,
                    companionRunning: true,
                    requiresPrivilegedBridge: true,
                    socketDirectory: KeyPathConstants.VirtualHID.rootOnlyTmp,
                    detail: nil
                ),
                legacySystemBinaryAvailable: true
            )
        )

        XCTAssertEqual(
            decision,
            .useSplitRuntime(
                reason: "bundled host can own input runtime and privileged output bridge is required at \(KeyPathConstants.VirtualHID.rootOnlyTmp)"
            )
        )
    }

    func testEvaluatorFallsBackToLegacyBinaryWhenHostRuntimeIsNotReady() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: true,
                hostConfigValid: true,
                hostRuntimeConstructible: false,
                helperReady: true,
                outputBridgeStatus: nil,
                legacySystemBinaryAvailable: true
            )
        )

        XCTAssertEqual(
            decision,
            .useLegacySystemBinary(
                reason: "bundled host runtime is not ready yet, so continue using the legacy system binary"
            )
        )
    }

    func testEvaluatorFallsBackToLegacyBinaryWhenCompanionIsInstalledButUnhealthy() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: true,
                hostConfigValid: true,
                hostRuntimeConstructible: true,
                helperReady: true,
                outputBridgeStatus: KanataOutputBridgeStatus(
                    available: true,
                    companionRunning: false,
                    requiresPrivilegedBridge: true,
                    socketDirectory: KeyPathConstants.OutputBridge.socketDirectory,
                    detail: "privileged output companion is installed but unhealthy"
                ),
                legacySystemBinaryAvailable: true
            )
        )

        XCTAssertEqual(
            decision,
            .useLegacySystemBinary(
                reason: "privileged output companion is installed but not healthy, so continue using the legacy system binary"
            )
        )
    }

    func testEvaluatorFallsBackToLegacyBinaryWhenOutputBridgeStatusIsUnavailable() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: true,
                hostConfigValid: true,
                hostRuntimeConstructible: true,
                helperReady: true,
                outputBridgeStatus: nil,
                legacySystemBinaryAvailable: true
            )
        )

        XCTAssertEqual(
            decision,
            .useLegacySystemBinary(
                reason: "privileged output bridge status is unavailable, so keep the legacy system binary as fallback"
            )
        )
    }

    func testEvaluatorBlocksWhenNeitherHostNorLegacyPathIsUsable() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: false,
                hostConfigValid: false,
                hostRuntimeConstructible: false,
                helperReady: false,
                outputBridgeStatus: nil,
                legacySystemBinaryAvailable: false
            )
        )

        XCTAssertEqual(
            decision,
            .blocked(reason: "bundled host bridge is unavailable and no legacy system binary exists")
        )
    }

    func testEvaluatorFallsBackToLegacyBinaryWhenHelperIsUnavailable() {
        let decision = KanataRuntimePathEvaluator.decide(
            KanataRuntimePathInputs(
                hostBridgeLoaded: true,
                hostConfigValid: true,
                hostRuntimeConstructible: true,
                helperReady: false,
                outputBridgeStatus: KanataOutputBridgeStatus(
                    available: true,
                    companionRunning: true,
                    requiresPrivilegedBridge: true,
                    socketDirectory: KeyPathConstants.OutputBridge.socketDirectory,
                    detail: "privileged output companion is installed and healthy"
                ),
                legacySystemBinaryAvailable: true
            )
        )

        XCTAssertEqual(
            decision,
            .useLegacySystemBinary(
                reason: "privileged helper is not ready, so continue using the legacy system binary"
            )
        )
    }
}
