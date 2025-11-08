import Foundation
import KeyPathPermissions
import SwiftUI

enum PGPermissionType: Hashable {
    case inputMonitoring
    case accessibility
}


enum PermissionGatedFeature {
    case keyboardRemapping
    case emergencyStop
    case keyCapture
    case configurationReload

    var requiredPermissions: Set<PGPermissionType> {
        switch self {
        case .keyboardRemapping:
            return [.inputMonitoring, .accessibility]
        case .emergencyStop:
            return [.accessibility]
        case .keyCapture:
            return [.accessibility]
        case .configurationReload:
            return [.inputMonitoring]
        }
    }

    var contextualExplanation: String {
        switch self {
        case .keyboardRemapping:
            return "KeyPath needs permission to remap your keyboard keys."
        case .emergencyStop:
            return "KeyPath needs Accessibility permission to detect the emergency stop and keep you safe."
        case .keyCapture:
            return "KeyPath needs Accessibility permission to capture keyboard input for configuration."
        case .configurationReload:
            return "KeyPath needs Input Monitoring permission to apply remapping changes."
        }
    }
}
@MainActor
final class PermissionGate {
    static let shared = PermissionGate()
    private init() {}

    private let permissionService = PermissionRequestService.shared
    private let oracle = PermissionOracle.shared

    func checkAndRequestPermissions(
        for feature: PermissionGatedFeature,
        onGranted: @escaping () async -> Void,
        onDenied: @escaping () -> Void
    ) async {
        let snapshot = await oracle.currentSnapshot()
        let missing = feature.requiredPermissions.filter { p in
            switch p {
            case .inputMonitoring:
                return !snapshot.keyPath.inputMonitoring.isReady || !snapshot.kanata.inputMonitoring.isReady
            case .accessibility:
                return !snapshot.keyPath.accessibility.isReady || !snapshot.kanata.accessibility.isReady
            }
        }

        if missing.isEmpty {
            await onGranted()
            return
        }

        // Pre-dialog with context
        let approved = await PermissionRequestDialog.show(
            explanation: feature.contextualExplanation,
            permissions: Set(missing)
        )
        if !approved {
            onDenied()
            return
        }

        // Request automatically for KeyPath.app (Kanata must still be toggled by user if needed)
        for perm in missing {
            switch perm {
            case .inputMonitoring:
                _ = permissionService.requestInputMonitoringPermission()
            case .accessibility:
                _ = permissionService.requestAccessibilityPermission()
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Poll until granted or timeout
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let snap = await oracle.currentSnapshot()
            let allGranted = feature.requiredPermissions.allSatisfy { p in
                switch p {
                case .inputMonitoring:
                    return snap.keyPath.inputMonitoring.isReady && snap.kanata.inputMonitoring.isReady
                case .accessibility:
                    return snap.keyPath.accessibility.isReady && snap.kanata.accessibility.isReady
                }
            }
            if allGranted {
                await onGranted()
                return
            }
        }
        onDenied()
    }
}