import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Kanata binary and service setup page
struct WizardKanataComponentsPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let onAutoFix: (AutoFixAction, Bool) async -> WizardFixResult // (action, suppressToast)
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []
    @State private var blockedByOtherFixIssueID: UUID?
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when engine is installed
            if kanataRelatedIssues.isEmpty, componentStatus(for: "Kanata Binary") == .completed {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "cpu.fill",
                        title: "Kanata Engine Setup",
                        subtitle:
                        "Kanata binary is installed & configured for advanced keyboard remapping functionality"
                    )

                    // Inline action status (immediately after hero for visual consistency)
                    if actionStatus.isActive, let message = actionStatus.message {
                        InlineStatusView(status: actionStatus, message: message)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Component details card below the subheading - horizontally centered
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            // Kanata Binary (always shown in success state)
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                HStack(spacing: 0) {
                                    Text("Kanata Binary")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Text(" - Installed at /Library/KeyPath/bin/kanata (Developer ID signed)")
                                        .font(.headline)
                                        .fontWeight(.regular)
                                }
                            }

                            // Kanata Service (if service is configured)
                            if componentStatus(for: "Kanata Service") == .completed {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
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
                    .padding(.top, WizardDesign.Spacing.pageVertical)

                    Button(nextStepButtonTitle) {
                        navigateToNextStep()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .heroSectionContainer()
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.warning(
                        icon: "cpu.fill",
                        title: "Kanata Engine Setup",
                        subtitle: "Install and configure the Kanata keyboard remapping engine",
                        iconTapAction: {
                            Task {
                                onRefresh()
                            }
                        }
                    )

                    // Inline action status (immediately after hero for visual consistency)
                    if actionStatus.isActive, let message = actionStatus.message {
                        InlineStatusView(status: actionStatus, message: message)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Component details for error/setup states
                    if !(kanataRelatedIssues.isEmpty && componentStatus(for: "Kanata Binary") == .completed) {
                        ScrollView {
                            VStack(spacing: WizardDesign.Spacing.elementGap) {
                                // System-installed kanata binary (stable path for TCC Input Monitoring).
                                InstallationItemView(
                                    title: "System Kanata Binary",
                                    description: "Required at /Library/KeyPath/bin/kanata so Input Monitoring permission applies to the daemon's exact binary path.",
                                    status: componentStatus(for: "Kanata Binary"),
                                    autoFixButton: kanataBinaryIssue?.autoFixAction != nil
                                        ? {
                                            let isThisIssueFixing = kanataBinaryIssue.map { fixingIssues.contains($0.id) } ?? false
                                            return AnyView(
                                                WizardButton(
                                                    isThisIssueFixing ? "Fixing..." : "Fix",
                                                    style: .secondary,
                                                    isLoading: isThisIssueFixing
                                                ) {
                                                    guard let issue = kanataBinaryIssue,
                                                          let autoFixAction = issue.autoFixAction
                                                    else { return }

                                                    AppLogger.shared.log("🔧 [WizardKanataComponentsPage] Fix tapped: \(autoFixAction)")
                                                    fixingIssues.insert(issue.id)
                                                    Task {
                                                        await MainActor.run {
                                                            PermissionGrantCoordinator.shared.setServiceBounceNeeded(
                                                                reason: "Kanata engine fix - \(autoFixAction)"
                                                            )
                                                            actionStatus = .inProgress(message: "Installing Kanata…")
                                                        }

                                                        // Don't suppress toast here; failures need a user-facing reason.
                                                        let result = await onAutoFix(autoFixAction, false)

                                                        await MainActor.run {
                                                            switch result {
                                                            case .applied:
                                                                fixingIssues.remove(issue.id)
                                                                blockedByOtherFixIssueID = nil
                                                                actionStatus = .success(message: "Kanata installed")
                                                                scheduleStatusClear()
                                                            case let .skipped(reason):
                                                                // "Fix already running…" / "Completing X before starting Y…"
                                                                // Keep the button spinner + inline status visible until the other fix completes.
                                                                actionStatus = .inProgress(message: reason)
                                                                blockedByOtherFixIssueID = issue.id
                                                                scheduleBlockedFixFailsafe(issueID: issue.id)
                                                            case .failed:
                                                                fixingIssues.remove(issue.id)
                                                                blockedByOtherFixIssueID = nil
                                                                let detail = KanataBinaryInstaller.shared.lastInstallErrorOutput?
                                                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                                                let detailLine = detail?.split(separator: "\n").first.map(String.init)
                                                                actionStatus = .error(
                                                                    message: detailLine.map { "Fix failed: \($0)" }
                                                                        ?? "Fix failed. See the message above for details."
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                            )
                                        } : nil
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
                                                        guard let autoFixAction = issue.autoFixAction else { return }

                                                        // Mark this specific issue as fixing
                                                        fixingIssues.insert(issue.id)

                                                        Task {
                                                            let componentTitle = getComponentTitle(for: issue)
                                                            await MainActor.run {
                                                                PermissionGrantCoordinator.shared.setServiceBounceNeeded(
                                                                    reason: "Kanata engine fix - \(autoFixAction)")
                                                                actionStatus = .inProgress(
                                                                    message: "Fixing \(componentTitle)…")
                                                            }

                                                            let result = await onAutoFix(autoFixAction, false)

                                                            await MainActor.run {
                                                                switch result {
                                                                case .applied:
                                                                    fixingIssues.remove(issue.id)
                                                                    blockedByOtherFixIssueID = nil
                                                                    actionStatus = .success(
                                                                        message: "\(componentTitle) fixed")
                                                                    scheduleStatusClear()
                                                                case let .skipped(reason):
                                                                    // Keep the button spinner + inline status visible until the other fix completes.
                                                                    actionStatus = .inProgress(message: reason)
                                                                    blockedByOtherFixIssueID = issue.id
                                                                    scheduleBlockedFixFailsafe(issueID: issue.id)
                                                                case .failed:
                                                                    fixingIssues.remove(issue.id)
                                                                    blockedByOtherFixIssueID = nil
                                                                    actionStatus = .error(message: "Fix failed. See the message above for details.")
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
                            .padding(.bottom, WizardDesign.Spacing.pageVertical)
                        }
                    }
                }
                .heroSectionContainer()
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onChange(of: isFixing) { _, newValue in
            guard !newValue else { return }
            clearBlockedFixUIIfNeeded()
        }
    }

    // MARK: - Helper Methods

    private var kanataRelatedIssues: [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Kanata
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataService),
                     .component(.bundledKanataMissing):
                    return true
                default:
                    return false
                }
            }

            return false
        }
    }

    private var kanataBinaryIssue: WizardIssue? {
        issues.first(where: { $0.identifier == .component(.kanataBinaryMissing) })
    }

    private func componentStatus(for componentName: String) -> InstallationStatus {
        // Use identifier-based checks instead of title substring matching
        switch componentName {
        case "Kanata Binary":
            let hasIssue = issues.contains { issue in
                if case let .component(component) = issue.identifier {
                    return component == .kanataBinaryMissing || component == .bundledKanataMissing
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
                return
                    "Install kanata to /Library/KeyPath/bin/kanata so Input Monitoring permission applies to the daemon's exact binary path."
            case .kanataService:
                return "Service configuration files for running kanata in the background"
            default:
                return issue.description
            }
        }
        return issue.description
    }

    private func installBundledKanata() {
        AppLogger.shared.log(
            "🔧 [WizardKanataComponentsPage] User requested bundled kanata installation")
        if let kanataIssue = issues.first(where: { $0.autoFixAction == .installBundledKanata }) {
            fixingIssues.insert(kanataIssue.id)

            Task {
                await MainActor.run {
                    actionStatus = .inProgress(message: "Installing bundled Kanata…")
                }

                let result = await onAutoFix(.installBundledKanata, true) // suppressToast=true
                await kanataManager.updateStatus()

                await MainActor.run {
                    switch result {
                    case .applied:
                        _ = fixingIssues.remove(kanataIssue.id)
                        blockedByOtherFixIssueID = nil
                        actionStatus = .success(message: "Bundled Kanata installed")
                        scheduleStatusClear()
                    case let .skipped(reason):
                        // Keep the button spinner + inline status visible until the other fix completes.
                        actionStatus = .inProgress(message: reason)
                        blockedByOtherFixIssueID = kanataIssue.id
                        scheduleBlockedFixFailsafe(issueID: kanataIssue.id)
                    case .failed:
                        _ = fixingIssues.remove(kanataIssue.id)
                        blockedByOtherFixIssueID = nil
                        actionStatus = .error(message: "Install failed. Please try again.")
                    }
                }
            }
        }
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            navigationCoordinator.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await navigationCoordinator.getNextPage(for: systemState, issues: issues),
               nextPage != navigationCoordinator.currentPage {
                navigationCoordinator.navigateToPage(nextPage)
            } else {
                navigationCoordinator.navigateToPage(.summary)
            }
        }
    }

    /// Auto-clear success status after 3 seconds
    private func scheduleStatusClear() {
        Task { @MainActor in
            _ = await WizardSleep.seconds(3)
            switch actionStatus {
            case .success:
                actionStatus = .idle
            case .idle, .inProgress, .error:
                break
            }
        }
    }

    @MainActor
    private func clearBlockedFixUIIfNeeded() {
        guard let blockedIssueID = blockedByOtherFixIssueID else { return }
        blockedByOtherFixIssueID = nil
        fixingIssues.remove(blockedIssueID)

        if case .inProgress = actionStatus {
            actionStatus = .idle
        }
    }

    private func scheduleBlockedFixFailsafe(issueID: UUID) {
        Task { @MainActor in
            _ = await WizardSleep.seconds(90)
            guard blockedByOtherFixIssueID == issueID else { return }

            // If another fix never clears, unblock the UI so the user isn't stuck.
            blockedByOtherFixIssueID = nil
            fixingIssues.remove(issueID)
            actionStatus = .error(
                message: "Another fix appears to be stuck. Try restarting KeyPath and running Fix again."
            )
        }
    }
}
