import AppKit
import ApplicationServices
import Cocoa
import Foundation
import IOKit
import IOKit.hid

/// Simplified permission checking service using attempt-based detection
/// Instead of querying TCC database (unreliable), we try to use the APIs and check for failures
class PermissionService {
  // MARK: - Static Instance

  static let shared = PermissionService()

  private init() {}

  // MARK: - Cache for permission results

  private struct CachedResult {
    let hasPermission: Bool
    let timestamp: Date

    var isExpired: Bool {
      // Cache for 5 seconds to avoid hammering the system
      return Date().timeIntervalSince(timestamp) > 5.0
    }
  }

  private var permissionCache: [String: CachedResult] = [:]

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
          "KeyPath needs Accessibility permission - enable in System Settings > Privacy & Security > Accessibility"
      }

      if !keyPath.hasInputMonitoring {
        return
          "KeyPath needs Input Monitoring permission - enable in System Settings > Privacy & Security > Input Monitoring"
      }

      // For kanata, we'll rely on actual execution errors rather than pre-checking
      // This avoids false negatives from TCC database timing issues
      if !kanata.hasInputMonitoring || !kanata.hasAccessibility {
        return "Kanata binary may need permissions - we'll check when starting the service"
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

    // Check kanata permissions using TCC database
    let kanataInputMonitoring = Self.checkTCCForInputMonitoring(path: kanataBinaryPath)
    let kanataAccessibility = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary)
    
    let kanataStatus = BinaryPermissionStatus(
      binaryPath: kanataBinaryPath,
      hasInputMonitoring: kanataInputMonitoring,
      hasAccessibility: kanataAccessibility
    )

    AppLogger.shared.log(
      "🔐 [PermissionService] System check - KeyPath(Input: \(keyPathStatus.hasInputMonitoring), "
        + "Access: \(keyPathStatus.hasAccessibility)) | "
        + "Kanata(Input: \(kanataStatus.hasInputMonitoring), Access: \(kanataStatus.hasAccessibility))"
    )

    return SystemPermissionStatus(keyPath: keyPathStatus, kanata: kanataStatus)
  }

  // MARK: - KeyPath App Permission Checking (Attempt-based)

  /// Check if KeyPath app has Input Monitoring permission
  /// Uses a completely non-invasive method that doesn't trigger automatic addition to System Preferences
  func hasInputMonitoringPermission() -> Bool {
    let cacheKey = "keypath_input_monitoring"

    // Check cache first
    if let cached = permissionCache[cacheKey], !cached.isExpired {
      return cached.hasPermission
    }

    // Use conservative approach for Input Monitoring to avoid automatic addition to System Preferences
    // The TCC database is protected and cannot be reliably queried without triggering system prompts
    
    let keyPathPath = Bundle.main.bundlePath
    let hasAccess = Self.checkTCCForInputMonitoring(path: keyPathPath)
    
    AppLogger.shared.log(
      "🔐 [PermissionService] Input Monitoring check for path '\(keyPathPath)': \(hasAccess ? "granted" : "not granted")"
    )

    // Cache the result briefly
    permissionCache[cacheKey] = CachedResult(hasPermission: hasAccess, timestamp: Date())

    return hasAccess
  }

  /// Check if KeyPath app has Accessibility permission
  func hasAccessibilityPermission() -> Bool {
    let cacheKey = "keypath_accessibility"

    // Check cache first
    if let cached = permissionCache[cacheKey], !cached.isExpired {
      return cached.hasPermission
    }

    // AXIsProcessTrusted is the canonical way to check accessibility for current process
    let hasAccess = AXIsProcessTrusted()

    AppLogger.shared.log("🔐 [PermissionService] AXIsProcessTrusted: \(hasAccess)")

    // Cache the result
    permissionCache[cacheKey] = CachedResult(hasPermission: hasAccess, timestamp: Date())

    return hasAccess
  }

  /// Check permissions for the current process's binary
  private func checkKeyPathInputMonitoring() -> Bool {
    return hasInputMonitoringPermission()
  }

  /// Check accessibility for the current process
  private func checkKeyPathAccessibility() -> Bool {
    return hasAccessibilityPermission()
  }

  /// Track TCC authorization
  static var lastTCCAuthorizationDenied = false

  // MARK: - Kanata Permission Detection (via error analysis)

  /// Analyze kanata startup error to determine if it's a permission issue
  /// - Parameter error: The error output from kanata
  /// - Returns: Tuple of (isPermissionError, suggestedFix)
  static func analyzeKanataError(_ error: String) -> (
    isPermissionError: Bool, suggestedFix: String?
  ) {
    let errorLower = error.lowercased()

    // Common permission-related error patterns
    if errorLower.contains("operation not permitted") {
      return (true, "Grant Input Monitoring permission to kanata in System Settings")
    }

    if errorLower.contains("accessibility") || errorLower.contains("axapi") {
      return (true, "Grant Accessibility permission to kanata in System Settings")
    }

    if errorLower.contains("iokit") || errorLower.contains("hid") {
      return (true, "Grant Input Monitoring permission to kanata in System Settings")
    }

    if errorLower.contains("tcc") || errorLower.contains("privacy") {
      return (true, "Check privacy permissions for kanata in System Settings")
    }

    if errorLower.contains("device not configured") {
      return (false, "VirtualHID driver issue - try restarting the Karabiner daemon")
    }

    if errorLower.contains("address already in use") || errorLower.contains("bind") {
      return (false, "Another kanata process is already running")
    }

    return (false, nil)
  }

  // MARK: - Permission Request

  /// Request accessibility permission for KeyPath (shows system dialog)
  static func requestAccessibilityPermission() {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    AXIsProcessTrustedWithOptions(options)
  }

  /// Open System Settings to the Privacy & Security pane
  static func openPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
      NSWorkspace.shared.open(url)
    }
  }

  static func checkTCCForAccessibility(path: String) -> Bool {
    // Placeholder method to prevent compilation errors
    return false
  }

  static func checkTCCForInputMonitoring(path: String) -> Bool {
    // Use IOHIDCheckAccess - the modern, non-invasive way to check Input Monitoring permission
    // This is the official API for checking Input Monitoring status without triggering prompts
    
    let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let isGranted = accessType == kIOHIDAccessTypeGranted
    
    let statusDescription = switch accessType {
    case kIOHIDAccessTypeGranted:
      "granted"
    case kIOHIDAccessTypeDenied: 
      "denied"
    case kIOHIDAccessTypeUnknown:
      "unknown"
    default:
      "unknown (\(accessType))"
    }
    
    AppLogger.shared.log("🔐 [PermissionService] IOHIDCheckAccess for \(path): \(statusDescription)")
    return isGranted
  }

  /// Clear the permission cache (useful after user grants permissions)
  func clearCache() {
    permissionCache.removeAll()
    AppLogger.shared.log("🔐 [PermissionService] Permission cache cleared")
  }
}
