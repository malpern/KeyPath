import KeyPathWizardCore
@preconcurrency import XCTest

/// Covers the shared automatic-prompt escalation logic (#931/#933): a permission
/// page must never sit at an unresolved grant without guidance. The pure resolver
/// decides when to offer the automatic prompt, when to keep waiting, and when to
/// fall back to explicit manual instructions — the same logic backs both the Input
/// Monitoring and Accessibility pages.
final class AutomaticPromptGuidanceTests: XCTestCase {
    private func resolve(
        keyPathReady: Bool,
        requestAttempted: Bool,
        secondsSinceRequest: TimeInterval?,
        waitWindow: TimeInterval = 6
    ) -> AutomaticPromptGuidance {
        resolveAutomaticPromptGuidance(
            AutomaticPromptGuidanceInput(
                keyPathReady: keyPathReady,
                requestAttempted: requestAttempted,
                secondsSinceRequest: secondsSinceRequest,
                waitWindow: waitWindow
            )
        )
    }

    func testGrantedShortCircuitsRegardlessOfAttempt() {
        XCTAssertEqual(resolve(keyPathReady: true, requestAttempted: false, secondsSinceRequest: nil), .granted)
        // A granted app must never show fallback copy even long after an attempt.
        XCTAssertEqual(resolve(keyPathReady: true, requestAttempted: true, secondsSinceRequest: 999), .granted)
    }

    func testNoAttemptOffersAutomaticPath() {
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: false, secondsSinceRequest: nil), .offerAutomatic)
    }

    func testWithinWaitWindowKeepsWaiting() {
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 0), .awaitingGrant)
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 5.9), .awaitingGrant)
    }

    func testAtOrAfterWaitWindowEscalatesToManualFallback() {
        // Boundary is inclusive of the window: at exactly the window we escalate.
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 6), .manualFallback)
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 30), .manualFallback)
    }

    func testAttemptedWithUnknownElapsedEscalatesRatherThanStalling() {
        // A missing timestamp must not strand the user in an infinite "waiting"
        // state — the whole point of #931 is to always reach guidance.
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: nil), .manualFallback)
    }

    func testNegativeElapsedFromClockRewindEscalatesRatherThanStalling() {
        // Wall-clock moving backwards after the click yields a negative elapsed;
        // it must escalate, not pin the user at .awaitingGrant forever (#931).
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: -50), .manualFallback)
    }

    func testProductionDefaultWaitWindowIsTwelveSeconds() {
        // The pages rely on the init default (they never pass waitWindow), so the
        // shipped escalation timing is locked in here: still waiting at 11s so a
        // real system dialog isn't contradicted, escalated by 12s (#931, review obs).
        let stillWaiting = resolveAutomaticPromptGuidance(
            AutomaticPromptGuidanceInput(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 11)
        )
        XCTAssertEqual(stillWaiting, .awaitingGrant)
        let escalated = resolveAutomaticPromptGuidance(
            AutomaticPromptGuidanceInput(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 12)
        )
        XCTAssertEqual(escalated, .manualFallback)
    }

    func testCustomWaitWindowIsHonored() {
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 2, waitWindow: 10), .awaitingGrant)
        XCTAssertEqual(resolve(keyPathReady: false, requestAttempted: true, secondsSinceRequest: 2, waitWindow: 1), .manualFallback)
    }
}
