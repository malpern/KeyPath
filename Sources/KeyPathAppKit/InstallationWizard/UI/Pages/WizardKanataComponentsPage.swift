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
    @EnvironmentObject var stateMachine: WizardStateMachine

    var body: some View {
        VStack(spacing: 0) {
            if !hasKanataIssues {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "cpu.fill",
                        title: "Kanata Engine Setup",
                        subtitle:
                        "Kanata binary is installed & configured for advanced keyboard remapping functionality"
                    )

                    InlineStatusView(status: actionStatus, message: actionStatus.message ?? " ")
                        .opacity(actionStatus.isActive ? 1 : 0)

                    Button(nextStepButtonTitle) {
                        navigateToNextStep()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    InlineStatusView(status: actionStatus, message: actionStatus.message ?? " ")
                        .opacity(actionStatus.isActive ? 1 : 0)

                    Button("Fix") {
                        handlePrimaryFix()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isPrimaryFixLoading))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPrimaryFixLoading || primaryFixIssue?.autoFixAction == nil)
                    .frame(minHeight: 44)
                    .padding(.top, WizardDesign.Spacing.itemGap)
                }
                .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private var kanataIssues: [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Kanata
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService),
                     .component(.launchDaemonServices),
                     .component(.launchDaemonServicesUnhealthy):
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
                return "Kanata is required for remapping. Click Fix to install it."
            case .kanataService:
                return "Background service configuration required for Kanata."
            default:
                return issue.description
            }
        }
        return issue.description
    }

    private var hasKanataIssues: Bool {
        !kanataIssues.isEmpty
    }

    private var primaryFixIssue: WizardIssue? {
        if let binaryIssue = kanataIssues.first(where: { $0.identifier == .component(.kanataBinaryMissing) }) {
            return binaryIssue
        }
        if let serviceIssue = kanataIssues.first(where: {
            switch $0.identifier {
            case .component(.kanataService),
                 .component(.launchDaemonServices),
                 .component(.launchDaemonServicesUnhealthy):
                true
            default:
                false
            }
        }) {
            return serviceIssue
        }
        return kanataIssues.first
    }

    private var isPrimaryFixLoading: Bool {
        if case .inProgress = actionStatus {
            return true
        }
        return isFixing
    }

    private func handlePrimaryFix() {
        guard let issue = primaryFixIssue else { return }

        if issue.autoFixAction == .installBundledKanata {
            installBundledKanata()
            return
        }

        guard let action = issue.autoFixAction else { return }
        let componentTitle = getComponentTitle(for: issue)
        requestIssueFix(issueId: issue.id, action: action, title: componentTitle)
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
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: issues),
               nextPage != stateMachine.currentPage
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
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
