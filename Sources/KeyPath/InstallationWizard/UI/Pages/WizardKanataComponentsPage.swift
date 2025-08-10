import SwiftUI

/// Kanata binary and service setup page
struct WizardKanataComponentsPage: View {
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: (AutoFixAction) async -> Bool
  let onRefresh: () async -> Void
  let kanataManager: KanataManager

  // Track which specific issues are being fixed
  @State private var fixingIssues: Set<UUID> = []

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.itemGap) {
      // Header with refresh button
      VStack(spacing: WizardDesign.Spacing.elementGap) {
        WizardPageHeader(
          icon: "cpu.fill",
          title: "Kanata Engine Setup",
          subtitle: "Install and configure the Kanata keyboard remapping engine",
          status: .info
        )
        
        // Subtle refresh button
        HStack {
          Spacer()
          Button("Refresh Status") {
            Task {
              await onRefresh()
            }
          }
          .font(.caption)
          .foregroundColor(.secondary)
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
      }

      ScrollView {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
          // Static components that should be present
          InstallationItemView(
            title: "Kanata Binary",
            description: "Core keyboard remapping engine executable",
            status: componentStatus(for: "Kanata Binary")
          )

          // Dynamic issues from installation category that are Kanata-specific
          ForEach(kanataRelatedIssues, id: \.id) { issue in
            InstallationItemView(
              title: getComponentTitle(for: issue),
              description: getComponentDescription(for: issue),
              status: .failed,
              autoFixButton: issue.autoFixAction != nil
                ? {
                  let isThisIssueFixing = fixingIssues.contains(issue.id)
                  return AnyView(
                    WizardButton(
                      isThisIssueFixing ? "Fixing..." : "Fix",
                      style: .secondary,
                      isLoading: isThisIssueFixing
                    ) {
                      if let autoFixAction = issue.autoFixAction {
                        // Mark this specific issue as fixing
                        fixingIssues.insert(issue.id)

                        Task {
                          let success = await onAutoFix(autoFixAction)

                          // Remove this issue from fixing state
                          await MainActor.run {
                            fixingIssues.remove(issue.id)
                          }
                        }
                      }
                    }
                  )
                } : nil
            )
          }
        }
        .padding(.horizontal, 40)
      }

      Spacer()

      // Manual installation options if Kanata binary is missing
      if needsManualInstallation {
        VStack(spacing: WizardDesign.Spacing.elementGap) {
          Text("Kanata can be installed via Homebrew:")
            .font(WizardDesign.Typography.body)
            .foregroundColor(WizardDesign.Colors.secondaryText)

          HStack(spacing: WizardDesign.Spacing.itemGap) {
            Button("Install via Homebrew") {
              installViaHomebrew()
            }
            .buttonStyle(WizardDesign.Component.PrimaryButton())

            Button("Check Status") {
              Task {
                await onRefresh()
              }
            }
            .buttonStyle(WizardDesign.Component.SecondaryButton())
          }

          Text("Command: brew install kanata")
            .font(WizardDesign.Typography.caption)
            .foregroundColor(WizardDesign.Colors.secondaryText)
            .padding(.top, 4)
        }
        .padding(.bottom, WizardDesign.Spacing.pageVertical)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
  }

  // MARK: - Helper Methods

  private var kanataRelatedIssues: [WizardIssue] {
    issues.filter { issue in
      // Include installation issues related to Kanata
      if issue.category == .installation {
        switch issue.identifier {
        case .component(.kanataBinary),
          .component(.kanataService),
          .component(.packageManager):
          return true
        default:
          return false
        }
      }

      return false
    }
  }

  private func componentStatus(for componentName: String) -> InstallationStatus {
    // Check if there's an issue for this component
    let hasIssue = issues.contains { issue in
      issue.category == .installation && issue.title.contains(componentName)
    }

    return hasIssue ? .failed : .completed
  }

  private var needsManualInstallation: Bool {
    // Need manual installation if Kanata binary is missing
    issues.contains { issue in
      issue.identifier == .component(.kanataBinary)
    }
  }

  private func getComponentTitle(for issue: WizardIssue) -> String {
    switch issue.title {
    case "Kanata Binary Missing":
      return "Kanata Binary"
    case "Kanata Service Missing":
      return "Kanata Service Configuration"
    case "Package Manager Missing":
      return "Package Manager"
    default:
      return issue.title
    }
  }

  private func getComponentDescription(for issue: WizardIssue) -> String {
    switch issue.title {
    case "Kanata Binary Missing":
      return "The kanata executable needs to be installed (typically via Homebrew)"
    case "Kanata Service Missing":
      return "Service configuration files for running kanata in the background"
    case "Package Manager Missing":
      return "Homebrew or another package manager is needed to install kanata"
    default:
      return issue.description
    }
  }

  private func installViaHomebrew() {
    // Try to install via the auto-fix system first
    if let homebrewIssue = issues.first(where: { $0.autoFixAction == .installViaBrew }) {
      fixingIssues.insert(homebrewIssue.id)

      Task {
        let success = await onAutoFix(.installViaBrew)

        await MainActor.run {
          fixingIssues.remove(homebrewIssue.id)
        }
      }
    } else {
      // Fallback to opening Terminal with the command
      let script = """
        tell application "Terminal"
            activate
            do script "brew install kanata"
        end tell
        """

      if let appleScript = NSAppleScript(source: script) {
        appleScript.executeAndReturnError(nil)
      }
    }
  }
}
