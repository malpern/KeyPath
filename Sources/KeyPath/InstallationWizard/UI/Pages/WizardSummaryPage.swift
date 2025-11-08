import KeyPathCore
import KeyPathWizardCore
import AppKit
import SwiftUI

/// Simplified summary page using extracted components
struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    @EnvironmentObject var kanataViewModel: KanataViewModel
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?
    let isInitializing: Bool

    // Access underlying KanataManager for business logic
    private var kanataManager: KanataManager {
        kanataViewModel.underlyingManager
    }

    // MARK: - Header State (no pending phase)
    private enum HeaderMode {
        case issues
        case success
    }

    @State private var headerMode: HeaderMode = .issues
    @State private var showAllItems: Bool = false

    var body: some View {
        VStack(spacing: 0) {
                // Final header (issues or success)
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    Image(systemName: headerIconName)
                        .font(.system(size: WizardDesign.Layout.statusCircleSize))
                        .foregroundColor(headerIconColor)
                        .modifier(AvailabilitySymbolBounce())

                    Text(headerTitle)
                        .font(WizardDesign.Typography.sectionTitle)
                        .fontWeight(.semibold)
                }
                .padding(.top, 20)
                .padding(.bottom, WizardDesign.Spacing.sectionGap)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(WizardDesign.Animation.statusTransition) {
                            showAllItems.toggle()
                        }
                    } label: {
                        Image(systemName: "eye.slash")
                            .foregroundColor(showAllItems ? .primary : .secondary)
                            .font(.system(size: 16, weight: .regular))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .help(showAllItems ? "Show issues only" : "Show all items")
                    .accessibilityLabel(showAllItems ? "Show issues only" : "Show all items")
                    .padding(.trailing, WizardDesign.Spacing.pageVertical)
                }
                .onAppear {
                    withAnimation(WizardDesign.Animation.statusTransition) {
                        headerMode = isEverythingComplete ? .success : .issues
                    }
                    // Clear any stray first responder to avoid focus ring artifact at launch
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
                .onChange(of: isEverythingComplete) { complete in
                    // Transition to success immediately when everything turns green
                    if complete {
                        withAnimation(WizardDesign.Animation.statusTransition) {
                            headerMode = .success
                        }
                    }
                }

                // System Status Overview
                WizardSystemStatusOverview(
                    systemState: systemState,
                    issues: issues,
                    stateInterpreter: stateInterpreter,
                    onNavigateToPage: onNavigateToPage,
                    kanataIsRunning: kanataManager.isRunning,
                    showAllItems: showAllItems
                )
                // Natural height — let the list dictate its own height
                .fixedSize(horizontal: false, vertical: true)

                // Minimal separation before action section
                Spacer(minLength: 0)

                // Action Section
                WizardActionSection(
                    systemState: systemState,
                    isFullyConfigured: isEverythingComplete,
                    onStartService: onStartService,
                    onDismiss: onDismiss
                )
                .padding(.bottom, WizardDesign.Spacing.elementGap) // Reduce bottom padding
        }
        .modifier(WizardDesign.DisableFocusEffects())
        .background(WizardDesign.Colors.wizardBackground)
    }

    // MARK: - Helper Properties

    private var isEverythingComplete: Bool {
        // CRITICAL: Trust the issues system - don't do additional file checks
        // The SystemValidator/IssueGenerator is the single source of truth
        // Any additional validation should be added there, not here

        // Check if system is active and running
        guard systemState == .active, kanataManager.isRunning else {
            return false
        }

        // Check that there are no issues
        // If there are configuration problems, they will appear in the issues list
        return issues.isEmpty
    }

    private var headerTitle: String {
        switch headerMode {
        case .issues:
            let n = failedIssueCount
            let suffix = n == 1 ? "issue" : "issues"
            return "\(n) setup \(suffix) to resolve"
        case .success:
            return "KeyPath Ready"
        }
    }

    private var headerIconName: String {
        switch headerMode {
        case .issues:
            return "xmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private var headerIconColor: Color {
        switch headerMode {
        case .issues:
            return WizardDesign.Colors.error
        case .success:
            return WizardDesign.Colors.success
        }
    }

    // MARK: - Issue Counting (summary indicator)

    private var failedIssueCount: Int {
        var count = 0

        // 1. Privileged Helper not installed (red)
        let hasHelperNotInstalled = issues.contains { issue in
            if case let .component(req) = issue.identifier { return req == .privilegedHelper }
            return false
        }
        if hasHelperNotInstalled { count += 1 }

        // 2. Conflicts (any => red)
        let hasConflicts = issues.contains { $0.category == .conflicts }
        if hasConflicts { count += 1 }

        // 3. Input Monitoring (any missing => red)
        let hasInputMonitoringIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathInputMonitoring || p == .kanataInputMonitoring
            }
            return false
        }
        if hasInputMonitoringIssues { count += 1 }

        // 4. Accessibility (any missing => red)
        let hasAccessibilityIssues = issues.contains { issue in
            if case let .permission(p) = issue.identifier {
                return p == .keyPathAccessibility || p == .kanataAccessibility
            }
            return false
        }
        if hasAccessibilityIssues { count += 1 }

        // 5. Karabiner Driver status (failed => red)
        let karabinerStatus = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: systemState,
            issues: issues
        )
        if karabinerStatus == .failed { count += 1 }

        // 6. Kanata Engine Setup (failed => red)
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService),
                     .component(.orphanedKanataProcess):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKanataIssues { count += 1 }

        return max(count, 1) // never show 0 in error mode
    }
}
