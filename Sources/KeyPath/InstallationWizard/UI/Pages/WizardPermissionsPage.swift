import SwiftUI

struct WizardPermissionsPage: View {
  enum PermissionType {
    case inputMonitoring
    case accessibility

    var title: String {
      switch self {
      case .inputMonitoring: return "Input Monitoring"
      case .accessibility: return "Accessibility"
      }
    }

    var description: String {
      switch self {
      case .inputMonitoring: return "Allow KeyPath to monitor keyboard input"
      case .accessibility: return "Allow KeyPath to control your computer"
      }
    }

    var icon: String {
      switch self {
      case .inputMonitoring: return "keyboard"
      case .accessibility: return "hand.raised.fill"
      }
    }
  }

  let permissionType: PermissionType
  let issues: [WizardIssue]
  let kanataManager: KanataManager

  @State private var showingDetails = false
  @State private var showingHelp = false

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.sectionGap) {
      // Header using design system
      WizardPageHeader(
        icon: permissionType.icon,
        title: permissionType.title,
        subtitle: permissionType.description,
        status: .info
      )

      // Permission Status Cards
      VStack(spacing: WizardDesign.Spacing.itemGap) {
        permissionCards()
      }
      .wizardPagePadding()

      // Permission status is shown via the cards above - no need to duplicate as issues

      Spacer()

      // Action Section using design system
      VStack(spacing: WizardDesign.Spacing.elementGap) {
        if allPermissionsGranted {
          HStack(spacing: WizardDesign.Spacing.labelGap) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(WizardDesign.Colors.success)
              .font(WizardDesign.Typography.body)
            Text("Permissions granted")
              .font(WizardDesign.Typography.status)
          }
          .foregroundColor(WizardDesign.Colors.secondaryText)
        } else {
          Button("Open \(permissionType.title) Settings") {
            openSettings()
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton())
        }

        HStack(spacing: WizardDesign.Spacing.itemGap) {
          Button("Show Details") {
            showingDetails.toggle()
          }
          .buttonStyle(.link)

          Button("Help") {
            showingHelp = true
          }
          .buttonStyle(.link)
        }
      }
      .padding(.bottom, WizardDesign.Spacing.pageVertical)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(WizardDesign.Colors.wizardBackground)
    .sheet(isPresented: $showingDetails) {
      PermissionDetailsSheet(kanataManager: kanataManager)
    }
    .sheet(isPresented: $showingHelp) {
      switch permissionType {
      case .inputMonitoring:
        InputMonitoringHelpSheet(kanataManager: kanataManager)
      case .accessibility:
        AccessibilityHelpSheet(kanataManager: kanataManager)
      }
    }
  }

  @ViewBuilder
  private func permissionCards() -> some View {
    switch permissionType {
    case .inputMonitoring:
      PermissionCard(
        appName: "KeyPath.app",
        appPath: Bundle.main.bundlePath,
        status: keyPathInputMonitoringStatus,
        permissionType: "Input Monitoring"
      )

      PermissionCard(
        appName: "kanata",
        appPath: WizardSystemPaths.kanataBinaryDefault,
        status: kanataInputMonitoringStatus,
        permissionType: "Input Monitoring"
      )

    case .accessibility:
      PermissionCard(
        appName: "KeyPath.app",
        appPath: Bundle.main.bundlePath,
        status: keyPathAccessibilityStatus,
        permissionType: "Accessibility"
      )

      PermissionCard(
        appName: "kanata",
        appPath: WizardSystemPaths.kanataBinaryDefault,
        status: kanataAccessibilityStatus,
        permissionType: "Accessibility"
      )
    }
  }

  // MARK: - Permission Status Computation

  private var keyPathInputMonitoringStatus: InstallationStatus {
    // For Input Monitoring page, check only Input Monitoring permission
    kanataManager.hasInputMonitoringPermission() ? .completed : .notStarted
  }

  private var kanataInputMonitoringStatus: InstallationStatus {
    // Check kanata's Input Monitoring permission specifically
    let kanataHasInputMonitoring = kanataManager.checkTCCForInputMonitoring(
      path: WizardSystemPaths.kanataBinaryDefault)
    return kanataHasInputMonitoring ? .completed : .notStarted
  }

  private var keyPathAccessibilityStatus: InstallationStatus {
    // Check KeyPath's Accessibility permission specifically
    kanataManager.hasAccessibilityPermission() ? .completed : .notStarted
  }

  private var kanataAccessibilityStatus: InstallationStatus {
    // Check kanata's Accessibility permission specifically
    let kanataAccessibility = kanataManager.checkAccessibilityForPath(
      WizardSystemPaths.kanataBinaryDefault)
    return kanataAccessibility ? .completed : .notStarted
  }

  private var allPermissionsGranted: Bool {
    // Use helper method to check for relevant permission issues
    return !hasRelevantPermissionIssues()
  }

  /// Helper method to check for permission issues relevant to the current page
  private func hasRelevantPermissionIssues() -> Bool {
    return issues.contains { issue in
      guard issue.category == .permissions else { return false }

      switch permissionType {
      case .inputMonitoring:
        return issue.title == "Kanata Input Monitoring"
      case .accessibility:
        return issue.title == "Kanata Accessibility"
      }
    }
  }

  private func openSettings() {
    switch permissionType {
    case .inputMonitoring:
      // Press Escape to close wizard for Input Monitoring
      let escapeEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: NSPoint.zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
      )

      if let event = escapeEvent {
        NSApplication.shared.postEvent(event, atStart: false)
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        kanataManager.openInputMonitoringSettings()
      }

    case .accessibility:
      // For Accessibility, open settings immediately without closing wizard
      kanataManager.openAccessibilitySettings()
    }
  }
}
