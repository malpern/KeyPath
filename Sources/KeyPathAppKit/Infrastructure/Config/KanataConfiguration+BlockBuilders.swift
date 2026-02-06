import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

extension KanataConfiguration {
    // MARK: - Block builders

    struct LayerActivationPlan {
        let activatorKeysBySourceLayer: [RuleCollectionLayer: Set<String>]
        let hyperLinkedLayerInfos: [HyperLinkedLayerInfo]
        let oneShotLayers: Set<RuleCollectionLayer>
    }

    struct CollectionBlock {
        let metadata: [String]
        let entries: [LayerEntry]
    }

    struct LayerEntry {
        let sourceKey: String
        let baseOutput: String
        let layerOutputs: [RuleCollectionLayer: String]
    }

    struct AliasDefinition {
        let aliasName: String
        let definition: String
    }

    /// Represents a chord mapping (simultaneous key presses)
    struct ChordMapping {
        let inputKeys: String // Space-separated keys, e.g., "lsft rsft"
        let output: String // Output action, e.g., "caps"
        let description: String?
    }

    static func buildCollectionBlocks(
        from collections: [RuleCollection],
        leaderKeyPreference: LeaderKeyPreference?
    ) -> ([CollectionBlock], [AliasDefinition], [RuleCollectionLayer], [ChordMapping]) {
        var blocks: [CollectionBlock] = []
        var aliasDefinitions: [AliasDefinition] = []
        var additionalLayers: [RuleCollectionLayer] = []
        var chordMappings: [ChordMapping] = []
        var seenLayers = Set<RuleCollectionLayer>()
        var activatorBlocks: [CollectionBlock] = []
        var seenActivators: Set<String> = []
        let oneShotTimeoutMs = 65000 // Max-safe timeout (Kanata limit 65535)
        let oneShotPauseMs = 10

        // Generate primary leader key alias from system preference (independent of collections)
        if let pref = leaderKeyPreference, pref.enabled {
            let tapKey = KanataKeyConverter.convertToKanataKey(pref.key)
            let tapOutput = tapKey
            let layerName = pref.targetLayer.kanataName
            let aliasName = aliasSafeName(layer: pref.targetLayer, key: tapKey)

            // Add to additional layers if not base
            if pref.targetLayer != .base {
                if !seenLayers.contains(pref.targetLayer) {
                    seenLayers.insert(pref.targetLayer)
                    additionalLayers.append(pref.targetLayer)
                }
            }

            seenActivators.insert(aliasName)

            let definition = if pref.targetLayer == .navigation {
                // Tap-hold enters nav, then keep it active until next key (one-shot)
                "(tap-hold $tap-timeout $hold-timeout \(tapOutput)\n    (multi\n      (on-press-fakekey kp-layer-\(layerName)-enter tap)\n      (one-shot-pause-processing \(oneShotPauseMs))\n      (one-shot-press \(oneShotTimeoutMs) (layer-while-held \(layerName)))))"
            } else {
                // Standard tap-hold for primary leader key (always from base layer)
                "(tap-hold $tap-timeout $hold-timeout \(tapOutput)\n    (multi\n      (layer-while-held \(layerName))\n      (on-press-fakekey kp-layer-\(layerName)-enter tap)\n      (on-release-fakekey kp-layer-\(layerName)-exit tap)))"
            }

            aliasDefinitions.append(AliasDefinition(aliasName: aliasName, definition: definition))

            let entry = LayerEntry(
                sourceKey: tapKey,
                baseOutput: "@\(aliasName)",
                layerOutputs: [:]
            )

            let metadata = [
                "  ;; === Primary Leader Key (System Preference) ===",
                "  ;; Input: \(pref.key)",
                "  ;; Activates: \(pref.targetLayer.displayName)"
            ]
            activatorBlocks.append(CollectionBlock(metadata: metadata, entries: [entry]))
        }

        let activationPlan = makeLayerActivationPlan(
            collections: collections,
            leaderKeyPreference: leaderKeyPreference
        )
        let activatorKeysBySourceLayer = activationPlan.activatorKeysBySourceLayer
        let hyperLinkedLayerInfos = activationPlan.hyperLinkedLayerInfos
        let oneShotLayers = activationPlan.oneShotLayers

        func wrapWithOneShotExit(
            _ output: String,
            layer: RuleCollectionLayer,
            sourceKey: String,
            hasLayerBasePush: Bool
        ) -> String {
            guard layer != .base, oneShotLayers.contains(layer) else { return output }
            guard !hasLayerBasePush else { return output }
            if activatorKeysBySourceLayer[layer]?.contains(sourceKey) == true { return output }
            // Use release-layer to explicitly release the layer-while-held, then output, then notify UI
            return "(multi (release-layer \(layer.kanataName)) \(output) (push-msg \"layer:base\"))"
        }

        // Precompute mapped keys for non-base layers to avoid blocking keys mapped by other collections.
        var layerMappedKeys: [RuleCollectionLayer: Set<String>] = [:]

        for collection in collections where collection.isEnabled {
            let mappings = effectiveMappings(for: collection)
            let regularMappings = mappings.filter { !$0.input.contains(" ") }
            let inputs = regularMappings.map { KanataKeyConverter.convertToKanataKey($0.input) }
            var existing = layerMappedKeys[collection.targetLayer, default: []]
            existing.formUnion(inputs)
            layerMappedKeys[collection.targetLayer] = existing
        }

        for collection in collections where collection.targetLayer != .base {
            if !seenLayers.contains(collection.targetLayer) {
                seenLayers.insert(collection.targetLayer)
                additionalLayers.append(collection.targetLayer)
            }
        }

        for collection in collections {
            guard collection.isEnabled, let activator = collection.momentaryActivator else { continue }

            // Skip "hyper" activators - they're integrated into the hyper hold action
            // (handled by KanataBehaviorRenderer via hyperLinkedLayerInfos set above)
            if activator.input.lowercased() == "hyper" {
                continue
            }

            let tapKey = KanataKeyConverter.convertToKanataKey(activator.input)
            let tapOutput = tapKey
            let aliasName = aliasSafeName(layer: activator.targetLayer, key: tapKey)
            if !seenActivators.contains(aliasName) {
                seenActivators.insert(aliasName)
                let layerName = activator.targetLayer.kanataName

                // For chained layers (sourceLayer != .base), use one-shot-press instead of tap-hold
                // This allows quick entry to nested layers without requiring hold
                let definition = if activator.sourceLayer == .base {
                    if activator.targetLayer == .navigation {
                        // Tap-hold enters nav, then keep it active until next key (one-shot)
                        "(tap-hold $tap-timeout $hold-timeout \(tapOutput)\n    (multi\n      (on-press-fakekey kp-layer-\(layerName)-enter tap)\n      (one-shot-pause-processing \(oneShotPauseMs))\n      (one-shot-press \(oneShotTimeoutMs) (layer-while-held \(layerName)))))"
                    } else {
                        // Standard tap-hold for base layer activators
                        // Use multi to combine layer-while-held with fake key triggers for TCP layer notifications.
                        // This works around Kanata's limitation where layer-while-held doesn't broadcast LayerChange messages.
                        "(tap-hold $tap-timeout $hold-timeout \(tapOutput)\n    (multi\n      (layer-while-held \(layerName))\n      (on-press-fakekey kp-layer-\(layerName)-enter tap)\n      (on-release-fakekey kp-layer-\(layerName)-exit tap)))"
                    }
                } else {
                    // One-shot for chained layers (e.g., nav → window, nav → sym)
                    // Activates target layer until next key press (or timeout).
                    // Include layer notification fake keys for overlay and UI updates.
                    "(multi (on-press-fakekey kp-layer-\(layerName)-enter tap) (one-shot-pause-processing \(oneShotPauseMs)) (one-shot-press \(oneShotTimeoutMs) (layer-while-held \(layerName))))"
                }
                aliasDefinitions.append(AliasDefinition(aliasName: aliasName, definition: definition))

                // Determine where to place the activator
                let entry = if activator.sourceLayer == .base {
                    LayerEntry(
                        sourceKey: tapKey,
                        baseOutput: "@\(aliasName)",
                        layerOutputs: [:]
                    )
                } else {
                    // Chained activator: place in source layer, passthrough in base
                    LayerEntry(
                        sourceKey: tapKey,
                        baseOutput: tapKey, // Passthrough in base layer
                        layerOutputs: [activator.sourceLayer: "@\(aliasName)"]
                    )
                }
                let metadata = metadataLines(for: activator, indent: "  ")
                activatorBlocks.append(CollectionBlock(metadata: metadata, entries: [entry]))
            }
        }

        for collection in collections where collection.isEnabled {
            var metadata = metadataLines(for: collection, indent: "  ", status: "enabled")

            // Handle special display styles: generate mappings from config
            let effectiveMappings = effectiveMappings(for: collection)

            // Separate chord mappings (input contains space = multiple simultaneous keys)
            let regularMappings = effectiveMappings.filter { !$0.input.contains(" ") }
            let chordInputMappings = effectiveMappings.filter { $0.input.contains(" ") }

            // Add chord mappings to the separate chord list
            for mapping in chordInputMappings {
                let inputKeys = mapping.input.split(separator: " ").map { KanataKeyConverter.convertToKanataKey(String($0)) }.joined(separator: " ")
                let output = KanataKeyConverter.convertToKanataSequence(mapping.output)
                chordMappings.append(ChordMapping(inputKeys: inputKeys, output: output, description: mapping.description))
            }

            if regularMappings.isEmpty {
                if !chordInputMappings.isEmpty {
                    // Collection has only chord mappings - add metadata comment
                    metadata.append("  ;; (chord mappings in defchordsv2 block)")
                } else {
                    metadata.append("  ;; (no mappings)")
                }
                blocks.append(CollectionBlock(metadata: metadata, entries: []))
                continue
            }
            var entries = regularMappings.map { mapping -> LayerEntry in
                let sourceKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                var layerOutputs: [RuleCollectionLayer: String] = [:]

                let trimmedOutput = mapping.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasLayerBasePush = trimmedOutput.contains("layer:base")

                // Determine the output action based on behavior or simple output
                var layerOutput: String
                if mapping.behavior != nil {
                    // Advanced behavior (tap-hold, tap-dance) - use renderer
                    // Pass hyperLinkedLayerInfos so "hyper" hold action includes linked layer activations
                    let rendered = KanataBehaviorRenderer.render(mapping, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
                    // Create alias for complex behaviors to keep deflayer clean
                    let aliasName = behaviorAliasName(for: mapping, layer: collection.targetLayer)
                    aliasDefinitions.append(AliasDefinition(aliasName: aliasName, definition: rendered))
                    layerOutput = "@\(aliasName)"
                } else if mapping.requiresFork {
                    // Generate fork alias for mappings with modifier-specific outputs
                    let aliasName = forkAliasName(for: mapping, layer: collection.targetLayer)
                    let forkDef = buildForkDefinition(for: mapping)
                    aliasDefinitions.append(AliasDefinition(aliasName: aliasName, definition: forkDef))
                    layerOutput = "@\(aliasName)"
                } else if trimmedOutput.hasPrefix("("), trimmedOutput.count > 1 {
                    // Complex action (push-msg, multi, etc.) - needs alias
                    let aliasName = actionAliasName(for: mapping, layer: collection.targetLayer)
                    aliasDefinitions.append(AliasDefinition(aliasName: aliasName, definition: trimmedOutput))
                    layerOutput = "@\(aliasName)"
                } else {
                    // Simple output (key name)
                    layerOutput = KanataKeyConverter.convertToKanataSequence(trimmedOutput)
                }

                if collection.targetLayer != .base {
                    layerOutputs[collection.targetLayer] = wrapWithOneShotExit(
                        layerOutput,
                        layer: collection.targetLayer,
                        sourceKey: sourceKey,
                        hasLayerBasePush: hasLayerBasePush
                    )
                }
                let baseOutput: String =
                    if collection.targetLayer == .base {
                        layerOutput
                    } else {
                        sourceKey
                    }
                return LayerEntry(
                    sourceKey: sourceKey,
                    baseOutput: baseOutput,
                    layerOutputs: layerOutputs
                )
            }

            // For Vim collection: optionally block unmapped keys in navigation layer
            if collection.id == RuleCollectionIdentifier.vimNavigation,
               collection.targetLayer != .base {
                let mappedKeys = layerMappedKeys[collection.targetLayer] ?? Set(entries.map(\.sourceKey))
                // Skip ALL activator keys that target this layer, not just Vim's own activator
                // This prevents blocking layer-switch keys like "w" (Nav → Window)
                let keysToSkip = activatorKeysBySourceLayer[collection.targetLayer] ?? []
                // Read user's selected physical layout from UserDefaults
                let selectedLayoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
                let layout = PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
                let extraKeys = Self.navigationUnmappedKeys(
                    excluding: mappedKeys,
                    skipping: keysToSkip,
                    layout: layout
                )
                let blockedEntries = extraKeys.map { key in
                    let layerOutput = wrapWithOneShotExit(
                        "XX",
                        layer: collection.targetLayer,
                        sourceKey: key,
                        hasLayerBasePush: false
                    )
                    return LayerEntry(
                        sourceKey: key,
                        baseOutput: key, // base layer keeps normal behavior
                        layerOutputs: [collection.targetLayer: layerOutput] // nav layer blocks output
                    )
                }
                entries.append(contentsOf: blockedEntries)
            }

            blocks.append(CollectionBlock(metadata: metadata, entries: entries))
        }

        if !oneShotLayers.isEmpty {
            var layerOutputs: [RuleCollectionLayer: String] = [:]
            for layer in oneShotLayers {
                // Use release-layer to explicitly release the layer-while-held, XX blocks output, notify UI
                layerOutputs[layer] = "(multi (release-layer \(layer.kanataName)) XX (push-msg \"layer:base\"))"
            }
            let entry = LayerEntry(
                sourceKey: KanataKeyConverter.convertToKanataKey("esc"),
                baseOutput: KanataKeyConverter.convertToKanataKey("esc"),
                layerOutputs: layerOutputs
            )
            let metadata = [
                "  ;; === One-Shot Cancel (Esc) ===",
                "  ;; Cancels one-shot layers and returns to base"
            ]
            blocks.append(CollectionBlock(metadata: metadata, entries: [entry]))
        }

        return (activatorBlocks + blocks, aliasDefinitions, additionalLayers, chordMappings)
    }

    static func makeLayerActivationPlan(
        collections: [RuleCollection],
        leaderKeyPreference: LeaderKeyPreference?
    ) -> LayerActivationPlan {
        // Collect all activator keys for each source layer to avoid blocking them.
        var activatorKeysBySourceLayer: [RuleCollectionLayer: Set<String>] = [:]

        // Include the primary leader key in activator tracking.
        if let pref = leaderKeyPreference, pref.enabled {
            let tapKey = KanataKeyConverter.convertToKanataKey(pref.key)
            activatorKeysBySourceLayer[.base, default: []].insert(tapKey)
        }

        for collection in collections {
            guard collection.isEnabled, let activator = collection.momentaryActivator else { continue }
            let tapKey = KanataKeyConverter.convertToKanataKey(activator.input)
            activatorKeysBySourceLayer[activator.sourceLayer, default: []].insert(tapKey)
        }

        // Detect layers that should be activated when "hyper" is triggered.
        // These are collections with momentaryActivator.input == "hyper" (like Quick Launcher).
        // Since "hyper" isn't a physical key, we integrate these layers into the hyper hold action
        // of collections like Caps Lock Remap that output hyper on hold.
        let hyperLinkedLayerInfos: [HyperLinkedLayerInfo] = collections
            .filter(\.isEnabled)
            .compactMap { collection -> HyperLinkedLayerInfo? in
                guard let activator = collection.momentaryActivator,
                      activator.input.lowercased() == "hyper"
                else {
                    return nil
                }
                // Get trigger mode from launcher config if available.
                let triggerMode: HyperTriggerMode = collection.configuration.launcherGridConfig?.hyperTriggerMode ?? .hold
                return HyperLinkedLayerInfo(layerName: activator.targetLayer.kanataName, triggerMode: triggerMode)
            }

        // Layers that should behave as one-shot (stay active until next key press).
        var oneShotLayers = Set<RuleCollectionLayer>()
        if let pref = leaderKeyPreference, pref.enabled, pref.targetLayer == .navigation {
            oneShotLayers.insert(pref.targetLayer)
        }
        for collection in collections where collection.isEnabled {
            guard let activator = collection.momentaryActivator else { continue }
            guard activator.input.lowercased() != "hyper" else { continue }
            if activator.targetLayer == .navigation {
                oneShotLayers.insert(activator.targetLayer)
            }
            if activator.sourceLayer != .base {
                oneShotLayers.insert(activator.targetLayer)
            }
        }

        return LayerActivationPlan(
            activatorKeysBySourceLayer: activatorKeysBySourceLayer,
            hyperLinkedLayerInfos: hyperLinkedLayerInfos,
            oneShotLayers: oneShotLayers
        )
    }

    static func effectiveMappings(for collection: RuleCollection) -> [KeyMapping] {
        switch collection.configuration {
        case let .homeRowMods(config):
            generateHomeRowModsMappings(from: config)
        case let .homeRowLayerToggles(config):
            generateHomeRowLayerTogglesMappings(from: config)
        case let .chordGroups(config):
            generateChordGroupsMappings(from: config)
        case .sequences:
            // Sequences don't generate mappings - handled by defseq.
            collection.mappings
        case .tapHoldPicker:
            generateTapHoldPickerMappings(from: collection)
        case .layerPresetPicker:
            generateLayerPresetMappings(from: collection)
        case let .launcherGrid(config):
            generateLauncherGridMappings(from: config)
        case .list, .table, .singleKeyPicker:
            collection.mappings
        }
    }

    static func deduplicateBlocks(_ blocks: [CollectionBlock]) -> [CollectionBlock] {
        // Merge entries with the same source key instead of just keeping the first one.
        // This ensures layer-specific mappings (like launcher in launcher layer) aren't lost
        // when another collection (like Vim) also uses the same keys in a different layer.
        var mergedEntries: [String: LayerEntry] = [:]
        var entriesByBlock: [[String]] = [] // Track which keys belong to which block
        var keyOrder: [String] = [] // Preserve insertion order

        for block in blocks {
            var blockKeys: [String] = []
            for entry in block.entries {
                if let existing = mergedEntries[entry.sourceKey] {
                    // Merge layer outputs from this entry into the existing one
                    var combinedLayerOutputs = existing.layerOutputs
                    for (layer, output) in entry.layerOutputs {
                        combinedLayerOutputs[layer] = output
                    }
                    // Keep the base output from the first entry (earlier collection takes precedence)
                    mergedEntries[entry.sourceKey] = LayerEntry(
                        sourceKey: existing.sourceKey,
                        baseOutput: existing.baseOutput,
                        layerOutputs: combinedLayerOutputs
                    )
                } else {
                    // New key - add it
                    mergedEntries[entry.sourceKey] = entry
                    keyOrder.append(entry.sourceKey)
                }
                blockKeys.append(entry.sourceKey)
            }
            entriesByBlock.append(blockKeys)
        }

        // Rebuild blocks with merged entries, keeping original block structure
        var result: [CollectionBlock] = []
        var usedKeys: Set<String> = []

        for (index, block) in blocks.enumerated() {
            let blockKeySet = Set(entriesByBlock[index])
            var uniqueEntries: [LayerEntry] = []
            for key in keyOrder {
                guard blockKeySet.contains(key), !usedKeys.contains(key) else { continue }
                if let entry = mergedEntries[key] {
                    uniqueEntries.append(entry)
                    usedKeys.insert(key)
                }
            }
            result.append(CollectionBlock(metadata: block.metadata, entries: uniqueEntries))
        }

        return result
    }

    /// Build a deterministic list of unmapped keys on the specified physical layout to block in navigation layer.
    /// Excludes modifier keys and any keys already mapped.
    /// - Parameters:
    ///   - mappedKeys: Keys that are already mapped (will not be blocked)
    ///   - extraSkips: Additional keys to skip (e.g., layer activator key)
    ///   - layout: The physical keyboard layout to use for determining available keys
    static func navigationUnmappedKeys(
        excluding mappedKeys: Set<String>,
        skipping extraSkips: Set<String> = [],
        layout: PhysicalLayout = .macBookUS
    ) -> [String] {
        // Skip modifier/utility keys and any explicitly provided skips (e.g., activator key)
        let defaultSkips: Set<String> = [
            "leftmeta", "rightmeta", "leftctrl", "rightctrl",
            "leftalt", "rightalt", "leftshift", "rightshift",
            "capslock", "fn"
        ]
        let skip = defaultSkips.union(extraSkips)

        let keys = layout.keys.compactMap { key -> String? in
            // Skip invalid keycodes (e.g., Touch ID uses 0xFFFF as placeholder)
            guard key.keyCode != 0xFFFF else { return nil }
            let name = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
            // Skip unknown keycodes
            guard !name.hasPrefix("unknown-") else { return nil }
            guard !skip.contains(name) else { return nil }
            let converted = KanataKeyConverter.convertToKanataKey(name)
            let kanata = normalizeInternationalKey(converted)
            guard !mappedKeys.contains(kanata) else { return nil }
            return kanata
        }

        return Array(Set(keys)).sorted()
    }

    static func normalizeInternationalKey(_ key: String) -> String {
        switch key {
        case "hangeul", "hangul", "lang1":
            "kana"
        case "hanja", "lang2":
            "eisu"
        default:
            key
        }
    }

    static func aliasSafeName(layer: RuleCollectionLayer, key: String) -> String {
        let sanitized =
            key
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        return "layer_\(layer.kanataName)_\(sanitized)"
    }

    /// Generate alias name for fork-based modifier detection
    static func forkAliasName(for mapping: KeyMapping, layer: RuleCollectionLayer) -> String {
        let sanitized =
            mapping.input
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        return "fork_\(layer.kanataName)_\(sanitized)"
    }

    /// Generate alias name for advanced behavior (tap-hold, tap-dance)
    static func behaviorAliasName(for mapping: KeyMapping, layer: RuleCollectionLayer) -> String {
        let sanitized =
            mapping.input
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        return "beh_\(layer.kanataName)_\(sanitized)"
    }

    /// Generate alias name for complex actions (push-msg, multi, etc.)
    static func actionAliasName(for mapping: KeyMapping, layer: RuleCollectionLayer) -> String {
        let sanitized =
            mapping.input
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        return "act_\(layer.kanataName)_\(sanitized)"
    }

    /// Build fork definition for modifier-aware mappings
    /// Fork syntax: (fork default-action alternate-action (trigger-keys))
    /// Note: Inside fork, modifier prefixes like m-right must be (multi lmet right)
    static func buildForkDefinition(for mapping: KeyMapping) -> String {
        let defaultOutput = normalizeForkOutput(convertToForkAction(mapping.output))

        // Shift modifier takes precedence
        if let shiftedOutput = mapping.shiftedOutput {
            let shiftOutput = normalizeForkOutput(convertToForkAction(shiftedOutput))
            return "(fork \(defaultOutput) \(shiftOutput) (lsft rsft))"
        }

        // Ctrl modifier
        if let ctrlOutput = mapping.ctrlOutput {
            let ctrlOutputConverted = normalizeForkOutput(convertToForkAction(ctrlOutput))
            return "(fork \(defaultOutput) \(ctrlOutputConverted) (lctl rctl))"
        }

        // Fallback (shouldn't reach here if requiresFork is true)
        return defaultOutput
    }

    /// Convert a key output to a fork-compatible action
    /// - Single keys with modifiers: (multi modifier key) format
    /// - Multi-key sequences: (macro ...) with chord syntax inside
    static func convertToForkAction(_ output: String) -> String {
        let tokens = output.split(separator: " ").map(String.init)

        if tokens.count > 1 {
            // Multi-key sequence -> wrap in macro
            // Inside macro, chord syntax (M-right) works and requires UPPERCASE prefixes
            let converted = tokens.map { KanataKeyConverter.convertToKanataKeyForMacro($0) }
            return "(macro \(converted.joined(separator: " ")))"
        } else if let single = tokens.first {
            // Single key - must use (multi ...) format for modifiers inside fork
            return convertSingleKeyToForkFormat(single)
        }
        return output
    }

    /// Normalize modifier-prefixed outputs inside fork actions.
    /// If an output looks like a modified key (e.g., m-right), convert to (multi ...).
    static func normalizeForkOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Leave complex actions or multi-token outputs alone.
        if trimmed.hasPrefix("(") || trimmed.contains(" ") {
            return output
        }

        let uppercased = trimmed.uppercased()
        let modifierMap: [(prefix: String, keys: String)] = [
            ("M-S-", "lmet lsft"),
            ("C-S-", "lctl lsft"),
            ("A-S-", "lalt lsft"),
            ("M-", "lmet"),
            ("A-", "lalt"),
            ("C-", "lctl"),
            ("S-", "lsft")
        ]

        guard let (prefix, keys) = modifierMap.first(where: { uppercased.hasPrefix($0.prefix) }) else {
            return output
        }

        let baseKey = String(trimmed.dropFirst(prefix.count))
        let kanataKey = KanataKeyConverter.convertToKanataKey(baseKey)
        return "(multi \(keys) \(kanataKey))"
    }

