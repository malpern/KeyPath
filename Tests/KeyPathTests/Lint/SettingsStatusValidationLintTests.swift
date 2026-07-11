import Foundation
@preconcurrency import XCTest

/// Prevents the status view from turning validation publication into a new
/// validation request, which previously produced repeated startup captures.
final class SettingsStatusValidationLintTests: XCTestCase {
    func testValidationDateObserverOnlyCopiesPublishedStatus() throws {
        let source = try String(
            contentsOf: LintScanner.path("Sources/KeyPathAppKit/UI/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let observerPattern = #"\.onChange\(of: MainAppStateController\.shared\.lastValidationDate\)[\s\S]*?\n        \}"#
        let observer = try XCTUnwrap(source.range(of: observerPattern, options: .regularExpression))
        let body = String(source[observer])

        XCTAssertTrue(body.contains("copyPublishedStatus()"))
        XCTAssertFalse(
            body.contains("refreshStatus()"),
            "Observing validation completion must not request another validation"
        )
    }
}
