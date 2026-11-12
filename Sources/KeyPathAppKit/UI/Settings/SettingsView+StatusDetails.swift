import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - Status Detail Evaluation

extension StatusSettingsTabView {
    enum OverallHealthLevel: Int {
        case success = 0
        case warning = 1
        case critical = 2
        case checking = 3
        case disabled = 4

        var accessibilityValue: String {
            switch self {
            case .success: String(localized: "success", comment: "VoiceOver status value")
            case .warning: String(localized: "warning", comment: "VoiceOver status value")
            case .critical: String(localized: "critical", comment: "VoiceOver status value")
            case .checking: String(localized: "checking", comment: "VoiceOver status value")
            case .disabled: String(localized: "disabled", comment: "VoiceOver status value")
            }
        }
    }

    /// Everything else is healthy and only Caps Lock rules are paused. The
    /// setup wizard knows nothing about Caps Lock, so "Fix it" must open
    /// Settings > General, where the Caps Lock controls live.
    var capsPausedIsOnlyIssue: Bool {
        Self.capsPausedIsOnlyIssue(
            capsPaused: kanataManager.capsPausedMessage != nil,
            runtimeHealthy: systemContext.map { $0.services.kanataRunning && $0.services.isHealthy } ?? false,
            permissionsReady: permissionSnapshot?.isSystemReady ?? false,
            wizardSeverities: wizardIssues.map(\.severity)
        )
    }

    /// Any wizard issue above `info` sends Fix it to the wizard instead.
    static func capsPausedIsOnlyIssue(
        capsPaused: Bool, runtimeHealthy: Bool,
        permissionsReady: Bool, wizardSeverities: [WizardIssue.IssueSeverity]
    ) -> Bool {
        capsPaused && runtimeHealthy && permissionsReady
            && !wizardSeverities.contains { $0 != .info }
    }

    var overallHealthLevel: OverallHealthLevel {
        // The user deliberately switched the service off. This is a calm,
        // intentional state — not a fault — so it takes precedence over both the
        // loading guard and the health checks below (which all assume the
        // service should be running). Checked before the guard so the icon/tint
        // stay in sync with systemHealthMessage's "KeyPath is Off".
        if isIntentionallyDisabled {
            return .disabled
        }

        guard let context = systemContext, permissionSnapshot != nil else { return .checking }

        let hasBlockingIssues = wizardIssues.contains { $0.severity == .critical || $0.severity == .error }
        if hasBlockingIssues {
            return .critical
        }

        // Extra app copies are housekeeping advice, not runtime health evidence.

        if !context.services.isHealthy || !(permissionSnapshot?.isSystemReady ?? false) {
            return .warning
        }

        if kanataManager.capsPausedMessage != nil {
            return .warning
        }

        return .success
    }

    var systemHealthIcon: String {
        switch overallHealthLevel {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .critical:
            "xmark.circle.fill"
        case .checking:
            "gear"
        case .disabled:
            "power.circle.fill"
        }
    }

    var systemHealthTint: Color {
        switch overallHealthLevel {
        case .success:
            .green
        case .warning:
            .orange
        case .critical:
            .red
        case .checking:
            .secondary
        case .disabled:
            .secondary
        }
    }

    var systemHealthMessage: String {
        if isIntentionallyDisabled {
            return String(localized: "KeyPath is Off")
        }
        guard let context = systemContext else { return String(localized: "Checking status…") }
        if !context.services.kanataRunning {
            return kanataServiceStatus
        }
        if !(permissionSnapshot?.isSystemReady ?? false) {
            // Distinguish "not verified" (no FDA) from actual missing permissions
            if let snapshot = permissionSnapshot {
                let evaluation = permissionGaps(in: snapshot)
                if evaluation.missingOrDenied.isEmpty, !evaluation.unknown.isEmpty {
                    return String(localized: "Permissions Unverified")
                }
            }
            return String(localized: "Permissions Required")
        }
        if kanataManager.capsPausedMessage != nil {
            return String(localized: "Caps Lock Needs Attention")
        }
        return overallHealthLevel == .success ? String(localized: "Everything's Working") : String(localized: "Setup Needed")
    }

