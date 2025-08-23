import AppKit
import ApplicationServices
import Foundation
import IOKit
import SQLite3

class PermissionService {
    // MARK: - Static Instance
    
    static let shared = PermissionService()
    
    private init() {}
    
    // MARK: - 🔮 Oracle Era: Safe TCC Database API Only
    //
    // The PermissionService has been slimmed down to provide only safe,
    // deterministic TCC database reading methods used by PermissionOracle.
    //
    // All heuristic detection, permission checking, and complex logic 
    // has been moved to PermissionOracle for single source of truth.
    
    // MARK: - Legacy Compatibility (Minimal Stubs)
    
    /// Legacy compatibility flag for TCC access
    static var lastTCCAuthorizationDenied = false
    
    /// Legacy method stub - functionality moved to Oracle
    func clearCache() {
        AppLogger.shared.log("🔮 [PermissionService] clearCache() called - Oracle handles caching now")
    }
    
    /// Legacy method stub - opens Input Monitoring settings
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Legacy method stub - functionality moved to Oracle  
    func markInputMonitoringPermissionGranted() {
        AppLogger.shared.log("🔮 [PermissionService] markInputMonitoringPermissionGranted() - Oracle handles state now")
    }
    
    
    /// Legacy compatibility for DI protocol
    struct SystemPermissionStatus {
        let keyPath: BinaryPermissionStatus
        let kanata: BinaryPermissionStatus
        var hasAllRequiredPermissions: Bool { false }
    }
    
    struct BinaryPermissionStatus {
        let binaryPath: String
        let hasInputMonitoring: Bool
        let hasAccessibility: Bool
        var hasAllRequiredPermissions: Bool { false }
    }
    
    /// Legacy method stub - use Oracle instead
    func checkSystemPermissions(kanataBinaryPath: String) -> SystemPermissionStatus {
        return SystemPermissionStatus(
            keyPath: BinaryPermissionStatus(binaryPath: "", hasInputMonitoring: false, hasAccessibility: false),
            kanata: BinaryPermissionStatus(binaryPath: kanataBinaryPath, hasInputMonitoring: false, hasAccessibility: false)
        )
    }
    
    /// Legacy method stub - use Oracle instead  
    func verifyKanataFunctionalPermissions(at path: String) -> (hasInputMonitoring: Bool, hasAccessibility: Bool, confidence: String, verificationMethod: String, hasAllRequiredPermissions: Bool, errorDetails: [String]) {
        return (hasInputMonitoring: false, hasAccessibility: false, confidence: "low", verificationMethod: "oracle-migration-stub", hasAllRequiredPermissions: false, errorDetails: [])
    }
    
    /// Legacy method stub - error analysis moved to Oracle
    static func analyzeKanataError(_ error: String) -> (isPermissionError: Bool, description: String, suggestedFix: String?) {
        return (isPermissionError: false, description: "Oracle system - see permission snapshot for details", suggestedFix: "Use Permission Oracle for diagnostics")
    }
    
    /// Legacy method stub - opens accessibility permission dialog
    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    
    /// Legacy stub for stale entry detection - returns array format
    static func detectPossibleStaleEntries() async -> (hasStaleEntries: Bool, details: [String]) {
        return (hasStaleEntries: false, details: ["Oracle system - no stale entry detection needed"])
    }
    
    /// Check TCC database for Accessibility permission for a specific binary path
    /// Returns true if permission is explicitly granted, false otherwise
    /// - Parameter path: Full path to binary or bundle identifier
    static func checkTCCForAccessibility(path: String) -> Bool {
        guard let db = openTCCDatabase() else {
            AppLogger.shared.log("🔍 [PermissionService] Failed to open TCC database for accessibility check")
            return false
        }
        
        defer { sqlite3_close(db) }
        
        let query = "SELECT allowed FROM access WHERE service = 'kTCCServiceAccessibility' AND client = ?;"
        return executeTCCQuery(db: db, query: query, path: path)
    }
    
    /// Check TCC database for Input Monitoring permission for a specific binary path  
    /// Returns true if permission is explicitly granted, false otherwise
    /// - Parameter path: Full path to binary or bundle identifier
    static func checkTCCForInputMonitoring(path: String) -> Bool {
        guard let db = openTCCDatabase() else {
            AppLogger.shared.log("🔍 [PermissionService] Failed to open TCC database for input monitoring check")
            return false
        }
        
        defer { sqlite3_close(db) }
        
        let query = "SELECT allowed FROM access WHERE service = 'kTCCServiceListenEvent' AND client = ?;"
        return executeTCCQuery(db: db, query: query, path: path)
    }
    
    // MARK: - Apple API Wrappers (for Oracle use)
    
    /// Check KeyPath's own Accessibility permission using official Apple API
    /// Safe to call - will not trigger permission prompt
    func hasAccessibilityPermission() -> Bool {
        let granted = AXIsProcessTrusted()
        AppLogger.shared.log("🔍 [PermissionService] KeyPath Accessibility permission: \(granted)")
        return granted
    }
    
    /// Check KeyPath's own Input Monitoring permission using official Apple API
    /// Safe to call - will not trigger permission prompt  
    func hasInputMonitoringPermission() -> Bool {
        let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let granted = accessType == kIOHIDAccessTypeGranted
        AppLogger.shared.log("🔍 [PermissionService] KeyPath Input Monitoring permission: \(granted)")
        return granted
    }
    
    // MARK: - Private TCC Database Utilities
    
    private static func openTCCDatabase() -> OpaquePointer? {
        let tccPath = NSHomeDirectory().appending("/Library/Application Support/com.apple.TCC/TCC.db")
        
        guard FileManager.default.isReadableFile(atPath: tccPath) else {
            AppLogger.shared.log("🔍 [PermissionService] TCC database not accessible - Full Disk Access required")
            return nil
        }
        
        var db: OpaquePointer?
        let result = sqlite3_open_v2(tccPath, &db, SQLITE_OPEN_READONLY, nil)
        
        if result != SQLITE_OK {
            AppLogger.shared.log("🔍 [PermissionService] Failed to open TCC database: \(result)")
            sqlite3_close(db)
            return nil
        }
        
        return db
    }
    
    private static func executeTCCQuery(db: OpaquePointer, query: String, path: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            AppLogger.shared.log("🔍 [PermissionService] Failed to prepare TCC query")
            return false
        }
        
        guard sqlite3_bind_text(stmt, 1, path, -1, nil) == SQLITE_OK else {
            AppLogger.shared.log("🔍 [PermissionService] Failed to bind TCC query parameter")
            return false
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let allowed = sqlite3_column_int(stmt, 0)
            let granted = allowed == 1
            AppLogger.shared.log("🔍 [PermissionService] TCC check for '\(path)': \(granted)")
            return granted
        } else {
            AppLogger.shared.log("🔍 [PermissionService] TCC check for '\(path)': no entry found")
            return false
        }
    }
}