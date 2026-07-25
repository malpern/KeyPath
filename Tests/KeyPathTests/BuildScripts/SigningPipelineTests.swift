import Foundation
@preconcurrency import XCTest

final class SigningPipelineTests: XCTestCase {
    private let signingLibPath = "Scripts/lib/signing.sh"
    private let submissionID = "68348f8a-cb0e-49ad-b130-8e071eb3c0f4"

    /// Simple helper to run a bash snippet and capture its exit code.
    private func runScript(_ script: String, env: [String: String] = [:]) -> (code: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]

        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0.key] = $0.value }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return (code: -1, stdout: "", stderr: "Failed to start process: \(error)")
        }
        process.waitUntilExit()

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

        return (
            code: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    func testCodesignWrapperRespectsDryRun() {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())

        let script = """
        set -e
        source \(signingLibPath)
        KP_SIGN_DRY_RUN=1 KP_SIGN_CMD=/bin/false kp_sign "\(tempFile.path)" --force
        """
        let result = runScript(script)
        XCTAssertEqual(result.code, 0, "Dry-run mode should not fail even if command is false. stderr: \(result.stderr)")
    }

    func testCodesignWrapperPropagatesFailures() {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())

        // Explicitly unset KP_SIGN_DRY_RUN to test real failure propagation
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_SIGN_CMD=/bin/false kp_sign "\(tempFile.path)" --force
        """
        let result = runScript(script)
        XCTAssertNotEqual(result.code, 0, "codesign wrapper should propagate underlying command failure")
    }

    func testNotaryWrapperPropagatesFailures() {
        // Explicitly unset KP_SIGN_DRY_RUN to test real failure propagation
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD=/bin/false kp_notarize_zip "/tmp/fake.zip" "NoProfile"
        """
        let result = runScript(script)
        XCTAssertNotEqual(result.code, 0, "notary wrapper should bubble up failures")
    }

    func testNotaryWrapperRejectsInaccessibleArchiveDirectory() {
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD=/bin/false kp_notarize_zip "/path/that/does/not/exist/KeyPath.zip" "NoProfile"
        """
        let result = runScript(script)

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("archive directory does not exist or is inaccessible"))
    }

    func testNotaryWrapperRejectsEmptySubmissionID() throws {
        let fixture = try makeNotaryFixture(
            waitExit: 0,
            infoStatus: nil,
            submitID: ""
        )
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("no parseable submission ID"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.state.path))
    }

    func testNotaryWrapperRecordsSubmissionBeforeBoundedWait() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Accepted", infoStatus: nil)
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        KP_NOTARY_KEYCHAIN="/tmp/keypath-notary.keychain-db"
        KP_NOTARY_WAIT_TIMEOUT="15m"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 0, result.stderr)
        let state = try notaryState(at: fixture.state)
        let recordedArchivePath = try XCTUnwrap(state["archivePath"] as? String)
        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(invocations.contains("submit \(recordedArchivePath)"))
        XCTAssertTrue(invocations.contains("--no-wait --output-format json --no-progress"))
        XCTAssertFalse(invocations.contains("submit \(recordedArchivePath) --keychain-profile KeyPath-Profile --keychain /tmp/keypath-notary.keychain-db --wait"))
        XCTAssertTrue(invocations.contains("wait \(submissionID)"))
        XCTAssertTrue(invocations.contains("--timeout 15m"))
        XCTAssertTrue(invocations.contains("--output-format json --no-progress"))
        XCTAssertFalse(invocations.contains("info \(submissionID)"))
        XCTAssertEqual(invocations.components(separatedBy: "--keychain /tmp/keypath-notary.keychain-db").count - 1, 2)

        XCTAssertEqual(state["submissionId"] as? String, submissionID)
        XCTAssertTrue(recordedArchivePath.hasSuffix("/KeyPath.zip"))
        XCTAssertEqual(state["status"] as? String, "accepted")
        XCTAssertEqual((state["archiveSHA256"] as? String)?.count, 64)
    }

    func testNotaryWrapperPreservesRecoveryEvidenceOnTimeout() throws {
        let fixture = try makeNotaryFixture(waitExit: 124, infoStatus: "In Progress")
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        KP_NOTARY_WAIT_TIMEOUT="15m"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        let state = try notaryState(at: fixture.state)
        let recordedArchivePath = try XCTUnwrap(state["archivePath"] as? String)
        XCTAssertEqual(result.code, 75)
        XCTAssertTrue(result.stdout.contains("Submission ID: \(submissionID)"))
        XCTAssertTrue(result.stdout.contains("Recovery state: \(fixture.state.path)"))
        XCTAssertTrue(result.stdout.contains("Check the existing submission before considering a retry"))
        XCTAssertTrue(result.stdout.contains("Do not submit another archive automatically"))
        XCTAssertTrue(result.stdout.contains("shasum -a 256 \"\(recordedArchivePath)\""))

        XCTAssertEqual(state["status"] as? String, "in-progress")
        XCTAssertEqual(state["submissionId"] as? String, submissionID)
    }

    func testNotaryWrapperRecoversWhenWaitClientFailsAfterAcceptance() throws {
        let fixture = try makeNotaryFixture(waitExit: 138, infoStatus: "Accepted")
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Apple notarization accepted submission \(submissionID)"))
        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "accepted")
    }

    func testNotaryWrapperDryRunShowsBoundedTwoPhaseFlow() {
        let script = """
        source \(signingLibPath)
        KP_SIGN_DRY_RUN=1
        KP_NOTARY_WAIT_TIMEOUT=15m
        KP_NOTARY_STATE_FILE=/tmp/KeyPath.notary-submission.json
        kp_notarize_zip "/tmp/KeyPath.zip" "KeyPath-Profile"
        """
        let result = runScript(script)

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("submit /tmp/KeyPath.zip"))
        XCTAssertTrue(result.stdout.contains("--no-wait --output-format json --no-progress"))
        XCTAssertTrue(result.stdout.contains("wait <submission-id>"))
        XCTAssertTrue(result.stdout.contains("--timeout 15m"))
        XCTAssertTrue(result.stdout.contains("persist submission evidence to /tmp/KeyPath.notary-submission.json"))
    }

    func testPinnedNotarytoolSupportsExplicitNoWait() {
        let result = runScript("xcrun notarytool submit --help")

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("--wait/--no-wait"))
    }

    private func makeNotaryFixture(
        waitExit: Int32,
        waitStatus: String? = nil,
        infoStatus: String?,
        submitID: String? = nil
    ) throws -> (archive: URL, stub: URL, log: URL, state: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let archive = directory.appendingPathComponent("KeyPath.zip")
        try Data("signed KeyPath archive".utf8).write(to: archive)
        let log = directory.appendingPathComponent("notary-invocations.log")
        let state = directory.appendingPathComponent("KeyPath.notary-submission.json")
        let stub = directory.appendingPathComponent("notarytool-stub")
        let waitResponse = waitStatus.map {
            "printf '%s\\n' '{\"id\":\"\(submissionID)\",\"status\":\"\($0)\"}'"
        } ?? ":"
        let infoResponse = infoStatus.map {
            "printf '%s\\n' '{\"id\":\"\(submissionID)\",\"status\":\"\($0)\"}'"
        } ?? "exit 69"
        let resolvedSubmitID = submitID ?? submissionID
        let stubSource = """
        #!/bin/bash
        printf '%s\\n' "$*" >> "$KP_NOTARY_TEST_LOG"
        case "$1" in
            submit)
                case " $* " in
                    *" --no-wait "*) ;;
                    *) exit 64 ;;
                esac
                printf '%s\\n' '{"id":"\(resolvedSubmitID)","message":"Successfully uploaded file"}'
                ;;
            wait)
                \(waitResponse)
                exit \(waitExit)
                ;;
            info)
                \(infoResponse)
                ;;
            *)
                exit 2
                ;;
        esac
        """
        try stubSource.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        return (archive, stub, log, state)
    }

    private func notaryState(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
