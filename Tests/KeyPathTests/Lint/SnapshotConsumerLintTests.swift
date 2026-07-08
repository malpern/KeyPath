import Foundation
@preconcurrency import XCTest

/// Guards Phase 1's "one owner for OS/system evidence" rule.
///
/// This is a structural ratchet, not a claim that every remaining cache is ideal.
/// It prevents new runtime/installer state caches outside the known provider-style
/// owners while follow-up work shrinks the allowlist.
final class SnapshotConsumerLintTests: XCTestCase {
    func testSMAppServiceStatusProviderCacheIsOnlyConsumedThroughSystemStateProvider() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [#"SMAppServiceStatusProvider\.shared"#],
            allowList: [
                "Sources/KeyPathAppKit/Core/SMAppServiceStatusProvider.swift",
                "Sources/KeyPathAppKit/Core/SystemStateProvider+SMAppService.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production consumers must reach SMAppService status/cache evidence \
            through SystemStateProvider, not SMAppServiceStatusProvider.shared:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testRuntimeAndInstallerStateCachesStayInKnownOwners() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [
                #"\bhealthCache\b"#,
                #"\bruntimeCache\b"#,
                #"\bserviceStatusCache\b"#,
                #"\bcachedManagementState\b"#,
                #"\bsmAppServicePendingCache\b"#,
                #"\bcachedHelperVersion\b"#
            ],
            allowList: [
                "Sources/KeyPathInstallationWizard/Core/ServiceHealthChecker.swift",
                "Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift"
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Runtime/installer state caches must stay in the known provider-style \
            owners while Phase 1 follow-ups shrink this allowlist. Do not add new \
            system-state caches in consumers:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
