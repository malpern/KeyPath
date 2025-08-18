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
        // Method 1: Check if kanata service is running successfully
        // If kanata is running without permission errors, KeyPath likely has permission
        if isKanataProcessRunning() && !Self.hasRecentPermissionErrors() {
            AppLogger.shared.log("🔐 [PermissionService] Kanata running without errors - assuming permission granted")
            return true
        }
        
        // Method 2: Check if we've previously cached a successful permission grant
        // This helps avoid repeated requests after the user has granted permission
        let userDefaults = UserDefaults.standard
        let lastGrantedTimestamp = userDefaults.double(forKey: "keypath_input_monitoring_granted")
        if lastGrantedTimestamp > 0 {
            let lastGranted = Date(timeIntervalSince1970: lastGrantedTimestamp)
            let daysSinceGrant = Date().timeIntervalSince(lastGranted) / (24 * 60 * 60)
            
            // If permission was granted within the last 30 days, assume it's still valid
            // (unless there are recent errors)
            if daysSinceGrant < 30 && !Self.hasRecentPermissionErrors() {
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
        // Note: This is a simplified check - ideally would use ProcessLifecycleManager.detectConflicts()
        // but that's an async method. For now, just check if kanata is running at all.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "pgrep -x kanata | wc -l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    try task.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

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
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings directly to Accessibility
    static func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func checkTCCForAccessibility(path: String) -> Bool {
        // For KeyPath app itself, use AXIsProcessTrusted which checks current process
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            let hasAccess = AXIsProcessTrusted()
            AppLogger.shared.log(
                "🔐 [PermissionService] AXIsProcessTrusted for current process: \(hasAccess)")
            return hasAccess
        }

        // For other binaries (like kanata), use API-based permission checking
        return checkBinaryPermission(for: path, service: "Accessibility")
    }

    static func checkTCCForInputMonitoring(path: String) -> Bool {
        // For KeyPath app itself, DO NOT use IOHIDCheckAccess as it can trigger automatic
        // addition to Input Monitoring preferences. Instead, use non-invasive checking.
        let currentProcessPath = Bundle.main.bundlePath
        if path == currentProcessPath {
            AppLogger.shared.log(
                "🔐 [PermissionService] Using non-invasive check for current process to avoid auto-registration"
            )
            return PermissionService.shared.checkInputMonitoringNonInvasively()
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
        AppLogger.shared.log(
            "🔐 [PermissionService] Cannot check Input Monitoring for non-kanata binary: \(path)")
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
    private static func testKanataInputAccess(at _: String) -> Bool {
        // Check if kanata service is currently running and healthy
        // If it's running without permission errors, it likely has the required permissions

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "kanata.*--cfg.*keypath.kbd"]

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
                // If not running, check if it's supposed to be running (LaunchDaemon exists)
                // and if there are recent permission errors in logs
                if hasRecentPermissionErrors() {
                    AppLogger.shared.log(
                        "🔐 [PermissionService] Kanata not running but permission errors found in logs")
                    return false
                } else {
                    // If not running and no recent errors, we can't determine permission status
                    // Default to requiring permission grant to be safe
                    AppLogger.shared.log(
                        "🔐 [PermissionService] Kanata not running - cannot determine permission status")
                    return false
                }
            }

        } catch {
            AppLogger.shared.log("⚠️ [PermissionService] Failed to check kanata process: \(error)")
            return false
        }
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
            // Service running without permission errors suggests permissions are OK
            inputMonitoring = true
            accessibility = true
            verificationMethod = "service_running_no_errors"
            confidence = .medium
            AppLogger.shared.log("🔍 [PermissionService] Service running without permission errors - assuming permissions granted")
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
            "/usr/local/var/log/kanata.log"
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
            (pattern: "Could not grab device", description: "Cannot grab input device - permission issue")
        ]

        let lines = output.components(separatedBy: .newlines)
        let recentLines = Array(lines.suffix(50)) // Focus on recent entries

        for line in recentLines {
            let lowerLine = line.lowercased()

            for (pattern, description) in permissionPatterns {
                if lowerLine.contains(pattern.lowercased()) ||
                    line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
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
        if checkResult.configCheckPassed {
            canAccessInput = true
            canAccessSystem = true
            confidence = .medium
            AppLogger.shared.log("🔍 [PermissionService] Kanata config check passed - permissions likely OK")
        } else if checkResult.hasPermissionErrors {
            hasErrors = true
            errorDetails.append(contentsOf: checkResult.errorDetails)
            confidence = .high
            AppLogger.shared.log("🔍 [PermissionService] Kanata config check failed with permission errors")
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
        permissionCache.removeAll()
        AppLogger.shared.log("🔐 [PermissionService] Permission cache cleared")
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
