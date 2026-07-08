import Foundation
@preconcurrency import XCTest

/// Guards the Phase 1 migration of permission-state reads behind `SystemStateProvider`.
///
/// `PermissionOracle` remains the low-level authority for permissions, but installer
/// and wizard consumers should ask `SystemStateProvider` so the immutable system
/// snapshot has one owner for OS evidence reads. This is intentionally tree-wide:
/// new files must not get a free bypass just because they were not known when the
/// ratchet was written.
final class PermissionSnapshotLintTests: XCTestCase {
    private static let allowList: Set<String> = [
        "Sources/KeyPathPermissions/SystemStateProvider+Permissions.swift"
    ]

    func testProductionPermissionSnapshotReadsDelegateToSystemStateProvider() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: [
                #"PermissionOracle\.shared(?:\.[A-Za-z0-9_]+\s*\()?"#
            ],
            allowList: Self.allowList
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production permission snapshot/status reads must delegate through \
            SystemStateProvider. Do not add new PermissionOracle.shared call sites \
            outside the provider façade:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}
