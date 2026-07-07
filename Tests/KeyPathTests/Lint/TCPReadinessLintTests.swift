import Foundation
@preconcurrency import XCTest

/// Guards the W1/W2 TCP-readiness migration for `ServiceHealthChecker`.
///
/// The wizard health checker used to carry a private POSIX socket probe because
/// the old `TCPProbe` utility lived in AppKit. The blessed readiness probe now
/// lives in `SystemStateProvider`; this ratchet prevents the private socket
/// implementation from drifting back into installer health checks.
final class TCPReadinessLintTests: XCTestCase {
    func testServiceHealthCheckerDelegatesTCPReadinessToSystemStateProvider() throws {
        let serviceHealthChecker = repositoryRoot()
            .appendingPathComponent("Sources/KeyPathInstallationWizard/Core/ServiceHealthChecker.swift")
        let contents = try String(contentsOf: serviceHealthChecker, encoding: .utf8)

        let forbiddenPatterns = [
            #"probeTCP\s*\("#,
            #"socket\s*\(\s*AF_INET"#,
            #"connect\s*\("#,
            #"poll\s*\("#,
            #"getsockopt\s*\("#
        ].map { try! NSRegularExpression(pattern: $0) }

        var violations: [String] = []
        for (idx, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") { continue }
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            if forbiddenPatterns.contains(where: { $0.firstMatch(in: rawLine, range: range) != nil }) {
                violations.append("ServiceHealthChecker.swift:\(idx + 1): \(trimmed)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            ServiceHealthChecker must delegate TCP readiness to SystemStateProvider \
            instead of carrying a private socket probe:
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
