import Foundation
@preconcurrency import XCTest

/// Guards the test seam that keeps the suite from deadlocking (issue #698).
///
/// Suites that construct `RuntimeCoordinator` / `InstallerEngine` / `SystemValidator`
/// / `VHIDDeviceManager` reach `VHIDDeviceManager.detectConnectionHealth()`, which
/// spawns `pgrep` subprocesses with 3s timeouts. Under parallel execution those can
/// deadlock and hang `swift test` indefinitely. `KeyPathTestCase` installs
/// `VHIDDeviceManager.testPIDProvider = { [] }` so no real subprocess is ever spawned.
///
/// This test fails if a suite extends `XCTestCase` *directly* while using one of those
/// types. To fix a new violation, change the base class to `KeyPathTestCase` (or
/// `KeyPathAsyncTestCase`) — do **not** extend the allowlist. The allowlist is a
/// ratchet of pre-existing suites still awaiting migration; it should only shrink.
final class TestSeamLintTests: XCTestCase {
    /// Pre-existing suites that use a hazard type but still extend XCTestCase directly.
    /// Migrate these to KeyPathTestCase and remove them here. Never add new entries.
    private static let allowList: Set<String> = [
        // Real-I/O suites: the seam fixes their pgrep hang but they also do real
        // saveConfiguration/updateStatus/resetToDefaultConfig that needs deeper mocking.
        "ErrorHandlingTests.swift",
        "KeyPathTests.swift",
        "RuntimeCoordinatorResetTests.swift",
        // The seam's own test (sets testPIDProvider per test, asserts real-pgrep fallthrough).
        "VHIDDeviceManagerTests.swift"
    ]

    func testCoordinatorSuitesUseKeyPathTestCase() throws {
        let testsDir = repositoryRoot().appendingPathComponent("Tests/KeyPathTests")

        // Type used as a constructor `Type(` or as a type annotation `: Type`. The
        // leading \b avoids matching a method name that merely ends in the type, e.g.
        // `testDoNotBypassInstallerEngine()`.
        let hazard = try NSRegularExpression(
            pattern: #"\b(RuntimeCoordinator|InstallerEngine|SystemValidator|VHIDDeviceManager)\s*\(|:\s*(RuntimeCoordinator|InstallerEngine|SystemValidator|VHIDDeviceManager)\b"#
        )

        guard let enumerator = FileManager.default.enumerator(at: testsDir, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(testsDir.path)")
        }

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let name = url.lastPathComponent
            if name == "TestSeamLintTests.swift" { continue }
            if Self.allowList.contains(name) { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Only suites that subclass XCTestCase directly are at risk; KeyPathTestCase
            // (and its async variant) already install the seam.
            guard contents.contains(": XCTestCase"),
                  !contents.contains(": KeyPathTestCase"),
                  !contents.contains(": KeyPathAsyncTestCase")
            else { continue }
            let range = NSRange(contents.startIndex..., in: contents)
            if hazard.firstMatch(in: contents, range: range) != nil {
                violations.append(name)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            These test suites construct deadlock-prone coordinators but extend XCTestCase \
            directly. Use KeyPathTestCase / KeyPathAsyncTestCase (installs the pgrep seam — \
            see issue #698) instead of adding to the allowlist:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
