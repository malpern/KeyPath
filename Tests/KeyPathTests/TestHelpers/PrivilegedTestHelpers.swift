@preconcurrency import XCTest

@testable import KeyPathAppKit
@testable import KeyPathCore

@MainActor
final class FakeAdminCommandExecutor: AdminCommandExecutor {
    private let resultProvider: ((String, String) -> CommandExecutionResult)?
    private var defaultResult: CommandExecutionResult

    init(
        defaultResult: CommandExecutionResult = CommandExecutionResult(exitCode: 0, output: ""),
        resultProvider: ((String, String) -> CommandExecutionResult)? = nil
    ) {
        self.defaultResult = defaultResult
        self.resultProvider = resultProvider
    }

    private(set) var commands: [(command: String, description: String)] = []
    private(set) var batches: [PrivilegedCommandRunner.Batch] = []

    func execute(command: String, description: String) async throws -> CommandExecutionResult {
        commands.append((command, description))
        if let provider = resultProvider {
            return provider(command, description)
        }
        return defaultResult
    }

    func execute(batch: PrivilegedCommandRunner.Batch) async throws -> CommandExecutionResult {
        batches.append(batch)
        if let provider = resultProvider {
            return provider(batch.script, batch.label)
        }
        return defaultResult
    }
}

@MainActor
extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure @Sendable @escaping () async throws -> some Sendable,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ handler: (_ error: Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            handler(error)
        }
    }
}
