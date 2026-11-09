import Foundation
import KeyPathCore
import KeyPathPermissions

enum PermissionGatedFeature {
    case keyboardRemapping
    case emergencyStop
    case keyCapture
    case configurationReload

    /// Whether the feature needs KeyPath's own Accessibility grant.
    /// Reloading a config uses TCP and does not capture or post keyboard events.
    var requiresAccessibility: Bool {
        switch self {
        case .keyboardRemapping, .emergencyStop, .keyCapture: true
        case .configurationReload: false
        }
    }

    /// Whether the feature needs the session runtime to report key access.
    var requiresRuntimeKeyAccess: Bool {
        self == .keyboardRemapping
    }

    var contextualExplanation: String {
        switch self {
        case .keyboardRemapping:
            "KeyPath needs permission to remap your keyboard keys."
        case .emergencyStop:
            "KeyPath needs \(AccessibilityPermissionPresentation.current.name) permission to detect the emergency stop and keep you safe."
        case .keyCapture:
            "KeyPath needs \(AccessibilityPermissionPresentation.current.name) permission to capture keyboard input for configuration."
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
        /// KeyPath's own Accessibility grant is missing.
        let accessibilityMissing: Bool
        /// The runtime reported it cannot read or post keys.
        let runtimeBlocked: Bool
        /// No runtime has reported key access yet.
        let runtimeNotVerified: Bool

        var canProceed: Bool {
            !accessibilityMissing && !runtimeBlocked && !runtimeNotVerified
        }
    }

    /// Pure evaluator so unit tests can cover semantics:
    /// unreported runtime key access is "not verified", never "denied".
    static func evaluate(_ snapshot: PermissionOracle.Snapshot, for feature: PermissionGatedFeature)
        -> Evaluation
    {
        let accessibilityMissing = feature.requiresAccessibility && !snapshot.accessibility.isReady
        var runtimeBlocked = false
        var runtimeNotVerified = false
        if feature.requiresRuntimeKeyAccess {
            switch snapshot.runtimeKeyAccess.status {
            case .unknown: runtimeNotVerified = true
            case .denied, .error: runtimeBlocked = true
            case .granted: break
            }
        }
        return Evaluation(
            accessibilityMissing: accessibilityMissing,
            runtimeBlocked: runtimeBlocked,
            runtimeNotVerified: runtimeNotVerified
        )
    }

    func checkAndRequestPermissions(
        for feature: PermissionGatedFeature,
        onGranted: @escaping () async -> Void,
        onDenied: @escaping () -> Void
    ) async {
        // TCP-only operations need no keyboard consent.
        if !feature.requiresAccessibility, !feature.requiresRuntimeKeyAccess {
            await onGranted()
            return
        }
        let snapshot = await SystemStateProvider.shared.currentPermissionSnapshot()
        let eval = Self.evaluate(snapshot, for: feature)

        if !eval.accessibilityMissing, eval.runtimeBlocked {
            let approved = await PermissionRequestDialog.show(
                title: "KeyPath Needs a Restart",
                explanation: PermissionOracle.Snapshot.sessionBlockingGuidance(
                    accessibilityBlocking: false, presentation: .current
                ),
                approveButtonTitle: "Open Setup",
                cancelButtonTitle: "Not Now"
            )
            if approved {
                NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
            }
            onDenied()
            return
        }

        // Unreported runtime access is not a denial; send the user to setup to check it.
        if !eval.accessibilityMissing, eval.runtimeNotVerified {
            let approved = await PermissionRequestDialog.show(
                title: "Keyboard Access Not Verified",
                explanation: "The KeyPath keyboard runtime has not reported its access yet. Open setup to check it.",
                approveButtonTitle: "Open Setup",
                cancelButtonTitle: "Not Now"
            )
            if approved {
                NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
            }
            onDenied()
            return
        }

        if !eval.accessibilityMissing {
            await onGranted()
            return
        }

        // Pre-dialog with context
        let approved = await PermissionRequestDialog.show(
            title: "Permission Required",
            explanation: feature.contextualExplanation,
            approveButtonTitle: "Allow",
            cancelButtonTitle: "Cancel"
        )
        if !approved {
            onDenied()
            return
        }

        // Ask macOS for KeyPath.app's Accessibility grant.
        permissionService.enterWizardContext()
        defer { permissionService.leaveWizardContext() }
        _ = await permissionService.requestAccessibilityPermission()

        // Poll until granted or timeout
        for _ in 0 ..< 30 {
            try? await Task.sleep(for: .seconds(1))
            let snap = await SystemStateProvider.shared.currentPermissionSnapshot()
            let refreshed = Self.evaluate(snap, for: feature)
            if !refreshed.accessibilityMissing {
                // An app grant must not bypass missing or unverified runtime key access.
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
