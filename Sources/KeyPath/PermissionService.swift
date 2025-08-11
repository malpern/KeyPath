import AppKit
import ApplicationServices
import Cocoa
import Foundation
import IOKit
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
            Date().timeIntervalSince(timestamp) > 5.0
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
            hasInputMonitoring && hasAccessibility
        }
    }

    /// Represents the overall system permission status
    struct SystemPermissionStatus {
        let keyPath: BinaryPermissionStatus
        let kanata: BinaryPermissionStatus

        var hasAllRequiredPermissions: Bool {
            keyPath.hasAllRequiredPermissions && kanata.hasAllRequiredPermissions
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
        let kanataAccessibility = Self.checkTCCForAccessibility(path: kanataBinaryPath)

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
        hasInputMonitoringPermission()
    }

    /// Check accessibility for the current process
    private func checkKeyPathAccessibility() -> Bool {
        hasAccessibilityPermission()
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

    /// Request Input Monitoring permission programmatically (macOS 10.15+)
    /// Returns true if permission was granted, false if denied or needs manual action
    @available(macOS 10.15, *)
    static func requestInputMonitoringPermission() -> Bool {
        AppLogger.shared.log("🔐 [PermissionService] Requesting Input Monitoring permission via IOHIDRequestAccess")

        // IOHIDRequestAccess returns a Bool: true if granted, false if denied/unknown
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        AppLogger.shared.log("🔐 [PermissionService] IOHIDRequestAccess result: \(granted ? "granted" : "denied/unknown")")

        // Clear cache after permission request
        PermissionService.shared.clearCache()

        return granted
    }

    /// Detect if there might be stale KeyPath entries in Input Monitoring
    /// This checks for common indicators of old or duplicate entries
    static func detectPossibleStaleEntries() -> (hasStaleEntries: Bool, details: [String]) {
        var indicators: [String] = []

        // Check if we're running from a development path
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains(".build/") || bundlePath.contains("DerivedData/") {
            indicators.append("Running from development build location")
        }

        // Check if KeyPath is NOT in /Applications but has been before
        if !bundlePath.hasPrefix("/Applications/") {
            // Check if /Applications/KeyPath.app exists
            let applicationsPath = "/Applications/KeyPath.app"
            if FileManager.default.fileExists(atPath: applicationsPath) {
                indicators.append("KeyPath exists in /Applications but running from \(bundlePath)")
            }
        }

        // Check for multiple kanata processes which might indicate permission confusion
        // Note: This is a simplified check - ideally would use ProcessLifecycleManager.detectConflicts()
        // but that's an async method. For now, just check if kanata is running at all.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "pgrep -x kanata | wc -l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)),
               count > 1 {
                indicators.append("Multiple kanata processes detected (\(count) running)")
            }
        } catch {
            // Ignore errors in detection
        }

        // Check if permission was previously granted but now failing
        // This often indicates a stale entry
        let hasInputMonitoring = checkTCCForInputMonitoring(path: bundlePath)
        if !hasInputMonitoring {
            // Try to detect if there's a mismatch between what macOS thinks and reality
            let homeDir = NSHomeDirectory()
            let possibleOldPaths = [
                "/Applications/KeyPath.app",
                "\(homeDir)/Applications/KeyPath.app",
                "\(homeDir)/Desktop/KeyPath.app",
                "\(homeDir)/Downloads/KeyPath.app"
            ]

            for oldPath in possibleOldPaths {
                if oldPath != bundlePath, FileManager.default.fileExists(atPath: oldPath) {
                    indicators.append("Found KeyPath at \(oldPath) - may have old permissions")
                }
            }
        }

        AppLogger.shared.log("🔐 [PermissionService] Stale entry detection: \(indicators.isEmpty ? "No indicators found" : indicators.joined(separator: ", "))")

        return (!indicators.isEmpty, indicators)
    }

    /// Open System Settings to the Privacy & Security pane
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings directly to Input Monitoring
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings directly to Accessibility
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func checkTCCForAccessibility(path: String) -> Bool {
        // For KeyPath app itself, use AXIsProcessTrusted which checks current process
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            let hasAccess = AXIsProcessTrusted()
            AppLogger.shared.log("🔐 [PermissionService] AXIsProcessTrusted for current process: \(hasAccess)")
            return hasAccess
        }
        
        // For other binaries (like kanata), use API-based permission checking
        return checkBinaryPermission(for: path, service: "Accessibility")
    }

    static func checkTCCForInputMonitoring(path: String) -> Bool {
        // For KeyPath app itself, use IOHIDCheckAccess which checks current process
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let isGranted = accessType == kIOHIDAccessTypeGranted
            
            AppLogger.shared.log("🔐 [PermissionService] IOHIDCheckAccess for current process: \(isGranted ? "granted" : "not granted")")
            return isGranted
        }
        
        // For other binaries (like kanata), use API-based permission checking
        return checkBinaryPermission(for: path, service: "InputMonitoring")
    }
    
    /// Check if a binary has permission using macOS APIs
    /// - Parameters:
    ///   - path: Full path to the binary
    ///   - service: Service type ("InputMonitoring" or "Accessibility")
    /// - Returns: True if the binary has the permission, false otherwise
    private static func checkBinaryPermission(for path: String, service: String) -> Bool {
        // For other binaries (not current process), we can't directly check their TCC status
        // without Full Disk Access. Instead, we use a practical approach:
        
        // 1. Try to detect if the binary has been granted permission by attempting a test operation
        // 2. For kanata specifically, we can check if it's able to create input events
        
        if service == "InputMonitoring" {
            return checkInputMonitoringForBinary(at: path)
        } else if service == "Accessibility" {
            return checkAccessibilityForBinary(at: path)
        }
        
        return false
    }
    
    /// Check Input Monitoring permission for a binary by testing its capabilities
    private static func checkInputMonitoringForBinary(at path: String) -> Bool {
        // For kanata, we can check if it can successfully initialize without permission errors
        if path.contains("kanata") {
            return testKanataInputAccess(at: path)
        }
        
        // For other binaries, we can't reliably test without running them
        // Return false to be safe
        AppLogger.shared.log("🔐 [PermissionService] Cannot check Input Monitoring for non-kanata binary: \(path)")
        return false
    }
    
    /// Check Accessibility permission for a binary
    private static func checkAccessibilityForBinary(at path: String) -> Bool {
        // Similar to Input Monitoring, we can't check other processes' accessibility permissions
        // without running them. For kanata, assume it needs both permissions together.
        if path.contains("kanata") {
            // If kanata has Input Monitoring, it likely has Accessibility too
            // (they're usually granted together for keyboard remappers)
            return testKanataInputAccess(at: path)
        }
        
        return false
    }
    
    /// Test if kanata has the necessary permissions by checking if the service is running successfully
    private static func testKanataInputAccess(at path: String) -> Bool {
        // Check if kanata service is currently running and healthy
        // If it's running without permission errors, it likely has the required permissions
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "kanata.*--cfg.*--watch"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let isRunning = task.terminationStatus == 0 && !pids.isEmpty
            
            if isRunning {
                // If kanata is running, check the log for recent permission errors
                return !hasRecentPermissionErrors()
            } else {
                // If not running, we can't determine permission status
                // Default to requiring permission grant to be safe
                AppLogger.shared.log("🔐 [PermissionService] Kanata not running - cannot determine permission status")
                return false
            }
            
        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Failed to check kanata process: \(error)")
            return false
        }
    }
    
    /// Check if there are recent permission errors in kanata logs
    private static func hasRecentPermissionErrors() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        task.arguments = ["-n", "50", "/var/log/kanata.log"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Look for permission-related errors in recent logs
            let permissionErrors = [
                "privilege violation",
                "operation not permitted", 
                "iokit/common",
                "IOHIDDeviceOpen error"
            ]
            
            for error in permissionErrors {
                if output.lowercased().contains(error.lowercased()) {
                    AppLogger.shared.log("🔐 [PermissionService] Found permission error in logs: \(error)")
                    return true
                }
            }
            
            AppLogger.shared.log("🔐 [PermissionService] No recent permission errors found in kanata logs")
            return false
            
        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Failed to read kanata logs: \(error)")
            // If we can't read logs, assume there might be permission issues
            return true
        }
    }

    /// Clear the permission cache (useful after user grants permissions)
    func clearCache() {
        permissionCache.removeAll()
        AppLogger.shared.log("🔐 [PermissionService] Permission cache cleared")
    }
}
