import Foundation
import KeyPathCore

/// Manages security settings and approvals for script execution in Quick Launcher.
///
/// Security Model:
/// 1. Script execution is globally disabled by default
/// 2. User must explicitly enable via Settings
/// 3. First run shows warning dialog (can be bypassed via setting)
/// 4. All executions are logged for audit trail
@MainActor
public final class ScriptSecurityService: ObservableObject {
    public static let shared = ScriptSecurityService()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let scriptExecutionEnabled = "KeyPath.Security.ScriptExecutionEnabled"
        static let bypassFirstRunDialog = "KeyPath.Security.BypassFirstRunDialog"
        static let scriptExecutionLog = "KeyPath.Security.ScriptExecutionLog"
    }

    // MARK: - Published Properties

    /// Whether script execution is globally enabled
    @Published public var isScriptExecutionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isScriptExecutionEnabled, forKey: Keys.scriptExecutionEnabled)
            AppLogger.shared.log("🔐 [ScriptSecurity] Script execution \(isScriptExecutionEnabled ? "ENABLED" : "DISABLED")")
        }
    }

    /// Whether to skip the first-run confirmation dialog
    @Published public var bypassFirstRunDialog: Bool {
        didSet {
            UserDefaults.standard.set(bypassFirstRunDialog, forKey: Keys.bypassFirstRunDialog)
            AppLogger.shared.log("🔐 [ScriptSecurity] Bypass dialog: \(bypassFirstRunDialog)")
        }
    }

    // MARK: - Initialization

    private init() {
        isScriptExecutionEnabled = UserDefaults.standard.bool(forKey: Keys.scriptExecutionEnabled)
        bypassFirstRunDialog = UserDefaults.standard.bool(forKey: Keys.bypassFirstRunDialog)
    }

    // MARK: - Security Checks

    /// Result of a script execution check
    public enum ExecutionCheckResult {
        case allowed
        case disabled
        case needsConfirmation(path: String)
        case fileNotFound(path: String)
        case notExecutable(path: String)
    }

    /// Check if a script can be executed
    /// - Parameter path: The path to the script file
    /// - Returns: The result of the check
    public func checkExecution(at path: String) -> ExecutionCheckResult {
        // First check: is script execution enabled?
        guard isScriptExecutionEnabled else {
            return .disabled
        }

        // Expand tilde in path
        let expandedPath = (path as NSString).expandingTildeInPath

        // Check file exists
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .fileNotFound(path: expandedPath)
        }

        // Check file is executable (or is a script type we can run)
        let isExecutable = FileManager.default.isExecutableFile(atPath: expandedPath)
        let isScriptType = isRecognizedScript(expandedPath)

        guard isExecutable || isScriptType else {
            return .notExecutable(path: expandedPath)
        }

        // Check if we need confirmation
        if !bypassFirstRunDialog {
            return .needsConfirmation(path: expandedPath)
        }

        return .allowed
    }

    /// Log a script execution for audit
    public func logExecution(path: String, success: Bool, error: String?) {
        let entry: [String: Any] = [
            "path": path,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "success": success,
            "error": error ?? ""
        ]

        var log = UserDefaults.standard.array(forKey: Keys.scriptExecutionLog) as? [[String: Any]] ?? []
        log.append(entry)

        // Keep last 100 entries
        if log.count > 100 {
            log = Array(log.suffix(100))
        }

        UserDefaults.standard.set(log, forKey: Keys.scriptExecutionLog)

        if success {
            AppLogger.shared.log("✅ [ScriptSecurity] Executed: \(path)")
        } else {
            AppLogger.shared.log("❌ [ScriptSecurity] Failed: \(path) - \(error ?? "unknown error")")
        }
    }

    /// Get execution log entries
    public var executionLog: [[String: Any]] {
        UserDefaults.standard.array(forKey: Keys.scriptExecutionLog) as? [[String: Any]] ?? []
    }

    // MARK: - Helper Methods

    /// Check if path is an AppleScript
    public func isAppleScript(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "applescript" || ext == "scpt"
    }

    /// Check if path is a shell script
    public func isShellScript(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "sh" || ext == "bash" || ext == "zsh"
    }

    /// Check if path is an interpreted script (Python, Ruby, Perl, etc.)
    public func isInterpretedScript(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext == "py" || ext == "rb" || ext == "pl" || ext == "lua"
    }

    /// Check if path is any recognized script type
    public func isRecognizedScript(_ path: String) -> Bool {
        isAppleScript(path) || isShellScript(path) || isInterpretedScript(path)
    }

    /// Reset all security settings (for uninstall/reset)
    public func resetAllSettings() {
        isScriptExecutionEnabled = false
        bypassFirstRunDialog = false
        UserDefaults.standard.removeObject(forKey: Keys.scriptExecutionLog)
        AppLogger.shared.log("🔐 [ScriptSecurity] All settings reset")
    }
}
