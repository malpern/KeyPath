import Foundation
@preconcurrency import XCTest

final class KanataFailureDiagnosisLintTests: XCTestCase {
    func testKanataFailureDiagnosisDoesNotAttemptBackgroundRecovery() throws {
        let recoveryCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RecoveryCoordinator.swift")
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")

        let violations = try matchingLines(
            in: recoveryCoordinator,
            patterns: [
                #"attemptRecovery"#,
                #"attempting automatic recovery"#,
                #"automatic recovery"#,
            ]
        ) + matchingLines(
            in: runtimeCoordinator,
            patterns: [
                #"attemptRecovery:\s*\{"#,
                #"diagnoseKanataFailure[\s\S]*attemptKeyboardRecovery"#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Kanata failure diagnosis is W3 passive detection. It may add diagnostics \
            that expose a user-initiated Fix action, but it must not launch keyboard \
            recovery from a background failure callback:
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

private func matchingLines(in fileURL: URL, patterns: [String]) throws -> [String] {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }

    return contents.components(separatedBy: .newlines).enumerated().compactMap { lineNumber, rawLine in
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return nil }

        let range = NSRange(rawLine.startIndex..., in: rawLine)
        guard regexes.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) else {
            return nil
        }
        return "\(fileURL.lastPathComponent):\(lineNumber + 1): \(trimmed)"
    }
}
