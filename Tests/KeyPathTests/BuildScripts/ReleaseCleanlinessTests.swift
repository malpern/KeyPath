import Foundation
@preconcurrency import XCTest

final class ReleaseCleanlinessTests: XCTestCase {
    func testCleanRepositoryPasses() throws {
        let repository = try makeRepository()

        let result = runCleanlinessGate(in: repository)

        XCTAssertEqual(result.code, 0, result.stderr)
        XCTAssertEqual(result.stderr, "")
    }

    func testTrackedAndUntrackedRepositoryChangesFail() throws {
        let repository = try makeRepository()
        try "changed\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "untracked\n".write(
            to: repository.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = runCleanlinessGate(in: repository)

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("Release repository has tracked, staged, or untracked changes"))
        XCTAssertTrue(result.stderr.contains("README.md"))
        XCTAssertTrue(result.stderr.contains("notes.txt"))
        XCTAssertTrue(result.stderr.contains("refusing to build an unattributable artifact"))
    }

    func testDirtyLockfileGetsSpecificFailure() throws {
        let repository = try makeRepository()
        try "changed-lock\n".write(
            to: repository.appendingPathComponent("Rust/Bridge/Cargo.lock"),
            atomically: true,
            encoding: .utf8
        )

        let result = runCleanlinessGate(in: repository)

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("Release lockfiles do not match HEAD"))
        XCTAssertTrue(result.stderr.contains("Rust/Bridge/Cargo.lock"))
    }

    func testDirtySubmoduleWorkingTreeFails() throws {
        let parent = try makeRepository()
        let child = try makeRepository()
        try addSubmodule(child, to: parent)
        let submodule = parent.appendingPathComponent("External/kanata", isDirectory: true)
        try "dirty\n".write(
            to: submodule.appendingPathComponent("local-change.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = runCleanlinessGate(in: parent)

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(result.stderr.contains("Release submodule working trees are dirty"))
        XCTAssertTrue(result.stderr.contains("External/kanata"))
        XCTAssertTrue(result.stderr.contains("local-change.txt"))
    }

    func testUninitializedSubmoduleFails() throws {
        let parent = try makeRepository()
        let child = try makeRepository()
        try addSubmodule(child, to: parent)

        let clone = temporaryDirectory().appendingPathComponent("clone", isDirectory: true)
        try runGit(["clone", parent.path, clone.path], at: parent.deletingLastPathComponent())

        let result = runCleanlinessGate(in: clone)

        XCTAssertNotEqual(result.code, 0)
        XCTAssertTrue(
            result.stderr.contains("Release submodules are uninitialized, conflicted, or not at the recorded revisions")
        )
        XCTAssertTrue(result.stderr.contains("External/kanata"))
    }

    func testCanonicalReleaseEntrypointsCannotBypassCleanlinessGate() throws {
        let root = repositoryRoot()
        let doctor = try contents(of: root.appendingPathComponent("Scripts/release-doctor.sh"))
        let candidate = try contents(of: root.appendingPathComponent("Scripts/release-candidate.sh"))
        let release = try contents(of: root.appendingPathComponent("Scripts/release.sh"))

        for (path, script) in [
            ("Scripts/release-doctor.sh", doctor),
            ("Scripts/release-candidate.sh", candidate),
            ("Scripts/release.sh", release),
        ] {
            XCTAssertTrue(
                script.contains(#"source "$SCRIPT_DIR/lib/release-cleanliness.sh""#),
                "\(path) must source the mandatory release cleanliness gate."
            )
            XCTAssertTrue(
                script.contains("kp_release_require_clean_source"),
                "\(path) must enforce source cleanliness."
            )
        }

        let candidateGate = try XCTUnwrap(candidate.range(of: "kp_release_require_clean_source"))
        let candidateBuild = try XCTUnwrap(candidate.range(of: #""$SCRIPT_DIR/build-and-sign.sh""#))
        XCTAssertLessThan(
            candidate.distance(from: candidate.startIndex, to: candidateGate.lowerBound),
            candidate.distance(from: candidate.startIndex, to: candidateBuild.lowerBound)
        )

        let releaseGate = try XCTUnwrap(release.range(of: "kp_release_require_clean_source"))
        let versionMutation = try XCTUnwrap(release.range(of: #"PlistBuddy -c "Set :CFBundleVersion"#))
        XCTAssertLessThan(
            release.distance(from: release.startIndex, to: releaseGate.lowerBound),
            release.distance(from: release.startIndex, to: versionMutation.lowerBound),
            "Public release cleanliness must be checked before the script mutates version metadata."
        )
        XCTAssertFalse(release.contains("Continue anyway? [y/N]"))
    }

    private func runCleanlinessGate(in repository: URL) -> ProcessResult {
        let library = repositoryRoot()
            .appendingPathComponent("Scripts/lib/release-cleanliness.sh")
            .path
        return runShell(
            #"source "\#(library)"; kp_release_require_clean_source "\#(repository.path)""#,
            at: repository
        )
    }

    private func makeRepository() throws -> URL {
        let repository = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("Rust/Bridge", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "clean\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "resolved\n".write(
            to: repository.appendingPathComponent("Package.resolved"),
            atomically: true,
            encoding: .utf8
        )
        try "lock\n".write(
            to: repository.appendingPathComponent("Rust/Bridge/Cargo.lock"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["init"], at: repository)
        try runGit(["config", "user.name", "KeyPath Tests"], at: repository)
        try runGit(["config", "user.email", "tests@keypath.local"], at: repository)
        try runGit(["add", "."], at: repository)
        try runGit(["commit", "-m", "fixture"], at: repository)
        return repository
    }

    private func addSubmodule(_ child: URL, to parent: URL) throws {
        try runGit(
            ["-c", "protocol.file.allow=always", "submodule", "add", child.path, "External/kanata"],
            at: parent
        )
        try runGit(["commit", "-am", "add submodule"], at: parent)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let result = runExecutable("/usr/bin/git", arguments: arguments, at: directory)
        guard result.code == 0 else {
            throw NSError(
                domain: "ReleaseCleanlinessTests",
                code: Int(result.code),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(result.stderr)"]
            )
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keypath-release-cleanliness-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct ProcessResult {
    let code: Int32
    let stdout: String
    let stderr: String
}

private func runShell(_ script: String, at directory: URL) -> ProcessResult {
    runExecutable("/bin/bash", arguments: ["-c", script], at: directory)
}

private func runExecutable(_ path: String, arguments: [String], at directory: URL) -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.currentDirectoryURL = directory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ProcessResult(code: -1, stdout: "", stderr: error.localizedDescription)
    }

    return ProcessResult(
        code: process.terminationStatus,
        stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // BuildScripts
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

private func contents(of url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}
