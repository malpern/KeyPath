import Foundation

@MainActor
extension KeyboardVisualizationViewModel {
    /// Load enabled states for optional feature collections (Typing Sounds)
    func loadFeatureCollectionStates() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()
            isTypingSoundsEnabled = collections.first { $0.id == RuleCollectionIdentifier.typingSounds }?.isEnabled ?? false
            updateTapHoldIdleLabels(from: collections)
        }
    }

    // MARK: - Tap-Hold Idle Labels

    func updateTapHoldIdleLabels(from collections: [RuleCollection]) {
        var labels: [UInt16: String] = [:]
        for collection in collections where collection.isEnabled {
            guard case let .tapHoldPicker(config) = collection.configuration else { continue }
            let output = config.selectedTapOutput ?? config.tapOptions.first?.output
            guard let output, let keyCode = Self.kanataNameToKeyCode(config.inputKey) else { continue }
            if let label = Self.tapHoldOutputDisplayLabel(output) {
                labels[keyCode] = label
            }
        }
        tapHoldIdleLabels = labels
    }

    /// Get display label for tap-hold output.
    /// Uses the centralized KeyDisplayFormatter utility.
    static func tapHoldOutputDisplayLabel(_ output: String) -> String? {
        KeyDisplayFormatter.tapHoldLabel(for: output)
    }

    /// Pre-load all icons for launcher mode and layer-based app launches
    /// Call on startup to ensure icons are cached before user enters launcher mode
    func preloadAllIcons() {
        Task {
            // Load collections once for both preload methods
            let collections = await RuleCollectionStore.shared.loadCollections()

            // Preload launcher grid icons (app icons and favicons)
            await IconResolverService.shared.preloadLauncherIcons()

            // Preload layer-based app/URL icons (Vim leader, etc.)
            await IconResolverService.shared.preloadLayerIcons(from: collections)
        }
    }
}
