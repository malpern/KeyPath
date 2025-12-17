import Foundation
import KeyPathWizardCore
import SwiftUI

struct SettingsSystemStatusRowModel: Identifiable {
    let id: String
    let title: String
    let icon: String
    let status: InstallationStatus
    let targetPage: WizardPage?
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
        rows.append(
            SettingsSystemStatusRowModel(
                id: "privileged-helper",
                title: "Privileged Helper",
                icon: "shield.checkered",
                status: helperStatus,
                targetPage: .helper
            )
        )

        // 2) Full Disk Access (optional)
        let fdaStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : (hasFullDiskAccess ? .completed : .notStarted)
        rows.append(
            SettingsSystemStatusRowModel(
                id: "full-disk-access",
                title: "Full Disk Access (Optional)",
                icon: "folder",
                status: fdaStatus,
                targetPage: .fullDiskAccess
            )
        )

        // 3) Conflicts
        let conflictIssues = wizardIssues.filter { $0.category == .conflicts }
        let conflictStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : issueStatus(for: conflictIssues)
        rows.append(
            SettingsSystemStatusRowModel(
                id: "conflicts",
                title: "System Conflicts",
                icon: "exclamationmark.triangle",
                status: conflictStatus,
                targetPage: .conflicts
            )
        )

        // 4) Karabiner Driver (permissions are shown in dedicated section above)
        let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: wizardSystemState,
            issues: wizardIssues
        )
        rows.append(
            SettingsSystemStatusRowModel(
                id: "karabiner-components",
                title: "Karabiner Driver",
                icon: "keyboard.macwindow",
                status: karabinerStatus,
                targetPage: .karabinerComponents
            )
        )

        // 5) Kanata Service
        let daemonIssues = wizardIssues.filter(\.identifier.isDaemon)
        let blockingPermissionIssue = ServiceStatusEvaluator.blockingIssueMessage(from: wizardIssues) != nil
        let serviceStatus: InstallationStatus = {
            if wizardSystemState == .initializing { return .inProgress }
            if !daemonIssues.isEmpty {
                return issueStatus(for: daemonIssues)
            }
            if blockingPermissionIssue {
                return .failed
            }
            if systemContext?.services.kanataRunning == true {
                return .completed
            }
            return .notStarted
        }()
        rows.append(
            SettingsSystemStatusRowModel(
                id: "kanata-service",
                title: "Kanata Service",
                icon: "app.badge.checkmark",
                status: serviceStatus,
                targetPage: .service
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
            rows.append(
                SettingsSystemStatusRowModel(
                    id: "kanata-components",
                    title: "Kanata Engine Setup",
                    icon: "cpu.fill",
                    status: kanataStatus,
                    targetPage: .kanataComponents
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
        rows.append(
            SettingsSystemStatusRowModel(
                id: "tcp-communication",
                title: "TCP Communication",
                icon: "network",
                status: commStatus,
                targetPage: .communication
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
    let onTap: (() -> Void)?

    var body: some View {
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
