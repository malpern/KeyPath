import SwiftUI

/// Simplified action section for the summary page
struct WizardActionSection: View {
  let systemState: WizardSystemState
  let onStartService: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: WizardDesign.Spacing.itemGap) {
      // Status indicator
      HStack(spacing: WizardDesign.Spacing.labelGap) {
        Image(systemName: statusIcon)
          .foregroundColor(statusColor)
          .font(.system(size: 20))

        Text(statusMessage)
          .font(WizardDesign.Typography.status)
          .foregroundColor(statusColor)
      }

      // Description text (if needed)
      if let description = statusDescription {
        Text(description)
          .font(WizardDesign.Typography.caption)
          .foregroundColor(WizardDesign.Colors.secondaryText)
          .multilineTextAlignment(.center)
      }

      // Action button
      actionButton
    }
    .padding(.bottom, WizardDesign.Spacing.pageVertical)
  }

  // MARK: - Status Properties

  private var statusIcon: String {
    switch systemState {
    case .active:
      return "checkmark.circle.fill"
    case .serviceNotRunning, .ready:
      return "exclamationmark.triangle.fill"
    case .conflictsDetected:
      return "exclamationmark.triangle.fill"
    default:
      return "gear.badge.xmark"
    }
  }

  private var statusColor: Color {
    switch systemState {
    case .active:
      return WizardDesign.Colors.success
    case .serviceNotRunning, .ready:
      return WizardDesign.Colors.warning
    case .conflictsDetected:
      return WizardDesign.Colors.error
    default:
      return WizardDesign.Colors.secondaryText
    }
  }

  private var statusMessage: String {
    switch systemState {
    case .active:
      return "KeyPath is Active"
    case .serviceNotRunning, .ready:
      return "Service Not Running"
    case .conflictsDetected:
      return "Conflicts Detected"
    default:
      return "Setup Incomplete"
    }
  }

  private var statusDescription: String? {
    switch systemState {
    case .active:
      return nil  // No description needed for success state
    case .serviceNotRunning, .ready:
      return "All components are installed but the Kanata service is not active."
    case .conflictsDetected:
      return "Please resolve conflicts to continue."
    default:
      return "Complete the setup process to start using KeyPath"
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    switch systemState {
    case .active:
      WizardButton("Close Setup", style: .primary) {
        onDismiss()
      }

    case .serviceNotRunning, .ready:
      WizardButton("Start Kanata Service", style: .primary) {
        onStartService()
      }

    case .conflictsDetected:
      // No action button for conflicts - user needs to navigate to conflicts page
      EmptyView()

    default:
      // No action button for incomplete setup - user needs to complete steps
      EmptyView()
    }
  }
}

// MARK: - Preview

struct WizardActionSection_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 40) {
      WizardActionSection(
        systemState: .active,
        onStartService: {},
        onDismiss: {}
      )

      WizardActionSection(
        systemState: .serviceNotRunning,
        onStartService: {},
        onDismiss: {}
      )

      WizardActionSection(
        systemState: .conflictsDetected(conflicts: []),
        onStartService: {},
        onDismiss: {}
      )
    }
    .padding()
  }
}
