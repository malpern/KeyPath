import SwiftUI

struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header using design system
            WizardPageHeader(
                icon: "keyboard.fill",
                title: "Welcome to KeyPath",
                subtitle: "Set up your keyboard customization tool",
                status: .info
            )

            // System Status Overview
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                systemStatusItems()
            }
            .wizardPagePadding()

            Spacer()

            // Action Section
            actionSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }

    @ViewBuilder
    private func systemStatusItems() -> some View {
        let statusItems = createStatusItems()

        ForEach(statusItems, id: \.title) { item in
            // Show the main status item
            WizardStatusItem(
                icon: item.icon,
                title: item.title,
                status: item.status,
                isNavigable: item.isNavigable,
                action: item.isNavigable ? { onNavigateToPage?(item.targetPage!) } : nil
            )

            // If this is the System Permissions item, show the permission breakdown immediately after
            if item.title == "System Permissions" && hasAnyPermissionIssues() {
                VStack(spacing: WizardDesign.Spacing.labelGap) {
                    let permissionItems = createPermissionStatusItems()
                    ForEach(permissionItems, id: \.title) { permissionItem in
                        HStack(spacing: WizardDesign.Spacing.iconGap) {
                            // Indent permission sub-items to show they belong to System Permissions
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: WizardDesign.Spacing.indentation)

                            WizardStatusItem(
                                icon: permissionItem.icon,
                                title: permissionItem.title,
                                status: permissionItem.status,
                                isNavigable: permissionItem.isNavigable,
                                action: permissionItem.isNavigable ? { onNavigateToPage?(permissionItem.targetPage!) } : nil
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection() -> some View {
        switch systemState {
        case .active:
            // Everything is ready and running
            VStack(spacing: WizardDesign.Spacing.itemGap) {
                HStack(spacing: WizardDesign.Spacing.labelGap) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(WizardDesign.Colors.success)
                    Text("KeyPath is Active")
                        .font(WizardDesign.Typography.status)
                }
                .foregroundColor(WizardDesign.Colors.success)

                WizardButton("Close Setup", style: .primary) {
                    onDismiss()
                }
            }
            .padding(.bottom, WizardDesign.Spacing.pageVertical)

        case .serviceNotRunning, .ready:
            // Components ready but service not running
            VStack(spacing: WizardDesign.Spacing.itemGap) {
                HStack(spacing: WizardDesign.Spacing.labelGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(WizardDesign.Colors.warning)
                    Text("Service Not Running")
                        .font(WizardDesign.Typography.status)
                }
                .foregroundColor(WizardDesign.Colors.warning)

                Text("All components are installed but the Kanata service is not active.")
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                    .multilineTextAlignment(.center)

                WizardButton("Start Kanata Service", style: .primary) {
                    onStartService()
                }
            }
            .padding(.bottom, WizardDesign.Spacing.pageVertical)

        case .conflictsDetected:
            // Conflicts detected
            VStack(spacing: WizardDesign.Spacing.itemGap) {
                HStack(spacing: WizardDesign.Spacing.labelGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(WizardDesign.Colors.error)
                    Text("Conflicts Detected")
                        .font(WizardDesign.Typography.status)
                }
                .foregroundColor(WizardDesign.Colors.error)

                Text("Please resolve conflicts to continue.")
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, WizardDesign.Spacing.pageVertical)

        default:
            // Components not ready
            VStack(spacing: WizardDesign.Spacing.itemGap) {
                HStack(spacing: WizardDesign.Spacing.labelGap) {
                    Image(systemName: "gear.badge.xmark")
                        .foregroundColor(WizardDesign.Colors.secondaryText)
                    Text("Setup Incomplete")
                        .font(WizardDesign.Typography.status)
                }
                .foregroundColor(WizardDesign.Colors.secondaryText)

                Text("Complete the setup process to start using KeyPath")
                    .font(WizardDesign.Typography.caption)
                    .foregroundColor(WizardDesign.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, WizardDesign.Spacing.pageVertical)
        }
    }

    // MARK: - Helper Methods

    private func openSystemPermissions() {
        // Open the main Privacy & Security settings - users can navigate to Input Monitoring/Accessibility from there
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    private func createStatusItems() -> [StatusItem] {
        var items: [StatusItem] = []

        // Follow the same order as wizard pages: conflicts → permissions → installation → daemon

        // 1. Conflicts (first thing to resolve)
        items.append(StatusItem(
            icon: "exclamationmark.triangle",
            title: "No Conflicts",
            status: hasIssueOfType(.conflicts) ? .failed : .completed,
            isNavigable: true,
            targetPage: .conflicts
        ))

        // 2. System Permissions (collapsed/expanded based on issues)
        let hasPermissionIssues = hasAnyPermissionIssues()
        items.append(StatusItem(
            icon: "lock.shield",
            title: "System Permissions",
            status: hasPermissionIssues ? .failed : .completed,
            isNavigable: true,
            targetPage: getSystemPermissionsTargetPage()
        ))

        // 3. Binary Installation
        items.append(StatusItem(
            icon: "keyboard",
            title: "Binary Installation",
            status: hasIssueOfType(.installation) ? .failed : .completed,
            isNavigable: true,
            targetPage: .installation
        ))

        // 4. Karabiner Driver
        items.append(StatusItem(
            icon: "cpu",
            title: "Karabiner Driver",
            status: hasDriverIssues() ? .failed : .completed,
            isNavigable: true,
            targetPage: .installation
        ))

        // 5. Daemon Status
        items.append(StatusItem(
            icon: "gear",
            title: "Karabiner Daemon",
            status: hasIssueOfType(.daemon) ? .failed : .completed,
            isNavigable: true,
            targetPage: .daemon
        ))

        // 6. Kanata Service Status (when components are ready)
        if shouldShowServiceStatus {
            items.append(StatusItem(
                icon: "play",
                title: "Kanata Service",
                status: serviceStatus,
                isNavigable: true,
                targetPage: .service
            ))
        }

        return items
    }

    private func createPermissionStatusItems() -> [StatusItem] {
        var items: [StatusItem] = []

        // Input Monitoring Permission
        items.append(StatusItem(
            icon: "eye",
            title: WizardConstants.Titles.inputMonitoring,
            status: stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues),
            isNavigable: true,
            targetPage: .inputMonitoring
        ))

        // Accessibility Permission
        items.append(StatusItem(
            icon: "accessibility",
            title: WizardConstants.Titles.accessibility,
            status: stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues),
            isNavigable: true,
            targetPage: .accessibility
        ))

        // Background Services
        items.append(StatusItem(
            icon: "gear.badge",
            title: "Background Services",
            status: stateInterpreter.areBackgroundServicesEnabled(in: issues) ? .completed : .failed,
            isNavigable: true,
            targetPage: .backgroundServices
        ))

        return items
    }

    private func hasAnyPermissionIssues() -> Bool {
        return stateInterpreter.hasAnyPermissionIssues(in: issues) ||
            !stateInterpreter.areBackgroundServicesEnabled(in: issues)
    }

    private var shouldShowServiceStatus: Bool {
        // Always show service status - it's a critical component users need to see
        // Service will show appropriate status (failed/not started/completed) based on system state
        return true
    }

    private var serviceStatus: InstallationStatus {
        switch systemState {
        case .active:
            return .completed
        case .serviceNotRunning, .ready:
            return .failed
        case .initializing:
            return .inProgress
        default:
            // For states with missing components, show as not started
            // Service can't run until prerequisites are met
            return .notStarted
        }
    }

    private func hasIssueOfType(_ category: WizardIssue.IssueCategory) -> Bool {
        issues.contains { $0.category == category }
    }

    private func hasDriverIssues() -> Bool {
        // Check for both driver extension permission issues AND driver component issues
        issues.contains { issue in
            // Driver extension permission issue (category: .permissions)
            (issue.category == .permissions && issue.title == "Driver Extension Disabled") ||
                // Karabiner driver component issue (category: .installation)
                (issue.category == .installation && issue.title == "Karabiner Driver Missing")
        }
    }

    private func getSystemPermissionsTargetPage() -> WizardPage {
        // Navigate to the first permission page that has issues, or inputMonitoring as default
        if stateInterpreter.getPermissionStatus(.kanataInputMonitoring, in: issues) == .failed {
            return .inputMonitoring
        } else if stateInterpreter.getPermissionStatus(.kanataAccessibility, in: issues) == .failed {
            return .accessibility
        } else if !stateInterpreter.areBackgroundServicesEnabled(in: issues) {
            return .backgroundServices
        } else {
            // If no issues, default to first permission page
            return .inputMonitoring
        }
    }
}

// MARK: - Supporting Types

private struct StatusItem {
    let icon: String
    let title: String
    let status: InstallationStatus
    let isNavigable: Bool
    let targetPage: WizardPage?

    init(icon: String, title: String, status: InstallationStatus, isNavigable: Bool = false, targetPage: WizardPage? = nil) {
        self.icon = icon
        self.title = title
        self.status = status
        self.isNavigable = isNavigable
        self.targetPage = targetPage
    }
}
