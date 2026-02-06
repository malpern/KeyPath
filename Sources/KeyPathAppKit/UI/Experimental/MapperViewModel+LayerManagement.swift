import Foundation
import KeyPathCore

extension MapperViewModel {
    // MARK: - Layer Management

    /// System layers that cannot be deleted
    private static let systemLayers: Set<String> = ["base", "nav", "navigation"]

    /// Get list of available layers (system + custom).
    /// Uses cached layer names refreshed from Kanata + rule collections.
    func getAvailableLayers() -> [String] {
        if availableLayers.isEmpty {
            return buildAvailableLayers(additional: [])
        }
        return availableLayers
    }

    /// Refresh cached layer names using RuntimeCoordinator + local rule collections.
    func refreshAvailableLayers() async {
        let tcpLayers = await kanataManager?.fetchLayerNamesFromKanata() ?? []
        let nextLayers = buildAvailableLayers(additional: tcpLayers)
        await MainActor.run {
            availableLayers = nextLayers
        }
    }

    private func buildAvailableLayers(additional: [String]) -> [String] {
        var layers = Set<String>(["base", "nav"])

        for layer in additional {
            layers.insert(layer.lowercased())
        }

        if let rulesManager {
            // Add layers from enabled rule collections
            for collection in rulesManager.ruleCollections where collection.isEnabled {
                layers.insert(collection.targetLayer.kanataName)
            }

            // Add layers from enabled custom rules
            for rule in rulesManager.customRules where rule.isEnabled {
                layers.insert(rule.targetLayer.kanataName)
            }
        }

        // Sort with system layers first, then alphabetically
        return layers.sorted { lhs, rhs in
            let lhsSystem = Self.systemLayers.contains(lhs.lowercased())
            let rhsSystem = Self.systemLayers.contains(rhs.lowercased())
            if lhsSystem != rhsSystem { return lhsSystem }
            return lhs < rhs
        }
    }

    /// Check if a layer is a system layer (cannot be deleted)
    func isSystemLayer(_ layer: String) -> Bool {
        Self.systemLayers.contains(layer.lowercased())
    }

    /// Create a new layer with persistence and Leader key activator
    func createLayer(_ name: String) {
        guard !name.isEmpty else { return }

        // Sanitize the layer name
        let sanitizedName = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        guard !sanitizedName.isEmpty else { return }

        // Check for duplicates
        let existingLayers = getAvailableLayers()
        if existingLayers.contains(where: { $0.lowercased() == sanitizedName }) {
            AppLogger.shared.warn("⚠️ [MapperViewModel] Layer already exists: \(sanitizedName)")
            setLayer(sanitizedName)
            return
        }

        // Create a RuleCollection for this layer with Leader key activator
        // Activator: first letter of layer name, from nav layer (Leader → letter)
        let activatorKey = String(sanitizedName.prefix(1))
        let targetLayer = RuleCollectionLayer.custom(sanitizedName)

        let collection = RuleCollection(
            id: UUID(),
            name: sanitizedName.capitalized,
            summary: "Custom layer: \(sanitizedName)",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "square.stack.3d.up",
            tags: ["custom-layer"],
            targetLayer: targetLayer,
            momentaryActivator: MomentaryActivator(
                input: activatorKey,
                targetLayer: targetLayer,
                sourceLayer: .navigation
            ),
            activationHint: "Leader → \(activatorKey.uppercased())",
            configuration: .list
        )

        // Persist via rulesManager
        if let rulesManager {
            Task {
                await rulesManager.addCollection(collection)
                AppLogger.shared.log("📚 [MapperViewModel] Created new layer: \(sanitizedName) (Leader → \(activatorKey.uppercased()))")
                await refreshAvailableLayers()
            }
        }

        // Switch to the new layer
        setLayer(sanitizedName)
    }

    /// Delete a layer and all associated rules (only non-system layers)
    func deleteLayer(_ layer: String) {
        guard !isSystemLayer(layer) else {
            AppLogger.shared.warn("⚠️ [MapperViewModel] Cannot delete system layer: \(layer)")
            return
        }

        // If we're on this layer, switch to base first
        if currentLayer.lowercased() == layer.lowercased() {
            setLayer("base")
        }

        // Remove all collections and rules for this layer
        if let rulesManager {
            Task {
                await rulesManager.removeLayer(layer)
                AppLogger.shared.log("🗑️ [MapperViewModel] Deleted layer: \(layer)")
                await refreshAvailableLayers()
            }
        }
    }

