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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header - changes when everything is complete
                Group {
                    if isEverythingComplete {
                        WizardPageHeader(
                            icon: "checkmark.circle.fill",
                            title: "KeyPath Ready",
                            subtitle: "Your keyboard customization tool is fully configured",
                            status: .success
                        )
                    } else {
                        WizardPageHeader(
                            icon: "keyboard.fill",
                            title: "Welcome to KeyPath",
                            subtitle: "Set up your keyboard customization tool",
                            status: .info
                        )
                    }
                }
                .padding(.bottom, WizardDesign.Spacing.sectionGap)

                // System Status Overview
                WizardSystemStatusOverview(
                    systemState: systemState,
                    issues: issues,
                    stateInterpreter: stateInterpreter,
                    onNavigateToPage: onNavigateToPage,
                    kanataIsRunning: kanataManager.isRunning
                )
                .frame(maxHeight: geometry.size.height * 0.5) // Limit list height

                Spacer(minLength: WizardDesign.Spacing.itemGap)

                // Action Section
                WizardActionSection(
                    systemState: systemState,
                    isFullyConfigured: isEverythingComplete,
                    onStartService: onStartService,
                    onDismiss: onDismiss
                )
                .padding(.bottom, WizardDesign.Spacing.pageVertical)
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
}
