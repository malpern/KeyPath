import CryptoKit
import Foundation
import KeyPathCore
import Observation

/// Remembers which scripts the user has chosen to always allow.
///
/// An approval names one script file and the exact contents the user approved,
/// so an edited script asks again.
@MainActor
public protocol ScriptApprovalStore: AnyObject {
    func isApproved(path: String, digest: String) -> Bool
    /// Returns false when the approval could not be saved.
    func approve(path: String, digest: String) -> Bool
    /// Returns false when the approvals could not be removed.
    func removeAll() -> Bool
    var count: Int { get }
}

/// Keeps approvals in an in-memory set. Used by tests and previews.
@MainActor
public final class InMemoryScriptApprovalStore: ScriptApprovalStore {
    private var approvals: Set<String> = []

    public init() {}

    public func isApproved(path: String, digest: String) -> Bool {
        approvals.contains(ScriptApproval.key(path: path, digest: digest))
    }

    public func approve(path: String, digest: String) -> Bool {
        approvals.insert(ScriptApproval.key(path: path, digest: digest))
        return true
    }

    public func removeAll() -> Bool {
        approvals.removeAll()
        return true
    }

    public var count: Int {
        approvals.count
    }
}

/// Keeps approvals in the login Keychain, where another process cannot add one silently.
@MainActor
public final class KeychainScriptApprovalStore: ScriptApprovalStore {
    private let items: KeychainStringSet

    public init() {
        items = KeychainStringSet(account: "script-approvals")
    }

    init(items: KeychainStringSet) {
        self.items = items
    }

    public func isApproved(path: String, digest: String) -> Bool {
        items.members.contains(ScriptApproval.key(path: path, digest: digest))
    }

    public func approve(path: String, digest: String) -> Bool {
        items.insert(ScriptApproval.key(path: path, digest: digest))
    }

    public func removeAll() -> Bool {
        items.removeAll()
    }

    public var count: Int {
        items.members.count
    }
}

enum ScriptApproval {
    static func key(path: String, digest: String) -> String {
        "\(digest) \(path)"
    }

    /// Scripts larger than this are not run; reading them would stall the main thread.
    static let maximumScriptBytes = 16 * 1_048_576

