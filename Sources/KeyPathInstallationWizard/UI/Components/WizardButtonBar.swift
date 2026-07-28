import SwiftUI

/// Standard wizard button bar following macOS HIG guidelines
/// Button order: Cancel (left) | Secondary (middle) | Primary (right)
public struct WizardButtonBar: View {
    public enum SecondaryPlacement: Equatable {
        /// Keep the secondary action beside Cancel for existing wizard screens.
        case leading
        /// Group Back with the primary action at the trailing edge.
        case trailing
    }

    /// Cancel button configuration (leftmost)
    public struct CancelButton {
        public let title: String
        public let action: () -> Void
        public let isEnabled: Bool
        /// Whether Escape activates this button. Disable when Escape is part of the interaction being taught.
        public let usesCancelShortcut: Bool

        public init(
            title: String = "Cancel",
            action: @escaping () -> Void,
            isEnabled: Bool = true,
            usesCancelShortcut: Bool = true
        ) {
            self.title = title
            self.action = action
            self.isEnabled = isEnabled
            self.usesCancelShortcut = usesCancelShortcut
        }
    }

    /// Secondary button configuration (middle)
    public struct SecondaryButton {
        public let title: String
        public let action: () -> Void
        public let isEnabled: Bool

        public init(title: String, action: @escaping () -> Void, isEnabled: Bool = true) {
            self.title = title
            self.action = action
            self.isEnabled = isEnabled
        }
    }

    /// Primary button configuration (rightmost, default action)
    public struct PrimaryButton {
        public let title: String
        public let action: () -> Void
        public let isEnabled: Bool
        public let isLoading: Bool
        public let style: ButtonStyle

        public enum ButtonStyle {
            case `default`
            case destructive
        }

        public init(
            title: String, action: @escaping () -> Void, isEnabled: Bool = true, isLoading: Bool = false,
            style: ButtonStyle = .default
        ) {
            self.title = title
            self.action = action
            self.isEnabled = isEnabled
            self.isLoading = isLoading
            self.style = style
        }
    }

    public let cancelButton: CancelButton?
    public let secondaryButton: SecondaryButton?
    public let primaryButton: PrimaryButton?
    public let secondaryPlacement: SecondaryPlacement

    public init(
        cancel: CancelButton? = nil,
        secondary: SecondaryButton? = nil,
        primary: PrimaryButton,
        secondaryPlacement: SecondaryPlacement = .leading
    ) {
        cancelButton = cancel
        secondaryButton = secondary
        primaryButton = primary
        self.secondaryPlacement = secondaryPlacement
    }

    public var body: some View {
        HStack(spacing: WizardDesign.Spacing.itemGap) {
            // Cancel button (leftmost)
            if let cancelButton {
                Button(cancelButton.title) {
                    cancelButton.action()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .keyboardShortcut(cancelButton.usesCancelShortcut ? .cancelAction : nil)
                .disabled(!cancelButton.isEnabled)
                .accessibilityIdentifier("wizard-cancel-button")
            }

            // Secondary button (middle)
            if let secondaryButton, secondaryPlacement == .leading {
                Button(secondaryButton.title) {
                    secondaryButton.action()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(!secondaryButton.isEnabled)
                .accessibilityIdentifier("wizard-secondary-button")
            }

            Spacer()

            if let secondaryButton, secondaryPlacement == .trailing {
                Button(secondaryButton.title) {
                    secondaryButton.action()
                }
                .buttonStyle(WizardDesign.Component.SecondaryButton())
                .disabled(!secondaryButton.isEnabled)
                .accessibilityIdentifier("wizard-secondary-button")
            }

            // Primary button (rightmost, default action)
            if let primaryButton {
                if primaryButton.style == .destructive {
                    Button(primaryButton.title) {
                        primaryButton.action()
                    }
                    .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: primaryButton.isLoading))
                    .keyboardShortcut(.defaultAction) // Return key
                    .disabled(!primaryButton.isEnabled || primaryButton.isLoading)
                    .accessibilityIdentifier("wizard-primary-button")
                } else {
                    Button(primaryButton.title) {
                        primaryButton.action()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: primaryButton.isLoading))
                    .keyboardShortcut(.defaultAction) // Return key
                    .disabled(!primaryButton.isEnabled || primaryButton.isLoading)
                    .accessibilityIdentifier("wizard-primary-button")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, WizardDesign.Spacing.pageVertical)
        .padding(.vertical, WizardDesign.Spacing.sectionGap)
    }
}

// MARK: - Convenience Initializers

public extension WizardButtonBar {
    /// Single primary button (most common case)
    static func primaryOnly(title: String, action: @escaping () -> Void, isLoading: Bool = false)
        -> WizardButtonBar
    {
        WizardButtonBar(
            primary: PrimaryButton(title: title, action: action, isLoading: isLoading)
        )
    }

    /// Primary + Cancel (common case)
    static func primaryAndCancel(
        primaryTitle: String, primaryAction: @escaping () -> Void, cancelTitle: String = "Cancel",
        cancelAction: @escaping () -> Void,
        isLoading: Bool = false
    ) -> WizardButtonBar {
        WizardButtonBar(
            cancel: CancelButton(title: cancelTitle, action: cancelAction),
            primary: PrimaryButton(title: primaryTitle, action: primaryAction, isLoading: isLoading)
        )
    }

    /// Primary + Secondary + Cancel (full set)
    static func full(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void,
        cancelTitle: String = "Cancel",
        cancelAction: @escaping () -> Void,
        isLoading: Bool = false
    ) -> WizardButtonBar {
        WizardButtonBar(
            cancel: CancelButton(title: cancelTitle, action: cancelAction),
            secondary: SecondaryButton(title: secondaryTitle, action: secondaryAction),
            primary: PrimaryButton(title: primaryTitle, action: primaryAction, isLoading: isLoading)
        )
    }
}
