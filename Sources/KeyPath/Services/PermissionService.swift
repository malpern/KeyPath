import AppKit
import ApplicationServices
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
    private let cacheQueue = DispatchQueue(label: "com.keypath.permission.cache", attributes: .concurrent)

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

    // MARK: - Helper Functions
    
    /// Trace permission grants for debugging
    private static func traceGrant(_ source: String, details: String) {
        AppLogger.shared.log("🧭 [PermissionTrace] GRANT via \(source): \(details)")
    }
    
    /// Standardize a file path to its canonical form (resolving symlinks)
    private static func standardizedPath(_ path: String) -> String {
        return URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
    
    /// Escape string for safe use in SQLite queries
    private static func escapeForSQLite(_ s: String) -> String {
        return s.replacingOccurrences(of: "'", with: "''")
    }
    
    /// Check if a binary is the kanata executable
    private static func isKanataBinary(at path: String) -> Bool {
        return URL(fileURLWithPath: path).lastPathComponent == "kanata"
    }
    
    /// Get the code signature identifier for a binary
    private static func codeSignatureIdentifier(at path: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe // codesign outputs to stderr
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            // Parse "Identifier=com.example.kanata" line
            if let line = output.split(separator: "\n").first(where: { $0.contains("Identifier=") }) {
                return line.split(separator: "=").dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Failed to get code signature identifier: \(error)")
        }
        return nil
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

        // IMPORTANT: Do NOT use IOHIDCheckAccess or any other API that could trigger automatic
        // addition to System Preferences. Instead, use conservative checking that only returns
        // true if we're absolutely certain permission is granted.

        // For now, we'll be conservative and assume permission is NOT granted unless we can
        // verify it through non-invasive means (like checking if the service is running successfully)
        let hasAccess = checkInputMonitoringNonInvasively()

        AppLogger.shared.log(
            "🔐 [PermissionService] Non-invasive Input Monitoring check: \(hasAccess ? "granted" : "not granted")"
        )

        // Cache the result briefly
        permissionCache[cacheKey] = CachedResult(hasPermission: hasAccess, timestamp: Date())

        return hasAccess
    }

    /// Check Input Monitoring permission without triggering any system APIs that could
    /// automatically add the app to Input Monitoring preferences
    private func checkInputMonitoringNonInvasively() -> Bool {
        // IMPORTANT: We cannot assume that kanata running = input monitoring permission granted
        // Kanata can run without Input Monitoring permission, it just won't capture any keys.
        // We need to be more conservative here.
        
        // Method 1: Check if we have recent successful key captures
        // This would indicate real input monitoring capability
        // For now, skip this check as it's unreliable

        // Method 2: Check if we've previously cached a successful permission grant
        // This helps avoid repeated requests after the user has granted permission
        let userDefaults = UserDefaults.standard
        let lastGrantedTimestamp = userDefaults.double(forKey: "keypath_input_monitoring_granted")
        if lastGrantedTimestamp > 0 {
            let lastGranted = Date(timeIntervalSince1970: lastGrantedTimestamp)
            let daysSinceGrant = Date().timeIntervalSince(lastGranted) / (24 * 60 * 60)

            // If permission was granted within the last 30 days, assume it's still valid
            // (unless there are recent errors)
            if daysSinceGrant < 30, !Self.hasRecentPermissionErrors() {
                AppLogger.shared.log("🔐 [PermissionService] Recent permission grant found in cache")
                return true
            }
        }

        // Method 3: Conservative fallback - assume permission is NOT granted
        // This is safer than triggering automatic addition to System Preferences
        AppLogger.shared.log("🔐 [PermissionService] Conservative check - assuming permission not granted")
        return false
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
        // For KeyPath app itself, we need to check both bundle ID and app path
        // since different builds might have different identifiers in TCC
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
        let appPath = Bundle.main.bundlePath
        
        AppLogger.shared.log("🔐 [PermissionService] Checking KeyPath Input Monitoring:")
        AppLogger.shared.log("  - Bundle ID: \(bundleIdentifier)")
        AppLogger.shared.log("  - App Path: \(appPath)")
        
        // Check bundle identifier first
        let bundleIdCheck = Self.checkTCCForInputMonitoring(path: bundleIdentifier)
        AppLogger.shared.log("  - Bundle ID check: \(bundleIdCheck)")
        if bundleIdCheck { return true }
        
        // Also check the app path (for development builds)
        let appPathCheck = Self.checkTCCForInputMonitoring(path: appPath)
        AppLogger.shared.log("  - App path check: \(appPathCheck)")
        if appPathCheck { return true }
        
        // As a fallback, try the alternate bundle identifier seen in TCC
        let altIdCheck = Self.checkTCCForInputMonitoring(path: "com.intelligencetest.KeyPath")
        AppLogger.shared.log("  - Alt ID check: \(altIdCheck)")
        if altIdCheck { return true }
        
        // Final check: try the runtime API (may trigger permission request)
        // This is more reliable than TCC database for the current process
        let runtimeCheck = checkInputMonitoringRuntimeAPI()
        AppLogger.shared.log("  - Runtime API check: \(runtimeCheck)")
        
        return runtimeCheck
    }
    
    /// Check Input Monitoring using runtime API (may trigger permission prompt)
    private func checkInputMonitoringRuntimeAPI() -> Bool {
        // Try to create a CGEventTap to test if we have permission
        // This will return nil if permission is not granted
        let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { (proxy, type, event, refcon) in
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
        
        if let tap = eventTap {
            // FIXED: Properly clean up the event tap without causing NULL pointer crashes
            // Don't try to remove from run loop since we never added it
            CFMachPortInvalidate(tap)
            return true
        }
        
        return false
    }

    /// Check Accessibility for the current process using both TCC DB and AX runtime API
    private func checkKeyPathAccessibility() -> Bool {
        // For KeyPath app itself, prefer TCC DB lookups using bundle ID first
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.keypath.KeyPath"
        let appPath = Bundle.main.bundlePath

        AppLogger.shared.log("🔐 [PermissionService] Checking KeyPath Accessibility:")
        AppLogger.shared.log("  - Bundle ID: \(bundleIdentifier)")
        AppLogger.shared.log("  - App Path: \(appPath)")

        // 1) Check TCC by bundle identifier
        let bundleIdCheck = Self.checkTCCForAccessibility(path: bundleIdentifier)
        AppLogger.shared.log("  - Bundle ID check: \(bundleIdCheck)")
        if bundleIdCheck {
            return true
        }

        // 2) Check TCC by app path (development builds or alt installs)
        let appPathCheck = Self.checkTCCForAccessibility(path: appPath)
        AppLogger.shared.log("  - App path check: \(appPathCheck)")
        if appPathCheck {
            return true
        }

        // 3) Also check alternate bundle ID we've seen in TCC DB
        let altIdCheck = Self.checkTCCForAccessibility(path: "com.intelligencetest.KeyPath")
        AppLogger.shared.log("  - Alt ID check: \(altIdCheck)")
        if altIdCheck {
            return true
        }

        // 4) Fallback: AXIsProcessTrusted (canonical for current process)
        let runtimeCheck = hasAccessibilityPermission()
        AppLogger.shared.log("  - Runtime API (AXIsProcessTrusted) check: \(runtimeCheck)")
        return runtimeCheck
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
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// This function is DISABLED to prevent automatic addition to Input Monitoring preferences.
    /// KeyPath will never automatically request Input Monitoring permission.
    /// Users must manually grant permission in System Settings to maintain control.
    @available(macOS 10.15, *)
    static func requestInputMonitoringPermission() -> Bool {
        AppLogger.shared.log(
            "🔐 [PermissionService] DISABLED: requestInputMonitoringPermission - will not auto-request permission")

        // NEVER call IOHIDRequestAccess as it automatically adds the app to Input Monitoring preferences
        // This was the source of the auto-reinstallation behavior the user complained about

        AppLogger.shared.log(
            "🔐 [PermissionService] Automatic permission requests are disabled. User must grant manually.")

        return false // Always return false to indicate manual action is required
    }

    /// Detect if there might be stale KeyPath entries in Input Monitoring
    /// This checks for common indicators of old or duplicate entries
    static func detectPossibleStaleEntries() async -> (hasStaleEntries: Bool, details: [String]) {
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
        // Use direct pgrep call without shell to avoid injection risks
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "kanata"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.terminationHandler = { _ in
                    continuation.resume(returning: ())  // Fixed: provide return value
                }
                do {
                    try task.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
                let count = pids.count
                if count > 1 {
                    indicators.append("Multiple kanata processes detected (\(count) running)")
                }
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
                "\(homeDir)/Downloads/KeyPath.app",
            ]

            for oldPath in possibleOldPaths {
                if oldPath != bundlePath, FileManager.default.fileExists(atPath: oldPath) {
                    indicators.append("Found KeyPath at \(oldPath) - may have old permissions")
                }
            }
        }

        AppLogger.shared.log(
            "🔐 [PermissionService] Stale entry detection: \(indicators.isEmpty ? "No indicators found" : indicators.joined(separator: ", "))"
        )

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
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings directly to Accessibility
    static func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    static func checkTCCForAccessibility(path: String) -> Bool {
        // For KeyPath app itself, use AXIsProcessTrusted for current process
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            let hasAccess = AXIsProcessTrusted()
            AppLogger.shared.log("🔐 [PermissionService] AXIsProcessTrusted for current process: \(hasAccess)")
            return hasAccess
        }

        // Try TCC database with robust service name candidates
        if let allowed = checkTCCDatabase(for: path, services: ["kTCCServiceAccessibility", "Accessibility"]) {
            AppLogger.shared.log("🔐 [PermissionService] TCC DB Accessibility for \(path): \(allowed)")
            if allowed {
                traceGrant("TCC", details: "Accessibility allowed for client \(path)")
            }
            return allowed
        }

        // Fallback heuristic if TCC DB is not accessible
        return checkBinaryPermission(for: path, service: "Accessibility")
    }

    static func checkTCCForInputMonitoring(path: String) -> Bool {
        // For KeyPath app itself, DO NOT invoke APIs that auto-register
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            AppLogger.shared.log("🔐 [PermissionService] Using non-invasive check for current process to avoid auto-registration")
            return PermissionService.shared.checkInputMonitoringNonInvasively()
        }

        // Try TCC database with robust service name candidates
        if let allowed = checkTCCDatabase(for: path, services: ["kTCCServiceListenEvent", "ListenEvent"]) {
            AppLogger.shared.log("🔐 [PermissionService] TCC DB ListenEvent for \(path): \(allowed)")
            if allowed {
                traceGrant("TCC", details: "ListenEvent allowed for client \(path)")
            }
            return allowed
        }

        // Fallback heuristic if TCC DB is not accessible
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
        if isKanataBinary(at: path) {
            // Try TCC DB first
            if let allowed = checkTCCDatabase(for: path, service: "kTCCServiceListenEvent") {
                return allowed
            }
            // Conservative fallback
            return testKanataInputAccess(at: path)
        }
        
        AppLogger.shared.log(
            "🔐 [PermissionService] Cannot check Input Monitoring for non-kanata binary: \(path)")
        return false
    }

    /// Check Accessibility permission for a binary
    private static func checkAccessibilityForBinary(at path: String) -> Bool {
        if isKanataBinary(at: path) {
            // Try TCC DB first (using correct service for Accessibility)
            if let allowed = checkTCCDatabase(for: path, service: "kTCCServiceAccessibility") {
                return allowed
            }
            // Conservative fallback - check if service is functional
            // Note: This is less reliable but better than nothing
            return testKanataAccessibilityAccess(at: path)
        }
        
        return false
    }
    
    /// Test if kanata has Accessibility permission specifically
    private static func testKanataAccessibilityAccess(at path: String) -> Bool {
        // Check TCC database for Accessibility service
        if let allowed = checkTCCDatabase(for: path, service: "kTCCServiceAccessibility") {
            AppLogger.shared.log("🔐 [PermissionService] TCC database check for kanata (Accessibility): \(allowed)")
            return allowed
        }
        
        // Conservative default: assume no permission
        AppLogger.shared.log("🔐 [PermissionService] Cannot verify kanata Accessibility permission - assuming not granted")
        return false
    }

    /// Test if kanata has the necessary permissions by checking TCC database
    private static func testKanataInputAccess(at path: String) -> Bool {
        // IMPORTANT: We cannot reliably determine if kanata has Input Monitoring permission
        // just by checking if it's running. Kanata can run without permission but won't
        // capture any keys.
        
        // Try to check the TCC database directly with multiple identifiers
        let candidates = [
            path,  // Full path
            codeSignatureIdentifier(at: path) ?? path,  // Code signature identifier
            URL(fileURLWithPath: path).lastPathComponent  // Just the binary name
        ]
        
        for candidate in candidates {
            if let hasTCCAccess = checkTCCDatabase(for: candidate, service: "kTCCServiceListenEvent") {
                AppLogger.shared.log("🔐 [PermissionService] TCC database check for kanata (\(candidate)): \(hasTCCAccess)")
                if hasTCCAccess {
                    return true
                }
            }
        }
        
        // If we can't find TCC entries, try functional verification
        // Check if kanata is in the process of capturing keys successfully
        if isKanataCapturingKeys() {
            AppLogger.shared.log("🔐 [PermissionService] Kanata appears to be capturing keys successfully - has functional permission")
            return true
        }
        
        // Try a simple test run to see if kanata can access input devices
        if testKanataCanAccessInputDevices(at: path) {
            AppLogger.shared.log("🔐 [PermissionService] Kanata test run shows it can access input devices")
            return true
        }
        
        // Conservative default: assume no permission
        AppLogger.shared.log("🔐 [PermissionService] Cannot verify kanata Input Monitoring permission - assuming not granted")
        return false
    }
    
    /// Test if kanata can access input devices by running a quick validation
    private static func testKanataCanAccessInputDevices(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.shared.log("🔐 [PermissionService] Kanata binary not found at \(path)")
            return false
        }
        
        // Create a minimal test config that doesn't interfere with anything
        let testConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc esc)
        (deflayer base esc)
        """
        
        let tempConfigPath = "/tmp/keypath_permission_test_\(UUID().uuidString).kbd"
        
        do {
            try testConfig.write(toFile: tempConfigPath, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: tempConfigPath) }
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["--cfg", tempConfigPath, "--check"]
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errorPipe
            
            // Set a timeout
            task.environment = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin"]
            
            try task.run()
            task.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let combinedOutput = output + errorOutput
            
            // Check for permission-related errors
            let permissionErrors = [
                "operation not permitted",
                "iokit",
                "hid",
                "device not accessible",
                "privilege violation"
            ]
            
            let hasPermissionError = permissionErrors.contains { error in
                combinedOutput.lowercased().contains(error)
            }
            
            if hasPermissionError {
                AppLogger.shared.log("🔐 [PermissionService] Kanata test run shows permission errors: \(combinedOutput)")
                return false
            } else if task.terminationStatus == 0 {
                AppLogger.shared.log("🔐 [PermissionService] Kanata test run successful - likely has permissions")
                return true
            } else {
                AppLogger.shared.log("🔐 [PermissionService] Kanata test run failed with exit code \(task.terminationStatus), but no clear permission errors")
                return false
            }
            
        } catch {
            AppLogger.shared.log("🔐 [PermissionService] Failed to test kanata permissions: \(error)")
            return false
        }
    }
    
    /// Check if kanata is actively capturing keys (by checking TCP layer info or logs)
    private static func isKanataCapturingKeys() -> Bool {
        // Respect TCP preferences for a non-invasive functional hint
        let tcpConfig = PreferencesService.tcpSnapshot()
        guard tcpConfig.shouldUseTCPServer else {
            AppLogger.shared.log("🔐 [PermissionService] TCP server disabled; skipping capture check")
            return false
        }
        let host = "127.0.0.1"
        let port = tcpConfig.port
        
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            AppLogger.shared.log("🔐 [PermissionService] Cannot create socket for kanata TCP check")
            return false
        }
        
        defer { close(sock) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        
        // Set a very short timeout for the connection attempt
        var timeout = timeval()
        timeout.tv_sec = 1
        timeout.tv_usec = 0
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if result == 0 {
            AppLogger.shared.log("🔐 [PermissionService] Successfully connected to kanata TCP server on port \(port) - likely has permissions")
            return true
        } else {
            AppLogger.shared.log("🔐 [PermissionService] Cannot connect to kanata TCP server on port \(port) - may not have permissions or not running")
            return false
        }
    }
    
    /// Try multiple TCC service names in order, returning the first definite result
    private static func checkTCCDatabase(for client: String, services: [String]) -> Bool? {
        for service in services {
            if let allowed = checkTCCDatabase(for: client, service: service) {
                return allowed
            }
        }
        return nil
    }

    /// Try to check TCC database directly (requires Full Disk Access)
    private static func checkTCCDatabase(for client: String, service: String) -> Bool? {
        // Detect whether input is a filesystem path or a bundle identifier / client ID
        let isPathLike = client.hasPrefix("/") || client.hasPrefix("~")
        var candidates: [String] = []
        var logClientKind = "identifier"

        if isPathLike {
            logClientKind = "path"
            let stdPath = standardizedPath(client)
            let escapedStd = escapeForSQLite(stdPath)
            candidates.append(escapedStd)

            // Also consider the original (possibly symlink) path if different
            if client != stdPath {
                let escapedOrig = escapeForSQLite(client)
                candidates.append(escapedOrig)
            }

            // Try to include the code-sign identifier for the path (if any)
            if FileManager.default.fileExists(atPath: stdPath),
               let identifier = codeSignatureIdentifier(at: stdPath)
            {
                candidates.append(escapeForSQLite(identifier))
                AppLogger.shared.log("🔍 [PermissionService] Added code signature identifier for \(stdPath): \(identifier)")
            }
        } else {
            // Treat as identifier (e.g., bundle identifier)
            let escapedId = escapeForSQLite(client)
            candidates.append(escapedId)

            // Try to resolve a bundle path for this identifier (best-effort, may fail on dev builds)
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
                let resolvedPath = standardizedPath(appURL.path)
                candidates.append(escapeForSQLite(resolvedPath))
                if let identifier = codeSignatureIdentifier(at: resolvedPath) {
                    candidates.append(escapeForSQLite(identifier))
                }
                AppLogger.shared.log("🔍 [PermissionService] Resolved bundle ID \(client) to app path: \(resolvedPath)")
            }
        }

        let escapedService = escapeForSQLite(service)
        AppLogger.shared.log("🔍 [PermissionService] Checking TCC database for service=\(service), client(\(logClientKind))=\(client)")
        AppLogger.shared.log("🔍 [PermissionService] Will check candidates: \(candidates)")
        
        // Check both user and system TCC databases
        let userDB = NSHomeDirectory().appending("/Library/Application Support/com.apple.TCC/TCC.db")
        let systemDB = "/Library/Application Support/com.apple.TCC/TCC.db"
        let dbs = [userDB, systemDB]
        
        for db in dbs where FileManager.default.fileExists(atPath: db) {
            AppLogger.shared.log("🔍 [PermissionService] Checking database: \(db)")
            for candidate in candidates {
                // Try modern schema (auth_value) first, then legacy (allowed)
                // auth_value: 0=denied, 1=unknown, 2=allowed
                let sqls = [
                    "SELECT auth_value FROM access WHERE service='\(escapedService)' AND client='\(candidate)' ORDER BY last_modified DESC LIMIT 1;",
                    "SELECT allowed FROM access WHERE service='\(escapedService)' AND client='\(candidate)' ORDER BY last_modified DESC LIMIT 1;"
                ]

                for sql in sqls {
                    AppLogger.shared.log("🔍 [PermissionService] SQL: \(sql)")

                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
                    task.arguments = ["-readonly", db, sql]
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = Pipe()

                    do {
                        try task.run()
                        task.waitUntilExit()
                        if task.terminationStatus == 0 {
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let raw = String(data: data, encoding: .utf8) ?? ""
                            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            if value == "2" || value == "1" { // 2 for auth_value, 1 for allowed
                                let mode = (value == "2") ? "auth_value=2" : "allowed=1"
                                AppLogger.shared.log("🔐 [PermissionService] TCC DB: Found permission (\(mode)) for \(service) at \(db) for client \(candidate)")
                                return true
                            } else if !value.isEmpty {
                                AppLogger.shared.log("🔐 [PermissionService] TCC DB: Found entry for \(candidate) but value=\(value) (not allowed)")
                            }
                        } else {
                            AppLogger.shared.log("🔐 [PermissionService] TCC DB query failed for \(candidate) with exit code \(task.terminationStatus)")
                        }
                    } catch {
                        // Most likely no FDA or access denied; continue trying other DBs/clients
                        AppLogger.shared.log("🔐 [PermissionService] TCC DB not accessible at \(db): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Could not determine (no FDA or no matching client rows)
        return nil
    }

    // MARK: - Enhanced Functional Verification

    /// Result of functional permission verification
    struct FunctionalVerificationResult {
        let hasInputMonitoring: Bool
        let hasAccessibility: Bool
        let hasRecentErrors: Bool
        let errorDetails: [String]
        let verificationMethod: String
        let confidence: VerificationConfidence

        enum VerificationConfidence {
            case high // Direct API test or clear log evidence
            case medium // Service running without errors
            case low // Fallback to TCC database only
            case unknown // Cannot determine due to errors
        }

        var hasAllRequiredPermissions: Bool {
            hasInputMonitoring && hasAccessibility && !hasRecentErrors
        }
    }

    /// Perform comprehensive functional verification for kanata permissions
    /// This checks actual device access capabilities rather than just TCC database entries
    func verifyKanataFunctionalPermissions(at kanataBinaryPath: String) -> FunctionalVerificationResult {
        AppLogger.shared.log("🔍 [PermissionService] Starting functional verification for kanata at \(kanataBinaryPath)")

        // Check cache first for performance
        let cacheKey = "kanata_functional_\(kanataBinaryPath)"
        if let cached = getFunctionalCache(key: cacheKey) {
            AppLogger.shared.log("🔍 [PermissionService] Using cached functional verification result")
            return cached
        }

        var inputMonitoring = false
        var accessibility = false
        var hasRecentErrors = false
        var errorDetails: [String] = []
        var verificationMethod = "unknown"
        var confidence = FunctionalVerificationResult.VerificationConfidence.unknown

        // Method 1: Check if kanata service is running and analyze logs
        let serviceAnalysis = analyzeKanataServiceLogs()
        if serviceAnalysis.hasRecentPermissionErrors {
            hasRecentErrors = true
            errorDetails.append(contentsOf: serviceAnalysis.errorDetails)
            inputMonitoring = false
            accessibility = false
            verificationMethod = "log_analysis_errors_found"
            confidence = .high
            AppLogger.shared.log("🔍 [PermissionService] Log analysis found permission errors - marking as failed")
        } else if serviceAnalysis.serviceIsRunning {
            // Do NOT infer permissions solely from service presence or lack of errors in logs.
            verificationMethod = "service_running_no_errors_but_no_permission_evidence"
            confidence = .unknown
            AppLogger.shared.log("🔍 [PermissionService] Service running, but not inferring permissions without positive evidence")
        }

        // Method 2: If service not running, try direct binary test (careful not to interfere)
        if !serviceAnalysis.serviceIsRunning {
            let binaryTest = testKanataBinaryPermissions(at: kanataBinaryPath)
            inputMonitoring = binaryTest.canAccessInputDevices
            accessibility = binaryTest.canAccessSystem
            if binaryTest.hasErrors {
                hasRecentErrors = true
                errorDetails.append(contentsOf: binaryTest.errorDetails)
            }
            verificationMethod = "binary_test"
            confidence = binaryTest.confidence
            AppLogger.shared.log("🔍 [PermissionService] Binary test result: input=\(inputMonitoring), access=\(accessibility)")
        }

        // Method 3: Fallback to TCC database if we can't determine functionally
        if confidence == .unknown || confidence == .low {
            let tccInput = Self.checkTCCForInputMonitoring(path: kanataBinaryPath)
            let tccAccess = Self.checkTCCForAccessibility(path: kanataBinaryPath)

            // Only override if we don't have better information
            if confidence == .unknown {
                inputMonitoring = tccInput
                accessibility = tccAccess
                verificationMethod = "tcc_database_fallback"
                confidence = .low
                AppLogger.shared.log("🔍 [PermissionService] Using TCC database fallback: input=\(inputMonitoring), access=\(accessibility)")
            }
        }

        let result = FunctionalVerificationResult(
            hasInputMonitoring: inputMonitoring,
            hasAccessibility: accessibility,
            hasRecentErrors: hasRecentErrors,
            errorDetails: errorDetails,
            verificationMethod: verificationMethod,
            confidence: confidence
        )

        // Cache result for performance
        cacheFunctionalResult(key: cacheKey, result: result)

        AppLogger.shared.log("🔍 [PermissionService] Functional verification complete: \(verificationMethod), confidence: \(confidence), permissions: \(result.hasAllRequiredPermissions)")
        return result
    }

    /// Analyze kanata service logs for permission errors and service status
    private func analyzeKanataServiceLogs() -> (serviceIsRunning: Bool, hasRecentPermissionErrors: Bool, errorDetails: [String]) {
        var serviceIsRunning = false
        var hasRecentErrors = false
        var errorDetails: [String] = []

        // First check if kanata process is running
        serviceIsRunning = isKanataProcessRunning()

        // Then analyze logs for recent errors
        let logAnalysis = parseKanataLogs()
        hasRecentErrors = logAnalysis.hasPermissionErrors
        errorDetails = logAnalysis.errorDetails

        return (serviceIsRunning, hasRecentErrors, errorDetails)
    }

    /// Parse kanata logs for permission-related errors
    private func parseKanataLogs() -> (hasPermissionErrors: Bool, errorDetails: [String]) {
        let logPaths = [
            "/var/log/kanata.log",
            "/tmp/kanata.log",
            "/usr/local/var/log/kanata.log",
        ]

        var hasPermissionErrors = false
        var errorDetails: [String] = []

        for logPath in logPaths {
            guard FileManager.default.fileExists(atPath: logPath) else { continue }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
            task.arguments = ["-n", "100", logPath] // Increased from 50 for better detection

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                let analysis = analyzeLogOutput(output, logPath: logPath)
                if analysis.hasPermissionErrors {
                    hasPermissionErrors = true
                    errorDetails.append(contentsOf: analysis.errorDetails)
                }

            } catch {
                AppLogger.shared.log("⚠️ [PermissionService] Failed to read log at \(logPath): \(error)")
            }
        }

        return (hasPermissionErrors, errorDetails)
    }

    /// Analyze log output for permission-related errors
    private func analyzeLogOutput(_ output: String, logPath: String) -> (hasPermissionErrors: Bool, errorDetails: [String]) {
        var hasPermissionErrors = false
        var errorDetails: [String] = []

        // Enhanced permission error patterns based on the bug report
        let permissionPatterns = [
            (pattern: "IOHIDDeviceOpen error.*not permitted", description: "Cannot open HID devices - Input Monitoring permission needed"),
            (pattern: "failed to open keyboard device.*Couldn't register any device", description: "No keyboard devices accessible - Input Monitoring permission needed"),
            (pattern: "privilege violation", description: "System privilege violation"),
            (pattern: "operation not permitted", description: "System operation not permitted"),
            (pattern: "iokit/common.*not permitted", description: "IOKit access denied"),
            (pattern: "TCC.*denied", description: "Transparency, Consent, and Control (TCC) access denied"),
            (pattern: "Device creation failed", description: "Virtual device creation failed - may need Accessibility permission"),
            (pattern: "Could not grab device", description: "Cannot grab input device - permission issue"),
        ]

        let lines = output.components(separatedBy: .newlines)
        let recentLines = Array(lines.suffix(50)) // Focus on recent entries

        for line in recentLines {
            let lowerLine = line.lowercased()

            for (pattern, description) in permissionPatterns {
                if lowerLine.contains(pattern.lowercased()) ||
                    line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                {
                    hasPermissionErrors = true
                    let errorDetail = "\(description) (from \(logPath))"
                    if !errorDetails.contains(errorDetail) {
                        errorDetails.append(errorDetail)
                    }
                    AppLogger.shared.log("🔍 [PermissionService] Found permission error pattern '\(pattern)' in logs")
                }
            }
        }

        return (hasPermissionErrors, errorDetails)
    }

    /// Check if kanata process is currently running
    private func isKanataProcessRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "kanata"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let pids = output.trimmingCharacters(in: .whitespacesAndNewlines)

            return task.terminationStatus == 0 && !pids.isEmpty
        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Failed to check kanata process: \(error)")
            return false
        }
    }

    /// Test kanata binary permissions without interfering with running service
    private func testKanataBinaryPermissions(at binaryPath: String) -> (
        canAccessInputDevices: Bool,
        canAccessSystem: Bool,
        hasErrors: Bool,
        errorDetails: [String],
        confidence: FunctionalVerificationResult.VerificationConfidence
    ) {
        var canAccessInput = false
        var canAccessSystem = false
        var hasErrors = false
        var errorDetails: [String] = []
        var confidence = FunctionalVerificationResult.VerificationConfidence.low

        // Test 1: Try to run kanata with --check flag (doesn't interfere with running service)
        let checkResult = testKanataConfigCheck(at: binaryPath)
        if checkResult.hasPermissionErrors {
            hasErrors = true
            errorDetails.append(contentsOf: checkResult.errorDetails)
            confidence = .high
            AppLogger.shared.log("🔍 [PermissionService] Kanata config check shows permission errors")
        } else {
            // Config check passing does not imply Input Monitoring or Accessibility.
            AppLogger.shared.log("🔍 [PermissionService] Kanata config check passed; not treating as permission evidence")
        }

        // Test 2: If binary exists, check if it's signed and trusted
        if FileManager.default.fileExists(atPath: binaryPath) {
            let signatureCheck = checkBinarySignature(at: binaryPath)
            if !signatureCheck.isTrusted {
                hasErrors = true
                errorDetails.append("Binary signature validation failed - may need permission reset")
            }
        } else {
            hasErrors = true
            errorDetails.append("Kanata binary not found at \(binaryPath)")
        }

        return (canAccessInput, canAccessSystem, hasErrors, errorDetails, confidence)
    }

    /// Test kanata config validation (safe, doesn't start service)
    private func testKanataConfigCheck(at binaryPath: String) -> (
        configCheckPassed: Bool,
        hasPermissionErrors: Bool,
        errorDetails: [String]
    ) {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            return (false, false, ["Binary not found"])
        }

        // Use a minimal test config to avoid interfering with user config
        let testConfig = """
        (defcfg
          process-unmapped-keys yes
        )
        (defsrc)
        (deflayer base)
        """

        let tempConfigPath = "/tmp/keypath_test_\(UUID().uuidString).kbd"

        do {
            try testConfig.write(toFile: tempConfigPath, atomically: true, encoding: .utf8)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: binaryPath)
            task.arguments = ["--cfg", tempConfigPath, "--check"] // Check mode doesn't start service

            let pipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errorPipe

            task.environment = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin"]

            try task.run()
            task.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: tempConfigPath)

            // Analyze output for permission issues
            let combinedOutput = output + errorOutput
            let logAnalysis = analyzeLogOutput(combinedOutput, logPath: "config_check")

            let configPassed = task.terminationStatus == 0 && !logAnalysis.hasPermissionErrors

            AppLogger.shared.log("🔍 [PermissionService] Config check result: exit=\(task.terminationStatus), errors=\(logAnalysis.hasPermissionErrors)")

            return (configPassed, logAnalysis.hasPermissionErrors, logAnalysis.errorDetails)

        } catch {
            // Clean up temp file on error
            try? FileManager.default.removeItem(atPath: tempConfigPath)
            AppLogger.shared.log("⚠️ [PermissionService] Config check failed: \(error)")
            return (false, false, ["Config check execution failed: \(error.localizedDescription)"])
        }
    }

    /// Check binary signature and trust status
    private func checkBinarySignature(at binaryPath: String) -> (isTrusted: Bool, details: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", binaryPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe // codesign outputs to stderr

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check for valid signature
            let isValid = task.terminationStatus == 0 &&
                !output.lowercased().contains("not signed") &&
                !output.lowercased().contains("invalid")

            return (isValid, output)

        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Code signature check failed: \(error)")
            return (false, "Signature check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Caching for Functional Verification

    private var functionalCache: [String: (result: FunctionalVerificationResult, timestamp: Date)] = [:]

    private func getFunctionalCache(key: String) -> FunctionalVerificationResult? {
        guard let cached = functionalCache[key] else { return nil }

        // Cache functional verification for 10 seconds (longer than TCC cache)
        let isExpired = Date().timeIntervalSince(cached.timestamp) > 10.0
        if isExpired {
            functionalCache.removeValue(forKey: key)
            return nil
        }

        return cached.result
    }

    private func cacheFunctionalResult(key: String, result: FunctionalVerificationResult) {
        functionalCache[key] = (result, Date())
    }

    /// Check if there are recent permission errors in kanata logs
    /// @deprecated Use analyzeKanataServiceLogs() instead for enhanced detection
    private static func hasRecentPermissionErrors() -> Bool {
        let logAnalysis = PermissionService.shared.parseKanataLogs()
        return logAnalysis.hasPermissionErrors
    }

    /// Clear the permission cache (useful after user grants permissions)
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.permissionCache.removeAll()
            self.functionalCache.removeAll()
        }
        AppLogger.shared.log("🔐 [PermissionService] Permission caches cleared")
    }

    /// Mark that Input Monitoring permission has been granted by the user
    /// This helps the non-invasive check return true without using system APIs
    func markInputMonitoringPermissionGranted() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(Date().timeIntervalSince1970, forKey: "keypath_input_monitoring_granted")
        clearCache() // Clear cache so next check uses the new timestamp
        AppLogger.shared.log("🔐 [PermissionService] Marked Input Monitoring permission as granted")
    }
}
