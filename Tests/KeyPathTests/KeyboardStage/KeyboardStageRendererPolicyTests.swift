@testable import KeyPathAppKit
import KeyPathCore
import XCTest

final class KeyboardStageRendererPolicyTests: XCTestCase {
    func testAutomaticPrefersMetalWhenAvailable() {
        XCTAssertEqual(
            policy(preference: .automatic, metalAvailable: true).backend,
            .metal
        )
    }

    func testAnyMetalFailureFallsBackToSwiftUI() {
        XCTAssertEqual(
            policy(preference: .metal, metalAvailable: true, metalFailed: true).backend,
            .swiftUI
        )
        XCTAssertEqual(
            policy(preference: .automatic, metalAvailable: false).backend,
            .swiftUI
        )
    }

    func testReducedMotionAlwaysUsesTheNativeFallback() {
        var displayMode = KeyboardStageDisplayMode.standard
        displayMode.reduceMotion = true
        XCTAssertEqual(
            KeyboardStageRendererPolicy(
                preference: .metal,
                displayMode: displayMode,
                metalAvailable: true,
                metalFailed: false
            ).backend,
            .swiftUI
        )
    }

    func testExplicitSwiftUIPreferenceWins() {
        XCTAssertEqual(
            policy(preference: .swiftUI, metalAvailable: true).backend,
            .swiftUI
        )
    }

    func testAutomaticSelectionHonorsTheDeveloperFeatureFlag() {
        FeatureFlags.setKeyboardStageRendererPreference(.swiftUI)
        defer { FeatureFlags.resetTestOverrides() }

        XCTAssertEqual(
            KeyboardStageRendererPolicy.effectivePreference(requested: .automatic),
            .swiftUI
        )
    }

    func testDrawableRecoveryRetriesAreBoundedAndRearmable() {
        var recovery = KeyboardStageDrawRecovery(retryLimit: 2)

        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: true, retryAlreadyScheduled: false),
            .waitForEvent
        )

        recovery.request()
        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: false, retryAlreadyScheduled: false),
            .waitForEvent
        )
        XCTAssertEqual(recovery.retriesRemaining, 2)
        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: true, retryAlreadyScheduled: false),
            .scheduleRetry
        )
        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: true, retryAlreadyScheduled: true),
            .waitForEvent
        )
        XCTAssertEqual(recovery.retriesRemaining, 1)
        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: true, retryAlreadyScheduled: false),
            .scheduleRetry
        )
        XCTAssertEqual(
            recovery.drawableUnavailable(isViewActive: true, retryAlreadyScheduled: false),
            .fail
        )
        XCTAssertFalse(recovery.isPending)

        recovery.request()
        XCTAssertTrue(recovery.isPending)
        XCTAssertEqual(recovery.retriesRemaining, 2)
        recovery.complete()
        XCTAssertFalse(recovery.isPending)
    }

    private func policy(
        preference: KeyboardStageRendererPreference,
        metalAvailable: Bool,
        metalFailed: Bool = false
    ) -> KeyboardStageRendererPolicy {
        KeyboardStageRendererPolicy(
            preference: preference,
            displayMode: .standard,
            metalAvailable: metalAvailable,
            metalFailed: metalFailed
        )
    }
}
