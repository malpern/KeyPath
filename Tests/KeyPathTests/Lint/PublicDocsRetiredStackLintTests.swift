import Foundation
import XCTest

/// The public docs once described the retired privileged stack as current
/// (project review 2026-11-09, B7): a helper install step, Full Disk Access,
/// Kanata as a LaunchDaemon, the Karabiner driver. This keeps those claims
/// from coming back. The phrases are narrow on purpose: legacy sections and
/// uninstall notes may still name the old pieces, as long as they do not
/// present them as part of setup.
final class PublicDocsRetiredStackLintTests: XCTestCase {
    private static let publicPaths = [
        "README.md", "PRIVACY.md", "SECURITY.md", "CONTRIBUTING.md", "docs.md",
        "guides", "getting-started", "migration",
    ]

    private static let retiredClaims = [
        #"(?i)privileged helper installation"#,
        #"(?i)(requires|grant|needs|asks? for) (keypath )?full disk access"#,
        #"(?i)full disk access is required"#,
        #"(?i)(starts|runs|installs?) (kanata )?as a launchdaemon"#,
        #"(?i)(uses|installs?|requires) the karabiner (virtualhid|driverkit|driver)"#,
    ]

    func testPublicDocsDoNotDescribeTheRetiredStackAsCurrent() throws {
        let violations = try Self.markdownFiles().flatMap {
            try LintScanner.matchingLines(in: $0, patterns: Self.retiredClaims)
        }
        XCTAssertTrue(
            violations.isEmpty,
            """
            Public docs describe the retired privileged stack as current. Current builds
            run the engine in the user session (ADR-045, ADR-047):
            \(violations.joined(separator: "\n"))
            """
        )
    }

    func testThePatternsCatchTheOriginalWording() throws {
        // Lines the review found on master before it was corrected.
        let examples = [
            "### Step 1: Privileged Helper Installation",
            "KeyPath asks for Full Disk Access to read the permission database.",
            "Kanata starts as a LaunchDaemon at boot.",
            "KeyPath uses the Karabiner VirtualHID driver to emit keys.",
        ]
        let regexes = try Self.retiredClaims.map { try NSRegularExpression(pattern: $0) }
        for line in examples {
            let range = NSRange(line.startIndex..., in: line)
            XCTAssertTrue(regexes.contains { $0.firstMatch(in: line, range: range) != nil }, line)
        }
    }

    private static func markdownFiles() -> [URL] {
        publicPaths.flatMap { relative -> [URL] in
            let url = LintScanner.path(relative)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
            guard isDirectory.boolValue else { return [url] }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "md" }
        }
    }
}
