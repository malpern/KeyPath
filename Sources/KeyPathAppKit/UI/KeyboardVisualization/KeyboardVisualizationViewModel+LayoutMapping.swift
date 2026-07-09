import AppKit
import Carbon
import Foundation
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

extension KeyboardVisualizationViewModel {
    // MARK: - Layout Management

    /// Update the physical keyboard layout and rebuild key mappings
    /// - Parameter newLayout: The new physical layout to use
    func setLayout(_ newLayout: PhysicalLayout) {
        guard layout.id != newLayout.id else { return }
        AppLogger.shared.info("🎹 [KeyboardViz] Layout changed: \(layout.id) -> \(newLayout.id)")
        layout = newLayout
        rebuildLayerMapping() // Rebuild mappings with new layout
    }

    // MARK: - Layer Mapping

    /// Update the current layer and rebuild key mapping
    func updateLayer(_ layerName: String) {
        let targetLayerName = layerName

        guard currentLayerName != targetLayerName else { return }

        let wasLauncherMode = isLauncherModeActive

        // Set layer name immediately so computed properties (isLauncherModeActive,
        // layer indicators) update without waiting for the async mapping rebuild.
        currentLayerName = targetLayerName

        // Clear tap-hold sources on layer change to prevent stale suppressions
        // (e.g., user switches layers while holding a tap-hold key)
        activeTapHoldSources.removeAll()

        // When returning to base layer, clear hold state for all keys.
        // This handles the case where KeyInput events are unavailable (older kanata)
        // and the Release event never fires to clear holdActiveKeyCodes.
        // Skip during layer preview — the physical keys are still held and the
        // preview system manages its own state transitions.
        if targetLayerName.lowercased() == "base", !isShowingLayerPreview {
            for keyCode in holdActiveKeyCodes {
                holdClearWorkItems[keyCode]?.cancel()
                holdClearWorkItems.removeValue(forKey: keyCode)
            }
            keyVisualStates.removeAll()
        }

        // Check if we'll be entering/exiting launcher mode
        let willBeLauncherMode = targetLayerName.lowercased() == Self.launcherLayerName

        // Load/clear launcher mappings when entering/exiting launcher mode
        if willBeLauncherMode, !wasLauncherMode {
            loadLauncherMappings()
        } else if !willBeLauncherMode, wasLauncherMode {
            launcherMappings.removeAll()
        }

        // Reset idle timer on any layer change (including returning to base)
        noteInteraction()
        noteTcpEventReceived()

        // Rebuild the detailed key map in the background
        rebuildLayerMappingForLayer(targetLayerName)
    }

    /// Load launcher mappings, using pre-warmed cache if available.
    func loadLauncherMappings() {
        if let cached = cachedLauncherMappings {
            launcherMappings = cached
            AppLogger.shared.info("🚀 [KeyboardViz] Loaded \(cached.count) launcher mappings from cache (instant)")
            return
        }

        Task { @MainActor in
            let mappings = await Self.buildLauncherMappings()
            launcherMappings = mappings
            cachedLauncherMappings = mappings
        }
    }

    /// Pre-warm launcher mappings cache at startup so layer switch is instant.
    func prewarmLauncherMappings() {
        Task {
            let mappings = await Self.buildLauncherMappings()
            await MainActor.run {
                cachedLauncherMappings = mappings
                AppLogger.shared.info("🚀 [KeyboardViz] Pre-warmed \(mappings.count) launcher mappings")
            }

            for (_, mapping) in mappings {
                AppIconResolver.prewarmIcon(for: mapping.action)
            }
        }
    }

