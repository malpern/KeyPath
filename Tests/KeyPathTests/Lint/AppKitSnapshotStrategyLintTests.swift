import Foundation
@preconcurrency import XCTest

/// Prevents reintroducing SnapshotTesting's Core Image-backed NSImage diff,
/// which raises an Objective-C exception under the pinned stable Xcode.
final class AppKitSnapshotStrategyLintTests: XCTestCase {
    func testSnapshotHarnessAvoidsCoreImageBackedImageStrategy() throws {
        let file = LintScanner.path("Tests/KeyPathSnapshotTests/Support/SnapshotHelpers.swift")
        let violations = try LintScanner.matchingLines(
            in: file,
            patterns: [#"Snapshotting<NSImage, NSImage>\s*=\s*\.image"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            AppKit snapshots must use appKitPNGStrategy; SnapshotTesting's
            tolerant `.image` diff crashes in CILabDeltaE on stable Xcode:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
