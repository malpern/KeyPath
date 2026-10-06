import Foundation
import KeyPathCore
import KeyPathPermissions

enum PGPermissionType: Hashable {
    case inputMonitoring
    case accessibility
}

enum PermissionGatedFeature {
    case keyboardRemapping
    case emergencyStop
    case keyCapture
    case configurationReload

    /// KeyPath's own grant is distinct from the remapping engine's capability.
    /// Reloading a config uses TCP and does not capture or post keyboard events.
    var requiredKeyPathPermissions: Set<PGPermissionType> {
        switch self {
        case .keyboardRemapping, .emergencyStop, .keyCapture:
            [.accessibility]
        case .configurationReload:
            []
        }
    }

    var requiredKanataPermissions: Set<PGPermissionType> {
        switch self {
        case .keyboardRemapping:
            [.accessibility, .inputMonitoring]
        case .emergencyStop, .keyCapture, .configurationReload:
            []
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
            "KeyPath sends configuration changes to the running remapping engine."
        }
    }
}

@MainActor
final class PermissionGate {
    static let shared = PermissionGate()
    private init() {}

    private let permissionService = PermissionRequestService.shared

    struct Evaluation: Equatable {
        let missingKeyPath: Set<PGPermissionType>
        let kanataBlocking: Set<PGPermissionType>
        let kanataNotVerified: Set<PGPermissionType>

        var canProceed: Bool {
            missingKeyPath.isEmpty && kanataBlocking.isEmpty && kanataNotVerified.isEmpty
        }
    }

    /// Pure evaluator so unit tests can cover semantics:
    /// - Kanata `.unknown` is "not verified" (often no FDA) and should not be treated as "required/denied".
    static func evaluate(_ snapshot: PermissionOracle.Snapshot, for feature: PermissionGatedFeature)
        -> Evaluation
    {
        var missingKeyPath: Set<PGPermissionType> = []
        var kanataBlocking: Set<PGPermissionType> = []
        var kanataNotVerified: Set<PGPermissionType> = []

        for perm in feature.requiredKeyPathPermissions {
            let status = perm == .accessibility
                ? snapshot.keyPath.accessibility : snapshot.keyPath.inputMonitoring
            if !status.isReady { missingKeyPath.insert(perm) }
        }
        for perm in feature.requiredKanataPermissions {
            let status = perm == .accessibility
                ? snapshot.kanata.accessibility : snapshot.kanata.inputMonitoring
            switch status {
            case .unknown:
                kanataNotVerified.insert(perm)
            case .denied, .error:
                kanataBlocking.insert(perm)
            case .granted:
                break
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
        // TCP-only operations need no TCC inspection or keyboard consent.
        if feature.requiredKeyPathPermissions.isEmpty, feature.requiredKanataPermissions.isEmpty {
            await onGranted()
            return
        }
        let snapshot = await SystemStateProvider.shared.currentPermissionSnapshot()
        let eval = Self.evaluate(snapshot, for: feature)

        // If Kanata permissions are not verifiable (unknown), do NOT label them "required".
        // Surface this as "not verified" and send the user to the setup verification flow.
        if eval.missingKeyPath.isEmpty, !eval.kanataBlocking.isEmpty {
            let perms = Array(eval.kanataBlocking).map { $0 == .inputMonitoring ? "Input Monitoring" : "Accessibility" }
                .joined(separator: ", ")
            let approved = await PermissionRequestDialog.show(
                title: "Kanata Permission Required",
                explanation:
                "Kanata is missing required permissions (\(perms)). Open the Installation Wizard to grant permissions.",
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
                snapshot.backend == .session
                    ? "The independently launched KeyPath keyboard runtime has not reported its access yet. Retry setup to check its current permissions."
                    :
                    "KeyPath has not verified the keyboard runtime’s permissions (\(perms)). Open the Installation Wizard to check current access.",
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
        permissionService.enterWizardContext()
        defer { permissionService.leaveWizardContext() }
        for perm in eval.missingKeyPath {
            switch perm {
            case .inputMonitoring:
                _ = await permissionService.requestInputMonitoringPermission()
            case .accessibility:
                _ = await permissionService.requestAccessibilityPermission()
            }
            try? await Task.sleep(for: .milliseconds(400))
        }

        // Poll until granted or timeout
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .seconds(1))
            let snap = await SystemStateProvider.shared.currentPermissionSnapshot()
            let refreshed = Self.evaluate(snap, for: feature)
            if refreshed.missingKeyPath.isEmpty {
                // An app grant must not bypass a missing/unverified engine grant.
                if refreshed.canProceed {
                    await onGranted()
                } else {
                    NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
                    onDenied()
                }
                return
            }
        }
        onDenied()
    }
}
