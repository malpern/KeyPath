import Foundation

/// Protocol defining permission checking and management capabilities.
///
/// This protocol establishes a consistent interface for checking system permissions
/// required by KeyPath components. It provides the foundation for clean separation
/// between permission logic and business functionality.
///
/// ## Usage
///
/// Permission services implement this protocol to provide centralized
/// permission management:
///
/// ```swift
/// class SystemPermissionChecker: PermissionChecking {
///     func checkPermission(_ type: SystemPermissionType, for subject: PermissionSubject) async -> PermissionStatus {
///         switch type {
///         case .accessibility:
///             return checkAccessibilityPermission(for: subject)
///         case .inputMonitoring:
///             return checkInputMonitoringPermission(for: subject)
///         }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All methods are async and implementations should ensure thread-safe
/// permission checking across concurrent requests.
protocol PermissionChecking {
    /// Checks the status of a specific permission for a given subject.
    ///
    /// This method performs the actual permission check using the appropriate
    /// system APIs and returns a detailed status result.
    ///
    /// - Parameters:
    ///   - type: The type of permission to check.
    ///   - subject: The subject (app, binary, etc.) to check permissions for.
    ///
    /// - Returns: The current permission status with confidence level.
    func checkPermission(_ type: SystemPermissionType, for subject: PermissionSubject) async -> PermissionStatus

    /// Checks multiple permissions at once for a given subject.
    ///
    /// This method provides an efficient way to check multiple permissions
    /// and returns a comprehensive permission set.
    ///
    /// - Parameters:
    ///   - types: The types of permissions to check.
    ///   - subject: The subject to check permissions for.
    ///
    /// - Returns: A set containing all requested permission statuses.
    func checkPermissions(_ types: [SystemPermissionType], for subject: PermissionSubject) async -> PermissionSet

    /// Gets a snapshot of system-wide permission status.
    ///
    /// This method provides a comprehensive view of all relevant permissions
    /// across all subjects, useful for diagnostic and UI purposes.
    ///
    /// - Returns: A snapshot containing system-wide permission information.
    func getSystemSnapshot() async -> SystemPermissionSnapshot
}

/// Extension providing convenience methods and default implementations.
extension PermissionChecking {
    /// Checks if a subject has all required permissions.
    ///
    /// - Parameters:
    ///   - types: The required permission types.
    ///   - subject: The subject to check.
    ///
    /// - Returns: `true` if all permissions are granted, `false` otherwise.
    func hasAllPermissions(_ types: [SystemPermissionType], for subject: PermissionSubject) async -> Bool {
        let permissions = await checkPermissions(types, for: subject)
        return permissions.hasAllGranted
    }

    /// Checks if the system is ready (all critical permissions granted).
    ///
    /// This convenience method checks the most common permission combination
    /// needed for KeyPath to function properly.
    ///
    /// - Returns: `true` if system is ready, `false` otherwise.
    func isSystemReady() async -> Bool {
        let snapshot = await getSystemSnapshot()
        return snapshot.isSystemReady
    }

    /// Gets a user-friendly message for the first blocking permission issue.
    ///
    /// - Returns: A descriptive message about permission issues, or `nil` if none.
    func getBlockingIssueMessage() async -> String? {
        let snapshot = await getSystemSnapshot()
        return snapshot.blockingIssue
    }
}

/// The types of permissions that can be checked.
enum SystemPermissionType: CaseIterable, Sendable {
    case accessibility
    case inputMonitoring
    case fullDiskAccess

    var displayName: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        case .fullDiskAccess:
            "Full Disk Access"
        }
    }

    var systemSettingsPath: String {
        switch self {
        case .accessibility:
            "Privacy & Security > Accessibility"
        case .inputMonitoring:
            "Privacy & Security > Input Monitoring"
        case .fullDiskAccess:
            "Privacy & Security > Full Disk Access"
        }
    }
}

/// Subjects that can have permissions checked.
enum PermissionSubject: Sendable {
    case currentApp
    case binary(path: String)
    case bundleIdentifier(String)

