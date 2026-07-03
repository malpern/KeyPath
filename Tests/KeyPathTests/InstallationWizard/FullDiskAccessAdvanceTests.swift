import KeyPathWizardCore
@preconcurrency import XCTest

/// Covers the FDA page's "should I auto-advance" decision (#933). The page must
/// advance only on a grant that lands *during* the visit — never on a review visit
/// to an already-granted page (the regression this guard fixes).
final class FullDiskAccessAdvanceTests: XCTestCase {
    func testFreshGrantDuringVisitAdvances() {
        // Not granted on appear, granted now → the user just enabled it → advance.
        XCTAssertTrue(shouldAdvanceOnFullDiskAccessGrant(isGrantedNow: true, wasGrantedOnAppear: false))
    }

    func testReviewVisitToAlreadyGrantedPageDoesNotAdvance() {
        // Granted before the visit → the user only opened the page to review it →
        // must NOT navigate them away.
        XCTAssertFalse(shouldAdvanceOnFullDiskAccessGrant(isGrantedNow: true, wasGrantedOnAppear: true))
    }

    func testNotGrantedNeverAdvances() {
        XCTAssertFalse(shouldAdvanceOnFullDiskAccessGrant(isGrantedNow: false, wasGrantedOnAppear: false))
        XCTAssertFalse(shouldAdvanceOnFullDiskAccessGrant(isGrantedNow: false, wasGrantedOnAppear: true))
    }
}