    var kanataServiceStatus: String {
        guard let context = systemContext else { return String(localized: "Checking…") }
        return context.services.kanataRunning ? String(localized: "Service Running") : String(localized: "Service Stopped")
    }

    var primaryIssueDetail: StatusDetail? {
        statusDetails
            .sorted { $0.level.rawValue > $1.level.rawValue }
            .first(where: { $0.level.isIssue })
    }

    var statusDetails: [StatusDetail] {
        var details: [StatusDetail] = [serviceStatusDetail]

        if let detail = permissionDetail {
            details.append(detail)
        }

        if let detail = kanataLogsDetail {
            details.append(detail)
        }

        if let duplicateDetail = duplicateAppsDetail {
            details.append(duplicateDetail)
        }

        return details
    }

    /// A stopped runtime says why when it knows, instead of only how to start it.
    static func stoppedMessage(lastError: String?) -> String {
        guard let lastError, !lastError.isEmpty else { return String(localized: "Runtime is stopped. Use the switch above to turn it on.") }
        return String(localized: "Runtime is stopped. \(lastError)")
    }

    var serviceStatusDetail: StatusDetail {
        guard let context = systemContext else {
            return StatusDetail(
                title: String(localized: "Keyboard remapping"),
                message: String(localized: "Checking current status…"),
                icon: "ellipsis.circle",
                level: .info
            )
        }

        if isIntentionallyDisabled {
            return StatusDetail(
                title: String(localized: "Keyboard remapping"),
                message: String(localized: "Turned off. Flip the switch above to resume remapping."),
                icon: "power",
                level: .info
            )
        }

        if context.services.kanataRunning {
            let runtimeMessage =
                if let runtimePathTitle = context.services.activeRuntimePathTitle {
                    String(localized: "Running via \(runtimePathTitle.lowercased()).")
                } else {
                    String(localized: "Running normally.")
                }
            if let paused = kanataManager.capsPausedMessage {
                return StatusDetail(
                    title: String(localized: "Keyboard remapping"),
                    message: "\(runtimeMessage) \(paused)",
                    icon: "capslock",
                    level: .warning
                )
            }
            return StatusDetail(
                title: String(localized: "Keyboard remapping"),
                message: String(localized: "\(runtimeMessage) Powered by Kanata."),
                icon: "bolt.fill",
                level: .success
            )
        }

        return StatusDetail(
            title: String(localized: "Keyboard remapping"),
            message: Self.stoppedMessage(lastError: kanataManager.lastError),
            icon: "pause.circle",
            level: .warning,
            actions: [
                StatusDetailAction(title: String(localized: "Open System Settings"), icon: "list.bullet") {
                    SystemDiagnostics.open(.systemSettings)
                },
                StatusDetailAction(title: String(localized: "Open Wizard"), icon: "wand.and.stars") {
                    wizardInitialPage = .summary
                }
            ]
        )
    }

