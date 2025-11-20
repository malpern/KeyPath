import SwiftUI

/// Standard wizard button bar following macOS HIG guidelines
/// Button order: Cancel (left) | Secondary (middle) | Primary (right)
struct WizardButtonBar: View {
  /// Cancel button configuration (leftmost)
  struct CancelButton {
    let title: String
    let action: () -> Void
    let isEnabled: Bool

    init(title: String = "Cancel", action: @escaping () -> Void, isEnabled: Bool = true) {
      self.title = title
      self.action = action
      self.isEnabled = isEnabled
    }
  }

  /// Secondary button configuration (middle)
  struct SecondaryButton {
    let title: String
    let action: () -> Void
    let isEnabled: Bool

    init(title: String, action: @escaping () -> Void, isEnabled: Bool = true) {
      self.title = title
      self.action = action
      self.isEnabled = isEnabled
    }
  }

  /// Primary button configuration (rightmost, default action)
  struct PrimaryButton {
    let title: String
    let action: () -> Void
    let isEnabled: Bool
    let isLoading: Bool
    let style: ButtonStyle

    enum ButtonStyle {
      case `default`
      case destructive
    }

    init(
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

  let cancelButton: CancelButton?
  let secondaryButton: SecondaryButton?
  let primaryButton: PrimaryButton?

  init(
    cancel: CancelButton? = nil,
    secondary: SecondaryButton? = nil,
    primary: PrimaryButton
  ) {
    cancelButton = cancel
    secondaryButton = secondary
    primaryButton = primary
  }

  var body: some View {
    HStack(spacing: WizardDesign.Spacing.itemGap) {
      // Cancel button (leftmost)
      if let cancelButton {
        Button(cancelButton.title) {
          cancelButton.action()
        }
        .buttonStyle(WizardDesign.Component.SecondaryButton())
        .keyboardShortcut(.cancelAction)  // Escape key
        .disabled(!cancelButton.isEnabled)
      }

      // Secondary button (middle)
      if let secondaryButton {
        Button(secondaryButton.title) {
          secondaryButton.action()
        }
        .buttonStyle(WizardDesign.Component.SecondaryButton())
        .disabled(!secondaryButton.isEnabled)
      }

      Spacer()

      // Primary button (rightmost, default action)
      if let primaryButton {
        if primaryButton.style == .destructive {
          Button(primaryButton.title) {
            primaryButton.action()
          }
          .buttonStyle(WizardDesign.Component.DestructiveButton(isLoading: primaryButton.isLoading))
          .keyboardShortcut(.defaultAction)  // Return key
          .disabled(!primaryButton.isEnabled || primaryButton.isLoading)
        } else {
          Button(primaryButton.title) {
            primaryButton.action()
          }
          .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: primaryButton.isLoading))
          .keyboardShortcut(.defaultAction)  // Return key
          .disabled(!primaryButton.isEnabled || primaryButton.isLoading)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
    .padding(.vertical, WizardDesign.Spacing.sectionGap)
  }
}

// MARK: - Convenience Initializers

extension WizardButtonBar {
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
