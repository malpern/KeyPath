import Foundation
@preconcurrency import XCTest

final class FacadeLintTests: XCTestCase {
    func testProductionSourcesDoNotBypassInstallerEngine() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [#"PrivilegedOperationsRouter\.shared"#],
            allowList: [
                "Sources/KeyPathAppKit/WizardProtocolConformances.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PrivilegedOperationsRouter.shared found outside the narrow wizard \
            dependency bridge. Installer, repair, and uninstall callers should \
            go through InstallerEngine:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testDirectAXChecksAreLimitedToPermissionOracle() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [#"AXIsProcessTrusted\("#],
            allowList: [
                "Sources/KeyPathPermissions/PermissionOracle.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Direct AXIsProcessTrusted use outside PermissionOracle:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
