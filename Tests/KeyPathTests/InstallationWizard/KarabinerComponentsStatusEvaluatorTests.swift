import XCTest
@testable import KeyPathAppKit
import KeyPathWizardCore

@MainActor
final class KarabinerComponentsStatusEvaluatorTests: XCTestCase {
  private func makeIssue(
    category: WizardIssue.IssueCategory,
    identifier: IssueIdentifier
  ) -> WizardIssue {
    WizardIssue(
      identifier: identifier,
      severity: .critical,
      category: category,
      title: "t",
      description: "d",
      autoFixAction: nil,
      userAction: nil
    )
  }

  func testDriverNotRedWhenOnlyKanataServiceIssue() {
    let daemonIssue = makeIssue(
      category: .daemon,
      identifier: IssueIdentifier.component(.kanataService)
    )

    let overall = KarabinerComponentsStatusEvaluator.evaluate(
      systemState: .ready,
      issues: [daemonIssue]
    )
    let driver = KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
      .driver,
      in: [daemonIssue]
    )
    let services = KarabinerComponentsStatusEvaluator.getIndividualComponentStatus(
      .backgroundServices,
      in: [daemonIssue]
    )

    XCTAssertEqual(driver, InstallationStatus.completed, "Driver should stay green when only Kanata service is pending")
    XCTAssertEqual(services, InstallationStatus.completed, "Background services row should stay green for Kanata-only issues")
    XCTAssertEqual(overall, InstallationStatus.completed, "Overall Karabiner status should stay green for Kanata-only issues")
  }
}
