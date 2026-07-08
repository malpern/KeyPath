import Foundation
@preconcurrency import XCTest

final class W6DeletionPassLintTests: XCTestCase {
    func testKarabinerConflictSingleImplementationProtocolDoesNotRegrow() throws {
        let serviceFile = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/Karabiner/KarabinerConflictService.swift")
        let runtimeCoordinator = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift")
        let requirementsChecker = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/System/SystemRequirementsChecker.swift")

        let violations = try [
            serviceFile,
            runtimeCoordinator,
            requirementsChecker,
        ].flatMap { file in
            try matchingLines(
                in: file,
                patterns: [
                    #"protocol\s+KarabinerConflictManaging\b"#,
                    #":\s*KarabinerConflictManaging\b"#,
                    #"\bKarabinerConflictManaging\b"#,
                ]
            )
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            W6 removes single-implementation protocols unless they provide \
            real injection value. KarabinerConflictService is the concrete \
            dependency; do not regrow KarabinerConflictManaging:
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
