import Foundation
@preconcurrency import XCTest

/// KeyPath wraps SwiftPM executables in a signed macOS app. Target resource
/// bundles are packaged in Contents/Resources, while SwiftPM's generated
/// Bundle.module accessor searches the app root and then an absolute build path.
final class PackagedResourceBundleAccessLintTests: XCTestCase {
    func testPackagedLibraryTargetsUseExplicitResourceResolvers() throws {
        let roots = [
            LintScanner.path("Sources/KeyPathApp"),
            LintScanner.path("Sources/KeyPathAppKit"),
            LintScanner.path("Sources/KeyPathInstallationWizard"),
        ]
        let violations = try roots.flatMap {
            try LintScanner.matchingLines(
                under: $0,
                patterns: [#"#bundle\b"#, #"Bundle\.module\b"#]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Packaged library code must use KeyPath's explicit target resource
            resolver. SwiftPM's generated accessor crashes after its absolute
            build-worktree fallback disappears:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
