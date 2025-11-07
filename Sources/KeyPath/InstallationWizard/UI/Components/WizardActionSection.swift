import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Simplified action section for the summary page
struct WizardActionSection: View {
    let systemState: WizardSystemState
    let isFullyConfigured: Bool // True only when EVERYTHING including TCP is working
    let onStartService: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.itemGap) {
            // Status indicator (hidden in full success state)
            if !(systemState == .active && isFullyConfigured) {
                HStack(spacing: WizardDesign.Spacing.labelGap) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.system(size: 20))

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(WizardDesign.Typography.status)
                            .foregroundColor(statusColor)
                    }
                }
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
        // Check full configuration first - only show success if EVERYTHING is working
        if systemState == .active, isFullyConfigured {
            return "checkmark.circle.fill"
        }

        // If active but not fully configured, show warning
        if systemState == .active, !isFullyConfigured {
            return "exclamationmark.triangle.fill"
        }

        // Otherwise use systemState-based logic
        switch systemState {
        case .serviceNotRunning, .ready:
            return "exclamationmark.triangle.fill"
        case .conflictsDetected:
            return "exclamationmark.triangle.fill"
        default:
            return "gear.badge.xmark"
        }
    }

    private var statusColor: Color {
        // Check full configuration first - only show green if EVERYTHING is working
        if systemState == .active, isFullyConfigured {
            return WizardDesign.Colors.success
        }

        // If active but not fully configured, show warning
        if systemState == .active, !isFullyConfigured {
            return WizardDesign.Colors.warning
        }

        // Otherwise use systemState-based logic
        switch systemState {
        case .serviceNotRunning, .ready:
            return WizardDesign.Colors.warning
        case .conflictsDetected:
            return WizardDesign.Colors.error
        default:
            return WizardDesign.Colors.secondaryText
        }
    }

    private var statusMessage: String {
        // Check full configuration first - only show "Active" if EVERYTHING is working
        if systemState == .active, isFullyConfigured {
            // Redundant with top icon and system status - omit label
            return ""
        }

        // If active but not fully configured, show issues message
        if systemState == .active, !isFullyConfigured {
            return "Setup Issues Detected"
        }

        // Otherwise use systemState-based logic
        switch systemState {
        case .serviceNotRunning, .ready:
            return "Service Not Running"
        case .conflictsDetected:
            return "Conflicts Detected"
        default:
            return "Setup Incomplete"
        }
    }

    private var statusDescription: String? {
        // Check full configuration first
        if systemState == .active, isFullyConfigured {
            return nil // No description needed for success state
        }

        // If active but not fully configured, explain the issue
        if systemState == .active, !isFullyConfigured {
            return "Some components need attention. Review the status above."
        }

        // Otherwise use systemState-based logic
        switch systemState {
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
        // Only show "Close Setup" if EVERYTHING is fully configured
        if systemState == .active, isFullyConfigured {
            WizardButton("Close Setup", style: .primary) {
                onDismiss()
            }
        } else {
            // Handle other cases based on systemState
            switch systemState {
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
}

// MARK: - Preview

struct WizardActionSection_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            WizardActionSection(
                systemState: .active,
                isFullyConfigured: true,
                onStartService: {},
                onDismiss: {}
            )

            WizardActionSection(
                systemState: .serviceNotRunning,
                isFullyConfigured: false,
                onStartService: {},
                onDismiss: {}
            )

            WizardActionSection(
                systemState: .conflictsDetected(conflicts: []),
                isFullyConfigured: false,
                onStartService: {},
                onDismiss: {}
            )
        }
        .padding()
    }
}
