import SwiftUI

/// Manages toast notifications for the installation wizard
/// Provides temporary feedback for user actions like auto-fix operations
@MainActor
class WizardToastManager: ObservableObject {
  @Published var currentToast: WizardToast?

  private var toastTask: Task<Void, Never>?

  /// Show a success toast notification
  func showSuccess(_ message: String, duration: TimeInterval = 3.0) {
    showToast(.success(message), duration: duration)
  }

  /// Show an error toast notification
  func showError(_ message: String, duration: TimeInterval = 4.0) {
    showToast(.error(message), duration: duration)
  }

  /// Show an info toast notification
  func showInfo(_ message: String, duration: TimeInterval = 3.0) {
    showToast(.info(message), duration: duration)
  }

  /// Dismiss the current toast immediately
  func dismissToast() {
    toastTask?.cancel()
    currentToast = nil
  }

  private func showToast(_ toast: WizardToast, duration: TimeInterval) {
    // Cancel any existing toast
    toastTask?.cancel()

    // Show new toast
    currentToast = toast

    // Auto-dismiss after duration
    toastTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

      guard !Task.isCancelled else { return }
      currentToast = nil
    }
  }
}

/// Represents different types of toast notifications
enum WizardToast: Equatable {
  case success(String)
  case error(String)
  case info(String)

  var message: String {
    switch self {
    case let .success(message), let .error(message), let .info(message):
      return message
    }
  }

  var icon: String {
    switch self {
    case .success: return "checkmark.circle.fill"
    case .error: return "exclamationmark.triangle.fill"
    case .info: return "info.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .success: return .green
    case .error: return .red
    case .info: return .blue
    }
  }
}

/// Toast notification view component
struct WizardToastView: View {
  let toast: WizardToast
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: toast.icon)
        .foregroundColor(toast.color)
        .font(.system(size: 16, weight: .medium))

      Text(toast.message)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss notification")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(.regularMaterial)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(toast.color.opacity(0.3), lineWidth: 1)
    }
    .frame(maxWidth: 400)
    .transition(
      .asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
      ))
  }
}

/// View modifier to add toast support to any view
struct ToastModifier: ViewModifier {
  @ObservedObject var toastManager: WizardToastManager

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let toast = toastManager.currentToast {
          WizardToastView(toast: toast) {
            toastManager.dismissToast()
          }
          .padding(.top, 16)
          .padding(.horizontal, 20)
          .zIndex(1000)
          .animation(.spring(response: 0.5, dampingFraction: 0.8), value: toastManager.currentToast)
        }
      }
  }
}

extension View {
  /// Add toast notification support to a view
  func withToasts(_ toastManager: WizardToastManager) -> some View {
    modifier(ToastModifier(toastManager: toastManager))
  }
}
