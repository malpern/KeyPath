import SwiftUI

/// Simplified system status overview component for the summary page
struct WizardSystemStatusOverview: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onNavigateToPage: ((WizardPage) -> Void)?

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
        items.append(
            StatusItemModel(
                id: "full-disk-access",
                icon: "folder.badge.gearshape",
                title: "Full Disk Access (Optional)",
                status: hasFullDiskAccess ? .completed : .notStarted,
                isNavigable: true,
                targetPage: .fullDiskAccess
            ))

        // 2. System Conflicts
        let hasConflicts = issues.contains { $0.category == .conflicts }
        items.append(
            StatusItemModel(
                id: "conflicts",
                icon: "exclamationmark.triangle",
                title: "Resolve System Conflicts",
                status: hasConflicts ? .failed : .completed,
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

        // 7. Start Keyboard Service
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
        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        return hasInputMonitoringIssues ? .failed : .completed
    }

    private func getAccessibilityStatus() -> InstallationStatus {
        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }
        return hasAccessibilityIssues ? .failed : .completed
    }

    private func getKarabinerComponentsStatus() -> InstallationStatus {
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
        // Check for Kanata-related issues
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinary),
                     .component(.kanataService),
                     .component(.packageManager):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        return hasKanataIssues ? .failed : .completed
    }

    private func getServiceStatus() -> InstallationStatus {
        switch systemState {
        case .active:
            .completed
        case .serviceNotRunning, .ready:
            .failed
        case .initializing:
            .inProgress
        default:
            .notStarted
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
                ),
            ],
            stateInterpreter: WizardStateInterpreter(),
            onNavigateToPage: { _ in }
        )
        .padding()
    }
}
