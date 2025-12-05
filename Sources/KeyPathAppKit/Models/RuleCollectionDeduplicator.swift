import Foundation

enum RuleCollectionDeduplicator {
    /// Deduplicates collections by removing duplicate input keys.
    /// - First collection to claim an input key (per layer) wins
    /// - Custom rules come before preset collections, so they take priority
    static func dedupe(_ collections: [RuleCollection]) -> [RuleCollection] {
        var seenActivators: Set<ActivatorKey> = []
        // Track seen input keys per layer across ALL collections
        var seenInputKeys: Set<InputKey> = []

        return collections.map { collection in
            var deduped = collection

            // Dedupe activators (existing logic)
            if let activator = collection.momentaryActivator {
                let key = ActivatorKey(
                    input: KanataKeyConverter.convertToKanataKey(activator.input),
                    layer: activator.targetLayer
                )
                if seenActivators.contains(key) {
                    deduped.momentaryActivator = nil
                } else {
                    seenActivators.insert(key)
                }
            }

            // Dedupe mappings - remove any mapping whose input key was already claimed
            deduped.mappings = dedupeMappingsAcrossCollections(
                in: collection,
                seenInputKeys: &seenInputKeys
            )
            return deduped
        }
    }

    /// Removes mappings whose input key has already been seen in a previous collection.
    /// Also removes duplicates within the same collection.
    private static func dedupeMappingsAcrossCollections(
        in collection: RuleCollection,
        seenInputKeys: inout Set<InputKey>
    ) -> [KeyMapping] {
        var seenWithinCollection: Set<MappingKey> = []
        var unique: [KeyMapping] = []

        for mapping in collection.mappings {
            let normalizedInput = KanataKeyConverter.convertToKanataKey(mapping.input)
            let inputKey = InputKey(input: normalizedInput, layer: collection.targetLayer)

            // Skip if this input key was already claimed by a previous collection
            if seenInputKeys.contains(inputKey) {
                continue
            }

            // Also dedupe within collection (existing behavior)
            let mappingKey = MappingKey(
                layer: collection.targetLayer,
                input: normalizedInput,
                output: KanataKeyConverter.convertToKanataSequence(mapping.output),
                shiftedOutput: mapping.shiftedOutput.map { KanataKeyConverter.convertToKanataSequence($0) },
                ctrlOutput: mapping.ctrlOutput.map { KanataKeyConverter.convertToKanataSequence($0) }
            )

            if seenWithinCollection.insert(mappingKey).inserted {
                unique.append(mapping)
                // Mark this input key as claimed
                seenInputKeys.insert(inputKey)
            }
        }

        return unique
    }

    private struct ActivatorKey: Hashable {
        let input: String
        let layer: RuleCollectionLayer
    }

    /// Key for tracking which input keys have been claimed (across collections)
    private struct InputKey: Hashable {
        let input: String
        let layer: RuleCollectionLayer
    }

    /// Key for tracking unique mappings (within a collection)
    private struct MappingKey: Hashable {
        let layer: RuleCollectionLayer
        let input: String
        let output: String
        let shiftedOutput: String?
        let ctrlOutput: String?
    }
}
