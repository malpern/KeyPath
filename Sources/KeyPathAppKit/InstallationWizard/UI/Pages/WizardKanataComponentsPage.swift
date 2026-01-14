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
    let onFixAll: () async -> FixAllResult
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
            if !hasKanataIssues {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "cpu.fill",
                        title: "Kanata Setup",
                        subtitle:
                        "Kanata engine, service, and TCP communication are configured"
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
                        title: "Kanata Setup",
                        subtitle: "Install Kanata, start the service, and enable TCP communication",
                        iconTapAction: {
                            Task {
                                onRefresh()
                            }
                        }
                    )

                    InlineStatusView(status: actionStatus, message: actionStatus.message ?? " ")
                        .opacity(actionStatus.isActive ? 1 : 0)

                    Button("Fix") { handlePrimaryFix() }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isPrimaryFixLoading))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPrimaryFixLoading)
                    .frame(minHeight: 44)
                    .padding(.top, WizardDesign.Spacing.itemGap)
                }
                .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
               let pendingTitle = pendingIssueFixTitle {
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
            guard case let .component(component) = issue.identifier else { return false }
            switch component {
            case .kanataBinaryMissing,
                 .kanataService,
                 .launchDaemonServices,
                 .launchDaemonServicesUnhealthy,
                 .orphanedKanataProcess,
                 .communicationServerConfiguration,
                 .communicationServerNotResponding,
                 .tcpServerConfiguration,
                 .tcpServerNotResponding:
                return true
            default:
                return false
            }
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
                return "Kanata Service"
            case .communicationServerConfiguration, .communicationServerNotResponding,
                 .tcpServerConfiguration, .tcpServerNotResponding:
                return "TCP Communication"
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
            case .communicationServerConfiguration, .communicationServerNotResponding,
                 .tcpServerConfiguration, .tcpServerNotResponding:
                return "TCP communication needs to be configured for KeyPath."
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
                return true
            default:
                return false
            }
        }) {
            return serviceIssue
        }
        if let communicationIssue = kanataIssues.first(where: {
            switch $0.identifier {
            case .component(.communicationServerConfiguration),
                 .component(.communicationServerNotResponding),
                 .component(.tcpServerConfiguration),
                 .component(.tcpServerNotResponding):
                return true
            default:
                return false
            }
        }) {
            return communicationIssue
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

        if kanataIssues.count > 1 {
            startFixAll(focusTitle: getComponentTitle(for: issue))
            return
        }

        if issue.autoFixAction == .installBundledKanata {
            installBundledKanata()
            return
        }

        guard let action = issue.autoFixAction else { return }
        let componentTitle = getComponentTitle(for: issue)
        requestIssueFix(issueId: issue.id, action: action, title: componentTitle)
    }

    private func startFixAll(focusTitle: String) {
        Task {
            await MainActor.run {
                actionStatus = .inProgress(message: "Fixing \(focusTitle)…")
            }

            let result = await onFixAll()

            await MainActor.run {
                switch result.status {
                case .success:
                    actionStatus = .success(message: "All issues resolved")
                    scheduleStatusClear()
                case .partial:
                    actionStatus = .error(message: formatPartialResultMessage(result))
                case .failed:
                    actionStatus = .error(message: formatFailureResultMessage(result))
                }
            }
        }
    }

    private func formatPartialResultMessage(_ result: FixAllResult) -> String {
        let fixedSteps = formatStepList(result.steps, success: true)
        let failedSteps = formatStepList(result.steps, success: false)
        let remainingIssues = formatIssueList(result.remainingIssueIDs)

        if !fixedSteps.isEmpty, !remainingIssues.isEmpty, !failedSteps.isEmpty {
            return "Fixed: \(fixedSteps). Failed: \(failedSteps). Remaining: \(remainingIssues)."
        }
        if !fixedSteps.isEmpty, !remainingIssues.isEmpty {
            return "Fixed: \(fixedSteps). Remaining: \(remainingIssues)."
        }
        if !fixedSteps.isEmpty, !failedSteps.isEmpty {
            return "Fixed: \(fixedSteps). Failed: \(failedSteps)."
        }
        if !remainingIssues.isEmpty {
            return "Fix incomplete. Remaining: \(remainingIssues)."
        }
        return "Fix incomplete. Re-check status."
    }

    private func formatFailureResultMessage(_ result: FixAllResult) -> String {
        let failedSteps = formatStepList(result.steps, success: false)
        let remainingIssues = formatIssueList(result.remainingIssueIDs)
        if !failedSteps.isEmpty, !remainingIssues.isEmpty {
            return "Fix failed. Failed: \(failedSteps). Remaining: \(remainingIssues)."
        }
        if !remainingIssues.isEmpty {
            return "Fix failed. Remaining: \(remainingIssues)."
        }
        return "Fix failed. See diagnostics for details."
    }

    private func formatStepList(_ steps: [FixStepResult], success: Bool) -> String {
        steps.filter { $0.success == success }.map { result in
            if let detail = result.detail, !detail.isEmpty {
                return "\(result.step.rawValue) (\(detail))"
            }
            return result.step.rawValue
        }.joined(separator: ", ")
    }

    private func formatIssueList(_ ids: [IssueIdentifier]) -> String {
        ids.map(issueTitle(for:)).joined(separator: ", ")
    }

    private func issueTitle(for identifier: IssueIdentifier) -> String {
        if case let .component(component) = identifier {
            switch component {
            case .kanataBinaryMissing:
                return "Kanata Binary"
            case .kanataService, .launchDaemonServices, .launchDaemonServicesUnhealthy:
                return "Kanata Service"
            case .communicationServerConfiguration,
                 .communicationServerNotResponding,
                 .tcpServerConfiguration,
                 .tcpServerNotResponding:
                return "TCP Communication"
            case .orphanedKanataProcess:
                return "Orphaned Kanata Process"
            default:
                return "Kanata Setup"
            }
        }
        return "Setup Issue"
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
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }
}
