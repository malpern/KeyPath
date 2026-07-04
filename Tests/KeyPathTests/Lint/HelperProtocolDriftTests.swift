import Foundation
@preconcurrency import XCTest

/// Enforces that the two hand-duplicated copies of the XPC `HelperProtocol` stay in
/// sync (issue #856).
///
/// The interface is intentionally duplicated because the client (`KeyPathAppKit`) and
/// the privileged helper (`KeyPathHelper`) are separate targets that cannot share a
/// module. A header comment asks developers to keep both copies identical, but nothing
/// enforced it — editing one and forgetting the other ships a silently-broken XPC
/// interface (the mismatch surfaces only at runtime as failed calls).
///
/// This test parses the `func` signatures out of each copy, normalizes whitespace, and
/// fails with a clear diff if they diverge.
final class HelperProtocolDriftTests: XCTestCase {
    func testHelperProtocolCopiesAreInSync() throws {
        let root = repositoryRoot()
        let clientURL = root.appendingPathComponent("Sources/KeyPathAppKit/Core/HelperProtocol.swift")
        let helperURL = root.appendingPathComponent("Sources/KeyPathHelper/HelperProtocol.swift")

        let clientSignatures = try methodSignatures(of: clientURL)
        let helperSignatures = try methodSignatures(of: helperURL)

        XCTAssertFalse(
            clientSignatures.isEmpty,
            "Parsed no method signatures from \(clientURL.path); the parser or the file moved."
        )

        let onlyInClient = clientSignatures.subtracting(helperSignatures).sorted()
        let onlyInHelper = helperSignatures.subtracting(clientSignatures).sorted()

        XCTAssertTrue(
            onlyInClient.isEmpty && onlyInHelper.isEmpty,
            """
            HelperProtocol drift detected (issue #856): the client and helper copies of the \
            XPC interface disagree. Synchronize both copies:
              - Sources/KeyPathAppKit/Core/HelperProtocol.swift
              - Sources/KeyPathHelper/HelperProtocol.swift

            Only in KeyPathAppKit copy:
            \(onlyInClient.isEmpty ? "  (none)" : onlyInClient.map { "  \($0)" }.joined(separator: "\n"))

            Only in KeyPathHelper copy:
            \(onlyInHelper.isEmpty ? "  (none)" : onlyInHelper.map { "  \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// Extracts every `func …` declaration from a protocol source file as a set of
    /// whitespace-normalized signatures. Multi-line signatures (arguments wrapped across
    /// lines) are stitched back together by balancing parentheses.
    private func methodSignatures(of url: URL) throws -> Set<String> {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)

        var signatures: Set<String> = []
        var buffer = ""
        var depth = 0
        var collecting = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Skip comments and attributes so they never leak into a signature.
            if line.hasPrefix("//") || line.hasPrefix("///") || line.hasPrefix("*") { continue }

            if !collecting {
                guard line.hasPrefix("func ") else { continue }
                collecting = true
                buffer = ""
                depth = 0
            }

            buffer += (buffer.isEmpty ? "" : " ") + line
            depth += line.filter { $0 == "(" }.count
            depth -= line.filter { $0 == ")" }.count

            // A signature is complete once all opened parens are closed AND we have
            // seen at least one paren (guards against `func` on a bare line).
            if collecting, depth <= 0, buffer.contains("(") {
                signatures.insert(normalize(buffer))
                collecting = false
                buffer = ""
            }
        }

        return signatures
    }

    /// Collapse all runs of whitespace to single spaces so cosmetic formatting
    /// differences between the two copies don't register as drift.
    private func normalize(_ signature: String) -> String {
        signature
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
