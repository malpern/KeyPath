import KeyPathCore
import KeyPathWizardCore
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

    // MARK: - Header Animation State
    private enum HeaderMode {
        case pending
        case issues
        case success
    }

    @State private var headerMode: HeaderMode = .pending

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Animated header (pending -> issues/success)
                VStack(spacing: WizardDesign.Spacing.elementGap) {
                    Image(systemName: headerIconName)
                        .font(.system(size: WizardDesign.Layout.statusCircleSize))
                        .foregroundColor(headerIconColor)
                        .modifier(AvailabilitySymbolBounce())

                    Text(headerTitle)
                        .font(WizardDesign.Typography.sectionTitle)
                        .fontWeight(.semibold)
                }
                .padding(.top, 36)
                .padding(.bottom, WizardDesign.Spacing.sectionGap)
                .onAppear {
                    headerMode = .pending
                    // After 3 seconds, transition based on current status
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        withAnimation(WizardDesign.Animation.statusTransition) {
                            headerMode = isEverythingComplete ? .success : .issues
                        }
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
                    kanataIsRunning: kanataManager.isRunning
                )
                .frame(maxHeight: geometry.size.height * 0.78)

                Spacer(minLength: WizardDesign.Spacing.labelGap)

                // Action Section
                WizardActionSection(
                    systemState: systemState,
                    isFullyConfigured: isEverythingComplete,
                    onStartService: onStartService,
                    onDismiss: onDismiss
                )
                .padding(.bottom, WizardDesign.Spacing.elementGap) // Reduce bottom padding
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
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
        case .pending:
            return "Setting up Keypath"
        case .issues:
            return "Setup issues detected"
        case .success:
            return "KeyPath Ready"
        }
    }

    private var headerIconName: String {
        switch headerMode {
        case .pending:
            return "keyboard.fill"
        case .issues:
            return "xmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        }
    }

    private var headerIconColor: Color {
        switch headerMode {
        case .pending:
            return WizardDesign.Colors.info
        case .issues:
            return WizardDesign.Colors.error
        case .success:
            return WizardDesign.Colors.success
        }
    }
}
