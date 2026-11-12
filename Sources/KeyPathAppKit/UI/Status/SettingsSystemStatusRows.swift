import Foundation
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import ServiceManagement
import SwiftUI

struct SettingsSystemStatusRowModel: Identifiable {
    let id: String
    let title: String
    let icon: String
    let status: InstallationStatus
    let targetPage: WizardPage?
    let message: String?
    /// Settings tab to open when the row is not a setup-wizard step.
    var settingsDestination: Notification.Name?
}

/// Everyday state that otherwise lives on other Settings tabs. Rows report and
/// link; the controls stay where they are.
enum SettingsStatusSummaryRows {
    static func rows(
        runtimeRunning: Bool,
        capsManaged: Bool,
        launchAtLogin: SMAppService.Status?,
        appCopies: Int
    ) -> [SettingsSystemStatusRowModel] {
        // While the runtime is healthy, the reload coordinator keeps the worker's
        // managed Caps Lock in step with the rules, so the worker is the truth.
        var rows = [
            SettingsSystemStatusRowModel(
                id: "caps-lock", title: String(localized: "Caps Lock remapping"), icon: "capslock",
                status: runtimeRunning && capsManaged ? .completed : .notStarted,
                targetPage: nil, message: nil, settingsDestination: .openSettingsGeneral
            ),
            SettingsSystemStatusRowModel(
                id: "launch-at-login", title: String(localized: "Launch at login"), icon: "power",
                status: launchAtLoginStatus(launchAtLogin),
                targetPage: nil,
                message: launchAtLogin == .requiresApproval ? String(localized: "Allow KeyPath in Login Items") : nil,
                settingsDestination: .openSettingsGeneral
            )
        ]
        if appCopies > 1 {
            rows.append(SettingsSystemStatusRowModel(
                id: "app-copies", title: String(localized: "Multiple KeyPath copies"), icon: "square.on.square",
                status: .warning, targetPage: nil,
                message: String(localized: "\(appCopies) copies found. Review them in Repair/Remove."),
                settingsDestination: .openSettingsAdvanced
            ))
        }
        return rows
    }

    private static func launchAtLoginStatus(_ status: SMAppService.Status?) -> InstallationStatus {
        switch status {
        case .enabled: .completed
        case .requiresApproval: .warning
        default: .notStarted
        }
    }
}

enum SettingsSystemStatusRowsBuilder {
    static func rows(
        wizardSystemState: WizardSystemState,
        wizardIssues: [WizardIssue],
        systemContext: SystemContext?,
        intentionallyOff: Bool = false
    ) -> [SettingsSystemStatusRowModel] {
        var rows: [SettingsSystemStatusRowModel] = []

        // The session runtime is the only system component to report.
        let daemonIssues = wizardIssues.filter(\.identifier.isDaemon)
        let blockingPermissionIssue = ServiceStatusEvaluator.blockingIssueMessage(from: wizardIssues)
        let serviceStatus: InstallationStatus = {
            if wizardSystemState == .initializing { return .inProgress }
            // The user turned remapping off with the switch: not a fault to fix.
            if intentionallyOff { return .notStarted }
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
            if intentionallyOff, wizardSystemState != .initializing { return String(localized: "Turned off") }
            if serviceStatus != .completed {
                return blockingPermissionIssue ?? daemonIssues.first?.title
            }
            return nil
        }()
        rows.append(
            SettingsSystemStatusRowModel(
                id: "kanata-service",
                title: String(localized: "Keyboard remapping"),
                icon: "app.badge.checkmark",
                status: serviceStatus,
                targetPage: .service,
                message: serviceMessage
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
    let id: String
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
            .accessibilityIdentifier("settings-status-row-button-\(id)")
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityValue)

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
        case .inProgress, .notStarted, .unverified:
            .secondary
        }
    }

    private var accessibilityValue: String {
        let value = status.accessibilityValue
        guard let message, !message.isEmpty else { return value }
        return "\(value): \(message)"
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
        case .unverified:
            "questionmark.circle"
        }
    }
}

private extension InstallationStatus {
    var accessibilityValue: String {
        switch self {
        case .notStarted: String(localized: "not started", comment: "VoiceOver status value")
        case .inProgress: String(localized: "in progress", comment: "VoiceOver status value")
        case .completed: String(localized: "completed", comment: "VoiceOver status value")
        case .warning: String(localized: "warning", comment: "VoiceOver status value")
        case .failed: String(localized: "failed", comment: "VoiceOver status value")
        case .unverified: String(localized: "unverified", comment: "VoiceOver status value")
        }
    }
}

/// A single visible permission must retain failures or uncertainty from either process.
enum SettingsPermissionSummary {
    static func combine(_ app: PermissionOracle.Status?, _ runtime: PermissionOracle.Status?) -> PermissionOracle.Status {
        let statuses = [app ?? .unknown, runtime ?? .unknown]
        if let error = statuses.first(where: { if case .error = $0 { return true }; return false }) { return error }
        if statuses.contains(.denied) { return .denied }
        if statuses.contains(.unknown) { return .unknown }
        return .granted
    }
}
