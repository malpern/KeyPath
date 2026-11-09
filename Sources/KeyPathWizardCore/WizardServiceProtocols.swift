import Foundation
import KeyPathCore
import KeyPathPermissions

// MARK: - SystemValidator Protocol

public enum WizardSystemSnapshotFreshness: Sendable, Equatable {
    /// Reuse a recent canonical snapshot when available; otherwise capture one.
    case cached
    /// Capture current evidence, coalescing only with an in-flight capture.
    case fresh
}

@MainActor
public protocol WizardSystemValidating: AnyObject, Sendable {
    func checkSystem() async -> SystemSnapshot
    func checkSystem(freshness: WizardSystemSnapshotFreshness) async -> SystemSnapshot
    func invalidateCaches()
}

public extension WizardSystemValidating {
    func checkSystem(freshness _: WizardSystemSnapshotFreshness) async -> SystemSnapshot {
        await checkSystem()
    }

    func invalidateCaches() {}
}

// MARK: - UninstallCoordinator Protocol

public enum WizardUninstallRecoveryAction: String, Sendable, Equatable {
    case emergencyCleanup = "emergency-cleanup"
}

public struct WizardUninstallStepResult: Sendable, Equatable {
    public let id: String
    public let success: Bool
    public let error: String?

    public init(id: String, success: Bool, error: String? = nil) {
        self.id = id
        self.success = success
        self.error = error
    }
}

public struct WizardUninstallResult: Sendable, Equatable {
    public let success: Bool
    public let failureReason: String?
    public let recommendedRecovery: WizardUninstallRecoveryAction?
    public let steps: [WizardUninstallStepResult]
    public let logs: [String]

    public init(
        success: Bool,
        failureReason: String? = nil,
        recommendedRecovery: WizardUninstallRecoveryAction? = nil,
        steps: [WizardUninstallStepResult] = [],
        logs: [String] = []
    ) {
        self.success = success
        self.failureReason = failureReason
        self.recommendedRecovery = recommendedRecovery
        self.steps = steps
        self.logs = logs
    }
}

@MainActor
public protocol WizardUninstalling: Sendable {
    func performUninstall(deleteConfig: Bool) async -> WizardUninstallResult
}

// MARK: - PermissionRequestService Protocol

@MainActor
public protocol WizardPermissionRequesting: AnyObject, Sendable {
    func requestInputMonitoringPermission(ignoreCooldown: Bool) async -> Bool
    func requestAccessibilityPermission(ignoreCooldown: Bool) async -> Bool
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

// MARK: - TCP readiness probe protocol

public protocol WizardTCPProbing: Sendable {
    static func probe(port: Int, timeoutMs: Int) -> Bool
}

// MARK: - Notification Names

public extension NSNotification.Name {
    static let wizardStartupRevalidate = NSNotification.Name("kp_startupRevalidate")
    static let wizardContentSizeChanged = NSNotification.Name("wizardContentSizeChanged")
    static let wizardOpenInstallationWizard = NSNotification.Name("openInstallationWizard")
}
