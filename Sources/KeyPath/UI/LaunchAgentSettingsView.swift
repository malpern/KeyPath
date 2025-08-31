import SwiftUI

/// Settings view for managing LaunchAgent (start at login)
struct LaunchAgentSettingsView: View {
    @State private var isLaunchAgentEnabled = false
    @State private var isCheckingStatus = true
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Startup Settings", systemImage: "power.circle")
                .font(.headline)

            Divider()

            // Launch at login toggle
            Toggle(isOn: $isLaunchAgentEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start KeyPath at Login")
                        .font(.body)
                    Text("Automatically start keyboard remapping when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isCheckingStatus)
            .onChange(
                of: isLaunchAgentEnabled,
                { _, newValue in
                    toggleLaunchAgent(enable: newValue)
                }
            )

            // Status indicator
            if isCheckingStatus {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Checking status...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if LaunchAgentManager.isInstalled() {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(
                        LaunchAgentManager.isLoaded()
                            ? "Launch Agent is active" : "Launch Agent is installed but not active"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Additional info
            Text(
                "Note: When enabled, KeyPath will run in the background and manage the keyboard remapping service."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await checkLaunchAgentStatus()
        }
        .alert("Launch Agent Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func checkLaunchAgentStatus() async {
        isCheckingStatus = true
        defer { isCheckingStatus = false }

        // Check if LaunchAgent is installed and loaded
        isLaunchAgentEnabled = LaunchAgentManager.isInstalled() && LaunchAgentManager.isLoaded()
    }

    private func toggleLaunchAgent(enable: Bool) {
        Task {
            do {
                if enable {
                    try await LaunchAgentManager.enable()
                    AppLogger.shared.log("✅ [Settings] LaunchAgent enabled")
                } else {
                    try await LaunchAgentManager.disable()
                    AppLogger.shared.log("✅ [Settings] LaunchAgent disabled")
                }

                // Refresh status
                await checkLaunchAgentStatus()
            } catch {
                errorMessage = error.localizedDescription
                showError = true

                // Revert toggle on error
                await MainActor.run {
                    isLaunchAgentEnabled = !enable
                }

                AppLogger.shared.log("❌ [Settings] Failed to toggle LaunchAgent: \(error)")
            }
        }
    }
}

// MARK: - Integration with existing SettingsView

extension SettingsView {
    /// Add LaunchAgent settings section to existing settings
    @ViewBuilder
    func launchAgentSection() -> some View {
        GroupBox {
            LaunchAgentSettingsView()
        }
    }
}
