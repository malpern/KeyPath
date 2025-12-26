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

    struct Evaluation: Equatable {
        let missingKeyPath: Set<PGPermissionType>
        let kanataBlocking: Set<PGPermissionType>
        let kanataNotVerified: Set<PGPermissionType>
    }

    /// Pure evaluator so unit tests can cover semantics:
    /// - Kanata `.unknown` is "not verified" (often no FDA) and should not be treated as "required/denied".
    static func evaluate(_ snapshot: PermissionOracle.Snapshot, for feature: PermissionGatedFeature)
        -> Evaluation {
        var missingKeyPath: Set<PGPermissionType> = []
        var kanataBlocking: Set<PGPermissionType> = []
        var kanataNotVerified: Set<PGPermissionType> = []

        for perm in feature.requiredPermissions {
            switch perm {
            case .inputMonitoring:
                if snapshot.keyPath.inputMonitoring.isBlocking { missingKeyPath.insert(.inputMonitoring) }
                switch snapshot.kanata.inputMonitoring {
                case .unknown:
                    kanataNotVerified.insert(.inputMonitoring)
                case .denied, .error:
                    kanataBlocking.insert(.inputMonitoring)
                case .granted:
                    break
                }

            case .accessibility:
                if snapshot.keyPath.accessibility.isBlocking { missingKeyPath.insert(.accessibility) }
                switch snapshot.kanata.accessibility {
                case .unknown:
                    kanataNotVerified.insert(.accessibility)
                case .denied, .error:
                    kanataBlocking.insert(.accessibility)
                case .granted:
                    break
                }
            }
        }

        return Evaluation(
            missingKeyPath: missingKeyPath,
            kanataBlocking: kanataBlocking,
            kanataNotVerified: kanataNotVerified
        )
    }

    func checkAndRequestPermissions(
        for feature: PermissionGatedFeature,
        onGranted: @escaping () async -> Void,
        onDenied: @escaping () -> Void
    ) async {
        let snapshot = await oracle.currentSnapshot()
        let eval = Self.evaluate(snapshot, for: feature)

        // If Kanata permissions are not verifiable (unknown), do NOT label them "required".
        // Surface this as "not verified" and send the user to the wizard/FDA flow.
        if eval.missingKeyPath.isEmpty, !eval.kanataBlocking.isEmpty {
            let perms = Array(eval.kanataBlocking).map { $0 == .inputMonitoring ? "Input Monitoring" : "Accessibility" }
                .joined(separator: ", ")
            let approved = await PermissionRequestDialog.show(
                title: "Kanata Permission Required",
                explanation:
                    "Kanata is missing required permissions (\(perms)). Open the Installation Wizard to grant permission to /Library/KeyPath/bin/kanata.",
                permissions: [],
                approveButtonTitle: "Open Wizard",
                cancelButtonTitle: "Not Now"
            )
            if approved {
                NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
            }
            onDenied()
            return
        }

        if eval.missingKeyPath.isEmpty, !eval.kanataNotVerified.isEmpty {
            let perms = Array(eval.kanataNotVerified).map { $0 == .inputMonitoring ? "Input Monitoring" : "Accessibility" }
                .joined(separator: ", ")
            let approved = await PermissionRequestDialog.show(
                title: "Kanata Permission Not Verified",
                explanation:
                    "KeyPath can’t verify Kanata’s permissions (\(perms)) without Full Disk Access. If remapping doesn’t work, grant Full Disk Access to KeyPath to verify, then use the wizard to add /Library/KeyPath/bin/kanata in System Settings.",
                permissions: [],
                approveButtonTitle: "Open Wizard",
                cancelButtonTitle: "Not Now"
            )
            if approved {
                NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
            }
            onDenied()
            return
        }

        if eval.missingKeyPath.isEmpty {
            await onGranted()
            return
        }

        // Pre-dialog with context
        let approved = await PermissionRequestDialog.show(
            title: "Permission Required",
            explanation: feature.contextualExplanation,
            permissions: eval.missingKeyPath,
            approveButtonTitle: "Allow",
            cancelButtonTitle: "Cancel"
        )
        if !approved {
            onDenied()
            return
        }

        // Request automatically for KeyPath.app (Kanata must still be toggled by user if needed)
        for perm in eval.missingKeyPath {
            switch perm {
            case .inputMonitoring:
                _ = permissionService.requestInputMonitoringPermission()
            case .accessibility:
                _ = permissionService.requestAccessibilityPermission()
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        // Poll until granted or timeout
        for _ in 0 ..< 30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let snap = await oracle.currentSnapshot()
            // JIT gates only request KeyPath permissions automatically. Kanata is handled via wizard.
            // Therefore, we only require KeyPath permission to proceed here.
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
