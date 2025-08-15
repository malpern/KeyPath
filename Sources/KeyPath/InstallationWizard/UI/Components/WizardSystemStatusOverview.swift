import SwiftUI

/// Simplified system status overview component for the summary page
struct WizardSystemStatusOverview: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onNavigateToPage: ((WizardPage) -> Void)?
    // Authoritative signal for service status - ensures consistency with detail page
    let kanataIsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
            ForEach(statusItems, id: \.id) { item in
                WizardStatusItem(
                    icon: item.icon,
                    title: item.title,
                    subtitle: item.subtitle,
                    status: item.status,
                    isNavigable: item.isNavigable,
                    action: item.isNavigable ? { onNavigateToPage?(item.targetPage) } : nil
                )

                // Show expanded details for failed items
                if item.status == .failed, !item.subItems.isEmpty {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                        ForEach(item.subItems, id: \.id) { subItem in
                            HStack(spacing: WizardDesign.Spacing.iconGap) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: WizardDesign.Spacing.indentation)

                                WizardStatusItem(
                                    icon: subItem.icon,
                                    title: subItem.title,
                                    subtitle: subItem.subtitle,
                                    status: subItem.status,
                                    isNavigable: subItem.isNavigable,
                                    action: subItem.isNavigable ? { onNavigateToPage?(subItem.targetPage) } : nil
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Status Items Creation

    private var statusItems: [StatusItemModel] {
        var items: [StatusItemModel] = []

        // 1. Full Disk Access (Optional but recommended)
        let hasFullDiskAccess = checkFullDiskAccess()
        let fullDiskAccessStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return hasFullDiskAccess ? .completed : .notStarted
        }()
        items.append(
            StatusItemModel(
                id: "full-disk-access",
                icon: "folder.badge.gearshape",
                title: "Full Disk Access (Optional)",
                status: fullDiskAccessStatus,
                isNavigable: true,
                targetPage: .fullDiskAccess
            ))

        // 2. System Conflicts
        let hasConflicts = issues.contains { $0.category == .conflicts }
        let conflictStatus: InstallationStatus = {
            if systemState == .initializing {
                return .notStarted
            }
            return hasConflicts ? .failed : .completed
        }()
        items.append(
            StatusItemModel(
                id: "conflicts",
                icon: "exclamationmark.triangle",
                title: "Resolve System Conflicts",
                status: conflictStatus,
                isNavigable: true,
                targetPage: .conflicts
            ))

        // 3. Input Monitoring Permission
        let inputMonitoringStatus = getInputMonitoringStatus()
        items.append(
            StatusItemModel(
                id: "input-monitoring",
                icon: "eye",
                title: "Input Monitoring Permission",
                status: inputMonitoringStatus,
                isNavigable: true,
                targetPage: .inputMonitoring
            ))

        // 4. Accessibility Permission
        let accessibilityStatus = getAccessibilityStatus()
        items.append(
            StatusItemModel(
                id: "accessibility",
                icon: "accessibility",
                title: "Accessibility Permission",
                status: accessibilityStatus,
                isNavigable: true,
                targetPage: .accessibility
            ))

        // 5. Karabiner Driver Setup
        let karabinerStatus = getKarabinerComponentsStatus()
        items.append(
            StatusItemModel(
                id: "karabiner-components",
                icon: "keyboard.macwindow",
                title: "Karabiner Driver Setup",
                status: karabinerStatus,
                isNavigable: true,
                targetPage: .karabinerComponents
            ))

        // 6. Kanata Engine Setup
        let kanataComponentsStatus = getKanataComponentsStatus()
        items.append(
            StatusItemModel(
                id: "kanata-components",
                icon: "cpu.fill",
                title: "Kanata Engine Setup",
                status: kanataComponentsStatus,
                isNavigable: true,
                targetPage: .kanataComponents
            ))

        // 7. TCP Server Status
        let tcpServerStatus = getTCPServerStatus()
        items.append(
            StatusItemModel(
                id: "tcp-server",
                icon: "network",
                title: "TCP Server",
                subtitle: tcpServerStatus == .completed ? "Port \(PreferencesService.shared.tcpServerPort) responding" : "Not available",
                status: tcpServerStatus,
                isNavigable: false,
                targetPage: .service // Could navigate to service page for troubleshooting
            ))

        // 8. Start Keyboard Service
        items.append(
            StatusItemModel(
                id: "service",
                icon: "play.fill",
                title: "Start Keyboard Service",
                status: getServiceStatus(),
                isNavigable: true,
                targetPage: .service
            ))

        return items
    }

    // MARK: - Status Helpers

    private func checkFullDiskAccess() -> Bool {
        // Use the same non-invasive check as WizardFullDiskAccessPage to maintain consistency
        // This prevents automatic addition to System Preferences while giving accurate status

        let testPath = "\(NSHomeDirectory())/Library/Preferences/com.apple.finder.plist"

        if FileManager.default.isReadableFile(atPath: testPath) {
            // Try a very light read operation
            if let data = try? Data(contentsOf: URL(fileURLWithPath: testPath), options: .mappedIfSafe) {
                if data.count > 0 {
                    AppLogger.shared.log("🔐 [WizardSystemStatusOverview] FDA detected via non-invasive check")
                    return true
                }
            }
        }

        AppLogger.shared.log("🔐 [WizardSystemStatusOverview] FDA not detected (non-invasive check)")
        return false
    }

    private func getInputMonitoringStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        return hasInputMonitoringIssues ? .failed : .completed
    }

    private func getAccessibilityStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }
        return hasAccessibilityIssues ? .failed : .completed
    }

    private func getKarabinerComponentsStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Check for Karabiner-related issues
        let hasKarabinerIssues = issues.contains { issue in
            // Installation issues related to Karabiner
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.launchDaemonServices),
                     .component(.launchDaemonServicesUnhealthy), // Include unhealthy state
                     .component(.vhidDaemonMisconfigured):
                    return true
                default:
                    return false
                }
            }
            // Include daemon and background services issues
            return issue.category == .daemon || issue.category == .backgroundServices
        }

        return hasKarabinerIssues ? .failed : .completed
    }

    private func getKanataComponentsStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Check for Kanata-related issues
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinary),
                     .component(.kanataService),
                     .component(.packageManager),
                     .component(.orphanedKanataProcess):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        return hasKanataIssues ? .failed : .completed
    }

    private func getTCPServerStatus() -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Check for TCP server issues
        let hasTCPServerIssues = issues.contains { issue in
            if case .component(.kanataTCPServer) = issue.identifier {
                return true
            }
            return false
        }

        // If Kanata is running and there are no TCP issues, consider TCP as working
        // This provides an optimistic view since TCP server is optional
        if kanataIsRunning, !hasTCPServerIssues {
            return .completed
        }

        // If not running or has TCP issues
        return hasTCPServerIssues ? .failed : .notStarted
    }

    private func getServiceStatus() -> InstallationStatus {
        // Use the authoritative signal - if Kanata process is running, show as completed
        // This ensures consistency with the detail page regardless of health status
        if kanataIsRunning {
            return .completed
        }

        // Fallback to system state when not running
        switch systemState {
        case .active:
            return .completed // Redundant but safe
        case .initializing:
            return .inProgress
        case .serviceNotRunning, .ready:
            return .notStarted
        default:
            return .notStarted
        }
    }
}

// MARK: - Status Item Model

private struct StatusItemModel {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage
    let subItems: [StatusItemModel]

    init(
        id: String,
        icon: String,
        title: String,
        subtitle: String? = nil,
        status: InstallationStatus,
        isNavigable: Bool = false,
        targetPage: WizardPage = .summary,
        subItems: [StatusItemModel] = []
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isNavigable = isNavigable
        self.targetPage = targetPage
        self.subItems = subItems
    }
}

// MARK: - Preview

struct WizardSystemStatusOverview_Previews: PreviewProvider {
    static var previews: some View {
        WizardSystemStatusOverview(
            systemState: .conflictsDetected(conflicts: []),
            issues: [
                WizardIssue(
                    identifier: .conflict(.karabinerGrabberRunning(pid: 123)),
                    severity: .critical,
                    category: .conflicts,
                    title: "Karabiner Conflict",
                    description: "Test conflict",
                    autoFixAction: .terminateConflictingProcesses,
                    userAction: nil
                )
            ],
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: { _ in },
            kanataIsRunning: true // Show running in preview
        )
        .padding()
    }
}
