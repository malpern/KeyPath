import Foundation
@testable import KeyPathAppKit
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Tests for WizardStateMachine navigation behavior
/// These tests verify navigation functionality after migrating from WizardNavigationCoordinator
@MainActor
final class WizardStateMachineNavigationTests: XCTestCase {
    var stateMachine: WizardStateMachine!

    override func setUp() async throws {
        try await super.setUp()
        stateMachine = WizardStateMachine()
    }

    override func tearDown() async throws {
        stateMachine = nil
        try await super.tearDown()
    }

    // MARK: - navigateToPage Tests

    func testNavigateToPage_updatesCurrentPage() {
        // Given
        XCTAssertEqual(stateMachine.currentPage, .summary)

        // When
        stateMachine.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertEqual(stateMachine.currentPage, .inputMonitoring)
    }

    func testNavigateToPage_updatesLastVisitedPage() {
        // Given
        XCTAssertNil(stateMachine.lastVisitedPage)

        // When
        stateMachine.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertEqual(stateMachine.lastVisitedPage, .summary)
    }

    func testNavigateToPage_setsUserInteractionMode() {
        // Given
        XCTAssertFalse(stateMachine.userInteractionMode)

        // When
        stateMachine.navigateToPage(.accessibility)

        // Then
        XCTAssertTrue(stateMachine.userInteractionMode)
    }

    func testNavigateToPage_multipleNavigations_tracksLastVisited() {
        // When
        stateMachine.navigateToPage(.inputMonitoring)
        stateMachine.navigateToPage(.accessibility)
        stateMachine.navigateToPage(.service)

        // Then
        XCTAssertEqual(stateMachine.currentPage, .service)
        XCTAssertEqual(stateMachine.lastVisitedPage, .accessibility)
    }

    // MARK: - isNavigatingForward Tests

    func testIsNavigatingForward_whenNoLastPage_returnsTrue() {
        // Given - no navigation yet
        XCTAssertNil(stateMachine.lastVisitedPage)

        // Then
        XCTAssertTrue(stateMachine.isNavigatingForward)
    }

    func testIsNavigatingForward_whenMovingForward_returnsTrue() {
        // Given - navigate forward in the flow
        // Order: .accessibility (6) -> .inputMonitoring (7) -> .service (10)
        stateMachine.navigateToPage(.accessibility)
        stateMachine.navigateToPage(.inputMonitoring)

        // Then - inputMonitoring comes after accessibility in orderedPages
        XCTAssertTrue(stateMachine.isNavigatingForward)
    }

    func testIsNavigatingForward_whenMovingBackward_returnsFalse() {
        // Given - navigate forward then back
        // Order: .accessibility (6) -> .inputMonitoring (7)
        stateMachine.navigateToPage(.inputMonitoring)
        stateMachine.navigateToPage(.accessibility)

        // Then - accessibility comes before inputMonitoring in orderedPages
        XCTAssertFalse(stateMachine.isNavigatingForward)
    }

    // MARK: - customSequence Tests

    func testCustomSequence_affectsCanNavigateBack() {
        // Given - default sequence, on summary (first page)
        XCTAssertFalse(stateMachine.canNavigateBack)

        // When - set custom sequence where summary is not first
        stateMachine.customSequence = [.inputMonitoring, .summary, .accessibility]
        stateMachine.navigateToPage(.summary)

        // Then - summary is now in middle, can go back
        XCTAssertTrue(stateMachine.canNavigateBack)
    }

    func testCustomSequence_affectsPreviousPage() {
        // Given
        stateMachine.customSequence = [.inputMonitoring, .accessibility, .service]
        stateMachine.navigateToPage(.accessibility)

        // Then
        XCTAssertEqual(stateMachine.previousPageInSequence, .inputMonitoring)
    }

    func testCustomSequence_affectsNextPage() {
        // Given
        stateMachine.customSequence = [.inputMonitoring, .accessibility, .service]
        stateMachine.navigateToPage(.accessibility)

        // Then
        XCTAssertEqual(stateMachine.nextPageInSequence, .service)
    }

    func testCustomSequence_whenNil_usesDefaultOrder() {
        // Given
        stateMachine.customSequence = nil
        stateMachine.navigateToPage(.summary)

        // Then - uses WizardPage.orderedPages
        XCTAssertFalse(stateMachine.canNavigateBack) // summary is first in default order
    }

