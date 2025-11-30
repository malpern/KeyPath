@preconcurrency import XCTest

final class SigningPipelineTests: XCTestCase {
    private let signingLibPath = "Scripts/lib/signing.sh"

    // Simple helper to run a bash snippet and capture its exit code.
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

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            code: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    func testCodesignWrapperRespectsDryRun() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())

        let script = """
        set -e
        source \(signingLibPath)
        KP_SIGN_DRY_RUN=1 KP_SIGN_CMD=/bin/false kp_sign "\(tempFile.path)" --force
        """
        let result = runScript(script)
        XCTAssertEqual(result.code, 0, "Dry-run mode should not fail even if command is false. stderr: \(result.stderr)")
    }

    func testCodesignWrapperPropagatesFailures() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())

        let script = """
        source \(signingLibPath)
        KP_SIGN_CMD=/bin/false kp_sign "\(tempFile.path)" --force
        """
        let result = runScript(script)
        XCTAssertNotEqual(result.code, 0, "codesign wrapper should propagate underlying command failure")
    }

    func testNotaryWrapperPropagatesFailures() throws {
        let script = """
        source \(signingLibPath)
        KP_NOTARY_CMD=/bin/false kp_notarize_zip "/tmp/fake.zip" "NoProfile"
        """
        let result = runScript(script)
        XCTAssertNotEqual(result.code, 0, "notary wrapper should bubble up failures")
    }
}
