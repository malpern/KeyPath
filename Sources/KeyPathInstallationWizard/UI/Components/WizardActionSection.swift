import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Simplified action section for the summary page
public struct WizardActionSection: View {
    public let systemState: WizardSystemState
    public let isFullyConfigured: Bool
    public let navSequence: [WizardPage]
    public let onStartService: () -> Void
    public let onDismiss: () -> Void
    public let onNavigateToPage: ((WizardPage) -> Void)?

    public init(
        systemState: WizardSystemState,
        isFullyConfigured: Bool,
        navSequence: [WizardPage] = [],
        onStartService: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onNavigateToPage: ((WizardPage) -> Void)? = nil
    ) {
        self.systemState = systemState
        self.isFullyConfigured = isFullyConfigured
        self.navSequence = navSequence
        self.onStartService = onStartService
        self.onDismiss = onDismiss
        self.onNavigateToPage = onNavigateToPage
    }

    public var body: some View {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
            if let description = statusDescription {
                Text(description)
                    .font(WizardDesign.Typography.body)
                    .foregroundStyle(WizardDesign.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            actionButton
        }
    }

    private var statusDescription: String? {
        nil
    }

    @ViewBuilder
    private var actionButton: some View {
        if systemState == .active, isFullyConfigured {
            WizardButton("Close Setup", style: .primary, isDefaultAction: true) {
                onDismiss()
            }
        } else if let firstPage = navSequence.first, let navigate = onNavigateToPage {
            WizardButton(buttonLabel(for: firstPage), style: .primary, isDefaultAction: true) {
                navigate(firstPage)
            }
        } else if case .serviceNotRunning = systemState {
            WizardButton("Start KeyPath Runtime", style: .primary, isDefaultAction: true) {
                onStartService()
            }
        } else if case .ready = systemState {
            WizardButton("Start KeyPath Runtime", style: .primary, isDefaultAction: true) {
                onStartService()
            }
        } else {
            EmptyView()
        }
    }

    private func buttonLabel(for page: WizardPage) -> String {
        switch page {
        case .inputMonitoring:
            "Fix Input Monitoring"
        case .accessibility:
            "Fix Accessibility"
        case .service:
            "Start KeyPath Runtime"
        case .helper:
            "Install Helper"
        case .conflicts:
            "Resolve Conflicts"
        case .karabinerComponents:
            "Fix Components"
        default:
            "Continue Setup"
        }
    }
}
