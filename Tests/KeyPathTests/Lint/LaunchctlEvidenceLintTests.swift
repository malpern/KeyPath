import Foundation
@preconcurrency import XCTest

/// Guards launchctl evidence-read migration slices.
///
/// Mutating launchctl operations still belong to installer/helper execution paths.
/// Read-only service-state evidence (`launchctl print`) should move behind
/// SystemStateProvider as Phase 1 builds the executable snapshot.
final class LaunchctlEvidenceLintTests: XCTestCase {
    func testVHIDDeviceManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider() {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/VHIDDeviceManager.swift")

        assertNoDirectLaunchctlPrintEvidenceReads(in: manager)
    }

    func testServiceHealthCheckerDelegatesLaunchctlPrintEvidenceToSystemStateProvider() {
        let checker = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/ServiceHealthChecker.swift")

        assertNoDirectLaunchctlPrintEvidenceReads(in: checker)
    }

    func testKanataDaemonManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider() {
        let manager = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/KanataDaemonManager.swift")

        assertNoDirectLaunchctlPrintEvidenceReads(in: manager)
    }

    func testHelperManagerDelegatesLaunchctlPrintEvidenceToSystemStateProvider() {
        let managerStatus = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Core/HelperManager+Status.swift")

        assertNoDirectLaunchctlPrintEvidenceReads(in: managerStatus)
    }
}

private func assertNoDirectLaunchctlPrintEvidenceReads(
    in fileURL: URL,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let violations = try matchingLines(
            in: fileURL,
            patterns: [
                #"SubprocessRunner\.shared\.launchctl\("print""#,
                #"subprocessRunner\.launchctl\("print""#,
                #"/bin/launchctl print"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production code must delegate launchctl print service-state \
            evidence to SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """,
            file: file,
            line: line
        )
    } catch {
        XCTFail("Failed to inspect \(fileURL.path): \(error)", file: file, line: line)
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
