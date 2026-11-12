import Foundation
@preconcurrency import XCTest

/// `InstallerServices.current` is the one launch-time global the installer reads
/// (project review O4). It stays main-actor isolated.
final class InstallerServicesLintTests: XCTestCase {
    func testInstallerServicesRemainMainActorIsolated() throws {
        let dependencies = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathWizardCore/InstallerServices.swift")

        let violations = try matchingLines(
            in: dependencies,
            patterns: [#"nonisolated\s*\(unsafe\)"#]
        )

        XCTAssertTrue(
            violations.isEmpty,
            "InstallerServices is @MainActor; do not bypass its isolation with unsafe global state:\n\(violations.joined(separator: "\n"))"
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
