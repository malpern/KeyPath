import Foundation
import KeyPathCore

enum RuleCollectionDeduplicator {
    // MARK: - Conflict Detection

    /// Detects mapping conflicts BEFORE deduplication.
    /// Returns conflicts where multiple collections map the same key in the same layer.
    /// Call this before `dedupe()` to catch conflicts that would otherwise be silently resolved.
    ///
    /// Uses `effectiveMappings(for:)` to include config-generated mappings (Home Row Mods,
    /// Layer Toggles, etc.) — not just the raw `.mappings` array.
    static func detectConflicts(in collections: [RuleCollection]) -> [KeyPathError.MappingConflictInfo] {
        struct ClaimInfo {
            let collectionName: String
            let holdDescription: String?
        }

        var claimedKeys: [InputKey: [ClaimInfo]] = [:]

        for collection in collections where collection.isEnabled {
            let mappings = KanataConfiguration.effectiveMappings(for: collection)
            var seenKeysInCollection = Set<String>()
            for mapping in mappings {
                let normalizedInput = KanataKeyConverter.convertToKanataKey(mapping.input)
                // Skip duplicate keys within the same collection (e.g., chord groups
                // sharing keys). Within-collection conflicts are detected separately.
                guard seenKeysInCollection.insert(normalizedInput).inserted else { continue }
                let inputKey = InputKey(input: normalizedInput, layer: collection.targetLayer)

                let holdDesc = mapping.behavior.flatMap { behavior -> String? in
                    if case let .dualRole(dr) = behavior {
                        return dr.holdActionString
                    }
                    return nil
                }

                claimedKeys[inputKey, default: []].append(
                    ClaimInfo(collectionName: collection.name, holdDescription: holdDesc)
                )
            }
        }

        var conflicts: [KeyPathError.MappingConflictInfo] = []
        for (inputKey, claims) in claimedKeys where claims.count > 1 {
            let collectionNames = claims.map(\.collectionName)
            let holdDescriptions = claims.compactMap { claim -> String? in
                guard let hold = claim.holdDescription else { return nil }
                return "\(claim.collectionName): hold → \(hold)"
            }

            conflicts.append(KeyPathError.MappingConflictInfo(
                inputKey: inputKey.input,
                layer: inputKey.layer.displayName,
                conflictingCollections: collectionNames,
                holdDescriptions: holdDescriptions
            ))
        }

        // Momentary activator conflicts (#466): two collections claim the same
        // physical activator key but route it to different layers. The silent
        // `seenActivators` dedup in buildCollectionBlocks would drop one without
        // notice — surface it via the same detect-and-explain path instead.
        // Identical activators (same key + same target layer) are redundant, not
        // conflicting, and are intentionally skipped (matching the toggle-time
        // conflictInfo semantics).
        struct ActivatorClaim {
            let collectionName: String
            let targetLayer: RuleCollectionLayer
        }
        var activatorClaims: [String: [ActivatorClaim]] = [:]
        for collection in collections where collection.isEnabled {
            guard let activator = collection.momentaryActivator else { continue }
            // "hyper" activators are folded into the hyper hold action, not emitted
            // as standalone layer activators — they never collide in seenActivators.
            guard activator.input.lowercased() != "hyper" else { continue }
            let normalizedInput = KanataKeyConverter.convertToKanataKey(activator.input)
            activatorClaims[normalizedInput, default: []].append(
                ActivatorClaim(collectionName: collection.name, targetLayer: activator.targetLayer)
            )
        }
        for (input, claims) in activatorClaims where claims.count > 1 {
            // Only a conflict if the activators disagree on which layer to activate.
            let distinctTargets = Set(claims.map(\.targetLayer))
            guard distinctTargets.count > 1 else { continue }
            conflicts.append(KeyPathError.MappingConflictInfo(
                inputKey: input,
                layer: RuleCollectionLayer.base.displayName,
                conflictingCollections: claims.map(\.collectionName),
                holdDescriptions: claims.map { "\($0.collectionName): activates \($0.targetLayer.displayName)" }
            ))
        }

        // Within-collection chord group conflicts: two chord groups sharing keys
        // produces duplicate aliases that kanata rejects.
        for collection in collections where collection.isEnabled {
            if case let .chordGroups(config) = collection.configuration {
                let chordConflicts = config.detectCrossGroupConflicts()
                for conflict in chordConflicts {
                    let groupNames = conflict.groups.map(\.name)
                    let chordDescriptions = conflict.groups.map { group -> String in
                        let chordOutputs = group.chords
                            .filter { $0.keys.contains(conflict.key) }
                            .map { "(\($0.keys.joined(separator: "+")) → \($0.action.displayName))" }
                            .joined(separator: ", ")
                        return "\(group.name): \(chordOutputs)"
                    }
                    conflicts.append(KeyPathError.MappingConflictInfo(
                        inputKey: conflict.key,
                        layer: collection.targetLayer.displayName,
                        conflictingCollections: groupNames,
                        holdDescriptions: chordDescriptions
                    ))
                }
            }
        }

        return conflicts.sorted { $0.inputKey < $1.inputKey }
    }

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
                AppLogger.shared.debug("🔀 [Dedup] Dropped mapping '\(mapping.input)' from '\(collection.name)' — key already claimed on \(collection.targetLayer.displayName) layer")
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
