import Foundation
@preconcurrency import XCTest

final class W3BackgroundMutationExceptionLintTests: XCTestCase {
    func testServiceHealthPollingOnlyAllowsVHIDEmergencyStopException() throws {
        let mainAppStateController = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/MainAppStateController.swift")
        let contents = try String(contentsOf: mainAppStateController, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("W3 safety exception: this background mutation only stops remapping"),
            "The background service-health mutation must be documented as a W3 safety exception."
        )
        XCTAssertTrue(
            contents.contains(#"stopKanata(reason: "Emergency: VirtualHID not running")"#),
            "The service-health polling exception should remain a stop-only safety action."
        )

        let forbidden = try matchingLines(
            in: mainAppStateController,
            patterns: [
                #"serviceHealthTask[\s\S]*restartKanata"#,
                #"serviceHealthTask[\s\S]*run\(intent:\s*\.repair"#,
                #"serviceHealthTask[\s\S]*runSingleAction"#,
            ]
        )

        XCTAssertTrue(
            forbidden.isEmpty,
            """
            W3 allows the service-health polling loop to stop Kanata for the \
            VirtualHID safety invariant, but it must not repair or restart \
            services in the background:
            \(forbidden.sorted().joined(separator: "\n"))
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
    let regexes = try patterns.map {
        try NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators])
    }

    return regexes.compactMap { regex in
        let range = NSRange(contents.startIndex..., in: contents)
        guard let match = regex.firstMatch(in: contents, range: range),
              let matchRange = Range(match.range, in: contents)
        else {
            return nil
        }
        let prefix = contents[..<matchRange.lowerBound]
        let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return "\(fileURL.lastPathComponent):\(line): \(contents[matchRange].prefix(120))"
    }
}
