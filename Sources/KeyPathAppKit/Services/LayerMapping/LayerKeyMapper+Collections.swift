import Foundation
import KeyPathCore
import KeyPathRulesCore

extension LayerKeyMapper {
    // MARK: - Collection Ownership Mapping

    /// Build reverse mapping from key names to collection UUIDs
    /// This allows us to track which collection each key belongs to in the overlay
    /// - Parameters:
    ///   - layerName: The layer to build mapping for (e.g., "nav", "window")
    ///   - collections: All enabled rule collections
    /// - Returns: Dictionary mapping Kanata key names to collection UUIDs
    nonisolated func buildKeyCollectionMap(
        for layerName: String,
        collections: [RuleCollection]
    ) -> [String: UUID] {
        var map: [String: UUID] = [:]

        // Convert layer name to RuleCollectionLayer for comparison
        let targetLayer = RuleCollectionLayer(kanataName: layerName)

        for collection in collections {
            guard collection.isEnabled else { continue }

            // Map regular keys from this collection's mappings
            if collection.targetLayer == targetLayer {
                // Preset-based rules (Home Row Arrows) keep their keys in the selected
                // preset, not in `mappings`; without them the keys draw unowned and pale.
                let presetMappings = collection.configuration.layerPresetPickerConfig?.selectedMappings ?? []
                for mapping in collection.mappings + presetMappings {
                    let kanataKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                    map[kanataKey] = collection.id
                    // Lookups use simulator names ("comm" for ","), which differ from
                    // config names for punctuation; record both so "," is owned too.
                    map[toSimulatorKeyName(kanataKey)] = collection.id
                }
            }

            // Map momentary activator keys (e.g., "w" for Window Snapping in Nav layer)
            if let activator = collection.momentaryActivator,
               activator.sourceLayer == targetLayer
            {
                let kanataKey = KanataKeyConverter.convertToKanataKey(activator.input)
                map[kanataKey] = collection.id
            }
        }

        return map
    }

    /// Mission Control keycap labels: what each key opens, short enough for one unit.
    static let missionControlKeycapLabels: [String: String] = [
        "m": "Mission",
        "q": "Exposé",
        "t": "Desktop",
        "c": "Alerts",
        ",": "◀ Space",
        ".": "Space ▶"
    ]

    /// Build mapping from key names to short vim overlay labels for VIM collections
    /// - Parameters:
    ///   - layerName: The layer to build mapping for
    ///   - collections: All enabled rule collections
    /// - Returns: Dictionary mapping Kanata key names to short vim labels
    nonisolated func buildKeyVimLabelMap(
        for layerName: String,
        collections: [RuleCollection]
    ) -> [String: String] {
        var map: [String: String] = [:]
        let targetLayer = RuleCollectionLayer(kanataName: layerName)

        for collection in collections {
            guard collection.isEnabled,
                  collection.targetLayer == targetLayer else { continue }

            if collection.id == RuleCollectionIdentifier.vimNavigation {
                AppLogger.shared.info("🗺️ [VimLabel] Found VIM collection for layer '\(layerName)', \(collection.mappings.count) mappings")
                for mapping in collection.mappings {
                    let kanataKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                    // Same names as the Shortcut List and Settings (VimLayerReference).
                    if let label = VimLayerReference.presentation(
                        forInput: mapping.input, style: VimKeyNameStyle.current(for: collection.id)
                    )?.keycapLabel {
                        map[kanataKey] = label
                    }
                }
            } else if collection.id == RuleCollectionIdentifier.missionControl {
                // Short names instead of the raw shortcuts (↓⌃, N⇧⌃, F11) the keys send.
                for mapping in collection.mappings {
                    let kanataKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                    if let label = Self.missionControlKeycapLabels[mapping.input.lowercased()] {
                        map[kanataKey] = label
                        map[toSimulatorKeyName(kanataKey)] = label
                    }
                }
            } else if collection.id == RuleCollectionIdentifier.neovimTerminal {
                AppLogger.shared.info("🗺️ [VimLabel] Found Neovim Terminal collection for layer '\(layerName)', \(collection.mappings.count) mappings")
                for mapping in collection.mappings {
                    let kanataKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                    // Same names as Vim Navigation, plus the word motions.
                    if let label = VimLayerReference.presentation(
                        forInput: mapping.input, style: VimKeyNameStyle.current(for: collection.id)
                    )?.keycapLabel {
                        map[kanataKey] = label
                    }
                }
            }
        }

        AppLogger.shared.info("🗺️ [VimLabel] Built keyToVimLabel for '\(layerName)': \(map.count) entries — \(map)")
        return map
    }

    /// Build a set of activator keys for the given source layer.
    /// Used to ensure layer-switch keys are highlighted even when simulator outputs are empty.
    nonisolated func buildActivatorKeySet(
        for layerName: String,
        collections: [RuleCollection]
    ) -> Set<String> {
        var keys = Set<String>()
        let targetLayer = RuleCollectionLayer(kanataName: layerName)

        for collection in collections where collection.isEnabled {
            guard let activator = collection.momentaryActivator,
                  activator.sourceLayer == targetLayer else { continue }
            let kanataKey = KanataKeyConverter.convertToKanataKey(activator.input)
            keys.insert(kanataKey.lowercased())
        }

        return keys
    }
}
