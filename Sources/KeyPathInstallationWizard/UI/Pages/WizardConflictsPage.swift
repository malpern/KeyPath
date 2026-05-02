import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Conflicts detection and resolution page — follows the standard wizard page pattern.
public struct WizardConflictsPage: View {
    public let isFixing: Bool
    public let onAutoFix: (AutoFixAction, Bool) async -> Bool
    public let onRefresh: () -> Void
    public let kanataManager: any RuntimeCoordinating

    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @Environment(WizardStateMachine.self) private var stateMachine

    private var systemState: WizardSystemState { stateMachine.wizardState }
    private var issues: [WizardIssue] { stateMachine.wizardIssues.filter { $0.category == .conflicts } }
    private var allIssues: [WizardIssue] { stateMachine.wizardIssues }

    public init(
        isFixing: Bool,
        onAutoFix: @escaping (AutoFixAction, Bool) async -> Bool,
        onRefresh: @escaping () -> Void,
        kanataManager: any RuntimeCoordinating
    ) {
        self.isFixing = isFixing
        self.onAutoFix = onAutoFix
        self.onRefresh = onRefresh
        self.kanataManager = kanataManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            if issues.isEmpty {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.success(
                        icon: "checkmark.circle.fill",
                        title: "No Conflicts Detected",
                        subtitle: "No conflicting keyboard remapping software found",
                        iconTapAction: { onRefresh() }
                    )

                    Button(nextStepButtonTitle) {
                        navigateToNextStep()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, WizardDesign.Spacing.sectionGap)
                }
                .heroSectionContainer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    WizardHeroSection.error(
                        icon: "exclamationmark.triangle.fill",
                        title: "Conflicts Detected",
                        subtitle: "\(issues.count) conflicting process\(issues.count == 1 ? "" : "es") found that must be resolved",
                        iconTapAction: { onRefresh() }
                    )

                    InlineStatusView(status: actionStatus, message: actionStatus.message ?? " ")
                        .opacity(actionStatus.isActive ? 1 : 0)

                    Button("Resolve") {
                        handleFix()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixLoading))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isFixLoading || primaryFixAction == nil)
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
        .onAppear {
            onRefresh()
        }
    }

    // MARK: - Fix Logic

    private var primaryFixAction: AutoFixAction? {
        issues.first?.autoFixAction
    }

    private var isFixLoading: Bool {
        if case .inProgress = actionStatus {
            return true
        }
        return isFixing
    }

    private func handleFix() {
        guard let action = primaryFixAction else { return }

        Task {
            await MainActor.run {
                actionStatus = .inProgress(message: "Resolving conflicts…")
            }

            let ok = await onAutoFix(action, true)

            if ok {
                // Wait briefly for processes to terminate
                for _ in 0 ..< 10 {
                    _ = await WizardSleep.ms(100)
                    if await !kanataManager.isKarabinerElementsRunning() {
                        break
                    }
                }
                onRefresh()
            }

            await MainActor.run {
                if ok {
                    actionStatus = .success(message: "Conflicts resolved")
                    scheduleStatusClear()
                } else {
                    actionStatus = .error(message: "Failed to resolve conflicts. Please try again.")
                }
            }
        }
    }

    // MARK: - Navigation

    private var nextStepButtonTitle: String {
        allIssues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    private func navigateToNextStep() {
        if allIssues.isEmpty {
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: allIssues),
               nextPage != stateMachine.currentPage
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private func scheduleStatusClear() {
        Task { @MainActor in
            _ = await WizardSleep.seconds(3)
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }
}
