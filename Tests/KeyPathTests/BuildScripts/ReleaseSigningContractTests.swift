import Foundation
@preconcurrency import XCTest

final class ReleaseSigningContractTests: XCTestCase {
    func testReleaseSigningContractScriptPassesFromSource() {
        let root = repositoryRoot()
        let script = root.appendingPathComponent("Scripts/verify-release-signing-contract.sh")

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path))

        let result = runScript("\"\(script.path)\" --source", workingDirectory: root)
        XCTAssertEqual(
            result.code,
            0,
            """
            Release signing contract should pass from source.
            stdout:
            \(result.stdout)
            stderr:
            \(result.stderr)
            """
        )
        XCTAssertTrue(result.stdout.contains("Release signing contract passed."))
    }

    func testReleaseSigningContractIsPartOfReleaseGates() throws {
        let root = repositoryRoot()
        let buildAndSign = try contents(of: root.appendingPathComponent("Scripts/build-and-sign.sh"))
        let releaseDoctor = try contents(of: root.appendingPathComponent("Scripts/release-doctor.sh"))

        XCTAssertTrue(
            buildAndSign.contains(#""$SCRIPT_DIR/verify-release-signing-contract.sh" --source"#),
            "build-and-sign must run the source signing contract before expensive signing/notarization work."
        )
        XCTAssertTrue(
            releaseDoctor.contains(#"verify-release-signing-contract.sh" --source"#),
            "release-doctor must run the source signing contract during release preflight."
        )
    }
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // BuildScripts
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

private func runScript(_ script: String, workingDirectory: URL) -> (code: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-lc", script]
    process.currentDirectoryURL = workingDirectory

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
