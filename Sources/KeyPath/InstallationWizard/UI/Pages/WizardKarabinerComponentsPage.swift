import SwiftUI

/// Karabiner driver and virtual HID components setup page
struct WizardKarabinerComponentsPage: View {
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction) async -> Bool
    let onRefresh: () -> Void
    let kanataManager: KanataManager

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when driver is installed
            if !hasKarabinerIssues {
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green keyboard icon with green check overlay
                        ZStack {
                            Image(systemName: "keyboard.macwindow")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
                            // Green check overlay hanging off right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Hang off the right edge
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }
                        
                        // Headline
                        Text("Karabiner Driver")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        // Subtitle
                        Text("Virtual keyboard driver is installed & configured for input capture")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        
                        // Component details card below the subheading - horizontally centered
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    HStack(spacing: 0) {
                                        Text("Karabiner Driver")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Virtual keyboard driver for input capture")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }

                                HStack(spacing: 12) {
                                    Image(systemName: backgroundServicesStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(backgroundServicesStatus == .completed ? .green : .red)
                                    HStack(spacing: 0) {
                                        Text("Background Services")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - Karabiner services in Login Items for startup")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Use hero design for error state too, with blue links below
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Orange keyboard icon with warning overlay
                        ZStack {
                            Image(systemName: "keyboard.macwindow")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.warning)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
                            // Warning overlay hanging off right edge
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Hang off the right edge
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Karabiner Driver Required")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("Karabiner virtual keyboard driver needs to be installed & configured for input capture")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

                        // Component details for error state
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            HStack(spacing: 12) {
                                Image(systemName: componentStatus(for: "Karabiner Driver") == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(componentStatus(for: "Karabiner Driver") == .completed ? .green : .red)
                                HStack(spacing: 0) {
                                    Text("Karabiner Driver")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Virtual keyboard driver")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if componentStatus(for: "Karabiner Driver") != .completed {
                                    Button("Fix") {
                                        // Find and execute auto-fix for driver issues
                                        if let driverIssue = karabinerRelatedIssues.first(where: { $0.autoFixAction != nil && $0.title.contains("Driver") }) {
                                            fixingIssues.insert(driverIssue.id)
                                            Task {
                                                if let autoFixAction = driverIssue.autoFixAction {
                                                    let success = await onAutoFix(autoFixAction)
                                                    await MainActor.run {
                                                        fixingIssues.remove(driverIssue.id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }

                            HStack(spacing: 12) {
                                Image(systemName: backgroundServicesStatus == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(backgroundServicesStatus == .completed ? .green : .red)
                                HStack(spacing: 0) {
                                    Text("Background Services")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Login Items for automatic startup")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                                Spacer()
                                if backgroundServicesStatus != .completed {
                                    Button("Fix") {
                                        openLoginItemsSettings()
                                    }
                                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                                    .scaleEffect(0.8)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(WizardDesign.Spacing.cardPadding)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                        .padding(.top, WizardDesign.Spacing.sectionGap)
                        
                        // Check Status link
                        Button("Check Status") {
                            Task {
                                onRefresh()
                            }
                        }
                        .buttonStyle(.link)
                        .padding(.top, WizardDesign.Spacing.elementGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            // Bottom buttons - primary action changes based on state
            HStack {
                Spacer()
                
                if hasKarabinerIssues {
                    // When issues exist, continue anyway as secondary
                    Button("Continue Anyway") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Karabiner Components page despite issues")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                } else {
                    // When all components are working, Continue is primary
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Karabiner Components page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Methods

    private var hasKarabinerIssues: Bool {
        componentStatus(for: "Karabiner Driver") != .completed || backgroundServicesStatus != .completed || !karabinerRelatedIssues.isEmpty
    }

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Karabiner Components] Navigated to next page: \(nextPage.displayName)")
    }

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
