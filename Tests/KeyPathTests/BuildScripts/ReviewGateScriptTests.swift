import Foundation
@preconcurrency import XCTest

/// Scripts/review-gate.sh must review what the branch would ship and pass only
/// on an explicit PASS verdict. Runs the real script in a scratch repository
/// with a stub `claude` on PATH.
final class ReviewGateScriptTests: XCTestCase {
    private var repo: URL!
    private var stubs: URL!

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            url.deleteLastPathComponent()
        }
        return url
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String], env extra: [String: String] = [:]) throws -> (code: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = repo
        var env = ["PATH": "\(stubs.path):/usr/bin:/bin:/opt/homebrew/bin", "HOME": NSTemporaryDirectory(),
                   "TMPDIR": NSTemporaryDirectory(), "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                   "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_NOSYSTEM": "1"]
        env.merge(extra) { $1 }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }

    private func git(_ args: String...) throws {
        try run("/usr/bin/env", ["git"] + args)
    }

    private func gate(_ env: [String: String] = [:]) throws -> (code: Int32, out: String, err: String) {
        try run("/bin/bash", ["Scripts/review-gate.sh"], env: env)
    }

    private var reviewed: String {
        (try? String(contentsOf: stubs.appendingPathComponent("stdin.txt"), encoding: .utf8)) ?? ""
    }

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-gate-\(UUID().uuidString)")
        repo = root.appendingPathComponent("repo")
        stubs = root.appendingPathComponent("stubs")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.repositoryRoot.appendingPathComponent("Scripts/review-gate.sh"),
                                         to: repo.appendingPathComponent("Scripts/review-gate.sh"))
        // The stub records what it was asked to review and answers as told.
        let stub = stubs.appendingPathComponent("claude")
        try """
        #!/bin/bash
        cat > "\(stubs.path)/stdin.txt"
        echo "Findings: none worth noting."
        [[ -n "${STUB_VERDICT:-}" ]] && echo "REVIEW-VERDICT: $STUB_VERDICT"
        exit "${STUB_EXIT:-0}"
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        try git("init", "-q", "-b", "master")
        try "base\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try git("add", "-A")
        try git("commit", "-q", "-m", "base")
        try git("update-ref", "refs/remotes/origin/master", "HEAD")
        try git("checkout", "-q", "-b", "feature")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repo.deletingLastPathComponent())
    }

    private func commitChange() throws {
        try "committed change\n".write(to: repo.appendingPathComponent("committed.txt"), atomically: true, encoding: .utf8)
        try git("add", "-A")
        try git("commit", "-q", "-m", "change")
    }

    func testPassesOnlyOnAnExplicitPassVerdictAndRunsTwice() throws {
        try commitChange()
        for _ in 0 ..< 2 { // the old fixed mktemp name collided on the second run
            let result = try gate(["STUB_VERDICT": "PASS"])
            XCTAssertEqual(result.code, 0, result.err)
        }
        XCTAssertTrue(reviewed.contains("committed change"), reviewed)
    }

    func testAConfirmedFindingFailsTheGate() throws {
        try commitChange()
        XCTAssertEqual(try gate(["STUB_VERDICT": "FAIL"]).code, 1)
    }

    func testAReviewWithoutAVerdictFailsTheGate() throws {
        try commitChange()
        let result = try gate()
        XCTAssertEqual(result.code, 1)
        XCTAssertTrue(result.err.contains("no REVIEW-VERDICT line"), result.err)
    }

    func testAReviewThatDidNotCompleteFailsTheGate() throws {
        try commitChange()
        XCTAssertEqual(try gate(["STUB_VERDICT": "PASS", "STUB_EXIT": "3"]).code, 1)
    }

    func testUncommittedAndUntrackedWorkIsReviewed() throws {
        try "edited\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try "brand new\n".write(to: repo.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try gate(["STUB_VERDICT": "PASS"]).code, 0)
        XCTAssertTrue(reviewed.contains("edited"), reviewed)
        XCTAssertTrue(reviewed.contains("brand new"), reviewed)
    }

    func testNothingToReviewNeverAsksTheReviewer() throws {
        let result = try gate(["STUB_VERDICT": "FAIL"])
        XCTAssertEqual(result.code, 0)
        XCTAssertTrue(result.out.contains("no branch or working-tree diff"), result.out)
        XCTAssertEqual(reviewed, "")
    }
}