    var displayName: String {
        switch self {
        case .currentApp:
            return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "KeyPath"
        case let .binary(path):
            return URL(fileURLWithPath: path).lastPathComponent
        case let .bundleIdentifier(id):
            return id
        }
    }
}

/// The status of a permission check.
enum PermissionStatus: Sendable {
    case granted
    case denied
    case unknown
    case error(String)

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }

    var isBlocking: Bool {
        switch self {
        case .denied, .error:
            true
        case .granted, .unknown:
            false
        }
    }

    var description: String {
        switch self {
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .unknown:
            "Unknown"
        case let .error(message):
            "Error: \(message)"
        }
    }
}

/// Confidence level in a permission check result.
enum PermissionConfidence: Sendable {
    case high
    case medium
    case low

    var description: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

/// A set of permission statuses for a specific subject.
struct PermissionSet: Sendable {
    let subject: PermissionSubject
    let permissions: [SystemPermissionType: PermissionStatus]
    let confidence: PermissionConfidence
    let source: String
    let timestamp: Date

    /// Whether all checked permissions are granted.
    var hasAllGranted: Bool {
        permissions.values.allSatisfy(\.isGranted)
    }

    /// Whether any permission is blocking.
    var hasBlockingIssues: Bool {
        permissions.values.contains { $0.isBlocking }
    }

    /// Get the status for a specific permission type.
    func status(for type: SystemPermissionType) -> PermissionStatus? {
        permissions[type]
    }
}

/// A system-wide snapshot of permission statuses.
struct SystemPermissionSnapshot: Sendable {
    let keyPathPermissions: PermissionSet
    let kanataPermissions: PermissionSet
    let timestamp: Date

    /// Whether the entire system has all required permissions.
    var isSystemReady: Bool {
        keyPathPermissions.hasAllGranted && kanataPermissions.hasAllGranted
    }

    /// The first blocking permission issue found, if any.
    var blockingIssue: String? {
        // Check KeyPath first (needed for UI)
        if let accessibility = keyPathPermissions.status(for: .accessibility),
           accessibility.isBlocking
        {
            return "KeyPath needs Accessibility permission - enable in System Settings > \(SystemPermissionType.accessibility.systemSettingsPath)"
        }

        if let inputMonitoring = keyPathPermissions.status(for: .inputMonitoring),
           inputMonitoring.isBlocking
        {
            return "KeyPath needs Input Monitoring permission - enable in System Settings > \(SystemPermissionType.inputMonitoring.systemSettingsPath)"
        }

        // Check Kanata
        if kanataPermissions.hasBlockingIssues {
            return "Kanata needs permissions - use the Installation Wizard to grant required access"
        }

        return nil
    }

    /// Diagnostic information for troubleshooting.
    var diagnosticSummary: String {
        let age = String(format: "%.3f", Date().timeIntervalSince(timestamp))
        return """
        Permission System Snapshot (\(age)s ago)

        KeyPath [\(keyPathPermissions.source), \(keyPathPermissions.confidence.description)]:
        \(formatPermissions(keyPathPermissions))

        Kanata [\(kanataPermissions.source), \(kanataPermissions.confidence.description)]:
        \(formatPermissions(kanataPermissions))

        System Ready: \(isSystemReady)
        """
    }

    private func formatPermissions(_ set: PermissionSet) -> String {
        set.permissions.map { type, status in
            "  • \(type.displayName): \(status.description)"
        }.joined(separator: "\n")
    }
}

/// Errors related to permission checking operations.
enum PermissionError: Error, LocalizedError {
    case checkFailed(String)
    case unsupportedPermissionType(SystemPermissionType)
    case invalidSubject(PermissionSubject)
    case systemError(String)

    var errorDescription: String? {
        switch self {
        case let .checkFailed(reason):
            "Permission check failed: \(reason)"
        case let .unsupportedPermissionType(type):
            "Unsupported permission type: \(type.displayName)"
        case let .invalidSubject(subject):
            "Invalid permission subject: \(subject.displayName)"
        case let .systemError(message):
            "System permission error: \(message)"
        }
    }
}
