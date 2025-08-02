import SwiftUI

struct WizardInstallationPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () async -> Void
    let kanataManager: KanataManager

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
            // Header using design system
            WizardPageHeader(
                icon: "arrow.down.circle.fill",
                title: "Install Components",
                subtitle: "Set up required system components",
                status: .info
            )

            // All Installation Components
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                InstallationItemView(
                    title: "Kanata Binary",
                    description: "Core keyboard remapping engine",
                    status: componentStatus(for: "Kanata Binary")
                )

                InstallationItemView(
                    title: "Kanata Service",
                    description: "Direct kanata execution with --watch support",
                    status: .completed // Always available
                )

                InstallationItemView(
                    title: "Karabiner Driver",
                    description: "Virtual keyboard driver for input capture",
                    status: componentStatus(for: "Karabiner Driver")
                )

                // VirtualHIDDevice and LaunchDaemon components - show as installation items with Fix buttons
                ForEach(issues.filter { $0.category == .installation && isVirtualHIDDeviceOrLaunchDaemonIssue($0) }, id: \.id) { issue in
                    InstallationItemView(
                        title: getComponentTitle(for: issue),
                        description: getComponentDescription(for: issue),
                        status: .failed,
                        autoFixButton: issue.autoFixAction != nil ? {
                            AnyView(
                                WizardButton(
                                    isFixing ? "Fixing..." : "Fix",
                                    style: .secondary,
                                    isLoading: isFixing
                                ) {
                                    if let autoFixAction = issue.autoFixAction {
                                        Task {
                                            let success = await onAutoFix(autoFixAction)
                                            AppLogger.shared.log("🔧 [InstallationPage] Auto-fix \(autoFixAction): \(success ? "success" : "failed")")
                                        }
                                    }
                                }
                            )
                        } : nil
                    )
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Methods

    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Check if there's an issue for this component
        let hasIssue = issues.contains { issue in
            issue.category == .installation && issue.title.contains(componentName)
        }

        return hasIssue ? .failed : .completed
    }

    private var allComponentsInstalled: Bool {
        // No installation issues means all components are installed
        !issues.contains { $0.category == .installation }
    }

    private var hasAutoFixableIssues: Bool {
        issues.contains { $0.autoFixAction != nil }
    }

    private func isVirtualHIDDeviceOrLaunchDaemonIssue(_ issue: WizardIssue) -> Bool {
        // Check if this is a VirtualHIDDevice or LaunchDaemon related issue
        let vhidIssues = ["VirtualHIDDevice Manager Not Activated", "VirtualHIDDevice Daemon Not Running"]
        let launchDaemonIssues = ["LaunchDaemon Services Not Installed"]

        return vhidIssues.contains(issue.title) || launchDaemonIssues.contains(issue.title)
    }

    private func getComponentTitle(for issue: WizardIssue) -> String {
        // Clean up the title to be more consistent
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            return "VirtualHIDDevice Manager"
        case "VirtualHIDDevice Daemon Not Running":
            return "VirtualHIDDevice Daemon"
        case "LaunchDaemon Services Not Installed":
            return "LaunchDaemon Services"
        default:
            return issue.title
        }
    }

    private func getComponentDescription(for issue: WizardIssue) -> String {
        // Provide consistent descriptions that match the style of other components
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            return "The VirtualHIDDevice Manager needs to be activated to enable virtual HID functionality"
        case "VirtualHIDDevice Daemon Not Running":
            return "Virtual keyboard driver daemon processes required for input capture"
        case "LaunchDaemon Services Not Installed":
            return "System services required for background operation"
        default:
            return issue.description
        }
    }
}
