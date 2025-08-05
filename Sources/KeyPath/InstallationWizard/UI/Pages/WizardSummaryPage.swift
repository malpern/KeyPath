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
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header
      WizardPageHeader(
        icon: "keyboard.fill",
        title: "Welcome to KeyPath",
        subtitle: "Set up your keyboard customization tool",
        status: .info
      )

      // System Status Overview
      WizardSystemStatusOverview(
        systemState: systemState,
        issues: issues,
        stateInterpreter: stateInterpreter,
        onNavigateToPage: onNavigateToPage
      )
      .wizardPagePadding()

      Spacer()

      // Action Section
      WizardActionSection(
        systemState: systemState,
        onStartService: onStartService,
        onDismiss: onDismiss
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
  }
}
