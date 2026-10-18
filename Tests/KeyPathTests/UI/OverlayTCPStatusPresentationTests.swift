@testable import KeyPathAppKit
import Testing

@Suite("Overlay TCP status presentation")
struct OverlayTCPStatusPresentationTests {
    @Test("connected runtime hides TCP status")
    func connectedHidesStatus() {
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: true,
            hasSeenConnection: true,
            isWithinStartupGrace: true
        ) == .hidden)
    }

    @Test("initial connection grace reports starting")
    func initialGraceReportsStarting() {
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false,
            hasSeenConnection: false,
            isWithinStartupGrace: true
        ) == .starting)
    }

    @Test("lost connection during grace reports restarting")
    func reconnectGraceReportsRestarting() {
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false,
            hasSeenConnection: true,
            isWithinStartupGrace: true
        ) == .restarting)
    }

    @Test("settled disconnection reports No TCP state")
    func settledDisconnectionReportsFailure() {
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false,
            hasSeenConnection: true,
            isWithinStartupGrace: false
        ) == .disconnected)
    }

    @Test("Recovery checking remains neutral after initial startup grace")
    func recoveryCheckingAfterGrace() {
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false, hasSeenConnection: true,
            isWithinStartupGrace: false, isCheckingHealth: true
        ) == .restarting)
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: true, hasSeenConnection: true,
            isWithinStartupGrace: false, isCheckingHealth: true
        ) == .hidden)
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false, hasSeenConnection: true,
            isWithinStartupGrace: false, isCheckingHealth: false
        ) == .disconnected)
    }
}
