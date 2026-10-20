import ServiceManagement
import SwiftUI

struct LaunchAtLoginSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = LaunchAtLoginController.shared
    @State private var errorMessage: String?

    var body: some View {
        SettingsSection(title: "Startup") {
            SettingsCard {
                VStack(alignment: .leading, spacing: SettingsDesign.rowGap) {
                    SettingsToggleRow(
                        title: "Launch at login",
                        subtitle: "Keep your mappings available when you log in to your Mac.",
                        isOn: Binding(get: { controller.isEnabled }, set: { enabled in
                            Task {
                                errorMessage = nil
                                do { try await controller.setEnabled(enabled) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }),
                        identifier: "settings-launch-at-login-toggle"
                    )
                    .disabled(controller.isBusy || !controller.hasLoaded)
                    if controller.status == .requiresApproval {
                        Text("Allow KeyPath in Login Items to finish enabling launch at login.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .settingsAction()
                            .accessibilityIdentifier("settings-launch-at-login-approval")
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier("settings-launch-at-login-error")
                    }
                }
            }
        }
        .task { await controller.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller.refresh() } }
        }
    }
}
