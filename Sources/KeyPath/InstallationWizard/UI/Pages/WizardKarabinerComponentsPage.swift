import SwiftUI

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () async -> Void
    let kanataManager: KanataManager

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
            // Header
            WizardPageHeader(
                icon: "keyboard.macwindow",
                title: "Karabiner Driver Setup",
                subtitle: "Install and configure Karabiner virtual keyboard driver",
                status: .info
            )

            ScrollView {
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    // Static components that should be present
                    InstallationItemView(
                        title: "Karabiner Driver",
                        description: "Virtual keyboard driver for input capture",
                        status: componentStatus(for: "Karabiner Driver")
                    )

                    // Background services status
                    InstallationItemView(
                        title: "Background Services",
                        description: "Karabiner services in Login Items for automatic startup",
                        status: backgroundServicesStatus
                    )

                    // Dynamic issues from installation, daemon, and backgroundServices categories
                    ForEach(karabinerRelatedIssues, id: \.id) { issue in
                        InstallationItemView(
                            title: getComponentTitle(for: issue),
                            description: getComponentDescription(for: issue),
                            status: .failed,
                            autoFixButton: issue.autoFixAction != nil
                                ? {
                                    let isThisIssueFixing = fixingIssues.contains(issue.id)
                                    return AnyView(
                                        WizardButton(
                                            isThisIssueFixing ? "Fixing..." : "Fix",
                                            style: .secondary,
                                            isLoading: isThisIssueFixing
                                        ) {
                                            if let autoFixAction = issue.autoFixAction {
                                                // Mark this specific issue as fixing
                                                fixingIssues.insert(issue.id)

                                                Task {
                                                    // IMMEDIATE crash-proof logging for REAL Fix button click
                                                    Swift.print(
                                                        "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKarabinerComponentsPage for action: \(autoFixAction) at \(Date())"
                                                    )
                                                    try?
                                                        "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKarabinerComponentsPage for action: \(autoFixAction) at \(Date())\n"
                                                        .write(
                                                            to: URL(
                                                                fileURLWithPath: NSHomeDirectory() + "/real-fix-button-debug.txt"),
                                                            atomically: true, encoding: .utf8
                                                        )

                                                    let success = await onAutoFix(autoFixAction)

                                                    // Remove this issue from fixing state
                                                    await MainActor.run {
                                                        fixingIssues.remove(issue.id)
                                                    }
                                                }
                                            }
                                        }
                                    )
                                } : nil
                        )
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            // Manual action buttons for non-auto-fixable items
            if needsManualAction {
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    if backgroundServicesStatus == .failed {
                        VStack(spacing: WizardDesign.Spacing.labelGap) {
                            Text("Background services need to be manually added to Login Items")
                                .font(WizardDesign.Typography.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(WizardDesign.Colors.secondaryText)

                            Button("Open Login Items Settings") {
                                openLoginItemsSettings()
                            }
                            .buttonStyle(WizardDesign.Component.PrimaryButton())
                        }
                    }

                    Button("Check Status") {
                        Task {
                            await onRefresh()
                        }
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                }
                .padding(.bottom, WizardDesign.Spacing.pageVertical)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Methods

    private var karabinerRelatedIssues: [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Karabiner
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.launchDaemonServices),
                     .component(.launchDaemonServicesUnhealthy),
                     .component(.vhidDaemonMisconfigured):
                    return true
                default:
                    return false
                }
            }

            // Include daemon category issues (VirtualHID related)
            if issue.category == .daemon {
                return true
            }

            // Include background services issues
            if issue.category == .backgroundServices {
                return true
            }

            return false
        }
    }

    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Check if there's an issue for this component
        let hasIssue = issues.contains { issue in
            (issue.category == .installation || issue.category == .daemon)
                && issue.title.contains(componentName)
        }

        return hasIssue ? .failed : .completed
    }

    private var backgroundServicesStatus: InstallationStatus {
        let hasBackgroundServiceIssues = issues.contains { $0.category == .backgroundServices }
        return hasBackgroundServiceIssues ? .failed : .completed
    }

    private var needsManualAction: Bool {
        backgroundServicesStatus == .failed
    }

    private func getComponentTitle(for issue: WizardIssue) -> String {
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            "VirtualHIDDevice Manager"
        case "VirtualHIDDevice Daemon":
            "VirtualHIDDevice Daemon"
        case "VirtualHIDDevice Daemon Misconfigured":
            "VirtualHIDDevice Daemon Configuration"
        case "LaunchDaemon Services Not Installed":
            "LaunchDaemon Services"
        case "LaunchDaemon Services Failing":
            "LaunchDaemon Services"
        case "Karabiner Daemon Not Running":
            "Karabiner Daemon"
        case "Driver Extension Disabled":
            "Driver Extension"
        case "Background Services Disabled":
            "Login Items"
        default:
            issue.title
        }
    }

    private func getComponentDescription(for issue: WizardIssue) -> String {
        switch issue.title {
        case "VirtualHIDDevice Manager Not Activated":
            "The VirtualHIDDevice Manager needs to be activated for virtual HID functionality"
        case "VirtualHIDDevice Daemon":
            "Virtual keyboard driver daemon processes required for input capture"
        case "VirtualHIDDevice Daemon Misconfigured":
            "The installed LaunchDaemon points to a legacy path and needs updating"
        case "LaunchDaemon Services Not Installed":
            "System launch services for VirtualHIDDevice daemon and manager"
        case "LaunchDaemon Services Failing":
            "LaunchDaemon services are loaded but crashing or failing and need to be restarted"
        case "Karabiner Daemon Not Running":
            "The Karabiner Virtual HID Device Daemon needs to be running"
        case "Driver Extension Disabled":
            "Karabiner driver extension needs to be enabled in System Settings"
        case "Background Services Disabled":
            "Karabiner services need to be added to Login Items for automatic startup"
        default:
            issue.description
        }
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
