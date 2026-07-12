import Foundation
import XCTest

enum KanataCheckHelper {
    struct Result: Sendable {
        let exitCode: Int32
        let errors: [String]

        var isValid: Bool {
            exitCode == 0
        }
    }

    static func runCheck(_ config: String) async throws -> Result {
        guard let binary = findKanataBinary() else {
            throw XCTSkip("Kanata binary not found — skipping CLI validation")
        }

        return try await runCheck(config, binary: binary)
    }

    static func runCheck(_ config: String, binary: String) async throws -> Result {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanata-test-\(UUID().uuidString).kbd")
        try config.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--cfg", tempFile.path, "--check"]
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            let context = CheckRunContext(continuation: continuation)

            process.terminationHandler = { completedProcess in
                context.setExitCode(completedProcess.terminationStatus)
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).async {
                    context.setOutput(pipe.fileHandleForReading.readDataToEndOfFile())
                }
            } catch {
                context.fail(error)
            }
        }
    }

    private static func findKanataBinary() -> String? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["KEYPATH_KANATA_PATH"],
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Integration
                .deletingLastPathComponent() // KeyPathTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/kanata")
                .path,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
            "/opt/homebrew/bin/kanata",
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private final class CheckRunContext: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<KanataCheckHelper.Result, Error>?
    private var exitCode: Int32?
    private var output: Data?

    init(continuation: CheckedContinuation<KanataCheckHelper.Result, Error>) {
        self.continuation = continuation
    }

    func setExitCode(_ exitCode: Int32) {
        let completion = lock.withLock { () -> Completion? in
            self.exitCode = exitCode
            return takeCompletionIfReady()
        }
        completion?.resume()
    }

    func setOutput(_ output: Data) {
        let completion = lock.withLock { () -> Completion? in
            self.output = output
            return takeCompletionIfReady()
        }
        completion?.resume()
    }

    func fail(_ error: Error) {
        let continuation = lock.withLock { () -> CheckedContinuation<KanataCheckHelper.Result, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(throwing: error)
    }

    private func takeCompletionIfReady() -> Completion? {
        guard let continuation, let exitCode, let output else { return nil }
        self.continuation = nil
        let text = String(decoding: output, as: UTF8.self)
        let errors = text.components(separatedBy: .newlines)
            .filter { $0.contains("[ERROR]") || $0.contains("help:") }
        return Completion(
            continuation: continuation,
            result: KanataCheckHelper.Result(exitCode: exitCode, errors: errors)
        )
    }

    private struct Completion {
        let continuation: CheckedContinuation<KanataCheckHelper.Result, Error>
        let result: KanataCheckHelper.Result

        func resume() {
            continuation.resume(returning: result)
        }
    }
}
