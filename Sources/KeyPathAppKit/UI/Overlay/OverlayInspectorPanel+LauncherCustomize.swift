import KeyPathCore
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

            // Suggestions & Setup section
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    Button {
                        Task {
                            await refreshLauncherExistingDomains()
                            showLauncherHistorySuggestions = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text("Suggest from Browser History")
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
                    .accessibilityIdentifier("launcher-customize-suggest-history")

                    Divider()

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
        .sheet(isPresented: $showLauncherHistorySuggestions) {
            BrowserHistorySuggestionsView(existingDomains: launcherExistingDomains) { selectedSites in
                addSuggestedSitesToLauncher(selectedSites)
            }
        }
    }

    /// Re-open the launcher welcome dialog from settings.
    private func showLauncherWelcomeFromSettings() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig {
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
        var updatedConfig = finalConfig
        updatedConfig.hasSeenWelcome = true

        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if var launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                launcherCollection.configuration = .launcherGrid(updatedConfig)
                var allCollections = collections
                if let index = allCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                    allCollections[index] = launcherCollection
                    try? await RuleCollectionStore.shared.saveCollections(allCollections)
                }
            }
        }
    }

    /// Description for launcher activation mode
    private var launcherActivationDescription: String {
        switch launcherActivationMode {
        case .holdHyper:
            launcherHyperTriggerMode.description + " Then press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    /// Load launcher config from store
    private func loadLauncherConfig() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig {
                await MainActor.run {
                    launcherActivationMode = config.activationMode
                    launcherHyperTriggerMode = config.hyperTriggerMode
                }
            }
        }
    }

    private func refreshLauncherExistingDomains() async {
        let collections = await RuleCollectionStore.shared.loadCollections()
        let domains = collections
            .first(where: { $0.id == RuleCollectionIdentifier.launcher })?
            .configuration
            .launcherGridConfig?
            .mappings
            .compactMap { mapping -> String? in
                if case let .url(domain) = mapping.target {
                    return normalizeDomain(domain)
                }
                return nil
            } ?? []

        await MainActor.run {
            launcherExistingDomains = Set(domains)
        }
    }

    /// Save launcher config to store
    private func saveLauncherConfig() {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    config.activationMode = launcherActivationMode
                    config.hyperTriggerMode = launcherHyperTriggerMode
                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    // Notify that rules changed so config regenerates
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    /// Add suggested sites from browser history to launcher
    private func addSuggestedSitesToLauncher(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    // Get existing keys
                    var existingKeys = Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) })
                    let existingDomains = Set(config.mappings.compactMap { mapping in
                        if case let .url(domain) = mapping.target {
                            return normalizeDomain(domain)
                        }
                        return nil
                    })

                    // Add new mappings for each suggested site
                    for site in sites {
                        if existingDomains.contains(normalizeDomain(site.domain)) {
                            continue
                        }
                        guard let key = LauncherGridConfig.suggestionKeyOrder.first(where: { !existingKeys.contains($0) }) else {
                            continue
                        }

                        existingKeys.insert(key)

                        let mapping = LauncherMapping(
                            key: key,
                            target: .url(site.domain)
                        )
                        config.mappings.append(mapping)
                    }

                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lower = domain.lowercased()
        if lower.hasPrefix("www.") {
            return String(lower.dropFirst(4))
        }
        return lower
    }
}
