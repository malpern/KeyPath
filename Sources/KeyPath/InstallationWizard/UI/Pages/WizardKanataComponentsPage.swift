import SwiftUI

/// Kanata binary and service setup page
struct WizardKanataComponentsPage: View {
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
            // Use experimental hero design when engine is installed
            if kanataRelatedIssues.isEmpty, componentStatus(for: "Kanata Binary") == .completed {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green CPU icon with green check overlay
                        ZStack {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)

                            // Green check overlay moved to the right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Move to the right
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }

                        // Headline
                        Text("Kanata Engine Setup")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Subtitle
                        Text("Kanata binary is installed & configured for advanced keyboard remapping functionality")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)

                        // Component details card below the subheading - horizontally centered
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                // Kanata Binary (always shown in success state)
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    HStack(spacing: 0) {
                                        Text("Kanata Binary")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text(" - KeyPath's bundled & Developer ID signed version")
                                            .font(.headline)
                                            .fontWeight(.regular)
                                    }
                                }

                                // Kanata Service (if service is configured)
                                if componentStatus(for: "Kanata Service") == .completed {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        HStack(spacing: 0) {
                                            Text("Kanata Service")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Text(" - System service configuration & management")
                                                .font(.headline)
                                                .fontWeight(.regular)
                                        }
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
                // Header for setup/error states with action link
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Custom header with colored CPU icon
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Orange CPU icon with warning overlay
                        ZStack {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(WizardDesign.Colors.warning)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)

                            // Warning overlay moved to the right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.warning)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -3) // Move to the right for smaller icon
                                }
                                Spacer()
                            }
                            .frame(width: 60, height: 60)
                        }
                        .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)

                        // Title
                        Text("Kanata Engine Setup")
                            .font(WizardDesign.Typography.sectionTitle)
                            .fontWeight(.semibold)

                        // Subtitle
                        Text("Install and configure the Kanata keyboard remapping engine")
                            .font(WizardDesign.Typography.subtitle)
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .wizardContentSpacing()
                    }
                    .padding(.top, 12)

                    // Check Status link under the subheader
                    Button("Check Status") {
                        Task {
                            onRefresh()
                        }
                    }
                    .buttonStyle(.link)
                }
            }

            // Component details for error/setup states
            if !(kanataRelatedIssues.isEmpty && componentStatus(for: "Kanata Binary") == .completed) {
                ScrollView {
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Static components that should be present
                        InstallationItemView(
                            title: "Kanata Binary",
                            description: "Core keyboard remapping engine executable",
                            status: componentStatus(for: "Kanata Binary")
                        )

                        // Dynamic issues from installation category that are Kanata-specific
                        ForEach(kanataRelatedIssues, id: \.id) { issue in
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
                                                        // IMMEDIATE crash-proof logging for REAL Fix button click in Kanata page
                                                        Swift.print(
                                                            "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKanataComponentsPage for action: \(autoFixAction) at \(Date())"
                                                        )
                                                        try?
                                                            "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKanataComponentsPage for action: \(autoFixAction) at \(Date())\n"
                                                            .write(
                                                                to: URL(
                                                                    fileURLWithPath: NSHomeDirectory() + "/kanata-fix-button-debug.txt"),
                                                                atomically: true, encoding: .utf8
                                                            )

                                                        // Set service bounce flag before performing auto-fix
                                                        await MainActor.run {
                                                            PermissionGrantCoordinator.shared.setServiceBounceNeeded(reason: "Kanata engine fix - \(autoFixAction)")
                                                        }

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
            }

            Spacer()

            // Bottom buttons
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                if needsManualInstallation, kanataRelatedIssues.count > 0 || componentStatus(for: "Kanata Binary") != .completed {
                    Button("Install via Homebrew") {
                        installViaHomebrew()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                }

                // Centered Continue button (always present)
                HStack {
                    Spacer()
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Kanata Components page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [Kanata Components] Navigated to next page: \(nextPage.displayName)")
    }

    private var kanataRelatedIssues: [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Kanata
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinary),
                     .component(.kanataBinaryUnsigned),
                     .component(.kanataService),
                     .component(.packageManager):
                    return true
                default:
                    return false
                }
            }

            return false
        }
    }

    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Use identifier-based checks instead of title substring matching
        switch componentName {
        case "Kanata Binary":
            let hasIssue = issues.contains { issue in
                if case let .component(component) = issue.identifier {
                    return component == .kanataBinary || component == .kanataBinaryUnsigned
                }
                return false
            }
            return hasIssue ? .failed : .completed

        case "Kanata Service":
            let hasIssue = issues.contains { issue in
                if case let .component(component) = issue.identifier {
                    return component == .kanataService
                        || component == .launchDaemonServices
                        || component == .launchDaemonServicesUnhealthy
                }
                return false
            }
            return hasIssue ? .failed : .completed

        case "Package Manager":
            let hasIssue = issues.contains { issue in
                if case let .component(component) = issue.identifier {
                    return component == .packageManager
                }
                return false
            }
            return hasIssue ? .failed : .completed

        default:
            // Fallback for any other potential component
            let hasIssue = issues.contains { issue in
                issue.category == .installation && issue.title.contains(componentName)
            }
            return hasIssue ? .failed : .completed
        }
    }

    private var needsManualInstallation: Bool {
        // Need manual installation if Kanata binary is missing
        issues.contains { issue in
            issue.identifier == .component(.kanataBinary)
        }
    }

    private func getComponentTitle(for issue: WizardIssue) -> String {
        // Use identifiers instead of stringly-typed title matching
        if case let .component(component) = issue.identifier {
            switch component {
            case .kanataBinary:
                return "Kanata Binary"
            case .kanataBinaryUnsigned:
                return "Kanata Binary (Signing Issue)"
            case .kanataService:
                return "Kanata Service Configuration"
            case .packageManager:
                return "Package Manager"
            default:
                return issue.title
            }
        }
        return issue.title
    }

    private func getComponentDescription(for issue: WizardIssue) -> String {
        // Use identifiers instead of stringly-typed title matching
        if case let .component(component) = issue.identifier {
            switch component {
            case .kanataBinary:
                return "The kanata executable needs to be installed (typically via Homebrew)"
            case .kanataBinaryUnsigned:
                return "System kanata is not Developer ID signed and cannot receive Input Monitoring permission. Click 'Fix' to replace with KeyPath's signed version."
            case .kanataService:
                return "Service configuration files for running kanata in the background"
            case .packageManager:
                return "Homebrew or another package manager is needed to install kanata"
            default:
                return issue.description
            }
        }
        return issue.description
    }

    private func installViaHomebrew() {
        // Try to install via the auto-fix system first
        if let homebrewIssue = issues.first(where: { $0.autoFixAction == .installViaBrew }) {
            fixingIssues.insert(homebrewIssue.id)

            Task {
                let success = await onAutoFix(.installViaBrew)

                await MainActor.run {
                    fixingIssues.remove(homebrewIssue.id)
                }
            }
        } else {
            // Fallback to opening Terminal with the command
            let script = """
            tell application "Terminal"
                activate
                do script "brew install kanata"
            end tell
            """

            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(nil)
            }
        }
    }
}
