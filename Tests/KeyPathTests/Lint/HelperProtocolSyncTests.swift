import Foundation
@preconcurrency import XCTest

/// Validates that the two copies of HelperProtocol.swift remain synchronized.
///
/// XPC architecture requires the protocol to be compiled into both the app and helper
/// separately - they cannot share a module at runtime. This test ensures the two
/// copies don't diverge, which would cause runtime XPC failures.
///
/// See ADR-018 in CLAUDE.md for architectural context.
final class HelperProtocolSyncTests: XCTestCase {
    func testHelperProtocolFilesAreIdentical() throws {
        let root = repositoryRoot()
        let appKitPath = root.appendingPathComponent("Sources/KeyPathAppKit/Core/HelperProtocol.swift")
        let helperPath = root.appendingPathComponent("Sources/KeyPathHelper/HelperProtocol.swift")

        let appKitContent = try String(contentsOf: appKitPath, encoding: .utf8)
        let helperContent = try String(contentsOf: helperPath, encoding: .utf8)

        XCTAssertEqual(
            appKitContent,
            helperContent,
            """
            HelperProtocol.swift files have diverged!

            Both copies must be identical for XPC communication to work.
            Sync the files before shipping:
              - Sources/KeyPathAppKit/Core/HelperProtocol.swift
              - Sources/KeyPathHelper/HelperProtocol.swift

            See ADR-018 in CLAUDE.md for why this duplication exists.
            """
        )
    }
}

// MARK: - Helpers

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    // …/KeyPath/Tests/KeyPathTests/Lint/HelperProtocolSyncTests.swift -> go up 4 levels
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
