import SwiftUI

struct WizardBackgroundServicesPage: View {
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: () -> Void
  let onRefresh: () async -> Void
  let kanataManager: KanataManager

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header using design system
      WizardPageHeader(
        icon: "gear.badge",
        title: "Background Services",
        subtitle:
          "Karabiner background services must be enabled for proper keyboard functionality.",
        status: .info
      )

      // Services Status using design system
      VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
          Image(
            systemName: backgroundServicesEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
          )
          .font(WizardDesign.Typography.sectionTitle)
          .foregroundColor(
            backgroundServicesEnabled ? WizardDesign.Colors.success : WizardDesign.Colors.warning
          )
          .frame(width: 30)

          VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap / 2) {
            Text("Karabiner Background Services")
              .font(WizardDesign.Typography.body)
              .fontWeight(.medium)

            Text(
              backgroundServicesEnabled
                ? "Services are enabled" : "Services not enabled in Login Items"
            )
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
      if !backgroundServicesEnabled {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
          Text("These services need to be manually added to Login Items for automatic startup.")
            .multilineTextAlignment(.center)
            .foregroundColor(WizardDesign.Colors.secondaryText)
            .font(WizardDesign.Typography.body)

          VStack(spacing: WizardDesign.Spacing.elementGap) {
            Button("Open System Settings") {
              if let url = URL(
                string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
              {
                NSWorkspace.shared.open(url)
              }
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())

            HStack(spacing: WizardDesign.Spacing.elementGap) {
              Button("Open Karabiner Folder") {
                openKarabinerFolderInFinder()
              }
              .buttonStyle(WizardDesign.Component.SecondaryButton())

              Button("Show Help") {
                // This will be handled by the parent view
              }
              .buttonStyle(WizardDesign.Component.SecondaryButton())
            }

            Button("Check Status") {
              Task {
                await onRefresh()
              }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
          }
        }
        .wizardContentSpacing()
      } else {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
          HStack(spacing: WizardDesign.Spacing.labelGap) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(WizardDesign.Colors.success)
            Text("Background services are enabled!")
              .font(WizardDesign.Typography.status)
          }

          Text("Karabiner services will start automatically at login.")
            .font(WizardDesign.Typography.caption)
            .foregroundColor(WizardDesign.Colors.secondaryText)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
  }

  // MARK: - Computed Properties

  private var backgroundServicesEnabled: Bool {
    // If there are no background services issues, assume they're enabled
    !issues.contains { $0.category == .backgroundServices }
  }

  // MARK: - Helper Methods

  private func openKarabinerFolderInFinder() {
    let karabinerPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/"
    if let url = URL(
      string:
        "file://\(karabinerPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? karabinerPath)"
    ) {
      NSWorkspace.shared.open(url)
    }
  }
}