    func testCustomSequence_whenEmpty_usesDefaultOrder() {
        // Given
        stateMachine.customSequence = []
        stateMachine.navigateToPage(.summary)

        // Then - uses WizardPage.orderedPages
        XCTAssertFalse(stateMachine.canNavigateBack)
    }

    // MARK: - canNavigateBack / canNavigateForward Tests

    func testCanNavigateBack_whenOnFirstPage_returnsFalse() {
        // Given - on summary (first in default order)
        XCTAssertEqual(stateMachine.currentPage, .summary)

        // Then
        XCTAssertFalse(stateMachine.canNavigateBack)
    }

    func testCanNavigateBack_whenNotOnFirstPage_returnsTrue() {
        // Given
        stateMachine.navigateToPage(.inputMonitoring)

        // Then
        XCTAssertTrue(stateMachine.canNavigateBack)
    }

    func testCanNavigateForward_whenOnLastPage_returnsFalse() throws {
        // Given - navigate to last page in default order
        let lastPage = try XCTUnwrap(WizardPage.orderedPages.last)
        stateMachine.navigateToPage(lastPage)

        // Then
        XCTAssertFalse(stateMachine.canNavigateForward)
    }

    func testCanNavigateForward_whenNotOnLastPage_returnsTrue() {
        // Given - on summary (first page)
        XCTAssertEqual(stateMachine.currentPage, .summary)

        // Then
        XCTAssertTrue(stateMachine.canNavigateForward)
    }

    // MARK: - previousPage / nextPage Tests

    func testPreviousPage_whenOnFirstPage_returnsNil() {
        // Given - on summary
        XCTAssertEqual(stateMachine.currentPage, .summary)

        // Then
        XCTAssertNil(stateMachine.previousPageInSequence)
    }

    func testPreviousPage_returnsCorrectPage() {
        // Given - inputMonitoring is at index 7, accessibility is at index 6
        stateMachine.navigateToPage(.inputMonitoring)

        // Then - previous page is accessibility (index 6), not summary
        XCTAssertEqual(stateMachine.previousPageInSequence, .accessibility)
    }

    func testNextPage_whenOnLastPage_returnsNil() throws {
        // Given
        let lastPage = try XCTUnwrap(WizardPage.orderedPages.last)
        stateMachine.navigateToPage(lastPage)

        // Then
        XCTAssertNil(stateMachine.nextPageInSequence)
    }

    func testNextPage_returnsCorrectPage() {
        // Given - on summary
        let expectedNext = WizardPage.orderedPages[1]

        // Then
        XCTAssertEqual(stateMachine.nextPageInSequence, expectedNext)
    }

    // MARK: - resetNavigation Tests

    func testResetNavigation_resetsCurrentPage() {
        // Given
        stateMachine.navigateToPage(.accessibility)

        // When
        stateMachine.resetNavigation()

        // Then
        XCTAssertEqual(stateMachine.currentPage, .summary)
    }

    func testResetNavigation_resetsUserInteractionMode() {
        // Given
        stateMachine.navigateToPage(.accessibility)
        XCTAssertTrue(stateMachine.userInteractionMode)

        // When
        stateMachine.resetNavigation()

        // Then
        XCTAssertFalse(stateMachine.userInteractionMode)
    }

    // MARK: - isCurrentPage Tests

    func testIsCurrentPage_returnsTrue_whenMatches() {
        XCTAssertTrue(stateMachine.isCurrentPage(.summary))
    }

    func testIsCurrentPage_returnsFalse_whenDoesNotMatch() {
        XCTAssertFalse(stateMachine.isCurrentPage(.accessibility))
    }

    // MARK: - User Interaction Grace Period Tests

    func testUserInteractionMode_blocksAutoNavigation_withinGracePeriod() async {
        // Given - user navigates (sets interaction mode)
        stateMachine.navigateToPage(.inputMonitoring)

        // When - try to auto-navigate immediately
        await stateMachine.autoNavigateIfNeeded(for: .active, issues: [])

        // Then - should NOT auto-navigate because we're in grace period
        XCTAssertEqual(stateMachine.currentPage, .inputMonitoring)
    }
}
