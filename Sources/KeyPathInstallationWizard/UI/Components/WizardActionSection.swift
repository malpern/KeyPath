import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Simplified action section for the summary page
public struct WizardActionSection: View {
    public let systemState: WizardSystemState
    public let isFullyConfigured: Bool // True only when EVERYTHING including TCP is working
    public let onStartService: () -> Void
    public let onDismiss: () -> Void

    public init(
        systemState: WizardSystemState,
        isFullyConfigured: Bool,
        onStartService: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.systemState = systemState
        self.isFullyConfigured = isFullyConfigured
        self.onStartService = onStartService
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
            // Footer status indicator removed - header now communicates overall status

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
        .padding(.bottom, WizardDesign.Spacing.elementGap)
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
        // Summary footer text removed; overall status is communicated in the header.
        nil
    }

    @ViewBuilder
    private var actionButton: some View {
        // Only show "Close Setup" if EVERYTHING is fully configured
        if systemState == .active, isFullyConfigured {
            WizardButton("Close Setup", style: .primary, isDefaultAction: true) {
                onDismiss()
            }
        } else if isFullyConfigured, case .serviceNotRunning = systemState {
            WizardButton("Start KeyPath Runtime", style: .primary, isDefaultAction: true) {
                onStartService()
            }
        } else if isFullyConfigured, case .ready = systemState {
            WizardButton("Start KeyPath Runtime", style: .primary, isDefaultAction: true) {
                onStartService()
            }
        } else {
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
