import AppKit
import SwiftUI

/// Small status indicator that shows system validation state in the top-right corner
///
/// Displays:
/// - Spinning gear while checking
/// - Green checkmark when all systems are good
/// - Red X when critical issues are detected
/// - Click handler to open full wizard
struct SystemStatusIndicator: View {
    @ObservedObject var validator: StartupValidator
    @Binding var showingWizard: Bool
    var onClick: (() -> Void)?

    @State private var isAnimating: Bool = false
    @State private var isHovered: Bool = false

    // MARK: - Constants

    private let indicatorSize: CGFloat = 20
    private let backgroundSize: CGFloat = 28

    var body: some View {
        Button(action: handleClick) {
            ZStack {
                // Background circle with subtle shadow
                Circle()
                    .fill(backgroundColor.opacity(0.8))
                    .frame(width: backgroundSize, height: backgroundSize)
                    .shadow(
                        color: shadowColor,
                        radius: isHovered ? 3 : 1,
                        x: 0,
                        y: 1
                    )
                    .overlay(
                        Circle()
                            .stroke(borderColor, lineWidth: 1)
                    )

                // Status icon
                iconView()
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
            }
        }
        .buttonStyle(.plain)
        .help(validator.statusTooltip)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Click to open system setup wizard")
    }

    // MARK: - Icon View

    @ViewBuilder
    private func iconView() -> some View {
        switch validator.validationState {
        case .checking:
            Image(systemName: "gear")
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: isAnimating)
                .onAppear { isAnimating = true }
                .onDisappear { isAnimating = false }
        case .success:
            Image(systemName: "checkmark")
        case let .failed(blockingCount, _):
            if blockingCount > 0 {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: "exclamationmark")
            }
        }
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        switch validator.validationState {
        case .checking:
            Color.blue.opacity(0.1)
        case .success:
            Color.green.opacity(0.1)
        case let .failed(blockingCount, _):
            blockingCount > 0 ? Color.red.opacity(0.1) : Color.orange.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch validator.validationState {
        case .checking:
            Color.blue.opacity(0.3)
        case .success:
            Color.green.opacity(0.3)
        case let .failed(blockingCount, _):
            blockingCount > 0 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3)
        }
    }

    private var iconColor: Color {
        switch validator.validationState {
        case .checking:
            .blue
        case .success:
            .green
        case let .failed(blockingCount, _):
            blockingCount > 0 ? .red : .orange
        }
    }

    private var shadowColor: Color {
        switch validator.validationState {
        case .checking:
            Color.blue.opacity(0.2)
        case .success:
            Color.green.opacity(0.2)
        case let .failed(blockingCount, _):
            blockingCount > 0 ? Color.red.opacity(0.2) : Color.orange.opacity(0.2)
        }
    }

    private var accessibilityLabel: String {
        switch validator.validationState {
        case .checking:
            "System status checking"
        case .success:
            "System status good"
        case let .failed(blockingCount, _):
            blockingCount > 0 ? "System has critical issues" : "System has warnings"
        }
    }

    // MARK: - Actions

    private func handleClick() {
        AppLogger.shared.log("🎯 [SystemStatusIndicator] Status indicator clicked")

        // Provide haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )

        // Open the wizard
        showingWizard = true

        // Call optional onClick callback
        onClick?()

        // Log the current state for debugging
        switch validator.validationState {
        case .checking:
            AppLogger.shared.log("🔍 [SystemStatusIndicator] Opening wizard while validation in progress")
        case .success:
            AppLogger.shared.log("✅ [SystemStatusIndicator] Opening wizard despite healthy system")
        case let .failed(blockingCount, totalCount):
            AppLogger.shared.log("❌ [SystemStatusIndicator] Opening wizard due to \(blockingCount) blocking issues out of \(totalCount) total")
        }
    }
}

// MARK: - Header Integration View

/// A view that integrates the system status indicator into the ContentView header
struct ContentViewSystemStatus: View {
    @ObservedObject var validator: StartupValidator
    @Binding var showingWizard: Bool

    var body: some View {
        SystemStatusIndicator(
            validator: validator,
            showingWizard: $showingWizard
        )
        .padding(.trailing, 4) // Small margin from edge
    }
}

// MARK: - Preview

struct SystemStatusIndicator_Previews: PreviewProvider {
    static var previews: some View {
        let validatorChecking = StartupValidator()
        validatorChecking.validationState = .checking

        let validatorSuccess = StartupValidator()
        validatorSuccess.validationState = .success

        let validatorFailed = StartupValidator()
        validatorFailed.validationState = .failed(blockingCount: 2, totalCount: 4)

        let validatorWarnings = StartupValidator()
        validatorWarnings.validationState = .failed(blockingCount: 0, totalCount: 2)

        return VStack(spacing: 20) {
            HStack(spacing: 20) {
                VStack {
                    Text("Checking")
                        .font(.caption)
                    SystemStatusIndicator(
                        validator: validatorChecking,
                        showingWizard: .constant(false)
                    )
                }

                VStack {
                    Text("Success")
                        .font(.caption)
                    SystemStatusIndicator(
                        validator: validatorSuccess,
                        showingWizard: .constant(false)
                    )
                }

                VStack {
                    Text("Failed")
                        .font(.caption)
                    SystemStatusIndicator(
                        validator: validatorFailed,
                        showingWizard: .constant(false)
                    )
                }

                VStack {
                    Text("Warnings")
                        .font(.caption)
                    SystemStatusIndicator(
                        validator: validatorWarnings,
                        showingWizard: .constant(false)
                    )
                }
            }

            // Example header integration
            HStack {
                Text("KeyPath")
                    .font(.title2)
                    .fontWeight(.medium)

                Spacer()

                ContentViewSystemStatus(
                    validator: validatorSuccess,
                    showingWizard: .constant(false)
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
        .padding()
        .frame(width: 400)
    }
}
