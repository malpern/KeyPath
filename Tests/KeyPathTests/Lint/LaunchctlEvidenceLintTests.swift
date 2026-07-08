import Foundation
@preconcurrency import XCTest

/// Guards launchctl evidence-read migration slices.
///
/// Mutating launchctl operations still belong to installer/helper execution paths.
/// Read-only service-state evidence (`launchctl print`) should move behind
/// SystemStateProvider as Phase 1 builds the executable snapshot.
final class LaunchctlEvidenceLintTests: XCTestCase {
    func testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider() throws {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/VHIDDeviceManager.swift")

        let violations = try matchingLines(
            in: manager,
            patterns: [
                #"SubprocessRunner\.shared\.launchctl\("print""#,
                #"subprocessRunner\.launchctl\("print""#,
                #"/bin/launchctl print"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            VHIDDeviceManager must delegate launchctl print service-state \
            evidence to SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // LaunchctlEvidenceLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
}

private func matchingLines(in fileURL: URL, patterns: [String]) throws -> [String] {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
    let relativePath = fileURL.path.replacingOccurrences(of: repositoryRoot().path + "/", with: "")

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
