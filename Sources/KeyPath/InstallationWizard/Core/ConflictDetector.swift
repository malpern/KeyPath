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

    // Check for Karabiner grabber conflicts with actual PIDs
    let karabinerConflicts = await detectKarabinerGrabberConflicts()
    conflicts.append(contentsOf: karabinerConflicts)

    // Check for VirtualHIDDevice conflicts
    let vhidConflicts = await detectVirtualHIDDeviceConflicts()
    conflicts.append(contentsOf: vhidConflicts)

    // Deduplicate conflicts by PID to avoid showing the same process multiple times
    conflicts = deduplicateConflictsByPID(conflicts)

    let canAutoResolve = !conflicts.isEmpty  // We can auto-terminate processes
    let description = createConflictDescription(conflicts)

    AppLogger.shared.log(
      "🔍 [ConflictDetector] Found \(conflicts.count) conflicts after deduplication")

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

          // Skip KeyPath's own Kanata processes (identified by config file path)
          if isKeyPathOwnedKanataProcess(command: command) {
            AppLogger.shared.log(
              "ℹ️ [ConflictDetector] Ignoring KeyPath's own Kanata process: PID \(pid), Command: \(command)"
            )
            continue
          }

          AppLogger.shared.log(
            "🔍 [ConflictDetector] Found external Kanata process: PID \(pid), Command: \(command)")
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

    // Check if we've permanently disabled Karabiner conflicts
    let markerPath = "\(NSHomeDirectory())/.keypath/karabiner-conflicts-disabled"
    let oldMarkerPath = "\(NSHomeDirectory())/.keypath/karabiner-grabber-disabled"  // backwards compatibility
    if FileManager.default.fileExists(atPath: markerPath)
      || FileManager.default.fileExists(atPath: oldMarkerPath) {
      AppLogger.shared.log(
        "ℹ️ [ConflictDetector] Karabiner conflicts permanently disabled by KeyPath - skipping VirtualHIDDevice conflict check"
      )
      return []
    }

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
      AppLogger.shared.log(
        "❌ [ConflictDetector] Error detecting VirtualHIDDevice processes: \(error)")
    }

    return conflicts
  }

  private func detectKarabinerGrabberConflicts() async -> [SystemConflict] {
    AppLogger.shared.log("🔍 [ConflictDetector] Checking for Karabiner grabber conflicts")

    // First check if we've permanently disabled Karabiner conflicts
    let markerPath = "\(NSHomeDirectory())/.keypath/karabiner-conflicts-disabled"
    let oldMarkerPath = "\(NSHomeDirectory())/.keypath/karabiner-grabber-disabled"  // backwards compatibility
    if FileManager.default.fileExists(atPath: markerPath)
      || FileManager.default.fileExists(atPath: oldMarkerPath) {
      AppLogger.shared.log(
        "ℹ️ [ConflictDetector] Karabiner conflicts permanently disabled by KeyPath - skipping conflict check"
      )
      return []
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-fl", "karabiner_grabber"]

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
            "🔍 [ConflictDetector] Found Karabiner grabber process: PID \(pid), Command: \(command)")
          conflicts.append(.karabinerGrabberRunning(pid: pid))
        }
      }
    } catch {
      AppLogger.shared.log(
        "❌ [ConflictDetector] Error detecting Karabiner grabber processes: \(error)")
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
      case .kanataProcessRunning(let pid, _):
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

  // MARK: - Deduplication

  private func deduplicateConflictsByPID(_ conflicts: [SystemConflict]) -> [SystemConflict] {
    var seenPIDs = Set<Int>()
    var deduplicatedConflicts: [SystemConflict] = []

    for conflict in conflicts {
      let pid = extractPID(from: conflict)

      if !seenPIDs.contains(pid) {
        seenPIDs.insert(pid)
        deduplicatedConflicts.append(conflict)
        AppLogger.shared.log("🔍 [ConflictDetector] Kept conflict: \(conflict) (PID: \(pid))")
      } else {
        AppLogger.shared.log(
          "🔍 [ConflictDetector] Removed duplicate conflict: \(conflict) (PID: \(pid))")
      }
    }

    return deduplicatedConflicts
  }

  private func extractPID(from conflict: SystemConflict) -> Int {
    switch conflict {
    case .kanataProcessRunning(let pid, _):
      return pid
    case .karabinerGrabberRunning(let pid):
      return pid
    case .karabinerVirtualHIDDeviceRunning(let pid, _):
      return pid
    case .karabinerVirtualHIDDaemonRunning(let pid):
      return pid
    case .exclusiveDeviceAccess:
      return -1  // Special case for device access conflicts (no PID)
    }
  }

  // MARK: - KeyPath Process Identification

  /// Determines if a Kanata process belongs to KeyPath by checking its config file path
  private func isKeyPathOwnedKanataProcess(command: String) -> Bool {
    // KeyPath's Kanata processes use specific config file paths
    let keyPathConfigPaths = [
      "/usr/local/etc/kanata/keypath.kbd",  // System config path
      "Library/Application Support/KeyPath/keypath.kbd"  // User config path (partial match)
    ]

    for configPath in keyPathConfigPaths {
      if command.contains(configPath) {
        return true
      }
    }

    return false
  }
}
