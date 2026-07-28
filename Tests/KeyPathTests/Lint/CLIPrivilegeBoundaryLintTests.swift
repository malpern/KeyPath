import Foundation
@preconcurrency import XCTest

/// The CLI is an authorized client of KeyPath's narrowly scoped XPC helper.
/// It must not grow a second privileged execution path through launchctl, sudo,
/// osascript, or the generic admin-command executor.
final class CLIPrivilegeBoundaryLintTests: KeyPathTestCase {
    func testCLIUsesBrokeredOrHelperBackedPrivilegedOperations() throws {
        let root = cliPrivilegeBoundaryRepositoryRoot()
        let sourceRoots = [
            "Sources/KeyPathCLI",
            "Sources/KeyPathCLISupport",
            "Sources/KeyPathAppKit/CLI",
        ]
        let forbidden = [
            ".launchctl(",
            "/bin/launchctl",
            "/usr/bin/sudo",
            "/usr/bin/osascript",
            "AdminCommandExecutor",
            "PrivilegedCommandRunner",
        ]
        var violations: [String] = []

        for relativeRoot in sourceRoots {
            let directory = root.appendingPathComponent(relativeRoot)
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                XCTFail("Could not enumerate \(relativeRoot)")
                continue
            }

            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                for (lineIndex, line) in source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated()
                {
                    for token in forbidden where line.contains(token) {
                        let relativePath = file.path.replacingOccurrences(
                            of: root.path + "/",
                            with: ""
                        )
                        violations.append("\(relativePath):\(lineIndex + 1): \(token)")
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            CLI privileged operations must use the explicit helper API or the
            installer privilege broker. Direct privileged execution found:
            \(violations.joined(separator: "\n"))
            """
        )
    }
}

private func cliPrivilegeBoundaryRepositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}
