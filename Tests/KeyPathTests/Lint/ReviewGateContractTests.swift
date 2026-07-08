import Foundation
import XCTest

final class ReviewGateContractTests: XCTestCase {
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
            script.contains("thermo-nuclear-swift-review and claude"),
            "review-gate output must not frame missing local tools as the status."
        )
        XCTAssertFalse(
            script.contains("not installed in this shell"),
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
            docs.contains("thermo-nuclear-swift-review and claude still are not installed"),
            "PR process docs must not contain the old stale status wording."
        )
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
