import Foundation
@preconcurrency import XCTest

final class StuckKeyRecoveryLintTests: XCTestCase {
    func testStuckKeyRecoveryDoesNotRestartKanataAutomatically() throws {
        let service = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Monitoring/StuckKeyRecoveryService.swift")
        let app = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/App.swift")

        let violations = try matchingLines(
            in: service,
            patterns: [
                #"restartKanata"#,
                #"automatic restart"#,
                #"triggering automatic restart"#
            ]
        ) + matchingLines(
            in: app,
            patterns: [
                #"StuckKeyRecoveryService\.shared\.restartKanata"#,
                #"StuckKeyRecoveryService.*restartKanata"#,
                #"kanataManager\?\.restartKanata\(reason: reason\)"#
            ]
        )

        XCTAssertTrue(
            violations.isEmpty,
            """
            Stuck-key detection is a passive W3 background monitor. It may capture \
            diagnostics and surface an incident, but it must not restart Kanata \
            automatically. Route recovery through a user-initiated installer action:
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
