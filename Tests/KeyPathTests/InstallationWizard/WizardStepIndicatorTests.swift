import Foundation
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Unit tests for `WizardPage.stepPosition(in:)`, the pure derivation behind
/// the "Step X of Y" progress indicator added for #934. Summary is the
/// overview page, not a numbered step, so it's excluded from both the
/// step number and the total.
final class WizardStepIndicatorTests: XCTestCase {
    func testSummaryHasNoStepPosition() {
        XCTAssertNil(WizardPage.summary.stepPosition())
    }

    func testFirstNonSummaryPageInDefaultOrderIsStepOne() {
        // orderedPages: [.summary, .kanataMigration, .stopExternalKanata, .karabinerImport, .helper, ...]
        let position = WizardPage.kanataMigration.stepPosition()
        XCTAssertEqual(position?.step, 1)
    }

    func testTotalMatchesNonSummaryPageCount() {
        let expectedTotal = WizardPage.orderedPages.filter { $0 != .summary }.count
        for page in WizardPage.orderedPages where page != .summary {
            XCTAssertEqual(
                page.stepPosition()?.total, expectedTotal,
                "Total step count must be consistent across all pages in the sequence"
            )
        }
    }

    func testStepNumbersAreSequentialAndUnique() {
        let nonSummaryPages = WizardPage.orderedPages.filter { $0 != .summary }
        let steps = nonSummaryPages.compactMap { $0.stepPosition()?.step }
        XCTAssertEqual(steps, Array(1 ... nonSummaryPages.count), "Steps must be sequential starting at 1")
    }

    func testPageNotInSequenceHasNoStepPosition() {
        // .service is not part of a custom sequence that omits it.
        let customSequence: [WizardPage] = [.summary, .helper, .accessibility]
        XCTAssertNil(WizardPage.service.stepPosition(in: customSequence))
    }

    func testCustomSequenceRecomputesStepsIndependently() {
        // A "skip green pages" custom sequence with only 2 non-summary steps.
        let customSequence: [WizardPage] = [.summary, .accessibility, .inputMonitoring]

        let first = WizardPage.accessibility.stepPosition(in: customSequence)
        let second = WizardPage.inputMonitoring.stepPosition(in: customSequence)

        XCTAssertEqual(first, WizardPage.StepPosition(step: 1, total: 2))
        XCTAssertEqual(second, WizardPage.StepPosition(step: 2, total: 2))
    }
}
