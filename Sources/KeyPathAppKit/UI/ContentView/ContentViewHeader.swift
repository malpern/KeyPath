import KeyPathCore
import SwiftUI

struct ContentViewHeader: View {
    @ObservedObject var validator: MainAppStateController // 🎯 Phase 3: New controller
    @Binding var showingInstallationWizard: Bool
    let onWizardRequest: () -> Void
    let layerIndicatorVisible: Bool
    let currentLayerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                Button(
                    action: {
                        AppLogger.shared.log(
                            "🔧 [ContentViewHeader] Keyboard icon tapped - launching installation wizard")
                        showingInstallationWizard = true
                    },
                    label: {
                        Image(systemName: "keyboard")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                )
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("launch-installation-wizard-button")
                .accessibilityLabel("Launch Installation Wizard")
                .accessibilityHint("Click to open the KeyPath installation and setup wizard")

                Text("KeyPath")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize()

                Spacer()

                // Status indicators grouped together
                HStack(spacing: 12) {
                    // Kanata Engine Health
                    LabeledKanataHealthIndicator()

                    // Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 20)

                    // System Status
                    HStack(spacing: 6) {
                        Text("System")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        SystemStatusIndicator(
                            validator: validator,
                            showingWizard: $showingInstallationWizard,
                            onClick: onWizardRequest
                        )
                    }
                }
                .frame(height: 28, alignment: .bottom) // lock indicator height to keep row baseline stable
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 36, alignment: .bottom) // Lock header row height to prevent spacing shifts

            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .offset(y: 2)

            if layerIndicatorVisible {
                LayerStatusIndicator(currentLayerName: currentLayerName)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Transparent background - no glass header
    }
}
