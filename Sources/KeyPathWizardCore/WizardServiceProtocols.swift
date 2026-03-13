import Foundation
import KeyPathCore
import KeyPathPermissions

// MARK: - SystemValidator Protocol

@MainActor
public protocol WizardSystemValidating: AnyObject, Sendable {
    func checkSystem() async -> SystemSnapshot
}

// MARK: - SplitRuntime Protocol

@MainActor
public protocol WizardSplitRuntimeHosting: AnyObject, Sendable {
    var isPersistentPassthruHostRunning: Bool { get }
    var activePersistentHostPID: Int? { get }
}

// MARK: - SplitRuntimeIdentity (extracted from KanataSplitRuntimeHostService)

public enum WizardSplitRuntimeIdentity {
    public static let hostTitle = "KeyPath Runtime (Split)"
    public static let hostDetailPrefix = "PID"
}

// MARK: - HelperMaintenance Protocol

@MainActor
public protocol WizardHelperMaintaining: AnyObject, Sendable {
    func detectDuplicateAppCopies() -> [String]
    func runCleanupAndRepair(useAppleScriptFallback: Bool) async -> Bool
    var logLines: [String] { get }
}

// MARK: - UninstallCoordinator Protocol

@MainActor
public protocol WizardUninstalling: Sendable {
    func uninstall(deleteConfig: Bool) async -> Bool
}

// MARK: - RuntimePathCoordinator Protocol

@MainActor
public protocol WizardRuntimePathCoordinating: Sendable {
    func evaluateCurrentPath() async -> KanataRuntimePathDecision?
}

// MARK: - FullDiskAccessChecker Protocol

public protocol WizardFullDiskAccessChecking: AnyObject, Sendable {
    func hasFullDiskAccess() -> Bool
    func updateCachedValue(_ value: Bool)
}

// MARK: - PermissionRequestService Protocol

@MainActor
public protocol WizardPermissionRequesting: AnyObject, Sendable {
    func requestInputMonitoringPermission(ignoreCooldown: Bool) -> Bool
    func requestAccessibilityPermission(ignoreCooldown: Bool) -> Bool
}

// MARK: - PermissionService Protocol

// STUB: WizardPermissionAnalyzing is an intentional no-op placeholder. Actual permission
// analysis is deferred entirely to the Permission Oracle system (PermissionOracle.shared),
// which uses IOHIDCheckAccess as the authoritative source. This type exists only to satisfy
// call sites that historically expected a permission-analysis helper; callers should use
// the Oracle and SystemSnapshot permission fields instead.
public enum WizardPermissionAnalyzing {
    public static func analyzeKanataError(_: String) -> (
        isPermissionError: Bool, description: String, suggestedFix: String?
    ) {
        (
            isPermissionError: false,
            description: "Oracle system - see permission snapshot for details",
            suggestedFix: "Use Permission Oracle for diagnostics"
        )
    }
}

// MARK: - SignatureHealthCheck Protocol

public enum WizardSignatureHealthCheck {
    /// Check if the current app is running ad-hoc signed (not notarized)
    public static func isRunningAdHoc() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dvvv", bundlePath]
        let pipe = Pipe()
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("adhoc")
        } catch {
            return false
        }
    }
}

// MARK: - TCPProbe Protocol

public protocol WizardTCPProbing: Sendable {
    static func probe(port: Int, timeoutMs: Int) -> Bool
}

// MARK: - Notification Names

public extension NSNotification.Name {
    static let wizardStartupRevalidate = NSNotification.Name("kp_startupRevalidate")
    static let wizardContentSizeChanged = NSNotification.Name("wizardContentSizeChanged")
    static let wizardSmAppServiceApprovalRequired = NSNotification.Name("smAppServiceApprovalRequired")
    static let wizardOpenInstallationWizard = NSNotification.Name("openInstallationWizard")
}

// MARK: - PrivilegedOperationsCoordinating Protocol

/// Abstraction for privileged system operations (helper + sudo).
/// Copied from KeyPathAppKit to avoid circular dependency.
@MainActor
public protocol WizardPrivilegedOperating: AnyObject {
    func cleanupPrivilegedHelper() async throws
    func installRequiredRuntimeServices() async throws
    func recoverRequiredRuntimeServices() async throws
    func installServicesIfUninstalled(context: String) async throws -> Bool
    func installNewsyslogConfig() async throws
    func regenerateServiceConfiguration() async throws
    func repairVHIDDaemonServices() async throws
    func downloadAndInstallCorrectVHIDDriver() async throws
    func activateVirtualHIDManager() async throws
    func terminateProcess(pid: Int32) async throws
    func killAllKanataProcesses() async throws
    func restartKarabinerDaemonVerified() async throws -> Bool
    func uninstallVirtualHIDDrivers() async throws
    func disableKarabinerGrabber() async throws
    func sudoExecuteCommand(_ command: String, description: String) async throws
}
