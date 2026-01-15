import Foundation
@preconcurrency import XCTest

@testable import KeyPathAppKit
@testable import KeyPathWizardCore

/// Tests for WizardNavigationCoordinator behavior
/// These tests capture the current behavior before migrating to WizardStateMachine
@MainActor
final class WizardNavigationCoordinatorTests: XCTestCase {
    var coordinator: WizardNavigationCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = WizardNavigationCoordinator()
    }

    override func tearDown() async throws {
        coordinator = nil
        try await super.tearDown()
    }

    // MARK: - navigateToPage Tests

    func testNavigateToPage_updatesCurrentPage() {
        // Given
        XCTAssertEqual(coordinator.currentPage, .summary)

        // When
        coordinator.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertEqual(coordinator.currentPage, .inputMonitoring)
    }

    func testNavigateToPage_updatesLastVisitedPage() {
        // Given
        XCTAssertNil(coordinator.lastVisitedPage)

        // When
        coordinator.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertEqual(coordinator.lastVisitedPage, .summary)
    }

    func testNavigateToPage_setsUserInteractionMode() {
        // Given
        XCTAssertFalse(coordinator.userInteractionMode)

        // When
        coordinator.navigateToPage(.accessibility)

        // Then
        XCTAssertTrue(coordinator.userInteractionMode)
    }

    func testNavigateToPage_multipleNavigations_tracksLastVisited() {
        // When
        coordinator.navigateToPage(.inputMonitoring)
        coordinator.navigateToPage(.accessibility)
        coordinator.navigateToPage(.service)

        // Then
        XCTAssertEqual(coordinator.currentPage, .service)
        XCTAssertEqual(coordinator.lastVisitedPage, .accessibility)
    }

    // MARK: - isNavigatingForward Tests

    func testIsNavigatingForward_whenNoLastPage_returnsTrue() {
        // Given - no navigation yet
        XCTAssertNil(coordinator.lastVisitedPage)

        // Then
        XCTAssertTrue(coordinator.isNavigatingForward)
    }

    func testIsNavigatingForward_whenMovingForward_returnsTrue() {
        // Given - navigate forward in the flow
        // Order: .accessibility (6) -> .inputMonitoring (7) -> .service (10)
        coordinator.navigateToPage(.accessibility)
        coordinator.navigateToPage(.inputMonitoring)

        // Then - inputMonitoring comes after accessibility in orderedPages
        XCTAssertTrue(coordinator.isNavigatingForward)
    }

    func testIsNavigatingForward_whenMovingBackward_returnsFalse() {
        // Given - navigate forward then back
        // Order: .accessibility (6) -> .inputMonitoring (7)
        coordinator.navigateToPage(.inputMonitoring)
        coordinator.navigateToPage(.accessibility)

        // Then - accessibility comes before inputMonitoring in orderedPages
        XCTAssertFalse(coordinator.isNavigatingForward)
    }

    // MARK: - customSequence Tests

    func testCustomSequence_affectsCanNavigateBack() {
        // Given - default sequence, on summary (first page)
        XCTAssertFalse(coordinator.canNavigateBack)

        // When - set custom sequence where summary is not first
        coordinator.customSequence = [.inputMonitoring, .summary, .accessibility]
        coordinator.navigateToPage(.summary)

        // Then - summary is now in middle, can go back
        XCTAssertTrue(coordinator.canNavigateBack)
    }

    func testCustomSequence_affectsPreviousPage() {
        // Given
        coordinator.customSequence = [.inputMonitoring, .accessibility, .service]
        coordinator.navigateToPage(.accessibility)

        // Then
        XCTAssertEqual(coordinator.previousPage, .inputMonitoring)
    }

    func testCustomSequence_affectsNextPage() {
        // Given
        coordinator.customSequence = [.inputMonitoring, .accessibility, .service]
        coordinator.navigateToPage(.accessibility)

        // Then
        XCTAssertEqual(coordinator.nextPage, .service)
    }

    func testCustomSequence_whenNil_usesDefaultOrder() {
        // Given
        coordinator.customSequence = nil
        coordinator.navigateToPage(.summary)

        // Then - uses WizardPage.orderedPages
        XCTAssertFalse(coordinator.canNavigateBack) // summary is first in default order
    }

    func testCustomSequence_whenEmpty_usesDefaultOrder() {
        // Given
        coordinator.customSequence = []
        coordinator.navigateToPage(.summary)

        // Then - uses WizardPage.orderedPages
        XCTAssertFalse(coordinator.canNavigateBack)
    }

    // MARK: - canNavigateBack / canNavigateForward Tests

    func testCanNavigateBack_whenOnFirstPage_returnsFalse() {
        // Given - on summary (first in default order)
        XCTAssertEqual(coordinator.currentPage, .summary)

        // Then
        XCTAssertFalse(coordinator.canNavigateBack)
    }

    func testCanNavigateBack_whenNotOnFirstPage_returnsTrue() {
        // Given
        coordinator.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertTrue(coordinator.canNavigateBack)
    }

    func testCanNavigateForward_whenOnLastPage_returnsFalse() {
        // Given - navigate to last page in default order
        let lastPage = WizardPage.orderedPages.last!
        coordinator.navigateToPage(lastPage)

        // Then
        XCTAssertFalse(coordinator.canNavigateForward)
    }

    func testCanNavigateForward_whenNotOnLastPage_returnsTrue() {
        // Given - on summary (first page)
        XCTAssertEqual(coordinator.currentPage, .summary)

        // Then
        XCTAssertTrue(coordinator.canNavigateForward)
    }

    // MARK: - previousPage / nextPage Tests

    func testPreviousPage_whenOnFirstPage_returnsNil() {
        // Given - on summary
        XCTAssertEqual(coordinator.currentPage, .summary)

        // Then
        XCTAssertNil(coordinator.previousPage)
    }

    func testPreviousPage_returnsCorrectPage() {
        // Given - inputMonitoring is at index 7, accessibility is at index 6
        coordinator.navigateToPage(.inputMonitoring)

        // Then - previous page is accessibility (index 6), not summary
        XCTAssertEqual(coordinator.previousPage, .accessibility)
    }

    func testNextPage_whenOnLastPage_returnsNil() {
        // Given
        let lastPage = WizardPage.orderedPages.last!
        coordinator.navigateToPage(lastPage)

        // Then
        XCTAssertNil(coordinator.nextPage)
    }

    func testNextPage_returnsCorrectPage() {
        // Given - on summary
        let expectedNext = WizardPage.orderedPages[1]

        // Then
        XCTAssertEqual(coordinator.nextPage, expectedNext)
    }

    // MARK: - resetNavigation Tests

    func testResetNavigation_resetsCurrentPage() {
        // Given
        coordinator.navigateToPage(.accessibility)

        // When
        coordinator.resetNavigation()

        // Then
        XCTAssertEqual(coordinator.currentPage, .summary)
    }

    func testResetNavigation_resetsUserInteractionMode() {
        // Given
        coordinator.navigateToPage(.accessibility)
        XCTAssertTrue(coordinator.userInteractionMode)

        // When
        coordinator.resetNavigation()

        // Then
        XCTAssertFalse(coordinator.userInteractionMode)
    }

    // MARK: - isCurrentPage Tests

    func testIsCurrentPage_returnsTrue_whenMatches() {
        XCTAssertTrue(coordinator.isCurrentPage(.summary))
    }

    func testIsCurrentPage_returnsFalse_whenDoesNotMatch() {
        XCTAssertFalse(coordinator.isCurrentPage(.accessibility))
    }

    // MARK: - User Interaction Grace Period Tests

    func testUserInteractionMode_blocksAutoNavigation_withinGracePeriod() async {
        // Given - user navigates (sets interaction mode)
        coordinator.navigateToPage(.inputMonitoring)

        // When - try to auto-navigate immediately
        await coordinator.autoNavigateIfNeeded(for: .active, issues: [])

        // Then - should NOT auto-navigate because we're in grace period
        XCTAssertEqual(coordinator.currentPage, .inputMonitoring)
    }
}
