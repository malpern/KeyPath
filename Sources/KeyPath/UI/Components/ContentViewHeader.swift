import SwiftUI

struct ContentViewHeader: View {
    @ObservedObject var validator: MainAppStateController
    @Binding var showingInstallationWizard: Bool
    @EnvironmentObject var kanataManager: KanataViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: {
                    AppLogger.shared.log("🔧 [ContentViewHeader] Keyboard icon tapped - launching installation wizard")
                    showingInstallationWizard = true
                }, label: {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.blue)
                })
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("launch-installation-wizard-button")
                .accessibilityLabel("Launch Installation Wizard")
                .accessibilityHint("Click to open the KeyPath installation and setup wizard")

                Text("KeyPath")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                // System Status Indicator in top-right
                SystemStatusIndicator(
                    validator: validator,
                    showingWizard: $showingInstallationWizard,
                    onClick: { kanataManager.requestWizardPresentation() }
                )
            }

            Text("Record keyboard shortcuts and create custom key mappings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

