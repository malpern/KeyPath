import Foundation
@preconcurrency import XCTest

/// Guards Workstream 2's blessed process-liveness predicate.
///
/// `kill(pid, 0)` has privilege-boundary semantics that are easy to get wrong:
/// EPERM means the process exists but cannot be signaled by this process, while
/// ESRCH is the dead-process condition. Keep that logic centralized in
/// `KeyPathSystemProbes` and delegate through `SystemStateProvider` instead of
/// reimplementing the primitive at call sites.
final class LivenessPredicateLintTests: XCTestCase {
    private static let allowList: Set<String> = [
        "SystemProbeClient.swift"
    ]

    func testKillZeroLivenessProbeIsCentralized() throws {
        let sourcesDir = repositoryRoot().appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern: #"kill\s*\([^,\n]+,\s*0\s*\)"#)

        guard let enumerator = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            return XCTFail("Could not enumerate \(sourcesDir.path)")
        }

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if Self.allowList.contains(url.lastPathComponent) { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (idx, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") { continue }
                let range = NSRange(rawLine.startIndex..., in: rawLine)
                if pattern.firstMatch(in: rawLine, range: range) != nil {
                    violations.append("\(url.lastPathComponent):\(idx + 1): \(trimmed)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Direct `kill(pid, 0)` liveness probes found outside KeyPathSystemProbes. \
            Delegate to SystemStateProvider.isProcessAlive(pid:) instead of adding \
            another process-liveness implementation:
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
