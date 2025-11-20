import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Kanata binary and service setup page
struct WizardKanataComponentsPage: View {
  let systemState: WizardSystemState
  let issues: [WizardIssue]
  let isFixing: Bool
  let onAutoFix: (AutoFixAction) async -> Bool
  let onRefresh: () -> Void
  let kanataManager: KanataManager

  // Track which specific issues are being fixed
  @State private var fixingIssues: Set<UUID> = []
  @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

  var body: some View {
    VStack(spacing: 0) {
      // Use experimental hero design when engine is installed
      if kanataRelatedIssues.isEmpty, componentStatus(for: "Kanata Binary") == .completed {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
          WizardHeroSection.success(
            icon: "cpu.fill",
            title: "Kanata Engine Setup",
            subtitle:
              "Kanata binary is installed & configured for advanced keyboard remapping functionality"
          )

          // Component details card below the subheading - horizontally centered
          HStack {
            Spacer()
            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
              // Kanata Binary (always shown in success state)
              HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                HStack(spacing: 0) {
                  Text("Kanata Binary")
                    .font(.headline)
                    .fontWeight(.semibold)
                  Text(" - KeyPath's bundled & Developer ID signed version")
                    .font(.headline)
                    .fontWeight(.regular)
                }
              }

              // Kanata Service (if service is configured)
              if componentStatus(for: "Kanata Service") == .completed {
                HStack(spacing: 12) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                  HStack(spacing: 0) {
                    Text("Kanata Service")
                      .font(.headline)
                      .fontWeight(.semibold)
                    Text(" - System service configuration & management")
                      .font(.headline)
                      .fontWeight(.regular)
                  }
                }
              }
            }
            Spacer()
          }
          .frame(maxWidth: .infinity)
          .padding(WizardDesign.Spacing.cardPadding)
          .background(Color.clear, in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, WizardDesign.Spacing.pageVertical)
          .padding(.top, WizardDesign.Spacing.pageVertical)

          Button(nextStepButtonTitle) {
            navigateToNextStep()
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton())
          .padding(.top, WizardDesign.Spacing.sectionGap)
        }
        .heroSectionContainer()
        .frame(maxWidth: .infinity)
      } else {
        // Header for setup/error states with action link
        WizardHeroSection.warning(
          icon: "cpu.fill",
          title: "Kanata Engine Setup",
          subtitle: "Install and configure the Kanata keyboard remapping engine",
          iconTapAction: {
            Task {
              onRefresh()
            }
          }
        )

        // Component details for error/setup states
        if !(kanataRelatedIssues.isEmpty && componentStatus(for: "Kanata Binary") == .completed) {
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
                              // IMMEDIATE crash-proof logging for REAL Fix button click in Kanata page
                              Swift.print(
                                "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKanataComponentsPage for action: \(autoFixAction) at \(Date())"
                              )
                              try?
                                "*** IMMEDIATE DEBUG *** REAL Fix button clicked in WizardKanataComponentsPage for action: \(autoFixAction) at \(Date())\n"
                                .write(
                                  to: URL(
                                    fileURLWithPath: NSHomeDirectory()
                                      + "/kanata-fix-button-debug.txt"),
                                  atomically: true, encoding: .utf8
                                )

                              // Set service bounce flag before performing auto-fix
                              await MainActor.run {
                                PermissionGrantCoordinator.shared.setServiceBounceNeeded(
                                  reason: "Kanata engine fix - \(autoFixAction)")
                              }

                              _ = await onAutoFix(autoFixAction)

                              // Remove this issue from fixing state
                              _ = await MainActor.run {
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
            .padding(.bottom, WizardDesign.Spacing.pageVertical)
          }
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .fixedSize(horizontal: false, vertical: true)
    .background(WizardDesign.Colors.wizardBackground)
    .wizardDetailPage()
  }

  // MARK: - Helper Methods

  private var kanataRelatedIssues: [WizardIssue] {
    issues.filter { issue in
      // Include installation issues related to Kanata
      if issue.category == .installation {
        switch issue.identifier {
        case .component(.kanataBinaryMissing),
          .component(.kanataService):
          return true
        default:
          return false
        }
      }

      return false
    }
  }

  private func componentStatus(for componentName: String) -> InstallationStatus {
    // Use identifier-based checks instead of title substring matching
    switch componentName {
    case "Kanata Binary":
      let hasIssue = issues.contains { issue in
        if case .component(let component) = issue.identifier {
          return component == .kanataBinaryMissing
        }
        return false
      }
      return hasIssue ? .failed : .completed

    case "Kanata Service":
      let hasIssue = issues.contains { issue in
        if case .component(let component) = issue.identifier {
          return component == .kanataService
            || component == .launchDaemonServices
            || component == .launchDaemonServicesUnhealthy
        }
        return false
      }
      return hasIssue ? .failed : .completed

    default:
      // Fallback for any other potential component
      let hasIssue = issues.contains { issue in
        issue.category == .installation && issue.title.contains(componentName)
      }
      return hasIssue ? .failed : .completed
    }
  }

  private var needsManualInstallation: Bool {
    // Need manual installation if Kanata binary is missing
    issues.contains { issue in
      issue.identifier == .component(.kanataBinaryMissing)
    }
  }

  private func getComponentTitle(for issue: WizardIssue) -> String {
    // Use identifiers instead of stringly-typed title matching
    if case .component(let component) = issue.identifier {
      switch component {
      case .kanataBinaryMissing:
        return "Kanata Binary"
      case .kanataService:
        return "Kanata Service Configuration"
      default:
        return issue.title
      }
    }
    return issue.title
  }

  private func getComponentDescription(for issue: WizardIssue) -> String {
    // Use identifiers instead of stringly-typed title matching
    if case .component(let component) = issue.identifier {
      switch component {
      case .kanataBinaryMissing:
        return
          "Kanata binary is bundled with KeyPath and ready for use (SMAppService uses BundleProgram)"
      case .kanataService:
        return "Service configuration files for running kanata in the background"
      default:
        return issue.description
      }
    }
    return issue.description
  }

  private func installBundledKanata() {
    AppLogger.shared.log(
      "🔧 [WizardKanataComponentsPage] User requested bundled kanata installation")
    if let kanataIssue = issues.first(where: { $0.autoFixAction == .installBundledKanata }) {
      fixingIssues.insert(kanataIssue.id)

      Task {
        _ = await onAutoFix(.installBundledKanata)
        await kanataManager.updateStatus()

        await MainActor.run {
          _ = fixingIssues.remove(kanataIssue.id)
        }
      }
    }
  }

  private var nextStepButtonTitle: String {
    issues.isEmpty ? "Return to Summary" : "Next Issue"
  }

  private func navigateToNextStep() {
    if issues.isEmpty {
      navigationCoordinator.navigateToPage(.summary)
      return
    }

    if let nextPage = navigationCoordinator.getNextPage(for: systemState, issues: issues),
      nextPage != navigationCoordinator.currentPage
    {
      navigationCoordinator.navigateToPage(nextPage)
    } else {
      navigationCoordinator.navigateToPage(.summary)
    }
  }
}
