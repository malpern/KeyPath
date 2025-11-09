import AppKit
import KeyPathCore
import SwiftUI

/// Small status indicator that shows system validation state in the top-right corner
///
/// Displays:
/// - Spinning gear while checking
/// - Green checkmark when all systems are good
/// - Red X when critical issues are detected
/// - Click handler to open full wizard
struct SystemStatusIndicator: View {
    @ObservedObject var validator: MainAppStateController // 🎯 Phase 3: New controller
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
                // Background: solid chip for success/error; glass for transient states
                if usesSolidChip {
                    Circle()
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.95))
                        .frame(width: backgroundSize, height: backgroundSize)
                        .shadow(color: shadowColor, radius: isHovered ? 3 : 1, x: 0, y: 1)
                        .overlay(Circle().stroke(borderColor, lineWidth: 0.5))
                } else {
                    AppGlassBackground(style: .chipBold, cornerRadius: backgroundSize / 2)
                        .frame(width: backgroundSize, height: backgroundSize)
                        .shadow(color: shadowColor, radius: isHovered ? 3 : 1, x: 0, y: 1)
                        .overlay(Circle().stroke(borderColor, lineWidth: 0.5))
                }
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
        .opacity(1) // Always visible; shows gear before first validation
        .animation(.easeIn(duration: 0.2), value: validator.validationState == nil) // Smooth fade-in
    }

    // MARK: - Icon View

    @ViewBuilder
    private func iconView() -> some View {
        // Fixed frame to prevent layout shifts
        ZStack {
            if let state = validator.validationState {
                switch state {
                case .checking:
                    Image(systemName: "gear")
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: isAnimating)
                        .onAppear { isAnimating = true }
                        // Don't stop animation on disappear - let it continue during transition
                        .transition(.opacity)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .transition(.opacity)
                case let .failed(blockingCount, _):
                    Group {
                        if blockingCount > 0 {
                            Image(systemName: "exclamationmark.triangle")
                        } else {
                            Image(systemName: "exclamationmark")
                        }
                    }
                    .transition(.opacity)
                }
            } else {
                // Before first validation, show animated gear as a neutral entrypoint
                Image(systemName: "gear")
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: isAnimating)
                    .onAppear { isAnimating = true }
                    // Don't stop animation on disappear - let it continue during transition
                    .transition(.opacity)
            }
        }
        .frame(width: indicatorSize, height: indicatorSize) // Fixed size to prevent jumps
        .animation(.easeInOut(duration: 0.3), value: iconIdentifier) // Smooth animation between states
        .onChange(of: validator.validationState) { _, newState in
            // Stop animation only when we're definitely not checking anymore
            if case .checking = newState {
                isAnimating = true
            } else {
                // Small delay before stopping to allow transition to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isAnimating = false
                }
            }
        }
    }

    /// Unique identifier for the current icon state to trigger animations
    private var iconIdentifier: String {
        guard let state = validator.validationState else { return "none" }
        switch state {
        case .checking: return "checking"
        case .success: return "success"
        case let .failed(blockingCount, _): return blockingCount > 0 ? "error" : "warning"
        }
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        guard let state = validator.validationState else { return Color.clear }
        switch state {
        case .checking:
            return Color.secondary.opacity(0.12)
        case .success:
            return Color.green.opacity(0.1)
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? Color.red.opacity(0.1) : Color.orange.opacity(0.1)
        }
    }

    private var usesSolidChip: Bool {
        guard let state = validator.validationState else { return false }
        switch state {
        case .success: return true
        case let .failed(blocking, _): return blocking > 0
        case .checking: return false
        }
    }

    private var borderColor: Color {
        guard let state = validator.validationState else { return Color.clear }
        switch state {
        case .checking:
            return Color.secondary.opacity(0.25)
        case .success:
            return Color.green.opacity(0.3)
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3)
        }
    }

    private var iconColor: Color {
        guard let state = validator.validationState else { return Color.gray }
        switch state {
        case .checking:
            return Color.secondary
        case .success:
            return Color.green
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? Color.red : Color.orange
        }
    }

    private var shadowColor: Color {
        guard let state = validator.validationState else { return Color.clear }
        switch state {
        case .checking:
            return Color.secondary.opacity(0.18)
        case .success:
            return Color.green.opacity(0.2)
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? Color.red.opacity(0.2) : Color.orange.opacity(0.2)
        }
    }

    private var accessibilityLabel: String {
        guard let state = validator.validationState else { return "System status unknown" }
        switch state {
        case .checking:
            return "System status checking"
        case .success:
            return "System status good"
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? "System has critical issues" : "System has warnings"
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
        if let state = validator.validationState {
            switch state {
            case .checking:
                AppLogger.shared.log("🔍 [SystemStatusIndicator] Opening wizard while validation in progress")
            case .success:
                AppLogger.shared.log("✅ [SystemStatusIndicator] Opening wizard despite healthy system")
            case let .failed(blockingCount, totalCount):
                AppLogger.shared.log("❌ [SystemStatusIndicator] Opening wizard due to \(blockingCount) blocking issues out of \(totalCount) total")
            }
        } else {
            AppLogger.shared.log("❓ [SystemStatusIndicator] Opening wizard with no validation result yet")
        }
    }
}

// MARK: - Header Integration View

/// A view that integrates the system status indicator into the ContentView header
struct ContentViewSystemStatus: View {
    @ObservedObject var validator: MainAppStateController // 🎯 Phase 3: New controller
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
        // 🎯 Phase 3: Updated previews for MainAppStateController
        let validatorChecking = MainAppStateController()
        validatorChecking.validationState = .checking

        let validatorSuccess = MainAppStateController()
        validatorSuccess.validationState = .success

        let validatorFailed = MainAppStateController()
        validatorFailed.validationState = .failed(blockingCount: 2, totalCount: 4)

        let validatorWarnings = MainAppStateController()
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