    /// Convert a single key (possibly with modifiers) to fork-compatible format
    /// e.g., "M-right" -> "(multi lmet right)", "pgup" -> "pgup"
    /// Note: Inside fork actions (not inside macro), modifier prefixes must be (multi ...)
    static func convertSingleKeyToForkFormat(_ key: String) -> String {
        // Map modifier prefixes to their key names
        let modifierMap: [(prefix: String, key: String)] = [
            ("M-S-", "lmet lsft"), // Meta+Shift
            ("C-S-", "lctl lsft"), // Ctrl+Shift
            ("A-S-", "lalt lsft"), // Alt+Shift
            ("M-", "lmet"), // Meta/Command
            ("A-", "lalt"), // Alt/Option
            ("C-", "lctl"), // Control
            ("S-", "lsft") // Shift
        ]

        var remainingKey = key
        var modifiers: [String] = []

        // Extract all modifier prefixes (only match first one, case-insensitive)
        let lowercasedKey = remainingKey.lowercased()
        if let (prefix, modKey) = modifierMap.first(where: { lowercasedKey.hasPrefix($0.key.lowercased()) }) {
            modifiers.append(contentsOf: modKey.split(separator: " ").map(String.init))
            remainingKey = String(remainingKey.dropFirst(prefix.count))
        }

        if modifiers.isEmpty {
            // No modifiers - return as-is (convert to kanata key format)
            return KanataKeyConverter.convertToKanataKey(remainingKey)
        }

        // Has modifiers - wrap in (multi ...)
        let baseKey = KanataKeyConverter.convertToKanataKey(remainingKey)
        return "(multi \(modifiers.joined(separator: " ")) \(baseKey))"
    }
}
