import KeyPathCore
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
    }

    var overallHealthLevel: OverallHealthLevel {
        guard let context = systemContext, permissionSnapshot != nil else { return .checking }

        let hasBlockingIssues = wizardIssues.contains { $0.severity == .critical || $0.severity == .error }
        if hasBlockingIssues {
            return .critical
        }

        if context.services.kanataRunning, tcpConfigured == false {
            return .critical
        }

        if duplicateAppCopies.count > 1 {
            return .warning
        }

        if !context.services.isHealthy || !(permissionSnapshot?.isSystemReady ?? false) {
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
        }
    }

    var systemHealthMessage: String {
        guard let context = systemContext else { return "Checking status…" }
        if !context.services.kanataRunning {
            return kanataServiceStatus
        }
        if tcpConfigured == false {
            return "TCP Communication Required"
        }
        if !(permissionSnapshot?.isSystemReady ?? false) {
            // Distinguish "not verified" (no FDA) from actual missing permissions
            if let snapshot = permissionSnapshot {
                let evaluation = permissionGaps(in: snapshot)
                if evaluation.missingOrDenied.isEmpty, !evaluation.unknown.isEmpty {
                    return "Permissions Unverified"
                }
            }
            return "Permissions Required"
        }
        return overallHealthLevel == .success ? "Everything's Working" : "Setup Needed"
    }

    var kanataServiceStatus: String {
        guard let context = systemContext else { return "Checking…" }
        if context.services.kanataRunning {
            return "Service Running"
        }
        if context.services.karabinerDaemonRunning {
            return "Service Starting"
        }
        return "Service Stopped"
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

        if let detail = tcpDetail {
            details.append(detail)
        }

        if let detail = karabinerDetail {
            details.append(detail)
        }

        if let detail = kanataLogsDetail {
            details.append(detail)
        }

        if let detail = karabinerLogsDetail {
            details.append(detail)
        }

        if let duplicateDetail = duplicateAppsDetail {
            details.append(duplicateDetail)
        }

        return details
    }

    var serviceStatusDetail: StatusDetail {
        guard let context = systemContext else {
            return StatusDetail(
                title: "KeyPath Runtime",
                message: "Checking current status…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        if context.services.kanataRunning {
            let runtimeMessage =
                if let runtimePathTitle = context.services.activeRuntimePathTitle {
                    "Running via \(runtimePathTitle.lowercased())."
                } else {
                    "Running normally."
                }
            return StatusDetail(
                title: "KeyPath Runtime",
                message: "\(runtimeMessage) Powered by Kanata.",
                icon: "bolt.fill",
                level: .success
            )
        }

        if context.services.karabinerDaemonRunning {
            return StatusDetail(
                title: "KeyPath Runtime",
                message: "Starting…",
                icon: "hourglass.circle",
                level: .info
            )
        }

        return StatusDetail(
            title: "KeyPath Runtime",
            message: "Runtime is stopped. Use the switch above to turn it on.",
            icon: "pause.circle",
            level: .warning,
            actions: [
                StatusDetailAction(title: "Open Login Items", icon: "list.bullet") {
                    SystemDiagnostics.open(.loginItems)
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .summary
                }
            ]
        )
    }

    var permissionDetail: StatusDetail? {
        guard let snapshot = permissionSnapshot else {
            return StatusDetail(
                title: "Permissions",
                message: "Checking current permissions…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        let evaluation = permissionGaps(in: snapshot)

        if evaluation.missingOrDenied.isEmpty, evaluation.unknown.isEmpty {
            return StatusDetail(
                title: "Permissions",
                message: "All required permissions are granted.",
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        var lines: [String] = []
        if let blocking = snapshot.blockingIssue {
            lines.append(blocking)
        }
        if !evaluation.missingOrDenied.isEmpty {
            lines.append("Missing: \(evaluation.missingOrDenied.joined(separator: ", "))")
        }
        if !evaluation.unknown.isEmpty {
            if hasFullDiskAccess {
                lines.append("Cannot verify: \(evaluation.unknown.joined(separator: ", "))")
            } else {
                lines.append(
                    "Cannot verify \(evaluation.unknown.joined(separator: ", ")) without Enhanced Diagnostics"
                )
            }
        }

        var actions: [StatusDetailAction] = []

        // When kanata permissions are unknown due to missing FDA, lead with the FDA action
        let hasUnverifiedKanata = !hasFullDiskAccess
            && (snapshot.kanata.accessibility == .unknown || snapshot.kanata.inputMonitoring == .unknown)
        if hasUnverifiedKanata {
            actions.append(
                StatusDetailAction(title: "Enable Enhanced Diagnostics", icon: "checkmark.shield") {
                    SystemDiagnostics.open(.fullDiskAccess)
                }
            )
        }

        if evaluation.hasErrors || !evaluation.missingOrDenied.isEmpty {
            actions.append(
                StatusDetailAction(title: "Fix", icon: "wand.and.stars") {
                    showingPermissionAlert = true
                }
            )
        }

        if !snapshot.keyPath.inputMonitoring.isReady || !snapshot.kanata.inputMonitoring.isReady {
            actions.append(
                StatusDetailAction(title: "Open Input Monitoring", icon: "lock.shield") {
                    SystemDiagnostics.open(.inputMonitoring)
                }
            )
        }

        if !snapshot.keyPath.accessibility.isReady || !snapshot.kanata.accessibility.isReady {
            actions.append(
                StatusDetailAction(title: "Open Accessibility", icon: "figure.walk") {
                    SystemDiagnostics.open(.accessibility)
                }
            )
        }

        return StatusDetail(
            title: "Permissions",
            message: lines.joined(separator: "\n"),
            icon: "exclamationmark.shield",
            level: evaluation.hasErrors ? .critical : .warning,
            actions: actions
        )
    }

    var tcpDetail: StatusDetail? {
        guard systemContext?.services.kanataRunning == true else { return nil }
        guard let tcpConfigured else {
            return StatusDetail(
                title: "TCP Communication",
                message: "Checking TCP configuration…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        if tcpConfigured {
            return StatusDetail(
                title: "TCP Communication",
                message: "Configured.",
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        return StatusDetail(
            title: "TCP Communication",
            message: "Service is missing the TCP port configuration. Open the wizard to repair communication settings.",
            icon: "exclamationmark.triangle",
            level: .critical,
            actions: [
                StatusDetailAction(title: "Open Kanata Logs", icon: "doc.text.magnifyingglass") {
                    SystemDiagnostics.openKanataLogsInEditor()
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .communication
                }
            ]
        )
    }

    var karabinerDetail: StatusDetail? {
        let status = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: wizardSystemState,
            issues: wizardIssues
        )
        guard status != .completed else { return nil }

        let level: StatusDetail.Level = wizardIssues.contains(where: { $0.severity == .critical || $0.severity == .error })
            ? .critical
            : .warning

        let message: String = {
            let relevant = wizardIssues.filter { issue in
                (issue.category == .installation && issue.identifier.isVHIDRelated)
                    || issue.category == .backgroundServices
                    || (issue.category == .daemon && issue.identifier == .component(.karabinerDaemon))
            }
            if let first = relevant.first {
                return first.title
            }
            return "Karabiner driver or related services are not healthy."
        }()

        return StatusDetail(
            title: "Karabiner Driver",
            message: message,
            icon: "keyboard.macwindow",
            level: level,
            actions: [
                StatusDetailAction(title: "Open Karabiner Logs", icon: "doc.on.doc") {
                    SystemDiagnostics.openKarabinerLogsDirectory()
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .karabinerComponents
                }
            ]
        )
    }

    var kanataLogsDetail: StatusDetail? {
        // Show logs affordance when service isn't healthy or has daemon issues.
        guard serviceStatusDetail.level != .success else { return nil }
        return StatusDetail(
            title: "Kanata Logs",
            message: "Open the daemon stderr log for startup errors and permission failures.",
            icon: "doc.text.magnifyingglass",
            level: .info,
            actions: [
                StatusDetailAction(title: "Open", icon: "doc.text") {
                    SystemDiagnostics.openKanataLogsInEditor()
                }
            ]
        )
    }

    var karabinerLogsDetail: StatusDetail? {
        guard karabinerDetail != nil else { return nil }
        return StatusDetail(
            title: "Karabiner Logs",
            message: "Open the Karabiner log directory for VirtualHID daemon/manager logs.",
            icon: "doc.on.doc",
            level: .info,
            actions: [
                StatusDetailAction(title: "Open", icon: "folder") {
                    SystemDiagnostics.openKarabinerLogsDirectory()
                }
            ]
        )
    }

    var duplicateAppsDetail: StatusDetail? {
        guard duplicateAppCopies.count > 1 else { return nil }
        let count = duplicateAppCopies.count
        return StatusDetail(
            title: "Duplicate Installations",
            message: "Found \(count) copies of KeyPath. Extra copies can confuse macOS permissions.",
            icon: "exclamationmark.triangle",
            level: .warning,
            actions: [
                StatusDetailAction(title: "Review", icon: "arrow.right") {
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

        append(status: snapshot.keyPath.accessibility, label: "KeyPath Accessibility")
        append(status: snapshot.keyPath.inputMonitoring, label: "KeyPath Input Monitoring")
        append(status: snapshot.kanata.accessibility, label: "Kanata Accessibility")
        append(status: snapshot.kanata.inputMonitoring, label: "Kanata Input Monitoring")

        return (missingOrDenied, unknown, hasErrors)
    }
}
