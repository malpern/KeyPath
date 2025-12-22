import Foundation
import KeyPathWizardCore
import SwiftUI

struct SettingsSystemStatusRowModel: Identifiable {
    let id: String
    let title: String
    let icon: String
    let status: InstallationStatus
    let targetPage: WizardPage?
    let message: String?
}

enum SettingsSystemStatusRowsBuilder {
    static func rows(
        wizardSystemState: WizardSystemState,
        wizardIssues: [WizardIssue],
        systemContext: SystemContext?,
        tcpConfigured: Bool?,
        hasFullDiskAccess: Bool
    ) -> [SettingsSystemStatusRowModel] {
        // Mirror wizard summary ordering and semantics.
        var rows: [SettingsSystemStatusRowModel] = []

        // 1) Helper
        let helperIssues = wizardIssues.filter { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelper || req == .privilegedHelperUnhealthy
            }
            return false
        }
        let helperStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : issueStatus(for: helperIssues)
        let helperMessage: String? = helperStatus != .completed ? helperIssues.first?.title : nil
        rows.append(
            SettingsSystemStatusRowModel(
                id: "privileged-helper",
                title: "Privileged Helper",
                icon: "shield.checkered",
                status: helperStatus,
                targetPage: .helper,
                message: helperMessage
            )
        )

        // 2) Full Disk Access (optional)
        let fdaStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : (hasFullDiskAccess ? .completed : .notStarted)
        let fdaMessage: String? = fdaStatus != .completed ? "Full Disk Access not granted" : nil
        rows.append(
            SettingsSystemStatusRowModel(
                id: "full-disk-access",
                title: "Full Disk Access (Optional)",
                icon: "folder",
                status: fdaStatus,
                targetPage: .fullDiskAccess,
                message: fdaMessage
            )
        )

        // 3) Conflicts
        let conflictIssues = wizardIssues.filter { $0.category == .conflicts }
        let conflictStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : issueStatus(for: conflictIssues)
        let conflictMessage: String? = conflictStatus != .completed ? conflictIssues.first?.title : nil
        rows.append(
            SettingsSystemStatusRowModel(
                id: "conflicts",
                title: "System Conflicts",
                icon: "exclamationmark.triangle",
                status: conflictStatus,
                targetPage: .conflicts,
                message: conflictMessage
            )
        )

        // 4) Karabiner Driver (permissions are shown in dedicated section above)
        let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: wizardSystemState,
            issues: wizardIssues
        )
        let karabinerIssues = wizardIssues.filter { issue in
            (issue.category == .installation && issue.identifier.isVHIDRelated)
                || issue.category == .backgroundServices
                || (issue.category == .daemon && issue.identifier == .component(.karabinerDaemon))
        }
        let karabinerMessage: String? = karabinerStatus != .completed ? karabinerIssues.first?.title : nil
        rows.append(
            SettingsSystemStatusRowModel(
                id: "karabiner-components",
                title: "Karabiner Driver",
                icon: "keyboard.macwindow",
                status: karabinerStatus,
                targetPage: .karabinerComponents,
                message: karabinerMessage
            )
        )

        // 5) Kanata Service
        let daemonIssues = wizardIssues.filter(\.identifier.isDaemon)
        let blockingPermissionIssue = ServiceStatusEvaluator.blockingIssueMessage(from: wizardIssues)
        let serviceStatus: InstallationStatus = {
            if wizardSystemState == .initializing { return .inProgress }
            if !daemonIssues.isEmpty {
                return issueStatus(for: daemonIssues)
            }
            if blockingPermissionIssue != nil {
                return .failed
            }
            if systemContext?.services.kanataRunning == true {
                return .completed
            }
            return .notStarted
        }()
        let serviceMessage: String? = {
            if serviceStatus != .completed {
                return blockingPermissionIssue ?? daemonIssues.first?.title
            }
            return nil
        }()
        rows.append(
            SettingsSystemStatusRowModel(
                id: "kanata-service",
                title: "Kanata Service",
                icon: "app.badge.checkmark",
                status: serviceStatus,
                targetPage: .service,
                message: serviceMessage
            )
        )

        // 6) Kanata Engine Setup (only once driver is healthy, mirrors wizard)
        if karabinerStatus == .completed {
            let kanataIssues = wizardIssues.filter { issue in
                if issue.category == .installation {
                    switch issue.identifier {
                    case .component(.kanataBinaryMissing),
                         .component(.kanataService),
                         .component(.orphanedKanataProcess):
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            let kanataStatus = issueStatus(for: kanataIssues)
            let kanataMessage: String? = kanataStatus != .completed ? kanataIssues.first?.title : nil
            rows.append(
                SettingsSystemStatusRowModel(
                    id: "kanata-components",
                    title: "Kanata Engine Setup",
                    icon: "cpu.fill",
                    status: kanataStatus,
                    targetPage: .kanataComponents,
                    message: kanataMessage
                )
            )
        }

        // 7) TCP Communication
        let commStatus: InstallationStatus = {
            if wizardSystemState == .initializing { return .notStarted }
            guard systemContext?.services.kanataRunning == true else { return .notStarted }
            guard let tcpConfigured else { return .inProgress }
            return tcpConfigured ? .completed : .failed
        }()
        let commMessage: String? = {
            if commStatus == .failed {
                return "TCP port configuration missing"
            } else if commStatus == .inProgress {
                return "Checking TCP configuration…"
            }
            return nil
        }()
        rows.append(
            SettingsSystemStatusRowModel(
                id: "tcp-communication",
                title: "TCP Communication",
                icon: "network",
                status: commStatus,
                targetPage: .communication,
                message: commMessage
            )
        )

        return rows
    }
}

private extension SettingsSystemStatusRowsBuilder {
    static func issueStatus(for issues: [WizardIssue]) -> InstallationStatus {
        IssueSeverityInstallationStatusMapper.installationStatus(for: issues)
    }
}

struct SettingsSystemStatusRow: View {
    let title: String
    let icon: String
    let status: InstallationStatus
    let message: String?
    let onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { onTap?() }) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundColor(statusColor)
                        .frame(width: 20)

                    Text(title)
                        .font(.body)

                    Spacer()

                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.body)
                }
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            if let message, status != .completed {
                Text(message)
                    .font(.caption)
                    .foregroundColor(statusColor)
                    .padding(.leading, 30)
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed:
            .green
        case .warning:
            .orange
        case .failed:
            .red
        case .inProgress, .notStarted:
            .secondary
        }
    }

    private var statusIcon: String {
        switch status {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .inProgress:
            "clock"
        case .notStarted:
            "circle"
        }
    }
}