    var permissionDetail: StatusDetail? {
        guard let snapshot = permissionSnapshot else {
            return StatusDetail(
                title: String(localized: "Permissions"),
                message: String(localized: "Checking current permissions…"),
                icon: "ellipsis.circle",
                level: .info
            )
        }

        let evaluation = permissionGaps(in: snapshot)

        if evaluation.missingOrDenied.isEmpty, evaluation.unknown.isEmpty {
            return StatusDetail(
                title: String(localized: "Permissions"),
                message: String(localized: "All required permissions are granted."),
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        var lines: [String] = []
        if let blocking = snapshot.blockingIssue {
            lines.append(blocking)
        }
        if !evaluation.missingOrDenied.isEmpty {
            lines.append(String(localized: "Missing: \(evaluation.missingOrDenied.joined(separator: ", "))"))
        }
        if !evaluation.unknown.isEmpty {
            lines.append(String(localized: "Not yet verified: \(evaluation.unknown.joined(separator: ", ")). Retry setup to check current access."))
        }

        var actions: [StatusDetailAction] = []

        if !evaluation.unknown.isEmpty {
            actions.append(
                StatusDetailAction(title: String(localized: "Retry Setup"), icon: "wand.and.stars") {
                    wizardInitialPage = .summary
                }
            )
        }

        if evaluation.hasErrors || !evaluation.missingOrDenied.isEmpty {
            actions.append(
                StatusDetailAction(title: String(localized: "Fix", comment: "Status action button: fix missing permissions"), icon: "wand.and.stars") {
                    showingPermissionAlert = true
                }
            )
        }

        if !snapshot.accessibility.isReady {
            actions.append(
                StatusDetailAction(
                    title: AccessibilityPermissionPresentation.current.openButtonTitle,
                    icon: "figure.walk",
                    handler: { SystemDiagnostics.open(.accessibility) },
                    identifier: "status-action-open-accessibility",
                    accessibilityTitle: AccessibilityPermissionPresentation.current.openTitle
                )
            )
        }

        return StatusDetail(
            title: String(localized: "Permissions"),
            message: lines.joined(separator: "\n"),
            icon: "exclamationmark.shield",
            level: evaluation.hasErrors ? .critical : .warning,
            actions: actions
        )
    }

    var kanataLogsDetail: StatusDetail? {
        // Show logs affordance when service isn't healthy or has daemon issues.
        // Not when the user simply turned the service off — there's nothing to
        // troubleshoot.
        guard !isIntentionallyDisabled else { return nil }
        guard serviceStatusDetail.level != .success else { return nil }
        return StatusDetail(
            title: String(localized: "KeyPath Logs"),
            message: String(localized: "Open KeyPath’s log for remapping startup errors and permission failures."),
            icon: "doc.text.magnifyingglass",
            level: .info,
            actions: [
                StatusDetailAction(title: String(localized: "Open", comment: "Status action button: open the log file"), icon: "doc.text") {
                    openFileInPreferredEditor(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/KeyPath/keypath-debug.log"))
                }
            ]
        )
    }

    var duplicateAppsDetail: StatusDetail? {
        guard duplicateAppCopies.count > 1 else { return nil }
        let count = duplicateAppCopies.count
        return StatusDetail(
            title: String(localized: "Other App Copies"),
            message: String(localized: "Found \(count) copies of KeyPath. If permissions stop working, review the extra copies in Repair/Remove."),
            icon: "info.circle",
            level: .info,
            actions: [
                StatusDetailAction(title: String(localized: "Review", comment: "Status action button: review extra app copies"), icon: "arrow.right") {
                    NotificationCenter.default.post(name: .openSettingsAdvanced, object: nil)
                }
            ]
        )
    }

    func permissionGaps(in snapshot: PermissionOracle.Snapshot) -> (
        missingOrDenied: [String],
        unknown: [String],
        hasErrors: Bool
    ) {
        var missingOrDenied: [String] = []
        var unknown: [String] = []
        var hasErrors = false

        func append(status: PermissionOracle.Status, label: String) {
            guard !status.isReady else { return }
            switch status {
            case .unknown:
                unknown.append(label)
            case .denied:
                missingOrDenied.append(label)
            case .error:
                missingOrDenied.append(label)
                hasErrors = true
            case .granted:
                break
            }
        }

        append(status: snapshot.accessibility, label: String(localized: "KeyPath \(AccessibilityPermissionPresentation.current.name)"))
        // The runtime's own report: it uses KeyPath's grant, so a gap here means it needs relaunching.
        append(status: snapshot.runtimeKeyAccess.status, label: String(localized: "Runtime key access"))

        return (missingOrDenied, unknown, hasErrors)
    }
}