    /// Save a mapping that launches an app
    func saveAppLaunchMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("🚀 [MapperViewModel] saveAppLaunchMapping called")

        guard let inputSeq = inputSequence, let app = selectedApp else {
            AppLogger.shared.log("⚠️ [MapperViewModel] saveAppLaunchMapping: missing input or app")
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("🚀 [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(app.kanataOutput)' layer=\(targetLayer)")

        // Use makeCustomRule to reuse existing rule ID for the same input key
        // This prevents duplicate keys in defsrc which causes Kanata validation errors
        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: app.kanataOutput)
        customRule.notes = "Launch \(app.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("🚀 [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved app launch: \(inputSeq.displayString) → launch:\(app.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Select a system action for the output
    func selectSystemAction(_ action: SystemActionInfo) {
        selectedSystemAction = action
        selectedApp = nil // Clear any app selection
        selectedURL = nil
        outputSequence = nil // Clear any key sequence output
        outputLabel = action.name

        AppLogger.shared.log("⚙️ [MapperViewModel] Selected system action: \(action.name) (\(action.id))")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("⚙️ [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveSystemActionMapping(kanataManager: manager)
            }
        }
    }

    /// Save a mapping that triggers a system action
    func saveSystemActionMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("⚙️ [MapperViewModel] saveSystemActionMapping called")

        guard let inputSeq = inputSequence, let action = selectedSystemAction else {
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("⚙️ [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(action.kanataOutput)' layer=\(targetLayer)")

        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: action.kanataOutput)
        customRule.notes = "\(action.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("⚙️ [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved system action: \(inputSeq.displayString) → \(action.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Show the URL input dialog
    func showURLInputDialog() {
        urlInputText = "https://"
        showingURLDialog = true
    }

    /// Submit the URL from the input dialog
    func submitURL() {
        let trimmed = urlInputText.trimmingCharacters(in: .whitespaces)

        // Validate URL (no spaces, not empty, not just "https://")
        guard !trimmed.isEmpty, !trimmed.contains(" "), trimmed != "https://", trimmed != "http://" else {
            statusMessage = "Invalid URL"
            statusIsError = true
            return
        }

        selectedURL = trimmed
        selectedApp = nil // Clear any app selection
        selectedSystemAction = nil // Clear any system action selection
        outputSequence = nil // Clear any key sequence output
        outputLabel = extractDomain(from: trimmed)
        selectedURLFavicon = nil // Clear old favicon while loading
        showingURLDialog = false

        AppLogger.shared.log("🌐 [MapperViewModel] Selected URL: \(trimmed)")

        // Fetch favicon asynchronously
        Task {
            let favicon = await FaviconFetcher.shared.fetchFavicon(for: trimmed)
            await MainActor.run {
                self.selectedURLFavicon = favicon
                if favicon != nil {
                    AppLogger.shared.log("🖼️ [MapperViewModel] Loaded favicon for \(trimmed)")
                }
            }
        }

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("🌐 [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveURLMapping(kanataManager: manager)
            }
        }
    }

    /// Save a mapping that opens a web URL
    func saveURLMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("🌐 [MapperViewModel] saveURLMapping called")

        guard let inputSeq = inputSequence, let url = selectedURL else {
            AppLogger.shared.log("⚠️ [MapperViewModel] saveURLMapping: missing input or URL")
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let encodedURL = URLMappingFormatter.encodeForPushMessage(url)
        let outputKanata = "(push-msg \"open:\(encodedURL)\")"
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("🌐 [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(outputKanata)' layer=\(targetLayer)")

        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: outputKanata)
        customRule.notes = "Open \(url) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("🌐 [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved URL mapping: \(inputSeq.displayString) → open:\(url) [layer: \(currentLayer)]")

            // Trigger favicon fetch (fire-and-forget)
            Task { _ = await FaviconFetcher.shared.fetchFavicon(for: url) }
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Extract domain from URL for display purposes
    func extractDomain(from url: String) -> String {
        KeyMappingFormatter.extractDomain(from: url)
    }
}
