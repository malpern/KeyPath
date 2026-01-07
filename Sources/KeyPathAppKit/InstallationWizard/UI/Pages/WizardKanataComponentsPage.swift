import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Kanata binary and service setup page
struct WizardKanataComponentsPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let isFixing: Bool
    let blockingFixDescription: String?
    let onAutoFix: (AutoFixAction, Bool) async -> Bool // (action, suppressToast)
    let onRefresh: () -> Void
    let kanataManager: RuntimeCoordinator

    // Track which specific issues are being fixed
    @State private var fixingIssues: Set<UUID> = []
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @State private var pendingBundledKanataInstall: UUID?
    @State private var pendingIssueFixAction: AutoFixAction?
    @State private var pendingIssueFixId: UUID?
    @State private var pendingIssueFixTitle: String?
    @State private var queuedFixTimeoutTask: Task<Void, Never>?
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
                // Header for setup/error states with action link
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
                            // Dynamic issues from installation category that are Kanata-specific
                            // (these have detailed descriptions and Fix buttons)
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

                                                    let componentTitle = getComponentTitle(for: issue)
                                                    requestIssueFix(
                                                        issueId: issue.id,
                                                        action: autoFixAction,
                                                        title: componentTitle
                                                    )
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

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .onChange(of: isFixing) { _, newValue in
            guard !newValue else { return }

            if let pendingId = pendingIssueFixId,
               let pendingAction = pendingIssueFixAction,
               let pendingTitle = pendingIssueFixTitle
            {
                pendingIssueFixId = nil
                pendingIssueFixAction = nil
                pendingIssueFixTitle = nil
                startIssueFix(issueId: pendingId, action: pendingAction, title: pendingTitle)
                return
            }

            guard let pendingId = pendingBundledKanataInstall else { return }

            guard let issue = issues.first(where: { $0.id == pendingId }) else {
                pendingBundledKanataInstall = nil
                queuedFixTimeoutTask?.cancel()
                queuedFixTimeoutTask = nil
                fixingIssues.remove(pendingId)
                actionStatus = .idle
                return
            }

            pendingBundledKanataInstall = nil
            startBundledKanataInstall(issue: issue)
        }
        .onDisappear {
            queuedFixTimeoutTask?.cancel()
            queuedFixTimeoutTask = nil
        }
    }

    // MARK: - Helper Methods

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
                return
                    "Kanata must be installed to /Library/KeyPath/bin/kanata for stable macOS permissions (Input Monitoring + Accessibility). KeyPath can install it automatically."
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
            if isFixing {
                pendingBundledKanataInstall = kanataIssue.id
                fixingIssues.insert(kanataIssue.id)

                let blocker = blockingFixDescription ?? "another fix"
                actionStatus = .inProgress(
                    message: "Completing \(blocker) before starting Kanata install…"
                )
                AppLogger.shared.log(
                    "⏳ [WizardKanataComponentsPage] Queued Kanata install - waiting for \(blocker)"
                )

                queuedFixTimeoutTask?.cancel()
                queuedFixTimeoutTask = Task { @MainActor in
                    _ = await WizardSleep.seconds(35)
                    guard pendingBundledKanataInstall == kanataIssue.id, isFixing else { return }
                    AppLogger.shared.log(
                        "⛔️ [WizardKanataComponentsPage] Queued Kanata install timed out while waiting"
                    )
                    pendingBundledKanataInstall = nil
                    fixingIssues.remove(kanataIssue.id)
                    actionStatus = .error(
                        message: "Another fix is still running. Wait for it to finish, or restart KeyPath if it appears stuck."
                    )
                }
                return
            }

            startBundledKanataInstall(issue: kanataIssue)
        }
    }

    private func startBundledKanataInstall(issue: WizardIssue) {
        queuedFixTimeoutTask?.cancel()
        queuedFixTimeoutTask = nil
        fixingIssues.insert(issue.id)

        Task {
            await MainActor.run {
                actionStatus = .inProgress(message: "Installing bundled Kanata…")
            }

            let ok = await onAutoFix(.installBundledKanata, true) // suppressToast=true
            await kanataManager.updateStatus()

            await MainActor.run {
                _ = fixingIssues.remove(issue.id)
                if ok {
                    actionStatus = .success(message: "Bundled Kanata installed")
                    scheduleStatusClear()
                } else {
                    actionStatus = .error(message: "Install failed. Please try again.")
                }
            }
        }
    }

    private func requestIssueFix(issueId: UUID, action: AutoFixAction, title: String) {
        if isFixing {
            pendingIssueFixId = issueId
            pendingIssueFixAction = action
            pendingIssueFixTitle = title
            fixingIssues.insert(issueId)

            let blocker = blockingFixDescription ?? "another fix"
            actionStatus = .inProgress(
                message: "Completing \(blocker) before starting \(title)…"
            )

            queuedFixTimeoutTask?.cancel()
            queuedFixTimeoutTask = Task { @MainActor in
                _ = await WizardSleep.seconds(35)
                guard pendingIssueFixId == issueId, isFixing else { return }
                AppLogger.shared.log(
                    "⛔️ [WizardKanataComponentsPage] Queued issue fix timed out while waiting"
                )
                pendingIssueFixId = nil
                pendingIssueFixAction = nil
                pendingIssueFixTitle = nil
                fixingIssues.remove(issueId)
                actionStatus = .error(
                    message: "Another fix is still running. Wait for it to finish, or restart KeyPath if it appears stuck."
                )
            }
            return
        }

        startIssueFix(issueId: issueId, action: action, title: title)
    }

    private func startIssueFix(issueId: UUID, action: AutoFixAction, title: String) {
        queuedFixTimeoutTask?.cancel()
        queuedFixTimeoutTask = nil
        fixingIssues.insert(issueId)

        Task {
            await MainActor.run {
                PermissionGrantCoordinator.shared.setServiceBounceNeeded(
                    reason: "Kanata engine fix - \(action)")
                actionStatus = .inProgress(message: "Fixing \(title)…")
            }

            let ok = await onAutoFix(action, true) // suppressToast=true

            await MainActor.run {
                fixingIssues.remove(issueId)
                if ok {
                    actionStatus = .success(message: "\(title) fixed")
                    scheduleStatusClear()
                } else {
                    actionStatus = .error(message: "Fix failed. See diagnostics for details.")
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
               nextPage != navigationCoordinator.currentPage
            {
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
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }
}
