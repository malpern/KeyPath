import Foundation
import KeyPathCore
import KeyPathRulesCore

enum RuleCollectionDeduplicator {
    // Conflict detection lives in `AdmissionEngine.conflicts(in:leaderKey:)`,
    // attributed by rule id. This type only applies the generator's structural
    // "first claim wins" after admission has refused every intentional overlap.

    /// Deduplicates collections by removing duplicate input keys.
    /// - First collection to claim an input key (per layer) wins
    /// - Custom rules come before preset collections, so they take priority
    static func dedupe(_ collections: [RuleCollection]) -> [RuleCollection] {
        var seenActivators: Set<ActivatorKey> = []
        // Track seen input keys per layer across ALL enabled collections
        var seenInputKeys: Set<InputKey> = []

        return collections.map { collection in
            var deduped = collection

            // Skip disabled collections for deduplication purposes
            // They don't claim keys and don't need their mappings filtered
            guard collection.isEnabled else {
                return deduped
            }

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

            if seenInputKeys.contains(inputKey) {
                // AdmissionEngine.conflicts runs before this and refuses any two
                // intentional claims on one slot, so reaching here is a gap in
                // detection, not a resolution: never silently (ADR-039 §1).
                AppLogger.shared.warnUnlessQuietTest(
                    "⚠️ [Dedup] Dropped mapping '\(mapping.input)' from '\(collection.name)' — key already claimed on \(collection.targetLayer.displayName) layer. Admission should have refused this."
                )
                continue
            }

            // Also dedupe within collection (existing behavior)
            let mappingKey = MappingKey(
                layer: collection.targetLayer,
                input: normalizedInput,
                output: KanataKeyConverter.convertToKanataSequence(mapping.action.kanataOutput),
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
