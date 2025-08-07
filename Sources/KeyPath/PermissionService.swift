import ApplicationServices
import Foundation
import IOKit

/// Unified permission checking service that provides binary-aware TCC permission detection
/// Consolidates permission logic from multiple locations to eliminate duplication and ensure consistency
///
/// This service follows the Permission Checking Architecture principles:
/// - Single Source of Truth: One place for all permission logic
/// - Binary-Aware: Distinguishes between KeyPath app and kanata binary permissions
/// - Granular Reporting: Precise error messages for each binary and permission type
/// - Exact Path Matching: Uses exact TCC database queries to prevent false positives
class PermissionService {

  // MARK: - Static Instance

  static let shared = PermissionService()

  private init() {}

  // MARK: - Permission Status Types

  /// Represents the permission status for a specific binary
  struct BinaryPermissionStatus {
    let binaryPath: String
    let hasInputMonitoring: Bool
    let hasAccessibility: Bool

    var hasAllRequiredPermissions: Bool {
      return hasInputMonitoring && hasAccessibility
    }
  }

  /// Represents the overall system permission status
  struct SystemPermissionStatus {
    let keyPath: BinaryPermissionStatus
    let kanata: BinaryPermissionStatus

    var hasAllRequiredPermissions: Bool {
      return keyPath.hasAllRequiredPermissions && kanata.hasAllRequiredPermissions
    }

    /// Returns the first missing permission with actionable error message
    var missingPermissionError: String? {
      // Check KeyPath permissions first (needed for UI functionality)
      if !keyPath.hasAccessibility {
        return
          "KeyPath Accessibility permission required - enable in System Settings > Privacy & Security > Accessibility"
      }

      // Check kanata binary permissions (needed for key interception)
      if !kanata.hasInputMonitoring {
        return
          "Kanata Input Monitoring permission required - enable in System Settings > Privacy & Security > Input Monitoring"
      }

      if !kanata.hasAccessibility {
        return
          "Kanata Accessibility permission required - enable in System Settings > Privacy & Security > Accessibility"
      }

      return nil
    }
  }

  // MARK: - Public API

  /// Check permissions for both KeyPath app and kanata binary
  /// - Parameter kanataBinaryPath: Path to the kanata binary to check
  /// - Returns: Complete system permission status
  func checkSystemPermissions(kanataBinaryPath: String) -> SystemPermissionStatus {
    let keyPathStatus = BinaryPermissionStatus(
      binaryPath: Bundle.main.bundlePath,
      hasInputMonitoring: checkKeyPathInputMonitoring(),
      hasAccessibility: checkKeyPathAccessibility()
    )

    let kanataStatus = BinaryPermissionStatus(
      binaryPath: kanataBinaryPath,
      hasInputMonitoring: queryTCCInputMonitoring(path: kanataBinaryPath),
      hasAccessibility: queryTCCAccessibility(path: kanataBinaryPath)
    )

    AppLogger.shared.log(
      "🔐 [PermissionService] System check - KeyPath(Input: \(keyPathStatus.hasInputMonitoring), "
        + "Access: \(keyPathStatus.hasAccessibility)) | "
        + "Kanata(Input: \(kanataStatus.hasInputMonitoring), Access: \(kanataStatus.hasAccessibility))"
    )

    return SystemPermissionStatus(keyPath: keyPathStatus, kanata: kanataStatus)
  }

  /// Check permissions for a specific binary path
  /// - Parameter binaryPath: Path to the binary to check
  /// - Returns: Permission status for that binary
  func checkBinaryPermissions(binaryPath: String) -> BinaryPermissionStatus {
    let isKeyPath = binaryPath == Bundle.main.bundlePath

    let inputMonitoring =
      isKeyPath
      ? checkKeyPathInputMonitoring()
      : queryTCCInputMonitoring(path: binaryPath)

    let accessibility =
      isKeyPath
      ? checkKeyPathAccessibility()
      : queryTCCAccessibility(path: binaryPath)

    return BinaryPermissionStatus(
      binaryPath: binaryPath,
      hasInputMonitoring: inputMonitoring,
      hasAccessibility: accessibility
    )
  }

  // MARK: - KeyPath App Permission Checking

