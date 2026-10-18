import Foundation
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

    @Test("Recovery remains neutral between validation success and TCP reconnect")
    func validationToStreamHandoff() {
        let start = Date(timeIntervalSince1970: 100)
        var grace = OverlayTCPRecoveryGrace()
        grace.update(isConnected: false, isCheckingHealth: true, now: start)
        grace.update(isConnected: false, isCheckingHealth: false, now: start.addingTimeInterval(8))
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false, hasSeenConnection: true,
            isWithinStartupGrace: grace.isActive(at: start.addingTimeInterval(8.761))
        ) == .restarting)
        grace.update(isConnected: true, isCheckingHealth: false, now: start.addingTimeInterval(9))
        #expect(!grace.isActive(at: start.addingTimeInterval(9)))
        #expect(grace.deadline == nil)
    }

    @Test("Persistent disconnect expires and routine checks cannot renew its grace")
    func persistentFailureIsVisible() {
        let start = Date(timeIntervalSince1970: 100)
        var grace = OverlayTCPRecoveryGrace()
        grace.update(isConnected: false, isCheckingHealth: true, now: start)
        grace.update(isConnected: false, isCheckingHealth: false, now: start)
        grace.update(isConnected: false, isCheckingHealth: true, now: start.addingTimeInterval(4))
        grace.update(isConnected: false, isCheckingHealth: false, now: start.addingTimeInterval(5))
        #expect(!grace.isActive(at: start.addingTimeInterval(5)))
        #expect(OverlayTCPStatusPresentation.resolve(
            isConnected: false, hasSeenConnection: true,
            isWithinStartupGrace: grace.isActive(at: start.addingTimeInterval(5))
        ) == .disconnected)
        grace.update(isConnected: true, isCheckingHealth: false, now: start.addingTimeInterval(6))
        grace.update(isConnected: false, isCheckingHealth: true, now: start.addingTimeInterval(7))
        #expect(grace.isActive(at: start.addingTimeInterval(7)))
    }
}
