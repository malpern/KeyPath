@testable import KeyPath
import XCTest

@MainActor
final class KanataManagerPublicAPITests: XCTestCase {
    func testAutoLaunchQuietModeCompletesAndProvidesSnapshot() async {
        let manager = KanataManager()

        await manager.startAutoLaunch(presentWizardOnFailure: false)

        // Should be able to retrieve a valid UI snapshot
        let snapshot = manager.getCurrentUIState()
        XCTAssertNotNil(snapshot.currentState.rawValue)
        // Auto-start attempts counter should be non-negative
        XCTAssertGreaterThanOrEqual(snapshot.autoStartAttempts, 0)
    }

    func testManualStartThenStopDoNotCrash() async {
        let manager = KanataManager()

        await manager.manualStart()
        await manager.manualStop()

        let snapshot = manager.getCurrentUIState()
        // Basic sanity: state is one of defined cases and call returned
        XCTAssertTrue(SimpleKanataState.allCases.contains(snapshot.currentState))
    }

    func testRequestWizardPresentationSetsFlag() async {
        let manager = KanataManager()

        manager.requestWizardPresentation()

        let snapshot = manager.getCurrentUIState()
        XCTAssertTrue(snapshot.showWizard)
    }
}