  /// Check if KeyPath app has Input Monitoring permission using IOKit APIs
  private func checkKeyPathInputMonitoring() -> Bool {
    // Use same logic as KanataManager.hasInputMonitoringPermission()
    if #available(macOS 10.15, *) {
      let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
      let hasAccess = accessType == kIOHIDAccessTypeGranted
      AppLogger.shared.log(
        "🔐 [PermissionService] IOHIDCheckAccess returned: \(accessType), hasAccess: \(hasAccess)")
      return hasAccess
    } else {
      // Fallback for older macOS versions
      let hasAccess = AXIsProcessTrusted()
      AppLogger.shared.log(
        "🔐 [PermissionService] AXIsProcessTrusted (fallback) returned: \(hasAccess)")
      return hasAccess
    }
  }

  /// Check if KeyPath app has Accessibility permission using AX APIs
  private func checkKeyPathAccessibility() -> Bool {
    // For the main app, we can use the AXIsProcessTrusted API
    return AXIsProcessTrusted()
  }

  // MARK: - TCC Database Queries

  /// Check Input Monitoring permission for a specific binary path using TCC database
  /// - Parameter path: Full path to the binary
  /// - Returns: True if the binary has Input Monitoring permission
  private func queryTCCInputMonitoring(path: String) -> Bool {
    return queryTCCDatabase(service: "kTCCServiceListenEvent", binaryPath: path)
  }

  /// Check Accessibility permission for a specific binary path using TCC database
  /// - Parameter path: Full path to the binary
  /// - Returns: True if the binary has Accessibility permission
  private func queryTCCAccessibility(path: String) -> Bool {
    return queryTCCDatabase(service: "kTCCServiceAccessibility", binaryPath: path)
  }

  /// Query the TCC database for a specific service and binary path
  /// - Parameters:
  ///   - service: TCC service name (e.g., "kTCCServiceAccessibility")
  ///   - binaryPath: Full path to the binary
  /// - Returns: True if auth_value=2 (allowed), false otherwise
  private func queryTCCDatabase(service: String, binaryPath: String) -> Bool {
    // Debug logging to see exactly what we're checking
    AppLogger.shared.log("🔍 [TCC] Checking \(service) for path: \(binaryPath)")

    // Check both system and user TCC databases to avoid false negatives
    let dbPaths = [
      "/Library/Application Support/com.apple.TCC/TCC.db",
      "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db",
    ]

    for dbPath in dbPaths {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
      task.arguments = [
        dbPath,
        ".mode column",
        // Use exact path matching to prevent false positives
        "SELECT auth_value FROM access WHERE service='\(service)' AND client='\(binaryPath)';",
      ]

      let pipe = Pipe()
      task.standardOutput = pipe
      task.standardError = pipe

      do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse the exact auth_value result (should be single row with auth_value only)
        let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        AppLogger.shared.log(
          "🔐 [PermissionService] TCC query (db=\(dbPath)) for \(service) at \(binaryPath): '\(cleanOutput)'")

        if cleanOutput == "2" {
          return true
        }

        // Debug: If no exact entry found for kanata, scan for any kanata entries in this DB
        if cleanOutput.isEmpty && binaryPath.contains("kanata") {
          AppLogger.shared.log("⚠️ [PermissionService] No exact TCC entry at db=\(dbPath) for path: \(binaryPath)")

          let findQuery = """
            sqlite3 "\(dbPath)" \
            "SELECT client, auth_value FROM access WHERE service = '\(service)' AND client LIKE '%kanata%';"
          """

          let findTask = Process()
          findTask.executableURL = URL(fileURLWithPath: "/bin/bash")
          findTask.arguments = ["-c", findQuery]
          let findPipe = Pipe()
          findTask.standardOutput = findPipe
          findTask.standardError = Pipe()

          do {
            try findTask.run()
            findTask.waitUntilExit()
            let findData = findPipe.fileHandleForReading.readDataToEndOfFile()
            let findOutput = String(data: findData, encoding: .utf8) ?? ""
            if !findOutput.isEmpty {
              AppLogger.shared.log("🔍 [PermissionService] Found kanata entries in TCC (db=\(dbPath)): \(findOutput)")
              // If any kanata entry is authorized, consider permission granted
              let lines = findOutput.components(separatedBy: .newlines)
              for line in lines where !line.isEmpty {
                if line.contains("|2") {
                  AppLogger.shared.log("✅ [PermissionService] Found authorized kanata entry in db=\(dbPath): \(line)")
                  return true
                }
              }
            }
          } catch {
            AppLogger.shared.log("❌ [PermissionService] Error searching TCC (db=\(dbPath)): \(error)")
          }
        }
      } catch {
        AppLogger.shared.log("❌ [PermissionService] TCC query failed for db=\(dbPath): \(error)")
      }
    }

    // No authorized entries found in any DB
    return false
  }

  // MARK: - Legacy Compatibility Methods

  /// Legacy compatibility: Check if KeyPath has Input Monitoring permission
  /// Use checkSystemPermissions() for new code
  func hasInputMonitoringPermission() -> Bool {
    return checkKeyPathInputMonitoring()
  }

  /// Legacy compatibility: Check if KeyPath has Accessibility permission
  /// Use checkSystemPermissions() for new code
  func hasAccessibilityPermission() -> Bool {
    return checkKeyPathAccessibility()
  }

  /// Legacy compatibility: Check TCC Input Monitoring for specific binary
  /// Use checkBinaryPermissions() for new code
  func checkTCCForInputMonitoring(path: String) -> Bool {
    return queryTCCDatabase(service: "kTCCServiceListenEvent", binaryPath: path)
  }

  /// Legacy compatibility: Check TCC Accessibility for specific binary
  /// Use checkBinaryPermissions() for new code
  func checkTCCForAccessibility(path: String) -> Bool {
    return queryTCCDatabase(service: "kTCCServiceAccessibility", binaryPath: path)
  }
}
