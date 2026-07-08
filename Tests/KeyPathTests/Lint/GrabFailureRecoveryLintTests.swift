import Foundation
@preconcurrency import XCTest

final class GrabFailureRecoveryLintTests: XCTestCase {
    func testGrabFailureHandlingDoesNotAttemptBackgroundRecovery() throws {
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")

        let violations = try matchingLines(
            in: runtimeCoordinator,
            patterns: [
                #"await attemptKeyboardRecovery\(\)"#,
                #"automatic recovery attempts"#,
                #"recovery attempt .*restarting"#,
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Grab-failure detection is W3 passive detection. It may record and \
            surface degraded state, but it must not run keyboard recovery from \
            the background InputGrab status path:
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
