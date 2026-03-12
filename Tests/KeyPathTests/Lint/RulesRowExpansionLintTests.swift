import Foundation
@preconcurrency import XCTest

final class RulesRowExpansionLintTests: XCTestCase {
    func testRulesSummaryExpandRowUsesFullWidthHitArea() throws {
        let root = repositoryRoot()
        let fileURL = root.appendingPathComponent("Sources/KeyPathAppKit/UI/Rules/RulesSummaryView+CollectionRow.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            content.contains("accessibilityIdentifier(\"rules-summary-expand-button-\\(collectionId)\")"),
            "Rules summary row should expose a stable accessibility identifier for the expand button."
        )
        XCTAssertTrue(
            content.contains("Spacer(minLength: 0)"),
            "Rules summary row should include an internal spacer so empty row space is tappable."
        )
        XCTAssertTrue(
            content.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
            "Rules summary expand button should stretch across the available row width."
        )
    }

    func testActiveRulesExpandRowUsesFullWidthHitArea() throws {
        let root = repositoryRoot()
        let fileURL = root.appendingPathComponent("Sources/KeyPathAppKit/UI/Rules/ActiveRulesView.swift")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            content.contains("accessibilityIdentifier(\"active-rules-expand-button-\\(collection.id)\")"),
            "Active rules row should expose a stable accessibility identifier for the expand button."
        )
        XCTAssertTrue(
            content.contains("Spacer(minLength: 0)"),
            "Active rules row should include an internal spacer so empty row space is tappable."
        )
        XCTAssertTrue(
            content.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
            "Active rules expand button should stretch across the available row width."
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
