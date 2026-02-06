import Foundation
import KeyPathCore

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
                for mapping in collection.mappings {
                    let kanataKey = KanataKeyConverter.convertToKanataKey(mapping.input)
                    map[kanataKey] = collection.id
                }
            }

            // Map momentary activator keys (e.g., "w" for Window Snapping in Nav layer)
            if let activator = collection.momentaryActivator,
               activator.sourceLayer == targetLayer {
                let kanataKey = KanataKeyConverter.convertToKanataKey(activator.input)
                map[kanataKey] = collection.id
            }
        }

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
