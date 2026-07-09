import KeyPathRulesCore
import SwiftUI

// MARK: - Window Snapping View

/// A visual, interactive view for the Window Snapping rule collection.
/// Displays a monitor canvas with snap zones and floating action cards.
struct WindowSnappingView: View {
    let mappings: [KeyMapping]
    let convention: WindowKeyConvention
    let activationMode: WindowSnappingActivationMode
    let onConventionChange: (WindowKeyConvention) -> Void
    var onActivationModeChange: ((WindowSnappingActivationMode) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Activation mode picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Activation")
                    .font(.headline)
                Picker("Activation Mode", selection: Binding(
                    get: { activationMode },
                    set: { onActivationModeChange?($0) }
                )) {
                    Text(WindowSnappingActivationMode.leader.displayName)
                        .tag(WindowSnappingActivationMode.leader)
                    Text(WindowSnappingActivationMode.quickLauncher.displayName)
                        .tag(WindowSnappingActivationMode.quickLauncher)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("window-snapping-activation-mode-picker")

                Text(activationDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Convention picker (leader key style)
            ConventionPicker(
                convention: convention,
                onConventionChange: onConventionChange
            )

            // Permission status indicator
            PermissionStatusBanner()

            // Monitor canvas with snap zones
            MonitorCanvas(convention: convention)

            // Floating action cards row
            ActionCardsRow(convention: convention)

            // Tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text(tipText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var activationDescription: String {
        switch activationMode {
        case .leader:
            "Press Leader → W, then press an action key."
        case .quickLauncher:
            "Hold Hyper, press W, then press an action key."
        }
    }

    private var tipText: String {
        switch activationMode {
        case .leader:
            "Activate via Leader → w, then press the action key"
        case .quickLauncher:
            "Activate via Hyper + w, then press the action key"
        }
    }
}

// MARK: - Preview

#Preview {
    WindowSnappingView(
        mappings: [],
        convention: .standard,
        activationMode: .leader,
        onConventionChange: { _ in }
    )
    .frame(width: 400)
    .padding()
}

#Preview("Window Snapping - Quick Launcher") {
    WindowSnappingView(
        mappings: [],
        convention: .standard,
        activationMode: .quickLauncher,
        onConventionChange: { _ in }
    )
    .frame(width: 400)
    .padding()
}
