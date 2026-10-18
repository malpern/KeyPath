import KeyPathCore
import KeyPathRulesCore
import SwiftUI

extension OverlayInspectorPanel {
    /// Content for the launcher customize slide-over panel
    var launcherCustomizePanelContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Activation section
            VStack(alignment: .leading, spacing: 10) {
                Text("Activation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Activation Mode", selection: $launcherActivationMode) {
                    Text(LauncherActivationMode.holdHyper.displayName)
                        .tag(LauncherActivationMode.holdHyper)
                    Text(LauncherActivationMode.leaderSequence.displayName)
                        .tag(LauncherActivationMode.leaderSequence)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("launcher-customize-activation-mode")
                .onChange(of: launcherActivationMode) { _, _ in
                    saveLauncherConfig()
                }

                // Hyper trigger mode segmented picker (only when Hyper mode selected)
                if launcherActivationMode == .holdHyper {
                    Picker("Trigger Mode", selection: $launcherHyperTriggerMode) {
                        Text(HyperTriggerMode.hold.displayName)
                            .tag(HyperTriggerMode.hold)
                        Text(HyperTriggerMode.tap.displayName)
                            .tag(HyperTriggerMode.tap)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("launcher-customize-trigger-picker")
                    .onChange(of: launcherHyperTriggerMode) { _, _ in
                        saveLauncherConfig()
                    }
                }

                // Description text
                Text(launcherActivationDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Setup section
            VStack(alignment: .leading, spacing: 10) {
                Text("Setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    Button {
                        showLauncherWelcomeFromSettings()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Open Launcher Setup")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("launcher-customize-open-setup")
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .onAppear {
            loadLauncherConfig()
        }
    }

    /// Re-open the launcher welcome dialog from settings.
    private func showLauncherWelcomeFromSettings() {
        Task {
            let collections = await services.ruleCollectionStore.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    var mutableConfig = config
                    LauncherWelcomeWindowController.show(
                        config: Binding(
                            get: { mutableConfig },
                            set: { mutableConfig = $0 }
                        ),
                        onComplete: { finalConfig, _ in
                            saveLauncherWelcomeConfig(finalConfig)
                        },
                        onDismiss: {}
                    )
                }
            }
        }
    }

    private func saveLauncherWelcomeConfig(_ finalConfig: LauncherGridConfig) {
        var welcomeConfig = finalConfig
        welcomeConfig.hasSeenWelcome = true
        let updatedConfig = welcomeConfig

        Task { @MainActor in
            guard let manager = kanataViewModel?.underlyingManager.rulesManager else { return }
            _ = await manager.editLauncherConfiguration { $0 = updatedConfig }
        }
    }

    /// Description for launcher activation mode
    private var launcherActivationDescription: String {
        KeyboardConceptCopy.launcherActivationDescription(
            mode: launcherActivationMode,
            hyperTriggerMode: launcherHyperTriggerMode
        )
    }

    /// Load launcher config from store
    private func loadLauncherConfig() {
        Task {
            let collections = await services.ruleCollectionStore.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    launcherActivationMode = config.activationMode
                    launcherHyperTriggerMode = config.hyperTriggerMode
                }
            }
        }
    }

    /// Save launcher config to store
    private func saveLauncherConfig() {
        let activationMode = launcherActivationMode
        let triggerMode = launcherHyperTriggerMode
        Task { @MainActor in
            guard let manager = kanataViewModel?.underlyingManager.rulesManager else { return }
            let saved = await manager.editLauncherConfiguration {
                $0.activationMode = activationMode
                $0.hyperTriggerMode = triggerMode
            }
            if !saved { loadLauncherConfig() }
        }
    }
}