    /// Build launcher mappings from rule collections (shared by load and prewarm).
    private static func buildLauncherMappings() async -> [String: LauncherMapping] {
        let collections = await RuleCollectionStore.shared.loadCollections()

        guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
              let config = launcherCollection.configuration.launcherGridConfig
        else {
            AppLogger.shared.debug("🚀 [KeyboardViz] No launcher config found")
            return [:]
        }

        let enabledMappings = config.mappings.filter { mapping in
            guard mapping.isEnabled else { return false }
            if case .openURL = mapping.action { return true }
            if case let .launchApp(name, bundleId) = mapping.action {
                return isAppInstalled(name: name, bundleId: bundleId)
            }
            return true
        }

        var result = Dictionary(
            uniqueKeysWithValues: enabledMappings.map { ($0.key.lowercased(), $0) }
        )

        // Inject synthetic "Windows" entry when Window Snapping uses Quick Launcher mode
        if let wsCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.windowSnapping }),
           wsCollection.isEnabled,
           wsCollection.windowSnappingActivationMode == .quickLauncher
        {
            result["w"] = LauncherMapping(
                key: "w",
                action: .systemAction(id: "window-snapping"),
                userDescription: "Window Snapping"
            )
        }

        AppLogger.shared.info("🚀 [KeyboardViz] Built \(result.count) launcher mappings (filtered for installed apps)")
        return result
    }

    /// Check if an app is installed on the system
    static func isAppInstalled(name: String, bundleId: String?) -> Bool {
        // Try bundle ID first (most reliable)
        if let bundleId, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
            return true
        }

        // Fall back to app name in /Applications
        let directPath = "/Applications/\(name).app"
        if Foundation.FileManager().fileExists(atPath: directPath) {
            return true
        }

        // Try capitalized name
        let capitalizedPath = "/Applications/\(name.capitalized).app"
        if Foundation.FileManager().fileExists(atPath: capitalizedPath) {
            return true
        }

        return false
    }

    /// Rebuild the key mapping for the current layer
    func rebuildLayerMapping() {
        rebuildLayerMappingForLayer(currentLayerName)
    }

    /// Rebuild the key mapping for a specific layer
    /// Updates both the layer name and mapping atomically to prevent UI flash
    func rebuildLayerMappingForLayer(_ targetLayerName: String) {
        // Cancel any in-flight mapping task
        layerMapTask?.cancel()

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Skipping layer mapping in test environment")
            currentLayerName = targetLayerName
            layerKeyMap = [:]
            remapOutputMap = [:]
            isLoadingLayerMap = false
            return
        }

        // Use prebuilt mapping immediately if available (from startup prebuild).
        // This prevents the overlay from flashing empty during the async rebuild.
        let cacheKey = targetLayerName.lowercased()
        if let cached = prebuiltLayerMappings[cacheKey] {
            layerKeyMap = cached
            remapOutputMap = LayerMappingBuilder.buildRemapOutputMap(from: cached)
        } else {
            // Cache miss (layer not yet warmed): clear the stale previous-layer map so
            // keys don't render with the prior layer's collection color during the async
            // rebuild below. Otherwise F-row keys — owned by the "macOS Function Keys"
            // collection on the base layer — flash orange when switching to a layer where
            // they're transparent, because `currentLayerName` already flipped (isLayerMode
            // true) while `layerKeyMap` still holds the base mapping. Restores the eager
            // clear from PR #515 that PR #581's prebuilt-cache change dropped.
            layerKeyMap = [:]
            remapOutputMap = [:]
        }

        isLoadingLayerMap = true
        AppLogger.shared.info("🗺️ [KeyboardViz] Starting layer mapping build for '\(targetLayerName)'...")

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                AppLogger.shared.debug("🗺️ [KeyboardViz] Using config: \(configPath)")

                // Load rule collections for collection ownership tracking
                // Only use enabled collections to match config generation behavior
                let allCollections = await RuleCollectionStore.shared.loadCollections()
                let ruleCollections = allCollections.filter(\.isEnabled)
                let frontmostBundleIdentifier =
                    currentAppBundleId
                        ?? AppContextService.shared.currentBundleIdentifier
                        ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let isApprovedNeovimTerminal = NeovimTerminalScope.isApprovedTerminal(
                    bundleIdentifier: frontmostBundleIdentifier
                )
                let scopedRuleCollections = isApprovedNeovimTerminal
                    ? ruleCollections
                    : ruleCollections.filter { $0.id != RuleCollectionIdentifier.neovimTerminal }

                AppLogger.shared.debug("🗺️ [KeyboardViz] Total collections: \(allCollections.count), Enabled: \(ruleCollections.count)")
                AppLogger.shared.debug("🗺️ [KeyboardViz] Enabled collection IDs: \(ruleCollections.map { $0.id.uuidString.prefix(8) }.joined(separator: ", "))")
                if !isApprovedNeovimTerminal {
                    AppLogger.shared.debug(
                        "🗺️ [KeyboardViz] Neovim scope inactive (frontmost=\(frontmostBundleIdentifier ?? "nil")); hiding Neovim overlay/key-list content"
                    )
                }

                // Build mapping for target layer
                let (rawMapping, simReport) = try await layerKeyMapper.getMapping(
                    for: targetLayerName,
                    configPath: configPath,
                    layout: layout,
                    collections: scopedRuleCollections,
                    cacheKeySuffix: "neovim-scope-\(isApprovedNeovimTerminal ? "approved" : "fallback")"
                )
                var mapping = rawMapping

                // DEBUG: Log what simulator returned
                AppLogger.shared.info("🗺️ [KeyboardViz] Simulator returned \(mapping.count) entries for '\(targetLayerName)'")

                // Outside approved terminals, strip Neovim-owned entries from display mappings.
                // This keeps layer behavior untouched while suppressing Neovim educational UI content.
                if !isApprovedNeovimTerminal {
                    mapping = mapping.filter { _, info in
                        info.collectionId != RuleCollectionIdentifier.neovimTerminal
                    }
                }

                let customRules = await CustomRulesStore.shared.loadRules()
                AppLogger.shared.info("🗺️ [KeyboardViz] Augmenting '\(targetLayerName)' with \(customRules.count) custom rules and \(scopedRuleCollections.count) collections")
                mapping = LayerMappingBuilder.augmentWithPushMsgActions(
                    mapping: mapping,
                    customRules: customRules,
                    ruleCollections: scopedRuleCollections,
                    currentLayerName: targetLayerName
                )

                mapping = await applyAppSpecificOverrides(to: mapping)

                mapping = LayerMappingBuilder.enrichWithCustomShiftLabels(
                    mapping: mapping,
                    customRules: customRules
                )

                // Update mapping (layer name was already set eagerly in updateLayer;
                // re-assign here for the rebuildLayerMapping() path from setLayout)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.currentLayerName = targetLayerName
                    self.layerKeyMap = mapping
                    self.remapOutputMap = LayerMappingBuilder.buildRemapOutputMap(from: mapping)
                    self.isLoadingLayerMap = false
                    AppLogger.shared
                        .info("🗺️ [KeyboardViz] Updated currentLayerName to '\(targetLayerName)' and layerKeyMap with \(mapping.count) entries, remapOutputMap with \(self.remapOutputMap.count) remaps")
                }

                AppLogger.shared.info("🗺️ [KeyboardViz] Built layer mapping for '\(targetLayerName)': \(mapping.count) keys")

                // Log a few sample mappings for debugging
                for (keyCode, info) in mapping.prefix(5) {
                    AppLogger.shared.debug("  keyCode \(keyCode) -> '\(info.displayLabel)'")
                }

                // Show alert if simulator had significant failures on a non-base layer
                if let report = simReport, report.hasSignificantFailures,
                   targetLayerName.lowercased() != "base"
                {
                    await MainActor.run {
                        Self.showSimulationFailureAlert(report)
                    }
                }
            } catch {
                AppLogger.shared.error("❌ [KeyboardViz] Failed to build layer mapping: \(error)")
                await MainActor.run {
                    self.isLoadingLayerMap = false
                }
            }
        }
    }

    // MARK: - Forwarding to LayerMappingBuilder

    nonisolated static func mergeAugmentation(
        _ augmented: LayerKeyInfo,
        with original: LayerKeyInfo
    ) -> LayerKeyInfo {
        LayerMappingBuilder.mergeAugmentation(augmented, with: original)
    }

    nonisolated static func extractPushMsgInfo(from output: String, description: String?) -> LayerKeyInfo? {
        LayerMappingBuilder.extractPushMsgInfo(from: output, description: description)
    }

    nonisolated static func extractAppLaunchIdentifier(from output: String) -> String? {
        LayerMappingBuilder.extractAppLaunchIdentifier(from: output)
    }

    nonisolated static func extractUrlIdentifier(from output: String) -> String? {
        LayerMappingBuilder.extractUrlIdentifier(from: output)
    }

    nonisolated static func extractSystemActionIdentifier(from output: String) -> String? {
        LayerMappingBuilder.extractSystemActionIdentifier(from: output)
    }

    nonisolated static func systemActionDisplayLabel(_ action: String) -> String {
        LayerMappingBuilder.systemActionDisplayLabel(action)
    }

    nonisolated static func mediaKeyDisplayLabel(_ kanataKey: String) -> String? {
        LayerMappingBuilder.mediaKeyDisplayLabel(kanataKey)
    }

    /// Fire-and-forget prebuild of all layer mappings so first layer switches hit cache.
    func prebuildLayerMappingsInBackground() {
        Task {
            let allCollections = await RuleCollectionStore.shared.loadCollections()
            let enabledCollections = allCollections.filter(\.isEnabled)

            var layerNames = Set<String>(["base"])
            for collection in enabledCollections {
                layerNames.insert(collection.targetLayer.kanataName.lowercased())
                if let activator = collection.momentaryActivator {
                    layerNames.insert(activator.targetLayer.kanataName.lowercased())
                }
            }

            let configPath = WizardSystemPaths.userConfigPath
            AppLogger.shared.info("🗺️ [KeyboardViz] Starting background prebuild for \(layerNames.count) layers")

            await layerKeyMapper.prebuildAllLayers(
                Array(layerNames),
                configPath: configPath,
                layout: layout,
                allEnabledCollections: enabledCollections
            )

            // Copy prebuilt mappings to a synchronous cache for instant layer switching.
            // Augment each mapping with push-msg actions (app launches, system actions, etc.)
            // so the cache includes the same data the async rebuild produces.
            let customRules = await CustomRulesStore.shared.loadRules()
            var localCache: [String: [UInt16: LayerKeyInfo]] = [:]
            for layer in layerNames {
                if var mapping = await layerKeyMapper.getCachedMapping(for: layer) {
                    mapping = LayerMappingBuilder.augmentWithPushMsgActions(
                        mapping: mapping,
                        customRules: customRules,
                        ruleCollections: enabledCollections,
                        currentLayerName: layer
                    )
                    localCache[layer] = mapping
                }
            }
            await MainActor.run {
                self.prebuiltLayerMappings = localCache
            }

            AppLogger.shared.info("🗺️ [KeyboardViz] Background prebuild complete (\(localCache.count) layers cached)")
        }
    }

    /// Layers that have already shown the simulation failure alert (don't repeat)
    private static var alertedLayers: Set<String> = []

    @MainActor
    private static func showSimulationFailureAlert(_ report: SimulationReport) {
        let layer = report.layerName
        guard !alertedLayers.contains(layer) else { return }
        alertedLayers.insert(layer)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Simulator failed for '\(layer)' layer"
        alert.informativeText = "\(report.failureCount)/\(report.totalKeys) keys could not be resolved. Overlay icons may be missing.\n\nClick \"Copy Error\" and paste into Claude Code to debug."
        alert.addButton(withTitle: "Copy Error")
        alert.addButton(withTitle: "Dismiss")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.copyableText(), forType: .string)
        }
    }

    /// Invalidate cached mappings (call when config changes)
    func invalidateLayerMappings() {
        AppLogger.shared.info("🔔 [KeyboardViz] invalidateLayerMappings called - will rebuild layer mapping for '\(currentLayerName)'")
        AppLogger.shared.info("🔔 [KeyboardViz] Current layerKeyMap has \(layerKeyMap.count) entries, keyCode 0 = '\(layerKeyMap[0]?.displayLabel ?? "nil")'")
        cachedLauncherMappings = nil
        Task {
            await layerKeyMapper.invalidateCache()
            AppLogger.shared.info("🔔 [KeyboardViz] Cache invalidated, now calling rebuildLayerMapping()")

            rebuildLayerMapping()
            prebuildLayerMappingsInBackground()
            prewarmLauncherMappings()
        }
    }
}
