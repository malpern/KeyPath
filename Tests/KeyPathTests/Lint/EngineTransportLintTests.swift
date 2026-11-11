import Foundation
import XCTest

/// ADR-046: KeyPath reaches the engine only through the session worker's
/// owner-checked Unix-domain socket. Loopback TCP admitted every local process,
/// including other users and sandboxed apps, and a TCP fallback would talk to
/// whatever squats the old port. This keeps production code off TCP.
final class EngineTransportLintTests: XCTestCase {
    private static let tcpEnginePatterns = [
        #"KanataTCPClient\(\s*(host|port):"#,
        #"\.tcp\(host:"#,
        #"NWEndpoint\.Host\("#,
        #"isTCPPortResponding\("#,
        #"\b37001\b"#,
        #"--session-port"#,
    ]

    func testProductionCodeDoesNotReachTheEngineOverTCP() throws {
        let violations = try LintScanner.matchingLines(
            under: LintScanner.path("Sources"),
            patterns: Self.tcpEnginePatterns,
            // The endpoint type defines the test-only TCP case, the client its
            // test-only initializer, and SystemStateProvider keeps a generic port probe.
            allowFileNames: ["KanataEngineEndpoint.swift", "KanataTCPClient.swift", "SystemStateProvider.swift"]
        )
        XCTAssertTrue(
            violations.isEmpty,
            """
            Production code reaches the engine over TCP. Use KanataTCPClient(timeout:) or
            KanataEventListener.start(endpoint: .session) (ADR-046):
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testThePatternsCatchTheOldConstructions() throws {
        let examples = [
            "let client = KanataTCPClient(port: port, timeout: 3.0)",
            "await SystemStateProvider.shared.isTCPPortResponding(port: Int(report.tcpPort), timeoutMs: 300)",
            "\"--session-port\", String(port),",
        ]
        let regexes = try Self.tcpEnginePatterns.map { try NSRegularExpression(pattern: $0) }
        for line in examples {
            let range = NSRange(line.startIndex..., in: line)
            XCTAssertTrue(regexes.contains { $0.firstMatch(in: line, range: range) != nil }, line)
        }
    }
}
