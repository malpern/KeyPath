import Foundation
import SwiftUI

// MARK: - Permission Service DI

/// Typed error cases for permission-related operations (reserved for future throwing APIs)
enum PermissionServiceError: LocalizedError {
    case notAuthorized
    case tccAccessDenied
    case invalidBinaryPath
    case logReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Operation requires authorization"
        case .tccAccessDenied:
            "Access denied by TCC (Transparency, Consent, and Control)"
        case .invalidBinaryPath:
            "Invalid binary path for permission check"
        case let .logReadFailed(reason):
            "Failed to read system or application logs: \(reason)"
        }
    }
}

/// Protocol abstraction for the PermissionService to enable dependency injection
protocol PermissionServicing: AnyObject {
    func hasInputMonitoringPermission() -> Bool
    func hasAccessibilityPermission() -> Bool
    func checkSystemPermissions(kanataBinaryPath: String) -> PermissionService.SystemPermissionStatus
    func clearCache()
}

/// Adopt the protocol for the existing concrete service
extension PermissionService: PermissionServicing {}

/// EnvironmentKey for PermissionService (DI)
private struct PermissionServiceKey: EnvironmentKey {
    static var defaultValue: PermissionServicing = PermissionService.shared
}

extension EnvironmentValues {
    var permissionService: PermissionServicing {
        get { self[PermissionServiceKey.self] }
        set { self[PermissionServiceKey.self] = newValue }
    }
}

// MARK: - Preferences Service DI

/// EnvironmentKey for PreferencesService (DI)
private struct PreferencesServiceKey: EnvironmentKey {
    static var defaultValue: PreferencesService = .shared
}

extension EnvironmentValues {
    var preferencesService: PreferencesService {
        get { self[PreferencesServiceKey.self] }
        set { self[PreferencesServiceKey.self] = newValue }
    }
}
