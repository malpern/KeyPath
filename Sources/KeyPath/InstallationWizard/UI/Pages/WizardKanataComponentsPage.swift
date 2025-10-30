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
                                .modifier(AvailabilitySymbolBounce())

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
                                .modifier(AvailabilitySymbolBounce())

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

                                                        _ = await onAutoFix(autoFixAction)

                                                        // Remove this issue from fixing state
                                                        _ = await MainActor.run {
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
                    Button("Install Kanata") {
                        installBundledKanata()
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                }

                // Centered Continue button (always present)
                HStack {
                    Spacer()
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from Kanata Components page")
                        Task {
                            await navigateToNextPage()
                        }
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

    private func navigateToNextPage() async {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]

        // Show spinning cursor during state refresh
        await MainActor.run {
            NSCursor.operationNotAllowed.push()
        }

        // Pre-fetch state for pages that need async checks
        if nextPage == .service {
            // Refresh state so Service page has current data
            onRefresh()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for refresh to complete
        }

        // Restore cursor and navigate
        await MainActor.run {
            NSCursor.pop()
            navigationCoordinator.navigateToPage(nextPage)
            AppLogger.shared.log("➡️ [Kanata Components] Navigated to next page: \(nextPage.displayName)")
        }
    }

    private var kanataRelatedIssues: [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Kanata
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService):
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
                    return component == .kanataBinaryMissing
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
            issue.identifier == .component(.kanataBinaryMissing)
        }
    }

    private func getComponentTitle(for issue: WizardIssue) -> String {
        // Use identifiers instead of stringly-typed title matching
        if case let .component(component) = issue.identifier {
            switch component {
            case .kanataBinaryMissing:
                return "Kanata Binary"
            case .kanataService:
                return "Kanata Service Configuration"
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
            case .kanataBinaryMissing:
                return "The kanata binary needs to be installed to system location from KeyPath's bundled Developer ID signed version"
            case .kanataService:
                return "Service configuration files for running kanata in the background"
            default:
                return issue.description
            }
        }
        return issue.description
    }

    private func installBundledKanata() {
        AppLogger.shared.log("🔧 [WizardKanataComponentsPage] User requested bundled kanata installation")
        if let kanataIssue = issues.first(where: { $0.autoFixAction == .installBundledKanata }) {
            fixingIssues.insert(kanataIssue.id)

            Task {
                _ = await onAutoFix(.installBundledKanata)
                await kanataManager.updateStatus()

                await MainActor.run {
                    _ = fixingIssues.remove(kanataIssue.id)
                }
            }
        }
    }
}
