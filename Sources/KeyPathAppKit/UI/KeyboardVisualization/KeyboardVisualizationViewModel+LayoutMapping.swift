import AppKit
import Carbon
import Foundation
import KeyPathCore
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
        let wasLauncherMode = isLauncherModeActive
        let targetLayerName = layerName

        // Set layer name immediately so computed properties (isLauncherModeActive,
        // layer indicators) update without waiting for the async mapping rebuild.
        currentLayerName = targetLayerName

        // Clear tap-hold sources on layer change to prevent stale suppressions
        // (e.g., user switches layers while holding a tap-hold key)
        activeTapHoldSources.removeAll()

        // When returning to base layer, clear hold state for all keys.
        // This handles the case where KeyInput events are unavailable (older kanata)
        // and the Release event never fires to clear holdActiveKeyCodes.
        if targetLayerName.lowercased() == "base" {
            for keyCode in holdActiveKeyCodes {
                holdClearWorkItems[keyCode]?.cancel()
                holdClearWorkItems.removeValue(forKey: keyCode)
            }
            holdActiveKeyCodes.removeAll()
            holdLabels.removeAll()
            pressedKeyCodes.removeAll()
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
            remapOutputMap = buildRemapOutputMap(from: cached)
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

                // Augment mapping with push-msg actions from custom rules and rule collections
                // Only include actions targeting this specific layer
                let customRules = await CustomRulesStore.shared.loadRules()
                AppLogger.shared.info("🗺️ [KeyboardViz] Augmenting '\(targetLayerName)' with \(customRules.count) custom rules and \(scopedRuleCollections.count) collections")
                mapping = augmentWithPushMsgActions(
                    mapping: mapping,
                    customRules: customRules,
                    ruleCollections: scopedRuleCollections,
                    currentLayerName: targetLayerName
                )

                // Apply app-specific overrides for the current frontmost app
                mapping = await applyAppSpecificOverrides(to: mapping)

                // Enrich mapping with custom shift labels from custom rules
                mapping = enrichWithCustomShiftLabels(mapping: mapping, customRules: customRules)

                // Update mapping (layer name was already set eagerly in updateLayer;
                // re-assign here for the rebuildLayerMapping() path from setLayout)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.currentLayerName = targetLayerName
                    self.layerKeyMap = mapping
                    self.remapOutputMap = self.buildRemapOutputMap(from: mapping)
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
                   targetLayerName.lowercased() != "base" {
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

    /// Build a map from input keyCode -> output keyCode for simple remaps.
    /// Used to suppress output key highlighting when the input key is pressed.
    /// - Parameter mapping: The layer key mapping to extract remap info from
    /// - Returns: Dictionary mapping input keyCodes to their output keyCodes
    func buildRemapOutputMap(from mapping: [UInt16: LayerKeyInfo]) -> [UInt16: UInt16] {
        var result: [UInt16: UInt16] = [:]
        for (inputKeyCode, info) in mapping {
            guard let outputKeyCode = info.outputKeyCode,
                  outputKeyCode != inputKeyCode, // Only actual remaps (A->B, not A->A)
                  !info.isTransparent // Transparent keys pass through, not remaps
            else {
                continue
            }
            result[inputKeyCode] = outputKeyCode
        }
        return result
    }

    /// Enrich layer mapping with custom shift labels from custom rules that have shiftedOutput.
    /// This lets the overlay keyboard show the custom shifted character instead of the system default.
    func enrichWithCustomShiftLabels(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule]
    ) -> [UInt16: LayerKeyInfo] {
        // Build lookup: kanata input name → custom shiftedOutput
        var shiftOverrides: [String: String] = [:]
        for rule in customRules where rule.isEnabled {
            guard let shiftedOutput = rule.shiftedOutput, !shiftedOutput.isEmpty else { continue }
            shiftOverrides[rule.input.lowercased()] = KeyDisplayFormatter.format(shiftedOutput)
        }
        guard !shiftOverrides.isEmpty else { return mapping }

        var result = mapping
        for (keyCode, info) in mapping {
            let kanataName = OverlayKeyboardView.keyCodeToKanataName(keyCode)
            if let customShift = shiftOverrides[kanataName.lowercased()] {
                result[keyCode] = LayerKeyInfo(
                    displayLabel: info.displayLabel,
                    outputKey: info.outputKey,
                    outputKeyCode: info.outputKeyCode,
                    isTransparent: info.isTransparent,
                    isLayerSwitch: info.isLayerSwitch,
                    appLaunchIdentifier: info.appLaunchIdentifier,
                    systemActionIdentifier: info.systemActionIdentifier,
                    urlIdentifier: info.urlIdentifier,
                    collectionId: info.collectionId,
                    vimLabel: info.vimLabel,
                    customShiftLabel: customShift
                )
            }
        }
        return result
    }

    /// Augment layer mapping with push-msg actions from custom rules and rule collections
    /// Handles app launches, system actions, and other push-msg patterns
    /// - Parameters:
    ///   - mapping: The base layer key mapping from the simulator
    ///   - customRules: Custom rules to check for push-msg patterns
    ///   - ruleCollections: Preset rule collections to check for push-msg patterns
    ///   - currentLayerName: The layer name to filter collections/rules by (only include matching layers)
    /// - Returns: Mapping with action info added where applicable
    func augmentWithPushMsgActions(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule],
        ruleCollections: [RuleCollection],
        currentLayerName: String
    ) -> [UInt16: LayerKeyInfo] {
        var augmented = mapping

        // Build lookups from input key -> LayerKeyInfo
        var actionByInput: [String: LayerKeyInfo] = [:]

        // First, process rule collections (lower priority - can be overridden by custom rules)
        // Only process collections that target the current layer or base layer
        for collection in ruleCollections where collection.isEnabled {
            // Check if this collection targets the current layer
            let collectionLayerName = collection.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            // Only include mappings from collections targeting this layer
            // Exception: base layer gets base-layer collections only
            guard collectionLayerName == currentLayer else {
                AppLogger.shared.debug("🗺️ [KeyboardViz] Skipping collection '\(collection.name)' (targets '\(collectionLayerName)', current layer '\(currentLayer)')")
                continue
            }

            for keyMapping in collection.mappings {
                let input = keyMapping.input.lowercased()
                if let info = Self.extractPushMsgInfo(from: keyMapping.action.kanataOutput, description: keyMapping.description) {
                    actionByInput[input] = info
                } else {
                    let outputKey = keyMapping.action.outputString.lowercased()
                    if let description = keyMapping.description,
                       let outputKeyCode = Self.kanataNameToKeyCode(outputKey) {
                        actionByInput[input] = .mapped(
                            displayLabel: description,
                            outputKey: outputKey,
                            outputKeyCode: outputKeyCode,
                            collectionId: collection.id
                        )
                    } else if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
                        actionByInput[input] = .systemAction(
                            action: systemAction.id,
                            description: keyMapping.description ?? systemAction.name,
                            collectionId: collection.id
                        )
                    } else if let outputKeyCode = Self.kanataNameToKeyCode(outputKey) {
                        let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                        actionByInput[input] = .mapped(
                            displayLabel: displayLabel,
                            outputKey: outputKey,
                            outputKeyCode: outputKeyCode,
                            collectionId: collection.id
                        )
                    }
                }
            }
        }

        // Then, process custom rules (higher priority - overrides collections)
        for rule in customRules where rule.isEnabled {
            // Check if this rule targets the current layer
            let ruleLayerName = rule.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            // Only include rules targeting this layer
            guard ruleLayerName == currentLayer else {
                continue
            }

            let input = rule.input.lowercased()
            // First try push-msg pattern (apps, system actions, URLs)
            if let info = Self.extractPushMsgInfo(from: rule.action.kanataOutput, description: rule.notes) {
                actionByInput[input] = info
            } else {
                // Simple key remap (e.g., "a" -> "b") or media key (e.g., "brup", "volu")
                let outputKey = rule.action.outputString.lowercased()

                // Check if this is a known system action/media key (brup, volu, pp, etc.)
                // If so, create a systemAction LayerKeyInfo so the SF Symbol renders correctly
                if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
                    actionByInput[input] = .systemAction(
                        action: systemAction.id,
                        description: systemAction.name
                    )
                } else if let outputKeyCode = Self.kanataNameToKeyCode(outputKey) {
                    // Regular key remap (e.g., "a" -> "b")
                    let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                    actionByInput[input] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: outputKeyCode
                    )
                }
            }
        }

        AppLogger.shared.info("🗺️ [KeyboardViz] Found \(actionByInput.count) actions (push-msg + simple remaps)")

        // Update mapping entries
        // IMPORTANT: Only augment keys that are NOT transparent (XX)
        // Transparent keys should pass through without showing action labels
        for (keyCode, originalInfo) in mapping {
            let keyName = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
            if let info = actionByInput[keyName] {
                let resolvedInfo = Self.mergeAugmentation(info, with: originalInfo)
                augmented[keyCode] = resolvedInfo
            }
        }

        return augmented
    }

    /// Merge augmented info with the original simulator entry, preserving vimLabel
    /// and preferring the simulator's displayLabel when a vimLabel exists (so arrow
    /// keys show "←" instead of description text like "h — left").
    nonisolated static func mergeAugmentation(
        _ augmented: LayerKeyInfo,
        with original: LayerKeyInfo
    ) -> LayerKeyInfo {
        let collectionId = original.collectionId ?? augmented.collectionId
        let vimLabel = original.vimLabel ?? augmented.vimLabel
        let displayLabel = vimLabel != nil ? (original.displayLabel.isEmpty ? augmented.displayLabel : original.displayLabel) : augmented.displayLabel

        return LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: augmented.outputKey ?? original.outputKey,
            outputKeyCode: augmented.outputKeyCode ?? original.outputKeyCode,
            isTransparent: augmented.isTransparent,
            isLayerSwitch: augmented.isLayerSwitch,
            appLaunchIdentifier: augmented.appLaunchIdentifier,
            systemActionIdentifier: augmented.systemActionIdentifier,
            urlIdentifier: augmented.urlIdentifier,
            collectionId: collectionId,
            vimLabel: vimLabel
        )
    }

    // MARK: - Cached Regex Patterns

    /// Cached regex for extracting push-msg type:value patterns
    /// Pattern: (push-msg "type:value")
    private nonisolated static let pushMsgTypeValueRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"([^:\"]+):([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    /// Cached regex for extracting app launch identifiers
    /// Pattern: (push-msg "launch:AppName")
    private nonisolated static let pushMsgLaunchRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"launch:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    /// Cached regex for extracting URL identifiers
    /// Pattern: (push-msg "open:domain.com")
    private nonisolated static let pushMsgOpenRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"open:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    /// Cached regex for extracting system action identifiers
    /// Pattern: (push-msg "system:notification-center")
    private nonisolated static let pushMsgSystemRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"system:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    /// Extract LayerKeyInfo from a push-msg output string
    /// Handles: launch:, system:, and generic push-msg patterns
    nonisolated static func extractPushMsgInfo(from output: String, description: String?) -> LayerKeyInfo? {
        guard let match = pushMsgTypeValueRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let typeRange = Range(match.range(at: 1), in: output),
              let valueRange = Range(match.range(at: 2), in: output)
        else {
            return nil
        }

        let msgType = String(output[typeRange]).lowercased()
        let msgValue = String(output[valueRange])

        switch msgType {
        case "launch":
            return .appLaunch(appIdentifier: msgValue)
        case "system":
            // Use description if available, otherwise format the system action
            let displayLabel = description ?? Self.systemActionDisplayLabel(msgValue)
            return .systemAction(action: msgValue, description: displayLabel)
        case "open":
            return .webURL(url: URLMappingFormatter.decodeFromPushMessage(msgValue))
        default:
            // Generic push-msg - use description or message value
            return .pushMsg(message: description ?? msgValue)
        }
    }

    /// Get a human-readable label for a system action
    nonisolated static func systemActionDisplayLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            "Do Not Disturb"
        case "spotlight":
            "Spotlight"
        case "dictation":
            "Dictation"
        case "mission-control", "missioncontrol":
            "Mission Control"
        case "launchpad":
            "Launchpad"
        case "notification-center", "notificationcenter":
            "Notification Center"
        case "siri":
            "Siri"
        default:
            action.capitalized
        }
    }

    /// Get a human-readable label for media/function keys (returns nil if not a recognized media key)
    /// These labels match what LabelMetadata.sfSymbol(forOutputLabel:) expects for icon lookup
    nonisolated static func mediaKeyDisplayLabel(_ kanataKey: String) -> String? {
        switch kanataKey.lowercased() {
        case "brup": "Brightness Up"
        case "brdn", "brdown": "Brightness Down"
        case "volu": "Volume Up"
        case "vold", "voldwn": "Volume Down"
        case "mute": "Mute"
        case "pp": "Play/Pause"
        case "next": "Next Track"
        case "prev": "Previous Track"
        default: nil
        }
    }

    /// Extract app identifier from a push-msg launch output string
    /// - Parameter output: The kanata output string (e.g., "(push-msg \"launch:Safari\")")
    /// - Returns: The app identifier if this is a launch action, nil otherwise
    nonisolated static func extractAppLaunchIdentifier(from output: String) -> String? {
        guard let match = pushMsgLaunchRegex.firstMatch(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ),
            let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        let value = String(output[range])
        return URLMappingFormatter.decodeFromPushMessage(value)
    }

    /// Extract URL from a push-msg open output string
    /// - Parameter output: The kanata output string (e.g., "(push-msg \"open:github.com\")")
    /// - Returns: The URL string if this is an open action, nil otherwise
    nonisolated static func extractUrlIdentifier(from output: String) -> String? {
        guard let match = pushMsgOpenRegex.firstMatch(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ),
            let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        let value = String(output[range])
        return URLMappingFormatter.decodeFromPushMessage(value)
    }

    /// Extract system action ID from a push-msg system output string
    /// - Parameter output: The kanata output string (e.g., "(push-msg \"system:notification-center\")")
    /// - Returns: The action identifier if this is a system action, nil otherwise
    nonisolated static func extractSystemActionIdentifier(from output: String) -> String? {
        guard let match = pushMsgSystemRegex.firstMatch(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ),
            let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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
                    mapping = await MainActor.run {
                        self.augmentWithPushMsgActions(
                            mapping: mapping,
                            customRules: customRules,
                            ruleCollections: enabledCollections,
                            currentLayerName: layer
                        )
                    }
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
