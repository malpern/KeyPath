import Foundation
@preconcurrency import XCTest

/// Guards the Phase 1 migration of permission-state reads behind `SystemStateProvider`.
///
/// `PermissionOracle` remains the low-level authority for permissions, but installer
/// and wizard consumers should ask `SystemStateProvider` so the eventual immutable
/// system snapshot has one owner for OS evidence reads.
final class PermissionSnapshotLintTests: XCTestCase {
    func testPermissionRequestServiceDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let service = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Permissions/PermissionRequestService.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: service,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PermissionRequestService must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testPermissionGateDelegatesPermissionSnapshotsToSystemStateProvider() throws {
        let gate = repositoryRootForPermissionSnapshotLint()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Permissions/PermissionGate.swift")

        let violations = try matchingPermissionSnapshotLines(
            in: gate,
            patterns: [
                #"PermissionOracle\.shared\.currentSnapshot"#,
                #"PermissionOracle\.shared\.forceRefresh"#,
                #"PermissionOracle\.shared"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            PermissionGate must delegate permission snapshot reads \
            through SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRootForPermissionSnapshotLint(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func matchingPermissionSnapshotLines(in fileURL: URL, patterns: [String]) throws -> [String] {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
    let relativePath = fileURL.path.replacingOccurrences(
        of: repositoryRootForPermissionSnapshotLint().path + "/",
        with: ""
    )

    var violations: [String] = []
    for (idx, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") { continue }
        let range = NSRange(rawLine.startIndex..., in: rawLine)
        if regexes.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) {
            violations.append("\(relativePath):\(idx + 1): \(trimmed)")
        }
    }
    return violations
}
