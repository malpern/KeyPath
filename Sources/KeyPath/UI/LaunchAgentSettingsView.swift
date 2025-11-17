import KeyPathCore
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

            // Legacy LaunchAgent control (deprecated)
            VStack(alignment: .leading, spacing: 8) {
                Text("Legacy Launch Agent (Deprecated)")
                    .font(.body)
                    .fontWeight(.semibold)

                Text("KeyPath no longer uses a headless LaunchAgent. The app is UI-only; if a legacy agent was previously enabled, you can disable it below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Disable Legacy Agent") {
                        toggleLaunchAgent(enable: false)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCheckingStatus || !(LaunchAgentManager.isInstalled() && LaunchAgentManager.isLoaded()))

                    if LaunchAgentManager.isInstalled() {
                        Text(
                            LaunchAgentManager.isLoaded()
                                ? "Status: Active (will be disabled)" : "Status: Installed (not active)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

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
                "Note: Startup at login will be provided via a Login Item in a future update if needed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await checkLaunchAgentStatus()
            // Proactively disable if still active
            if isLaunchAgentEnabled {
                await MainActor.run { isCheckingStatus = true }
                defer { isCheckingStatus = false }
                try? await LaunchAgentManager.disable()
                await checkLaunchAgentStatus()
            }
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

// MARK: - Integration with existing StatusSettingsTabView

extension StatusSettingsTabView {
    /// Add LaunchAgent settings section to existing settings
    @ViewBuilder
    func launchAgentSection() -> some View {
        GroupBox {
            LaunchAgentSettingsView()
        }
    }
}
