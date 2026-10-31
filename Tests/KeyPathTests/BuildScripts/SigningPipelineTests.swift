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

    private func devSigningIdentity(listing: String, preferred: String = "Developer ID Application: Micah Alpern (X2RKZ5TG99)") throws -> String {
        let listingFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try listing.write(to: listingFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listingFile) }

        let result = runScript("""
        set -euo pipefail
        source \(signingLibPath)
        KP_FIND_IDENTITY_CMD="cat \(listingFile.path)" kp_dev_signing_identity "\(preferred)"
        """)
        XCTAssertEqual(result.code, 0, result.stderr)
        // `bash -l` may print profile output first; the identity is the last line.
        return result.stdout.split(separator: "\n").last.map(String.init) ?? ""
    }

    func testDevSigningPrefersDeveloperIDWhenPresent() throws {
        let identity = try devSigningIdentity(listing: """
          1) AAAA "Apple Development: Micah Alpern (3YFH89N33S)"
          2) BBBB "Developer ID Application: Micah Alpern (X2RKZ5TG99)"
        """)
        XCTAssertEqual(identity, "Developer ID Application: Micah Alpern (X2RKZ5TG99)")
    }

    func testDevSigningFallsBackToAppleDevelopmentByHash() throws {
        let identity = try devSigningIdentity(listing: """
          1) AAAA "Apple Development: Micah Alpern (3YFH89N33S)"
             1 valid identities found
        """)
        XCTAssertEqual(identity, "AAAA")
    }

    func testDevSigningIsEmptyWithoutAUsableIdentity() throws {
        let identity = try devSigningIdentity(listing: """
          1) CCCC "Apple Distribution: Micah Alpern (X2RKZ5TG99)"
             1 valid identities found
        """)
        XCTAssertEqual(identity, "", "A certificate that cannot sign development builds means ad-hoc.")
    }

    func testDevSigningTakesOneHashWhenARenewedCertificateSharesTheName() throws {
        let identity = try devSigningIdentity(listing: """
          1) AAAA "Apple Development: Micah Alpern (3YFH89N33S)"
          2) BBBB "Apple Development: Micah Alpern (3YFH89N33S)"
             2 valid identities found
        """)
        XCTAssertEqual(identity, "AAAA")
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

    func testNotaryWrapperPreservesCandidateWhenSubmitClientFailsAfterUpload() throws {
        let fixture = try makeNotaryFixture(
            waitExit: 0,
            infoStatus: nil,
            submitExit: 138,
            submitOutput: "",
            submitError: "notarytool terminated unexpectedly",
            historyEntries: [
                [
                    "id": submissionID,
                    "name": "KeyPath.zip",
                    "status": "In Progress",
                    "createdDate": "2099-07-25T16:21:02.550Z",
                ],
            ]
        )
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 138)
        XCTAssertTrue(result.stderr.contains("client exited 138"))
        XCTAssertTrue(result.stderr.contains("notarytool terminated unexpectedly"))
        XCTAssertTrue(result.stderr.contains("Do not retry automatically"))
        XCTAssertTrue(result.stderr.contains(submissionID))

        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "submit-client-failed")
        XCTAssertEqual(state["submitExitCode"] as? Int, 138)
        XCTAssertEqual(state["submitStderr"] as? String, "notarytool terminated unexpectedly")
        let candidates = try XCTUnwrap(state["candidateSubmissions"] as? [[String: Any]])
        XCTAssertEqual(candidates.compactMap { $0["id"] as? String }, [submissionID])

        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(invocations.contains("history --keychain-profile KeyPath-Profile --output-format json"))
    }

    func testNotaryWrapperPreservesAllRecentCandidatesWhenSubmitRecoveryIsAmbiguous() throws {
        let alternateSubmissionID = "ed168bf6-1910-4bb9-9d57-9114cea6e013"
        let fixture = try makeNotaryFixture(
            waitExit: 0,
            infoStatus: nil,
            submitExit: 138,
            submitOutput: "",
            historyEntries: [
                [
                    "id": submissionID,
                    "name": "KeyPath.zip",
                    "status": "In Progress",
                    "createdDate": "2099-07-25T16:21:02.550Z",
                ],
                [
                    "id": alternateSubmissionID,
                    "name": "KeyPath.zip",
                    "status": "In Progress",
                    "createdDate": "2099-07-25T16:22:20.233Z",
                ],
            ]
        )
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 138)
        XCTAssertTrue(result.stderr.contains(submissionID))
        XCTAssertTrue(result.stderr.contains(alternateSubmissionID))

        let state = try notaryState(at: fixture.state)
        let candidates = try XCTUnwrap(state["candidateSubmissions"] as? [[String: Any]])
        XCTAssertEqual(candidates.compactMap { $0["id"] as? String }, [submissionID, alternateSubmissionID])
        XCTAssertNil(state["submissionId"] as? String)
    }

    func testNotaryWrapperKeepsAuthoritativeSubmitIDWhenClientExitsAfterResponse() throws {
        let fixture = try makeNotaryFixture(
            waitExit: 0,
            infoStatus: nil,
            submitExit: 138,
            submitOutput: "{\"id\":\"\(submissionID)\",\"message\":\"Successfully uploaded file\"}",
            historyEntries: [
                [
                    "id": "ed168bf6-1910-4bb9-9d57-9114cea6e013",
                    "name": "KeyPath.zip",
                    "status": "In Progress",
                    "createdDate": "2099-07-25T16:22:20.233Z",
                ],
            ]
        )
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 138)
        XCTAssertTrue(result.stderr.contains("captured before the local client failed: \(submissionID)"))
        XCTAssertFalse(result.stdout.contains(submissionID))

        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["submissionId"] as? String, submissionID)
        XCTAssertTrue((state["candidateSubmissions"] as? [[String: Any]])?.isEmpty == true)

        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertFalse(invocations.contains("history --keychain-profile"))
    }

    func testNotaryWrapperWritesRecoveryStateWhenHistoryIsMalformed() throws {
        let fixture = try makeNotaryFixture(
            waitExit: 0,
            infoStatus: nil,
            submitExit: 138,
            submitOutput: "",
            historyOutput: "[]"
        )
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 138)
        XCTAssertTrue(result.stderr.contains("Recovery state: \(fixture.state.path)"))

        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "submit-client-failed")
        XCTAssertTrue((state["candidateSubmissions"] as? [[String: Any]])?.isEmpty == true)
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

    func testNotaryWrapperRecordsPermanentInvalidStatus() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Invalid", infoStatus: nil)
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 1)
        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "invalid")
        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertFalse(invocations.contains("info \(submissionID)"))
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

    func testNotaryWrapperUsesAPIKeyAuthWhenConfigured() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Accepted", infoStatus: nil)
        let keyFile = fixture.archive.deletingLastPathComponent().appendingPathComponent("AuthKey_TESTKEY.p8")
        try Data("test key".utf8).write(to: keyFile)

        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        KP_NOTARY_KEY_PATH="\(keyFile.path)"
        KP_NOTARY_KEY_ID="TESTKEY"
        KP_NOTARY_ISSUER="00000000-0000-0000-0000-000000000000"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 0, result.stderr)
        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(invocations.contains("--key \(keyFile.path) --key-id TESTKEY --issuer 00000000-0000-0000-0000-000000000000"))
        XCTAssertFalse(invocations.contains("--keychain-profile"))
        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "accepted")
    }

    func testNotaryWrapperRejectsIncompleteAPIKeyConfiguration() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Accepted", infoStatus: nil)
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        KP_NOTARY_KEY_PATH="/tmp/AuthKey_MISSINGBITS.p8"
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("KP_NOTARY_KEY_ID or KP_NOTARY_ISSUER"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.log.path), "no notarytool call should be made with incomplete key auth")
    }

    func testNotaryAwaitSubmissionResumesRecordedSubmission() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Accepted", infoStatus: nil)
        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        kp_notary_await_submission "\(submissionID)" "KeyPath-Profile" "\(fixture.state.path)" "\(fixture.archive.path)" "0000000000000000000000000000000000000000000000000000000000000000"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Apple notarization accepted submission \(submissionID)"))
        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(invocations.contains("wait \(submissionID) --keychain-profile KeyPath-Profile"))
        XCTAssertFalse(invocations.contains("submit "), "resume must not re-upload the archive")
        let state = try notaryState(at: fixture.state)
        XCTAssertEqual(state["status"] as? String, "accepted")
        XCTAssertEqual(state["submissionId"] as? String, submissionID)
    }

    func testNotaryForcedKeychainProfileBeatsPopulatedKeyPath() throws {
        let fixture = try makeNotaryFixture(waitExit: 0, waitStatus: "Accepted", infoStatus: nil)
        let keyFile = fixture.archive.deletingLastPathComponent().appendingPathComponent("AuthKey_STALE.p8")
        try Data("stale key".utf8).write(to: keyFile)

        let script = """
        unset KP_SIGN_DRY_RUN
        source \(signingLibPath)
        KP_NOTARY_CMD="\(fixture.stub.path)"
        KP_NOTARY_STATE_FILE="\(fixture.state.path)"
        KP_NOTARY_KEY_PATH="\(keyFile.path)"
        KP_NOTARY_KEY_ID="STALE"
        KP_NOTARY_ISSUER="00000000-0000-0000-0000-000000000000"
        KP_NOTARY_AUTH=keychain-profile
        kp_notarize_zip "\(fixture.archive.path)" "KeyPath-Profile"
        """
        let result = runScript(script, env: ["KP_NOTARY_TEST_LOG": fixture.log.path])

        XCTAssertEqual(result.code, 0, result.stderr)
        let invocations = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(invocations.contains("--keychain-profile KeyPath-Profile"))
        XCTAssertFalse(invocations.contains("--key "), "forced keychain-profile auth must ignore a populated key path")
    }

    func testNotaryDefaultAuthPrefersApiKeyFileAndRespectsOptOut() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appendingPathComponent("AuthKey_DEFAULT.p8")
        try Data("test key".utf8).write(to: keyFile)

        let script = """
        source \(signingLibPath)
        unset KP_NOTARY_KEY_PATH KP_NOTARY_AUTH
        KP_NOTARY_DEFAULT_KEY_PATH="\(keyFile.path)"
        kp_notary_default_auth_from_environment
        echo "auto:${KP_NOTARY_KEY_PATH:-none}"
        unset KP_NOTARY_KEY_PATH
        KP_NOTARY_AUTH=keychain-profile
        kp_notary_default_auth_from_environment
        echo "forced:${KP_NOTARY_KEY_PATH:-none}"
        """
        let result = runScript(script)

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("auto:\(keyFile.path)"))
        XCTAssertTrue(result.stdout.contains("forced:none"))
    }

    func testXcodeSelectionRefusesADirectoryWithoutXcodebuild() throws {
        // Stands in for Command Line Tools: a developer directory with no xcodebuild.
        let notXcode = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-not-xcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notXcode, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notXcode) }
        let result = runScript(
            "source Scripts/lib/xcode.sh && keypath_use_selected_xcode",
            env: ["KEYPATH_DEV_XCODE_DEVELOPER_DIR": notXcode.path]
        )

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("is not a full Xcode developer directory"), result.stderr)
    }

    func testBetaGuardMatchesBetaPathsAndVersionsButNotReleaseBuildNumbers() {
        let result = runScript("""
        source Scripts/lib/xcode.sh
        check() { if keypath_xcode_looks_beta "$1" "$2"; then echo "$1|$2=beta"; else echo "$1|$2=release"; fi; }
        check /Applications/Xcode-beta.app/Contents/Developer 27.1
        check /Applications/Xcode.app/Contents/Developer "27.1 beta 2"
        check /Applications/Xcode.app/Contents/Developer 16.0
        check /Applications/Xcode-27.app/Contents/Developer 27.0
        """)

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Xcode-beta.app/Contents/Developer|27.1=beta"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Xcode.app/Contents/Developer|27.1 beta 2=beta"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Xcode.app/Contents/Developer|16.0=release"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Xcode-27.app/Contents/Developer|27.0=release"), result.stdout)
    }

    func testShippingConfirmationMatchesOnlyTheExactNonEmptyBuild() {
        let result = runScript("""
        source Scripts/lib/xcode.sh
        check() { if keypath_xcode_confirmed "$1"; then echo "$2=confirmed"; else echo "$2=refused"; fi; }
        unset KEYPATH_CONFIRM_XCODE
        check "" empty-build-unset
        check 27A266a unset
        KEYPATH_CONFIRM_XCODE="" check "" empty-build-empty
        KEYPATH_CONFIRM_XCODE=27A266a check 27A266b mismatch
        KEYPATH_CONFIRM_XCODE=27A266a check 27A266a match
        """)

        XCTAssertEqual(result.code, 0, result.stderr)
        for refused in ["empty-build-unset", "unset", "empty-build-empty", "mismatch"] {
            XCTAssertTrue(result.stdout.contains("\(refused)=refused"), result.stdout)
        }
        XCTAssertTrue(result.stdout.contains("match=confirmed"), result.stdout)
    }

    func testXcodeSelectionDefaultsToXcodeSelectWithoutOverride() throws {
        let selected = runScript("/usr/bin/xcode-select -p").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "\(selected)/usr/bin/xcodebuild"),
                          "needs a full Xcode selected on this machine")
        // `xcode-select -p` reports an exported DEVELOPER_DIR, so it drives the default branch here.
        let notXcode = FileManager.default.temporaryDirectory.appendingPathComponent("keypath-not-xcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: notXcode, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notXcode) }
        let chosen = runScript(
            #"unset KEYPATH_DEV_XCODE_DEVELOPER_DIR; source Scripts/lib/xcode.sh && keypath_use_selected_xcode && echo "dev=$DEVELOPER_DIR""#,
            env: ["DEVELOPER_DIR": selected]
        )
        let refused = runScript(
            "unset KEYPATH_DEV_XCODE_DEVELOPER_DIR; source Scripts/lib/xcode.sh && keypath_use_selected_xcode",
            env: ["DEVELOPER_DIR": notXcode.path]
        )

        XCTAssertEqual(chosen.code, 0, chosen.stderr)
        XCTAssertTrue(chosen.stdout.contains("dev=\(selected)"), chosen.stdout)
        XCTAssertNotEqual(refused.code, 0)
        XCTAssertTrue(refused.stderr.contains("is not a full Xcode developer directory"), refused.stderr)
    }

    func testXcodeSelectionHonorsOverrideAndExportsMatchingSDK() throws {
        let selected = runScript("/usr/bin/xcode-select -p").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "\(selected)/usr/bin/xcodebuild"),
                          "needs a full Xcode selected on this machine")
        let result = runScript(
            #"source Scripts/lib/xcode.sh && keypath_use_selected_xcode && echo "dev=$DEVELOPER_DIR" && echo "sdk=$SDKROOT""#,
            env: ["KEYPATH_DEV_XCODE_DEVELOPER_DIR": selected]
        )

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("dev=\(selected)"), result.stdout)
        XCTAssertTrue(result.stdout.contains("sdk=\(selected)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"), result.stdout)
    }

    func testPinnedNotarytoolSupportsExplicitNoWait() {
        let script = """
        source Scripts/lib/xcode.sh
        keypath_use_selected_xcode
        xcrun notarytool submit --help
        """
        let result = runScript(script)

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("--wait/--no-wait"))
    }

    private func makeNotaryFixture(
        waitExit: Int32,
        waitStatus: String? = nil,
        infoStatus: String?,
        submitID: String? = nil,
        submitExit: Int32 = 0,
        submitOutput: String? = nil,
        submitError: String? = nil,
        historyOutput: String? = nil,
        historyEntries: [[String: String]] = []
    ) throws -> (archive: URL, stub: URL, log: URL, state: URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

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
        let resolvedSubmitOutput = submitOutput ?? "{\"id\":\"\(resolvedSubmitID)\",\"message\":\"Successfully uploaded file\"}"
        let historyJSON: String = if let historyOutput {
            historyOutput
        } else {
            try XCTUnwrap(
                String(
                    data: JSONSerialization.data(withJSONObject: ["history": historyEntries]),
                    encoding: .utf8
                )
            )
        }
        let submitErrorStatement = submitError.map {
            "printf '%s\\n' '\($0)' >&2"
        } ?? ":"
        let stubSource = """
        #!/bin/bash
        printf '%s\\n' "$*" >> "$KP_NOTARY_TEST_LOG"
        case "$1" in
            submit)
                case " $* " in
                    *" --no-wait "*) ;;
                    *) exit 64 ;;
                esac
                printf '%s\\n' '\(resolvedSubmitOutput)'
                \(submitErrorStatement)
                exit \(submitExit)
                ;;
            wait)
                \(waitResponse)
                exit \(waitExit)
                ;;
            info)
                \(infoResponse)
                ;;
            history)
                printf '%s\\n' '\(historyJSON)'
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
