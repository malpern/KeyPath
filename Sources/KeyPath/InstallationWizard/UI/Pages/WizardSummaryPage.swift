import SwiftUI

/// Simplified summary page using extracted components
struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    @ObservedObject var kanataManager: KanataManager
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header - changes when everything is complete
                Group {
                    if isEverythingComplete {
                        WizardPageHeader(
                            icon: "keyboard.badge.checkmark",
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
                ScrollView {
                    WizardSystemStatusOverview(
                        systemState: systemState,
                        issues: issues,
                        stateInterpreter: stateInterpreter,
                        onNavigateToPage: onNavigateToPage,
                        kanataIsRunning: kanataManager.isRunning
                    )
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }
                .frame(maxHeight: geometry.size.height * 0.5) // Limit scroll area

                Spacer(minLength: WizardDesign.Spacing.itemGap)

                // Action Section
                WizardActionSection(
                    systemState: systemState,
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
        // Check if system is active and running, meaning everything is properly configured
        systemState == .active && kanataManager.isRunning && issues.isEmpty
    }
}
