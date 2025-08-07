import Foundation
import XCTest

@testable import KeyPath

/// Mock system environment for autonomous testing
class MockSystemEnvironment {
  // MARK: - Mock Filesystem

  private var mockFileSystem: [String: MockFile] = [:]
  private var mockProcesses: [String: MockProcess] = [:]

  struct MockFile {
    let content: String
    let permissions: String
    let owner: String
    let exists: Bool
  }

  struct MockProcess {
    let pid: Int
    let user: String
    let command: String
    let isRunning: Bool
  }

  // MARK: - Setup Methods

  func reset() {
    mockFileSystem.removeAll()
    mockProcesses.removeAll()
  }

  func setupCleanInstallation() {
    reset()
    // Simulate clean system with no KeyPath components
  }

  func setupPartialInstallation() {
    reset()
    // Simulate system with some components installed
    addMockFile(
      path: "/usr/local/bin/kanata-cmd",
      content: "mock-kanata-binary",
      permissions: "755",
      owner: "root"
    )
  }

  func setupCompleteInstallation() {
    reset()
    // Simulate fully installed system
    addMockFile(
      path: "/usr/local/bin/kanata-cmd",
      content: "mock-kanata-binary",
      permissions: "755",
      owner: "root"
    )
    addMockFile(
      path: "/Library/LaunchDaemons/com.keypath.kanata.plist",
      content: mockLaunchDaemonPlist(),
      permissions: "644",
      owner: "root"
    )
    addMockFile(
      path: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice",
      content: "mock-driver",
      permissions: "755",
      owner: "root"
    )
    addMockProcess(pid: 1234, user: "root", command: "kanata-cmd", isRunning: true)
  }

  // MARK: - Mock File Operations

  func addMockFile(path: String, content: String, permissions: String, owner: String) {
    mockFileSystem[path] = MockFile(
      content: content,
      permissions: permissions,
      owner: owner,
      exists: true
    )
  }

  func removeMockFile(path: String) {
    mockFileSystem[path] = MockFile(
      content: "",
      permissions: "",
      owner: "",
      exists: false
    )
  }

  func fileExists(atPath path: String) -> Bool {
    return mockFileSystem[path]?.exists ?? false
  }

  func fileContent(atPath path: String) -> String? {
    return mockFileSystem[path]?.content
  }

  // MARK: - Mock Process Operations

  func addMockProcess(pid: Int, user: String, command: String, isRunning: Bool) {
    let processKey = "\(pid)_\(command)"
    mockProcesses[processKey] = MockProcess(
      pid: pid,
      user: user,
      command: command,
      isRunning: isRunning
    )
  }

  func isProcessRunning(command: String) -> Bool {
    return mockProcesses.values.contains { process in
      process.command.contains(command) && process.isRunning
    }
  }

  func getProcessUser(command: String) -> String? {
    return mockProcesses.values.first { process in
      process.command.contains(command) && process.isRunning
    }?.user
  }

  // MARK: - Mock System Commands

