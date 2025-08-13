import SwiftUI

/// Simplified summary page using extracted components
struct WizardSummaryPage: View {
    let systemState: WizardSystemState
    let issues: [WizardIssue]
    let stateInterpreter: WizardStateInterpreter
    let onStartService: () -> Void
    let onDismiss: () -> Void
    let onNavigateToPage: ((WizardPage) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                WizardPageHeader(
                    icon: "keyboard.fill",
                    title: "Welcome to KeyPath",
                    subtitle: "Set up your keyboard customization tool",
                    status: .info
                )
                .padding(.bottom, WizardDesign.Spacing.sectionGap)

                // System Status Overview
                ScrollView {
                    WizardSystemStatusOverview(
                        systemState: systemState,
                        issues: issues,
                        stateInterpreter: stateInterpreter,
                        onNavigateToPage: onNavigateToPage
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
}
