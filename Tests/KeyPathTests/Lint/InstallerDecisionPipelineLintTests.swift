import Foundation
@preconcurrency import XCTest

final class InstallerDecisionPipelineLintTests: XCTestCase {
    func testProductionPlanningUsesCanonicalDecisionPipeline() throws {
        let root = repositoryRoot()
        let consumers = [
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/InstallerEngine+Recipes.swift"),
            root.appendingPathComponent("Sources/KeyPathInstallationWizard/Core/SystemContextAdapter.swift"),
        ]
        var violations: [String] = []

        for file in consumers {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("ActionDeterminer")
            {
                violations.append("\(file.lastPathComponent):\(index + 1): \(line)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Production planning must consume InstallerDecisionPipeline so the
            matrix assessment and executable plan share one captured context:
            \(violations.joined(separator: "\n"))
            """
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // InstallerDecisionPipelineLintTests.swift
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
}