  func mockLaunchctlResult(command: [String]) -> (exitCode: Int, output: String) {
    let action = command.first ?? ""

    switch action {
    case "kickstart":
      if fileExists(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist"),
        fileExists(atPath: "/usr/local/bin/kanata-cmd")
      {
        addMockProcess(pid: 1234, user: "root", command: "kanata-cmd", isRunning: true)
        return (0, "Service started successfully")
      } else {
        return (1, "Service not found")
      }
    case "kill":
      // Remove running process
      mockProcesses.removeAll()
      return (0, "Service stopped")
    case "list":
      if isProcessRunning(command: "kanata") {
        return (0, "com.keypath.kanata")
      } else {
        return (0, "")
      }
    default:
      return (1, "Unknown command")
    }
  }

  func mockInstallationScript() -> (exitCode: Int, output: String) {
    // Simulate successful installation
    setupCompleteInstallation()
    return (0, "Installation completed successfully")
  }

  // MARK: - Helper Methods

  private func mockLaunchDaemonPlist() -> String {
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>com.keypath.kanata</string>
          <key>ProgramArguments</key>
          <array>
              <string>/usr/local/bin/kanata-cmd</string>
              <string>--cfg</string>
              <string>/usr/local/etc/kanata/keypath.kbd</string>
          </array>
          <key>UserName</key>
          <string>root</string>
          <key>GroupName</key>
          <string>wheel</string>
          <key>ProcessType</key>
          <string>Interactive</string>
      </dict>
      </plist>
      """
  }
}

/// Mock KanataManager for testing
class MockKanataManager: ObservableObject {
  private let mockEnvironment: MockSystemEnvironment

  @Published var isRunning: Bool = false
  @Published var lastError: String?

  init(mockEnvironment: MockSystemEnvironment) {
    self.mockEnvironment = mockEnvironment
  }

  // Mock system-dependent methods
  func isInstalled() -> Bool {
    return mockEnvironment.fileExists(atPath: "/usr/local/bin/kanata-cmd")
  }

  func isServiceInstalled() -> Bool {
    return mockEnvironment.fileExists(atPath: "/Library/LaunchDaemons/com.keypath.kanata.plist")
  }

  func isKarabinerDriverInstalled() -> Bool {
    return mockEnvironment.fileExists(
      atPath: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice")
  }

  func isCompletelyInstalled() -> Bool {
    return isInstalled() && isServiceInstalled() && isKarabinerDriverInstalled()
  }

  func getInstallationStatus() -> String {
    let kanataInstalled = isInstalled()
    let serviceInstalled = isServiceInstalled()
    let driverInstalled = isKarabinerDriverInstalled()

    if kanataInstalled && serviceInstalled && driverInstalled {
      return "✅ Fully installed"
    } else if kanataInstalled && serviceInstalled {
      return "⚠️ Driver missing"
    } else if kanataInstalled {
      return "⚠️ Service & driver missing"
    } else {
      return "❌ Not installed"
    }
  }

  // Mock async operations for testing
  func startKanata() async {
    guard isCompletelyInstalled() else {
      await MainActor.run {
        self.lastError = "Service not found"
        self.isRunning = false
      }
      return
    }

    let result = mockEnvironment.mockLaunchctlResult(command: [
      "kickstart", "system/com.keypath.kanata",
    ])

    await MainActor.run {
      if result.exitCode == 0 {
        self.isRunning = true
        self.lastError = nil
      } else {
        self.isRunning = false
        self.lastError = "Failed to start: \(result.output)"
      }
    }
  }

  func stopKanata() async {
    let result = mockEnvironment.mockLaunchctlResult(command: ["kill", "system/com.keypath.kanata"])

    await MainActor.run {
      if result.exitCode == 0 {
        self.isRunning = false
        self.lastError = nil
      } else {
        self.lastError = "Failed to stop: \(result.output)"
      }
    }
  }

  func restartKanata() async {
    await stopKanata()
    await startKanata()
  }

  func emergencyStop() async {
    await MainActor.run {
      self.isRunning = false
      self.lastError = nil
    }
  }

  func cleanup() async {
    if isRunning {
      await stopKanata()
    }
  }

  func performTransparentInstallation() async -> Bool {
    let result = mockEnvironment.mockInstallationScript()
    return result.exitCode == 0
  }

  func saveConfiguration(input: String, output: String) async throws {
    // Mock configuration saving
    guard isCompletelyInstalled() else {
      throw NSError(
        domain: "MockError", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "LaunchDaemon missing. Please run: sudo ./install-system.sh"
        ]
      )
    }

    // Simulate config validation
    if input.isEmpty || output.isEmpty {
      throw NSError(
        domain: "MockError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid configuration"]
      )
    }

    // Simulate successful save - would restart Kanata in real system
    if isRunning {
      await restartKanata()
    }
  }
}
