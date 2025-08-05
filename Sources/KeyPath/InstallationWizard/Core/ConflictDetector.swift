import Foundation

/// Responsible for detecting process conflicts and system conflicts
/// Handles all conflict detection logic
class ConflictDetector {
  private let kanataManager: KanataManager

  init(kanataManager: KanataManager) {
    self.kanataManager = kanataManager
  }

  // MARK: - Conflict Detection

  func detectConflicts() async -> ConflictDetectionResult {
    AppLogger.shared.log("🔍 [ConflictDetector] Detecting system conflicts")

    var conflicts: [SystemConflict] = []

    // Check for running Kanata processes
    let kanataConflicts = await detectKanataProcessConflicts()
    conflicts.append(contentsOf: kanataConflicts)

    // Check for Karabiner grabber conflicts
    if kanataManager.isKarabinerElementsRunning() {
      // Note: We don't get PID from isKarabinerElementsRunning, so we use a placeholder
      conflicts.append(.karabinerGrabberRunning(pid: -1))
    }

    // Check for VirtualHIDDevice conflicts
    let vhidConflicts = await detectVirtualHIDDeviceConflicts()
    conflicts.append(contentsOf: vhidConflicts)

    let canAutoResolve = !conflicts.isEmpty  // We can auto-terminate processes
    let description = createConflictDescription(conflicts)

    AppLogger.shared.log("🔍 [ConflictDetector] Found \(conflicts.count) conflicts")

    return ConflictDetectionResult(
      conflicts: conflicts,
      canAutoResolve: canAutoResolve,
      description: description
    )
  }

  private func detectKanataProcessConflicts() async -> [SystemConflict] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-fl", "kanata"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var conflicts: [SystemConflict] = []

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus == 0,
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
          let components = line.components(separatedBy: " ")
          guard let pidString = components.first,
            let pid = Int(pidString),
            components.count > 1
          else {
            continue
          }

          let command = components.dropFirst().joined(separator: " ")

          // Skip the pgrep command itself
          if command.contains("pgrep") {
            continue
          }

          AppLogger.shared.log(
            "🔍 [ConflictDetector] Found Kanata process: PID \(pid), Command: \(command)")
          conflicts.append(.kanataProcessRunning(pid: pid, command: command))
        }
      }
    } catch {
      AppLogger.shared.log("❌ [ConflictDetector] Error detecting Kanata processes: \(error)")
    }

    return conflicts
  }

  private func detectVirtualHIDDeviceConflicts() async -> [SystemConflict] {
    AppLogger.shared.log("🔍 [ConflictDetector] Checking for VirtualHIDDevice conflicts")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-fl", "VirtualHIDDevice"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var conflicts: [SystemConflict] = []

    do {
      try task.run()
      task.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(data: data, encoding: .utf8) ?? ""

      if task.terminationStatus == 0,
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
          let components = line.components(separatedBy: " ")
          guard let pidString = components.first,
            let pid = Int(pidString),
            components.count > 1
          else {
            continue
          }

          let command = components.dropFirst().joined(separator: " ")

          // Skip the pgrep command itself
          if command.contains("pgrep") {
            continue
          }

          AppLogger.shared.log(
            "🔍 [ConflictDetector] Found VirtualHIDDevice process: PID \(pid), Command: \(command)")

          // Classify the type of VirtualHID process
          if command.contains("Karabiner-VirtualHIDDevice-Daemon") {
            conflicts.append(.karabinerVirtualHIDDaemonRunning(pid: pid))
          } else if command.contains("Karabiner-DriverKit-VirtualHIDDevice") {
            let processName = "Karabiner-DriverKit-VirtualHIDDevice"
            conflicts.append(.karabinerVirtualHIDDeviceRunning(pid: pid, processName: processName))
          } else {
            // Generic VirtualHIDDevice process
            let processName = command.components(separatedBy: "/").last ?? "VirtualHIDDevice"
            conflicts.append(.karabinerVirtualHIDDeviceRunning(pid: pid, processName: processName))
          }
        }
      }
    } catch {
      AppLogger.shared.log("❌ [ConflictDetector] Error detecting VirtualHIDDevice processes: \(error)")
    }

    return conflicts
  }

  private func createConflictDescription(_ conflicts: [SystemConflict]) -> String {
    if conflicts.isEmpty {
      return "No conflicts detected"
    }

    var descriptions: [String] = []

    for conflict in conflicts {
      switch conflict {
      case .kanataProcessRunning(let pid, let command):
        descriptions.append("Kanata process running (PID: \(pid))")
      case .karabinerGrabberRunning(let pid):
        descriptions.append("Karabiner Elements grabber running (PID: \(pid))")
      case .karabinerVirtualHIDDeviceRunning(let pid, let processName):
        descriptions.append("Karabiner VirtualHID Device running: \(processName) (PID: \(pid))")
      case .karabinerVirtualHIDDaemonRunning(let pid):
        descriptions.append("Karabiner VirtualHIDDevice Daemon running (PID: \(pid))")
      case .exclusiveDeviceAccess(let device):
        descriptions.append("Exclusive device access conflict: \(device)")
      }
    }

    return descriptions.joined(separator: "; ")
  }
}
