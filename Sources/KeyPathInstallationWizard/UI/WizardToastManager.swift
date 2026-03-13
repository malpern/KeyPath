import KeyPathCore
import KeyPathWizardCore
import Observation
import SwiftUI

/// Manages toast notifications for the installation wizard
/// Provides temporary feedback for user actions like auto-fix operations
@Observable
@MainActor
public class WizardToastManager: ToastPresenting {
    public var currentToast: WizardToast?

    private var toastTask: Task<Void, Never>?

    public init() {}

    /// Show a success toast notification
    public func showSuccess(_ message: String, duration: TimeInterval = WizardDesign.Toast.Duration.info) {
        showToast(.success(message), duration: duration)
    }

    /// Show an error toast notification
    public func showError(_ message: String, duration: TimeInterval = WizardDesign.Toast.Duration.error) {
        showToast(.error(message), duration: duration)
    }

    /// Show an info toast notification
    public func showInfo(_ message: String, duration: TimeInterval = WizardDesign.Toast.Duration.info) {
        showToast(.info(message), duration: duration)
    }

    /// Show a launch failure toast notification
    public func showLaunchFailure(
        _ status: LaunchFailureStatus,
        duration: TimeInterval = WizardDesign.Toast.Duration.launchFailure
    ) {
        showToast(makeActionableToast(from: status), duration: duration)
    }

    /// Maps LaunchFailureStatus to actionable toast (UI layer mapping)
    private func makeActionableToast(from status: LaunchFailureStatus) -> WizardToast {
        let message = status.shortMessage
        let actionTitle = WizardConstants.Actions.fixInSetup

        switch status {
        case .permissionDenied:
            return .actionable(
                message: message, icon: "lock.circle", style: .warning, actionTitle: actionTitle
            )
        case .configError:
            return .actionable(
                message: message, icon: "exclamationmark.triangle", style: .error, actionTitle: actionTitle
            )
        case .serviceFailure:
            return .actionable(
                message: message, icon: "gear.badge.xmark", style: .error, actionTitle: actionTitle
            )
        case .missingDependency:
            return .actionable(
                message: message, icon: "minus.circle", style: .info, actionTitle: actionTitle
            )
        }
    }

    /// Dismiss the current toast immediately
    public func dismissToast() {
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
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                _ = await WizardSleep.ms(100) // 100ms tick, cancellable
            }
            guard !Task.isCancelled else { return }
            currentToast = nil
        }
    }
}

/// Toast style for consistent theming
public enum ToastStyle: Equatable {
    case success
    case error
    case info
    case warning
}

/// Represents different types of toast notifications
public enum WizardToast: Equatable {
    case success(String)
    case error(String)
    case info(String)
    case actionable(message: String, icon: String, style: ToastStyle, actionTitle: String)

    public var message: String {
        switch self {
        case let .success(message), let .error(message), let .info(message):
            message
        case let .actionable(message, _, _, _):
            message
        }
    }

    public var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case let .actionable(_, icon, _, _): icon
        }
    }

    public var style: ToastStyle {
        switch self {
        case .success: .success
        case .error: .error
        case .info: .info
        case let .actionable(_, _, style, _): style
        }
    }

    public var color: Color {
        switch style {
        case .success: WizardDesign.Colors.success
        case .error: WizardDesign.Colors.error
        case .info: WizardDesign.Colors.info
        case .warning: WizardDesign.Colors.warning
        }
    }

    public var actionTitle: String? {
        switch self {
        case .success, .error, .info: nil
        case let .actionable(_, _, _, actionTitle): actionTitle
        }
    }
}

/// Toast notification view component
public struct WizardToastView: View {
    public let toast: WizardToast
    public let onDismiss: () -> Void
    public let onAction: (() -> Void)?

    @State private var isVisible = false

    public init(toast: WizardToast, onDismiss: @escaping () -> Void, onAction: (() -> Void)? = nil) {
        self.toast = toast
        self.onDismiss = onDismiss
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Icon with adaptive circle background
                ZStack {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor)) // Adapts to dark mode
                        .frame(width: 16, height: 16)
                    Image(systemName: toast.icon)
                        .foregroundColor(toast.color)
                        .font(.headline.weight(.medium))
                }

                Text(toast.message)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }

            // Action button for actionable toasts
            if let actionTitle = toast.actionTitle, let action = onAction {
                HStack {
                    Spacer()
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                }
            }
        }
        .padding(.horizontal, WizardDesign.Spacing.cardPadding)
        .padding(.vertical, WizardDesign.Spacing.itemGap)
        .wizardToastCard()
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            withAnimation {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            )
        )
    }
}

/// View modifier to add toast support to any view
public struct ToastModifier: ViewModifier {
    @Bindable public var toastManager: WizardToastManager
    public let onToastAction: (() -> Void)?

    public init(toastManager: WizardToastManager, onToastAction: (() -> Void)? = nil) {
        self.toastManager = toastManager
        self.onToastAction = onToastAction
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    WizardToastView(
                        toast: toast,
                        onDismiss: {
                            toastManager.dismissToast()
                        },
                        onAction: onToastAction
                    )
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
    public func withToasts(_ toastManager: WizardToastManager, onToastAction: (() -> Void)? = nil)
        -> some View
    {
        modifier(ToastModifier(toastManager: toastManager, onToastAction: onToastAction))
    }
}
