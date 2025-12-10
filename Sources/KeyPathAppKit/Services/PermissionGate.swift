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
            [.inputMonitoring, .accessibility]
        case .emergencyStop:
            [.accessibility]
        case .keyCapture:
            [.accessibility]
        case .configurationReload:
            [.inputMonitoring]
        }
    }

    var contextualExplanation: String {
        switch self {
        case .keyboardRemapping:
            "KeyPath needs permission to remap your keyboard keys."
        case .emergencyStop:
            "KeyPath needs Accessibility permission to detect the emergency stop and keep you safe."
        case .keyCapture:
            "KeyPath needs Accessibility permission to capture keyboard input for configuration."
        case .configurationReload:
            "KeyPath needs Input Monitoring permission to apply remapping changes."
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
        // NOTE: Only check KeyPath permissions - Kanata doesn't need TCC (uses Karabiner driver)
        let missing = feature.requiredPermissions.filter { p in
            switch p {
            case .inputMonitoring:
                !snapshot.keyPath.inputMonitoring.isReady
            case .accessibility:
                !snapshot.keyPath.accessibility.isReady
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
            try? await Task.sleep(for: .milliseconds(400))
        }

        // Poll until granted or timeout
        // NOTE: Only check KeyPath permissions - Kanata doesn't need TCC (uses Karabiner driver)
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .seconds(1))
            let snap = await oracle.currentSnapshot()
            let allGranted = feature.requiredPermissions.allSatisfy { p in
                switch p {
                case .inputMonitoring:
                    snap.keyPath.inputMonitoring.isReady
                case .accessibility:
                    snap.keyPath.accessibility.isReady
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
