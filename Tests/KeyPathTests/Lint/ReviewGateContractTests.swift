import Foundation
import XCTest

final class ReviewGateContractTests: XCTestCase {
    private let staleToolingStatus = [
        "thermo-nuclear-swift-review",
        "and claude",
    ].joined(separator: " ")

    private let staleShellStatus = [
        "not installed",
        "in this shell",
    ].joined(separator: " ")

    private let staleFullStatus = [
        ["thermo-nuclear-swift-review", "and claude"].joined(separator: " "),
        "still are not installed",
    ].joined(separator: " ")

    func testReviewGateRemoteFallbackUsesCanonicalStatus() throws {
        let root = repositoryRoot()
        let script = try contents(of: root.appendingPathComponent("Scripts/review-gate.sh"))

        XCTAssertTrue(
            script.contains("remote review gate selected"),
            "review-gate must expose the canonical remote-review status."
        )
        XCTAssertTrue(
            script.contains("exit 2"),
            "review-gate must keep exit 2 as the expected remote-review path."
        )
        XCTAssertFalse(
            script.contains(staleToolingStatus),
            "review-gate output must not frame missing local tools as the status."
        )
        XCTAssertFalse(
            script.contains(staleShellStatus),
            "review-gate output must not revive the old shell-specific failure wording."
        )
    }

    func testPRWorkflowDocumentsRemoteReviewAsTheReportedGateState() throws {
        let root = repositoryRoot()
        let workflow = try contents(of: root.appendingPathComponent("docs/process/agent-pr-workflow.md"))
        let invariants = try contents(of: root.appendingPathComponent("docs/process/agent-pr-invariants.md"))
        let agents = try contents(of: root.appendingPathComponent("AGENTS.md"))
        let docs = [workflow, invariants, agents].joined(separator: "\n")

        XCTAssertTrue(
            docs.contains("remote review gate selected"),
            "PR process docs must preserve the canonical status agents should report."
        )
        XCTAssertTrue(
            docs.contains("Do not report missing local review tools as a PR issue"),
            "PR process docs must tell agents not to repeat shell-specific tool-install wording."
        )
        XCTAssertFalse(
            docs.contains(staleFullStatus),
            "PR process docs must not contain the old stale status wording."
        )
    }

    func testProcessSurfaceDoesNotContainStaleReviewGatePhrasing() throws {
        let root = repositoryRoot()
        let processSurface = [
            "AGENTS.md",
            "Scripts/review-gate.sh",
            "docs/process/agent-pr-workflow.md",
            "docs/process/agent-pr-invariants.md",
            "Tests/KeyPathTests/Lint/ReviewGateContractTests.swift",
        ]

        for relativePath in processSurface {
            let file = root.appendingPathComponent(relativePath)
            let text = try contents(of: file)

            XCTAssertFalse(
                text.contains(staleShellStatus),
                "\(relativePath) must not contain the stale shell-specific review-gate wording."
            )
            XCTAssertFalse(
                text.contains(staleFullStatus),
                "\(relativePath) must not contain the stale local-tooling review-gate wording."
            )
        }
    }
}

// MARK: - Helpers

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}