    /// SHA-256 of the file's contents, or nil when it is not a regular file,
    /// is larger than `maximumScriptBytes`, or cannot be read.
    /// A symlinked script (stow, chezmoi) is read through its link; pointing the
    /// link somewhere else changes the digest, so it asks again.
    static func digest(ofFileAt path: String) -> String? {
        let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? Foundation.FileManager().attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= maximumScriptBytes,
              let data = Foundation.FileManager().contents(atPath: path)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Manages security settings and approvals for script execution in Quick Launcher.
///
/// Security model:
/// 1. Script execution is off by default and turned on in Settings.
/// 2. Each script asks before it first runs. "Always Allow" remembers that
///    script, with its exact contents, in the Keychain. Editing the script
///    makes it ask again.
/// 3. Every run is logged.
@Observable
@MainActor
public final class ScriptSecurityService {
    public static let shared = ScriptSecurityService(approvals: KeychainScriptApprovalStore())

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let scriptExecutionEnabled = "KeyPath.Security.ScriptExecutionEnabled"
        /// Retired: a global "skip the warning" switch that any process could set.
        static let retiredBypassFirstRunDialog = "KeyPath.Security.BypassFirstRunDialog"
        static let scriptExecutionLog = "KeyPath.Security.ScriptExecutionLog"
    }

    private let defaults: UserDefaults
    private let approvals: ScriptApprovalStore

    // MARK: - Published Properties

    /// Whether script execution is globally enabled
    public var isScriptExecutionEnabled: Bool {
        didSet {
            defaults.set(isScriptExecutionEnabled, forKey: Keys.scriptExecutionEnabled)
            AppLogger.shared.log("🔐 [ScriptSecurity] Script execution \(isScriptExecutionEnabled ? "ENABLED" : "DISABLED")")
        }
    }

    /// Number of scripts the user has chosen to always allow. Read from the
    /// Keychain only when Settings asks (`refreshApprovedScriptCount`), never at launch.
    public private(set) var approvedScriptCount = 0

    // MARK: - Initialization

    /// Approvals default to memory, so only `shared` touches the Keychain.
    init(defaults: UserDefaults? = nil, approvals: ScriptApprovalStore? = nil) {
        self.defaults = defaults ?? .standard
        self.approvals = approvals ?? InMemoryScriptApprovalStore()
        isScriptExecutionEnabled = self.defaults.bool(forKey: Keys.scriptExecutionEnabled)
        self.defaults.removeObject(forKey: Keys.retiredBypassFirstRunDialog)
    }

    /// Re-reads how many scripts are always allowed, for Settings.
    public func refreshApprovedScriptCount() {
        approvedScriptCount = approvals.count
    }

    // MARK: - Security Checks

    /// Result of a script execution check
    public enum ExecutionCheckResult {
        case allowed(digest: String)
        case disabled
        case needsConfirmation(path: String, digest: String)
        case fileNotFound(path: String)
        case notExecutable(path: String)
    }

    /// Check if a script can be executed
    /// - Parameter path: The path to the script file
    /// - Returns: The result of the check
    public func checkExecution(at path: String) -> ExecutionCheckResult {
        guard isScriptExecutionEnabled else {
            return .disabled
        }

        let expandedPath = (path as NSString).expandingTildeInPath

        guard Foundation.FileManager().fileExists(atPath: expandedPath) else {
            return .fileNotFound(path: expandedPath)
        }

        let isExecutable = Foundation.FileManager().isExecutableFile(atPath: expandedPath)
        guard isExecutable || isRecognizedScript(expandedPath) else {
            return .notExecutable(path: expandedPath)
        }

        guard let digest = ScriptApproval.digest(ofFileAt: expandedPath) else {
            return .notExecutable(path: expandedPath)
        }

        if approvals.isApproved(path: expandedPath, digest: digest) {
            return .allowed(digest: digest)
        }
        return .needsConfirmation(path: expandedPath, digest: digest)
    }

    /// Remember that the user always allows this script with these contents.
    /// Returns false when the choice could not be saved; the script then asks again next time.
    @discardableResult
    public func alwaysAllow(path: String, digest: String) -> Bool {
        let saved = approvals.approve(path: path, digest: digest)
        approvedScriptCount = approvals.count
        AppLogger.shared.log("🔐 [ScriptSecurity] Always allow \(saved ? "saved" : "NOT saved"): \(path)")
        return saved
    }

    /// Forget every "Always Allow" choice, so each script asks again.
    /// Returns false when the Keychain refused; the approvals then still apply.
    @discardableResult
    public func forgetApprovedScripts() -> Bool {
        let removed = approvals.removeAll()
        approvedScriptCount = approvals.count
        AppLogger.shared.log("🔐 [ScriptSecurity] Forget approved scripts: \(removed ? "done" : "FAILED")")
        return removed
    }

    /// Log a script execution for audit
    public func logExecution(path: String, success: Bool, error: String?) {
        let entry: [String: Any] = [
            "path": path,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "success": success,
            "error": error ?? ""
        ]

        var log = defaults.array(forKey: Keys.scriptExecutionLog) as? [[String: Any]] ?? []
        log.append(entry)

        // Keep last 100 entries
        if log.count > 100 {
            log = Array(log.suffix(100))
        }

        defaults.set(log, forKey: Keys.scriptExecutionLog)

        if success {
            AppLogger.shared.log("✅ [ScriptSecurity] Executed: \(path)")
        } else {
            AppLogger.shared.log("❌ [ScriptSecurity] Failed: \(path) - \(error ?? "unknown error")")
        }
    }

    /// Get execution log entries
    public var executionLog: [[String: Any]] {
        defaults.array(forKey: Keys.scriptExecutionLog) as? [[String: Any]] ?? []
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

    /// Reset all security settings (for uninstall/reset). Returns false when
    /// the Keychain refused to remove the approvals.
    @discardableResult
    public func resetAllSettings() -> Bool {
        isScriptExecutionEnabled = false
        let forgot = forgetApprovedScripts()
        defaults.removeObject(forKey: Keys.scriptExecutionLog)
        AppLogger.shared.log("🔐 [ScriptSecurity] All settings reset")
        return forgot
    }
}
