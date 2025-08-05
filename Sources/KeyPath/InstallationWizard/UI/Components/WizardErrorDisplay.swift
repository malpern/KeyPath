import SwiftUI

/// A user-friendly error display component that shows helpful recovery actions
struct WizardErrorDisplay: View {
  let error: WizardError
  let onRetry: (() -> Void)?
  let onDismiss: (() -> Void)?
  
  init(error: WizardError, onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
    self.error = error
    self.onRetry = onRetry
    self.onDismiss = onDismiss
  }
  
  var body: some View {
    VStack(spacing: WizardDesign.Spacing.itemGap) {
      // Error icon and message
      VStack(spacing: WizardDesign.Spacing.elementGap) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 32))
          .foregroundColor(WizardDesign.Colors.error)
        
        Text(error.userMessage)
          .font(WizardDesign.Typography.body)
          .multilineTextAlignment(.center)
          .foregroundColor(.primary)
      }
      
      // Recovery suggestions
      if !error.recoveryActions.isEmpty {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
          Text("Here's how to fix this:")
            .font(WizardDesign.Typography.subsectionTitle)
            .foregroundColor(.primary)
          
          VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
            ForEach(Array(error.recoveryActions.enumerated()), id: \.offset) { index, action in
              HStack(alignment: .top, spacing: WizardDesign.Spacing.labelGap) {
                // Step number
                Text("\(index + 1).")
                  .font(.system(size: 14, weight: .medium, design: .monospaced))
                  .foregroundColor(WizardDesign.Colors.info)
                  .frame(width: 20, alignment: .leading)
                
                // Step description
                Text(action)
                  .font(.system(size: 14))
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.leading)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          .padding(.leading, WizardDesign.Spacing.elementGap)
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(WizardDesign.Colors.info.opacity(0.05))
        .cornerRadius(8)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(WizardDesign.Colors.info.opacity(0.2), lineWidth: 1)
        )
      }
      
      // Action buttons
      HStack(spacing: WizardDesign.Spacing.elementGap) {
        if let onDismiss = onDismiss {
          WizardButton("Dismiss", style: .secondary) {
            onDismiss()
          }
        }
        
        if let onRetry = onRetry {
          WizardButton("Try Again", style: .primary) {
            onRetry()
          }
        }
      }
    }
    .wizardCard()
    .wizardContentSpacing()
  }
}

/// Toast-style error notification for non-blocking errors
struct WizardErrorToast: View {
  let error: WizardError
  let isVisible: Bool
  let onDismiss: () -> Void
  
  var body: some View {
    HStack(spacing: WizardDesign.Spacing.elementGap) {
      // Error icon
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 16))
        .foregroundColor(WizardDesign.Colors.error)
      
      // Error message
      VStack(alignment: .leading, spacing: 4) {
        Text(error.userMessage)
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.primary)
          .multilineTextAlignment(.leading)
        
        if let firstAction = error.recoveryActions.first {
          Text(firstAction)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
        }
      }
      
      Spacer()
      
      // Dismiss button
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(WizardDesign.Spacing.cardPadding)
    .background(.regularMaterial)
    .cornerRadius(8)
    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    .opacity(isVisible ? 1.0 : 0.0)
    .scaleEffect(isVisible ? 1.0 : 0.8)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
  }
}

/// Error banner for page-level errors
struct WizardErrorBanner: View {
  let error: WizardError
  let onRetry: (() -> Void)?
  
  var body: some View {
    HStack(spacing: WizardDesign.Spacing.elementGap) {
      // Error icon
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 20))
        .foregroundColor(WizardDesign.Colors.error)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(error.userMessage)
          .font(WizardDesign.Typography.status)
          .foregroundColor(.primary)
        
        if let suggestion = error.recoverySuggestion {
          Text(suggestion)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(2)
        }
      }
      
      Spacer()
      
      if let onRetry = onRetry {
        Button("Retry") {
          onRetry()
        }
        .buttonStyle(WizardDesign.Component.SecondaryButton())
      }
    }
    .padding(WizardDesign.Spacing.cardPadding)
    .background(WizardDesign.Colors.error.opacity(0.05))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(WizardDesign.Colors.error.opacity(0.3), lineWidth: 1)
    )
  }
}

// MARK: - Preview

struct WizardErrorDisplay_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 20) {
      WizardErrorDisplay(
        error: WizardError(
          operation: "Auto Fix: Install Missing Components",
          underlying: nil,
          userMessage: "Failed to install required keyboard remapping components",
          recoveryActions: [
            "Check your internet connection",
            "Make sure you have administrator privileges",
            "Try installing Kanata manually using: brew install kanata"
          ]
        ),
        onRetry: {},
        onDismiss: {}
      )
      
      WizardErrorBanner(
        error: WizardError(
          operation: "System State Detection",
          underlying: nil,
          userMessage: "Unable to check your system's current setup",
          recoveryActions: ["Try closing and reopening KeyPath"]
        ),
        onRetry: {}
      )
      
      WizardErrorToast(
        error: WizardError(
          operation: "Auto Fix: Start Service",
          underlying: nil,
          userMessage: "The keyboard service won't start",
          recoveryActions: ["Grant necessary permissions in System Preferences"]
        ),
        isVisible: true,
        onDismiss: {}
      )
    }
    .padding()
  }
}