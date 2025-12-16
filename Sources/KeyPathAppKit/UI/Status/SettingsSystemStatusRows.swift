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
            : (helperIssues.isEmpty ? .completed : .failed)
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
            : (conflictIssues.isEmpty ? .completed : .failed)
        rows.append(
            SettingsSystemStatusRowModel(
                id: "conflicts",
                title: "Resolve System Conflicts",
                icon: "exclamationmark.triangle",
                status: conflictStatus,
                targetPage: .conflicts
            )
        )

        // 4) Input Monitoring
        let inputIssues = wizardIssues.filter { issue in
            if case let .permission(req) = issue.identifier {
                return req == .keyPathInputMonitoring || req == .kanataInputMonitoring
            }
            return false
        }
        let inputStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : (inputIssues.isEmpty ? .completed : .failed)
        rows.append(
            SettingsSystemStatusRowModel(
                id: "input-monitoring",
                title: "Input Monitoring Permission",
                icon: "eye",
                status: inputStatus,
                targetPage: .inputMonitoring
            )
        )

        // 5) Accessibility
        let accessibilityIssues = wizardIssues.filter { issue in
            if case let .permission(req) = issue.identifier {
                return req == .keyPathAccessibility || req == .kanataAccessibility
            }
            return false
        }
        let accessibilityStatus: InstallationStatus = wizardSystemState == .initializing
            ? .notStarted
            : (accessibilityIssues.isEmpty ? .completed : .failed)
        rows.append(
            SettingsSystemStatusRowModel(
                id: "accessibility",
                title: "Accessibility",
                icon: "accessibility",
                status: accessibilityStatus,
                targetPage: .accessibility
            )
        )

        // 6) Karabiner Driver
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

        // 7) Kanata Service
        let serviceStatus: InstallationStatus = {
            if wizardSystemState == .initializing { return .inProgress }
            if systemContext?.services.kanataRunning == true { return .completed }
            let hasServiceIssues = wizardIssues.contains { $0.category == .daemon }
            return hasServiceIssues ? .failed : .notStarted
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

        // 8) Kanata Engine Setup (only once driver is healthy, mirrors wizard)
        if karabinerStatus == .completed {
            let hasKanataIssues = wizardIssues.contains { issue in
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
            rows.append(
                SettingsSystemStatusRowModel(
                    id: "kanata-components",
                    title: "Kanata Engine Setup",
                    icon: "cpu.fill",
                    status: hasKanataIssues ? .failed : .completed,
                    targetPage: .kanataComponents
                )
            )
        }

        // 9) TCP Communication
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
