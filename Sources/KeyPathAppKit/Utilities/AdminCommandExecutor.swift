import Foundation

public struct CommandExecutionResult: Sendable {
  public let exitCode: Int32
  public let output: String
}

public protocol AdminCommandExecutor: Sendable {
  func execute(command: String, description: String) async throws -> CommandExecutionResult
}

public final class DefaultAdminCommandExecutor: AdminCommandExecutor {
  public init() {}

  public func execute(command: String, description _: String) async throws -> CommandExecutionResult
  {
    let osascriptCommand = """
      do shell script "\(escapeForAppleScript(command))" with administrator privileges with prompt "KeyPath needs to install system services"
      """
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", osascriptCommand]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    try task.run()
    task.waitUntilExit()

    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""
    return CommandExecutionResult(exitCode: task.terminationStatus, output: output)
  }

  private func escapeForAppleScript(_ command: String) -> String {
    command
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
  }
}

@MainActor
public enum AdminCommandExecutorHolder {
  public static var shared: AdminCommandExecutor = DefaultAdminCommandExecutor()
}
