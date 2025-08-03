import SwiftUI

struct WizardDaemonPage: View {
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: () -> Void
  let onRefresh: () async -> Void
  let kanataManager: KanataManager

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header using design system
      WizardPageHeader(
        icon: "gear.circle.fill",
        title: "Karabiner Daemon",
        subtitle:
          "The Karabiner Virtual HID Device Daemon is required for keyboard remapping to work properly.",
        status: .info
      )

      // Daemon Status using design system
      VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
          Image(systemName: daemonRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(WizardDesign.Typography.sectionTitle)
            .foregroundColor(
              daemonRunning ? WizardDesign.Colors.success : WizardDesign.Colors.error
            )
            .frame(width: 30)

          VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap / 2) {
            Text("Karabiner Virtual HID Device Daemon")
              .font(WizardDesign.Typography.body)
              .fontWeight(.medium)

            Text(daemonRunning ? "Daemon is running" : "Daemon is not running")
              .font(WizardDesign.Typography.caption)
              .foregroundColor(WizardDesign.Colors.secondaryText)
          }

          Spacer()
        }
        .wizardCard()
      }
      .wizardContentSpacing()

      // Issues (if any)
      if !issues.isEmpty {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
          ForEach(issues) { issue in
            IssueCardView(
              issue: issue,
              onAutoFix: issue.autoFixAction != nil ? onAutoFix : nil,
              isFixing: isFixing,
              kanataManager: kanataManager
            )
          }
        }
        .wizardPagePadding()
      }

      Spacer()

      // Action Section using design system
      if !daemonRunning {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
          Text(
            "The daemon needs to be running for Kanata to communicate with the keyboard hardware."
          )
          .multilineTextAlignment(.center)
          .foregroundColor(WizardDesign.Colors.secondaryText)
          .font(WizardDesign.Typography.body)

          Button(action: {
            onAutoFix()
          }) {
            HStack(spacing: WizardDesign.Spacing.labelGap) {
              if isFixing {
                ProgressView()
                  .scaleEffect(0.8)
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Starting Daemon...")
              } else {
                Image(systemName: "play.circle.fill")
                Text("Start Karabiner Daemon")
              }
            }
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isFixing))
          .disabled(isFixing)
        }
        .wizardContentSpacing()
      } else {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
          HStack(spacing: WizardDesign.Spacing.labelGap) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(WizardDesign.Colors.success)
            Text("Daemon is running successfully!")
              .font(WizardDesign.Typography.status)
          }

          Text("You can proceed to the next step.")
            .font(WizardDesign.Typography.caption)
            .foregroundColor(WizardDesign.Colors.secondaryText)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
  }

  // MARK: - Computed Properties

  private var daemonRunning: Bool {
    // If there are no daemon issues, assume it's running
    !issues.contains { $0.category == .daemon }
  }
}
