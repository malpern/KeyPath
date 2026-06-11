import Foundation
@preconcurrency import XCTest

/// Guards the single-source-of-truth invariant for the kanata `(defcfg ...)` header
/// (issue #860, completing #859).
///
/// Every config KeyPath writes must render its header through `KanataDefcfg` — that
/// type is where the root daemon's command-execution posture
/// (`KanataCommandActionsPolicy` / `danger-enable-cmd`) is decided. Before the
/// consolidation, at least five call sites hand-built the header and drifted apart.
/// This test fails if a `(defcfg` literal reappears in `Sources/` outside
/// `KanataDefcfg.swift`, so a new hand-built emitter can't quietly bypass the policy.
///
/// Allowed, by construction:
/// - comment lines,
/// - *detection* of the literal in existing text (`contains(`/`range(of:` calls,
///   used by repair and the defcfg-stripping canonicalizer — they inspect configs,
///   they don't emit headers),
/// - Swift string interpolation that merely starts with the letters `defcfg`
///   (`\(defcfgInstruction)`).
final class DefcfgEmitterLintTests: XCTestCase {
    func testNoHandBuiltDefcfgOutsideKanataDefcfg() throws {
        let sourcesDir = repositoryRoot().appendingPathComponent("Sources")
        // `\(defcfg…` is interpolation, not the kanata literal — exclude via lookbehind.
        let literal = try NSRegularExpression(pattern: #"(?<!\\)\(defcfg"#)

        guard let enumerator = FileManager.default.enumerator(
            at: sourcesDir, includingPropertiesForKeys: nil
        ) else {
            return XCTFail("Could not enumerate \(sourcesDir.path)")
        }

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if url.lastPathComponent == "KanataDefcfg.swift" { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard contents.contains("(defcfg") else { continue }

            for (number, line) in contents.components(separatedBy: "\n").enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard literal.firstMatch(in: line, range: range) != nil else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if line.contains("contains(\"(defcfg") || line.contains("range(of: \"(defcfg") {
                    continue
                }
                violations.append("\(url.lastPathComponent):\(number + 1): \(trimmed)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Hand-built kanata defcfg header(s) found outside KanataDefcfg.swift. Render \
            the header through a KanataDefcfg named profile instead — it is the single \
            auditable place where the root daemon's command-execution posture \
            (danger-enable-cmd / KanataCommandActionsPolicy) is decided (#859/#860):
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
