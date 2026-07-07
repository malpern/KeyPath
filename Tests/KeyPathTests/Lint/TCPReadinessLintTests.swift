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

    func testProductionTCPProbeAdapterIsNoLongerUsed() throws {
        let violations = try sourceFiles(excludingPathSuffixes: ["Sources/KeyPathAppKit/Utilities/TCPProbe.swift"])
            .flatMap { fileURL in
                try matchingLines(
                    in: fileURL,
                    patterns: [#"TCPProbe\.probe\s*\("#]
                )
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production TCP readiness must call SystemStateProvider directly \
            instead of the legacy TCPProbe adapter:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }

    func testProductionRawTCPSocketProbeIsCentralized() throws {
        let violations = try sourceFiles(excludingPathSuffixes: ["Sources/KeyPathCore/SystemStateProvider.swift"])
            .flatMap { fileURL in
                try matchingLines(
                    in: fileURL,
                    patterns: [
                        #"socket\s*\(\s*AF_INET"#,
                        #"getsockopt\s*\("#,
                        #"EINPROGRESS"#,
                        #"POLLOUT"#
                    ]
                )
            }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production raw TCP socket readiness probes must stay centralized in \
            SystemStateProvider:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // TCPReadinessLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
}

private func sourceFiles(excludingPathSuffixes excludedSuffixes: Set<String>) throws -> [URL] {
    let sourcesRoot = repositoryRoot().appendingPathComponent("Sources")
    let enumerator = FileManager.default.enumerator(
        at: sourcesRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    var files: [URL] = []
    while let fileURL = enumerator?.nextObject() as? URL {
        guard fileURL.pathExtension == "swift" else { continue }
        let relativePath = fileURL.path.replacingOccurrences(of: repositoryRoot().path + "/", with: "")
        if excludedSuffixes.contains(where: { relativePath.hasSuffix($0) }) { continue }
        files.append(fileURL)
    }
    return files
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
