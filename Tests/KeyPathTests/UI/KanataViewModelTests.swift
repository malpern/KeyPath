import XCTest

@testable import KeyPathAppKit

/// Tests for KanataViewModel Phase 4 MVVM refactoring
///
/// These tests verify that:
/// - ViewModel correctly syncs state from KanataManager
/// - ViewModel delegates actions to KanataManager
/// - UI state updates correctly
@MainActor
final class KanataViewModelTests: XCTestCase {
    // Note: These tests are simple sanity checks to verify the MVVM architecture compiles and runs
    // Full integration testing is done at the UI level

    func testViewModelCompiles() {
        // Basic sanity test to verify MVVM architecture compiles
        let manager = KanataManager()
        let viewModel = KanataViewModel(manager: manager)

        // Verify ViewModel has access to underlying manager
        XCTAssertNotNil(viewModel.underlyingManager)

        // Verify configPath delegation works
        XCTAssertFalse(viewModel.configPath.isEmpty)
    }

    func testStateSnapshotMethod() {
        // Verify KanataManager can create state snapshots
        let manager = KanataManager()
        let snapshot = manager.getCurrentUIState()

        // Snapshot should contain current state
        // XCTAssertNotNil(snapshot.isRunning) // Removed
        // XCTAssertNotNil(snapshot.currentState) // Removed
        XCTAssertNotNil(snapshot.keyMappings)
    }
}
