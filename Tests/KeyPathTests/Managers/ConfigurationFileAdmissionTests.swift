import Darwin
import Foundation
@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class ConfigurationFileAdmissionTests: KeyPathTestCase {
    private let original = "(defcfg)\n(defsrc a)\n(deflayer base a)"
    private let replacement = "(defcfg)\n(defsrc a)\n(deflayer base b)"

    func testWritableDirectoryDoesNotRequireAWritableParent() async throws {
        // /private is not writable by this user, while /private/tmp is.
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let gate = ConfigurationOperationGate(configurationDirectory: directory)
        let result = try await gate.withOperation { _ in 17 }
        XCTAssertEqual(result, 17)
        XCTAssertNotEqual(ConfigurationOperationGate.lockFileURL(for: directory).deletingLastPathComponent().path, "/private")
    }

    func testDirectoryBackedGateAllowsExplicitNestedPermit() async throws {
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let result = try await gate.withOperation { permit in
                try await gate.withOperation(using: permit) { _ in 42 }
            }
            XCTAssertEqual(result, 42)
        }
    }

    func testLeaseExcludesAnotherProcessAndReleasesAfterCompletion() async throws {
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let lockURL = ConfigurationOperationGate.lockFileURL(for: directory)
            try await gate.withOperation { _ in
                let status = try await Self.probeFromChildProcess(lockURL)
                XCTAssertEqual(status, 23, "A separate process must observe the held lease")
            }
            let status = try await Self.probeFromChildProcess(lockURL)
            XCTAssertEqual(status, 0)
        }
    }

    func testIndependentServicesWaitForTheSameDirectory() async throws {
        try await withDirectory { directory in
            let firstService = ConfigurationService(configDirectory: directory.path)
            let secondService = ConfigurationService(configDirectory: directory.path)
            let entered = self.expectation(description: "first operation entered")
            let forbidden = self.expectation(description: "second write must wait")
            forbidden.isInverted = true
            let completionCheck = CompletionCheck()
            var resume: CheckedContinuation<Void, Never>?
            let first = Task { @MainActor in
                try await firstService.operationGate.withOperation { @MainActor _ in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let second = Task { @MainActor in
                try await secondService.writeConfigurationContent(self.replacement)
                if completionCheck.isBlocked { forbidden.fulfill() }
            }
            await self.fulfillment(of: [forbidden], timeout: 0.15)
            completionCheck.isBlocked = false
            XCTAssertEqual(try String(contentsOfFile: firstService.configurationPath, encoding: .utf8), self.original)
            resume?.resume()
            try await first.value
            try await second.value
            XCTAssertEqual(try String(contentsOfFile: secondService.configurationPath, encoding: .utf8), self.replacement)
        }
    }

    func testAliasCallbackCannotReenterOrReleaseTheOriginalLease() async throws {
        try await withDirectory { directory in
            let alias = directory.deletingLastPathComponent().appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
            let first = ConfigurationService(configDirectory: directory.path)
            let second = ConfigurationService(configDirectory: alias.path)
            try await first.operationGate.withOperation { @MainActor _ in
                do {
                    try await second.writeConfigurationContent(self.replacement)
                    XCTFail("An alias must not let a callback reenter the same directory")
                } catch ConfigurationOperationGate.Failure.recursiveOperation {
                    // Expected before writing.
                }
                let status = try await Self.probeFromChildProcess(ConfigurationOperationGate.lockFileURL(for: directory))
                XCTAssertEqual(status, 23, "Closing the rejected caller's descriptor must not unlock the owner")
            }
            XCTAssertEqual(try String(contentsOfFile: first.configurationPath, encoding: .utf8), self.original)
        }
    }

    func testCallbackRejectsBeforeQueueingBehindAnotherFileLockWaiter() async throws {
        try await withDirectory { directory in
            let owner = ConfigurationOperationGate(configurationDirectory: directory)
            let other = ConfigurationOperationGate(configurationDirectory: directory)
            let entered = self.expectation(description: "owner entered")
            let waiting = self.expectation(description: "other service is waiting")
            waiting.isInverted = true
            let callbackFinished = self.expectation(description: "callback rejects without waiting for owner release")
            let callbackStarted = self.expectation(description: "callback started")
            let phase = CompletionCheck()
            var startCallback: CheckedContinuation<Void, Never>?
            var releaseOwner: CheckedContinuation<Void, Never>?
            var callback: Task<Void, Never>?
            let first = Task { @MainActor in
                try await owner.withOperation { @MainActor _ in
                    await withCheckedContinuation { continuation in
                        startCallback = continuation
                        entered.fulfill()
                    }
                    callback = Task {
                        do {
                            _ = try await other.withOperation { _ in true }
                            XCTFail("Callback must reject before the other service's FIFO queue")
                        } catch ConfigurationOperationGate.Failure.recursiveOperation {
                            // Expected while the original lease remains held.
                        } catch { XCTFail("Unexpected error: \(error)") }
                        callbackFinished.fulfill()
                    }
                    await withCheckedContinuation { continuation in
                        releaseOwner = continuation
                        callbackStarted.fulfill()
                    }
                }
            }
            await self.fulfillment(of: [entered], timeout: 5)
            let second = Task {
                try await other.withOperation { @MainActor _ in
                    if phase.isBlocked { waiting.fulfill() }
                }
            }
            await self.fulfillment(of: [waiting], timeout: 0.15)
            startCallback?.resume()
            await self.fulfillment(of: [callbackStarted, callbackFinished], timeout: 2)
            phase.isBlocked = false
            releaseOwner?.resume()
            try await first.value
            try await second.value
            await callback?.value
        }
    }

    func testDirectoryReplacementAndThrowPreserveThenReleaseTheLease() async throws {
        enum Expected: Error { case failure }
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let lockURL = ConfigurationOperationGate.lockFileURL(for: directory)
            do {
                try await gate.withOperation { _ in
                    let backup = directory.deletingLastPathComponent().appendingPathComponent("old-config")
                    try FileManager.default.moveItem(at: directory, to: backup)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    XCTAssertEqual(ConfigurationOperationGate.lockFileURL(for: directory), lockURL)
                    let status = try await Self.probeFromChildProcess(lockURL)
                    XCTAssertEqual(status, 23)
                    throw Expected.failure
                }
            } catch Expected.failure {
                // Expected, including descriptor release.
            }
            let status = try await Self.probeFromChildProcess(lockURL)
            XCTAssertEqual(status, 0)
            let value = try await gate.withOperation { _ in 7 }
            XCTAssertEqual(value, 7)
        }
    }

    func testCancelledFileWaitLeavesNoMutationAndReleasesItsQueueSlot() async throws {
        try await withDirectory { directory in
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            let lockURL = ConfigurationOperationGate.lockFileURL(for: directory)
            let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
            XCTAssertGreaterThanOrEqual(fd, 0)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }
            XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
            let started = self.expectation(description: "wait requested")
            let forbidden = self.expectation(description: "operation cannot enter")
            forbidden.isInverted = true
            let waiting = Task { @MainActor in
                started.fulfill()
                try await gate.withOperation { _ in forbidden.fulfill() }
            }
            await self.fulfillment(of: [started], timeout: 5)
            await self.fulfillment(of: [forbidden], timeout: 0.15)
            waiting.cancel()
            do {
                try await waiting.value
                XCTFail("A cancelled file wait must not enter its operation")
            } catch is CancellationError {
                // Expected while the other file description still owns the lock.
            }
            XCTAssertEqual(flock(fd, LOCK_UN), 0)
            let value = try await gate.withOperation { _ in 9 }
            XCTAssertEqual(value, 9)
        }
    }

    func testChildOutlivingItsLeaseCanUseAnotherServiceLater() async throws {
        try await withDirectory { directory in
            let first = ConfigurationOperationGate(configurationDirectory: directory)
            let second = ConfigurationOperationGate(configurationDirectory: directory)
            let childWaiting = self.expectation(description: "child waiting")
            var resume: CheckedContinuation<Void, Never>?
            let child = try await first.withOperation { @MainActor _ in
                let child = Task { @MainActor in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        childWaiting.fulfill()
                    }
                    return try await second.withOperation { _ in 11 }
                }
                await self.fulfillment(of: [childWaiting], timeout: 5)
                return child
            }
            resume?.resume()
            let value = try await child.value
            XCTAssertEqual(value, 11)
        }
    }

    @MainActor
    private final class CompletionCheck {
        var isBlocked = true
    }

    func testSymlinkSentinelIsRejectedBeforeMutation() async throws {
        try await withDirectory { directory in
            let lockURL = ConfigurationOperationGate.lockFileURL(for: directory)
            let target = directory.deletingLastPathComponent().appendingPathComponent("unrelated")
            try "preserve".write(to: target, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)
            let gate = ConfigurationOperationGate(configurationDirectory: directory)
            do {
                try await gate.withOperation { _ in XCTFail("A symlink sentinel must not admit a write") }
                XCTFail("Expected lock-open failure")
            } catch ConfigurationOperationGate.Failure.fileLock {
                // O_NOFOLLOW rejects it before acquiring or invoking the operation.
            }
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "preserve")
        }
    }

    private nonisolated static func probeFromChildProcess(_ lockURL: URL) async throws -> Int32 {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", """
            import fcntl, sys
            with open(sys.argv[1], 'a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    sys.exit(23)
            """, lockURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    private func withDirectory(_ body: @MainActor (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ConfigurationOperationGate.lockFileURL(for: directory).deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            // Only remove this test's unique sentinel after all its operations finish.
            try? FileManager.default.removeItem(at: ConfigurationOperationGate.lockFileURL(for: directory))
            try? FileManager.default.removeItem(at: root)
        }
        try original.write(to: directory.appendingPathComponent("keypath.kbd"), atomically: true, encoding: .utf8)
        try await body(directory)
    }
}
