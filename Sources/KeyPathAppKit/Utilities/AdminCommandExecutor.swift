import Foundation
import KeyPathCore

public struct CommandExecutionResult: Sendable {
    public let exitCode: Int32
    public let output: String
}

public protocol AdminCommandExecutor: Sendable {
    func execute(command: String, description: String) async throws -> CommandExecutionResult
}

public final class DefaultAdminCommandExecutor: AdminCommandExecutor {
    public init() {}

    public func execute(command: String, description: String) async throws -> CommandExecutionResult {
        // Use centralized PrivilegedCommandRunner (uses sudo if KEYPATH_USE_SUDO=1, otherwise osascript)
        let result = PrivilegedCommandRunner.execute(
            command: command,
            prompt: "KeyPath needs to \(description.lowercased())."
        )
        return CommandExecutionResult(exitCode: result.exitCode, output: result.output)
    }
}

@MainActor
public enum AdminCommandExecutorHolder {
    public static var shared: AdminCommandExecutor = DefaultAdminCommandExecutor()
}
