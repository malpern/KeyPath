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
    static func detectConflicts(
        in collections: [RuleCollection],
        leaderKey: LeaderKeyPreference? = nil
    ) -> [KeyPathError.MappingConflictInfo] {
        struct ClaimInfo {
            let collectionName: String
            let holdDescription: String?
        }

        var claimedKeys: [InputKey: [ClaimInfo]] = [:]
        // Which collections place a regular mapping on each (input, layer) slot.
        // Mappings only — NOT activators or the leader — so it can be cross-checked
        // against activator placements without double-reporting.
        var mappingOwners: [InputKey: Set<String>] = [:]

        for collection in collections where collection.isEnabled {
            let mappings = KanataConfiguration.effectiveMappings(for: collection)
            var seenKeysInCollection = Set<String>()
            for mapping in mappings {
                let normalizedInput = KanataKeyConverter.convertToKanataKey(mapping.input)
                // Skip duplicate keys within the same collection (e.g., chord groups
                // sharing keys). Within-collection conflicts are detected separately.
                guard seenKeysInCollection.insert(normalizedInput).inserted else { continue }
                let inputKey = InputKey(input: normalizedInput, layer: collection.targetLayer)
                mappingOwners[inputKey, default: []].insert(collection.name)

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

        // The leader key (#463) also consumes its physical key's BASE-layer slot:
        // buildCollectionBlocks emits the leader as a base entry (tap = key, hold =
        // layer) before any collection, and deduplicateBlocks keeps it over a later
        // base mapping — so a base-layer collection or custom rule that maps the same
        // key is silently dropped. Claim that base slot so the collision surfaces.
        if let leaderKey, leaderKey.enabled {
            let normalizedInput = KanataKeyConverter.convertToKanataKey(leaderKey.key)
            let inputKey = InputKey(input: normalizedInput, layer: .base)
            claimedKeys[inputKey, default: []].append(
                ClaimInfo(
                    collectionName: "Leader Key",
                    holdDescription: "\(leaderKey.targetLayer.displayName) layer"
                )
            )
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
        // physical activator key from the same source layer but route it to
        // different target layers. The silent `seenActivators` dedup in
        // buildCollectionBlocks would drop one without notice — surface it via the
        // same detect-and-explain path instead.
        //
        // The claim slot is (sourceLayer, input): a key can only carry one binding
        // per layer. The same key activating different targets from *different*
        // source layers is a valid chained-layer setup (e.g. `f` → arrows from base
        // and `f` → function from nav), not a conflict. Identical activators (same
        // slot + same target) are redundant, not conflicting. Both are skipped so
        // the detection does not over-fire (matching the toggle-time conflictInfo).
        struct ActivatorSlot: Hashable {
            let sourceLayer: RuleCollectionLayer
            let input: String
        }
        struct ActivatorClaim {
            let collectionName: String
            let targetLayer: RuleCollectionLayer
        }
        var activatorClaims: [ActivatorSlot: [ActivatorClaim]] = [:]
        // The system leader key (#463) is an activator too: pressing it from the
        // base layer activates its target layer. buildCollectionBlocks seeds it into
        // seenActivators before any collection, so a collection activator on the
        // same base-layer key is silently dropped — include it as a claim so the
        // collision is surfaced instead.
        if let leaderKey, leaderKey.enabled {
            let slot = ActivatorSlot(
                sourceLayer: .base,
                input: KanataKeyConverter.convertToKanataKey(leaderKey.key)
            )
            activatorClaims[slot, default: []].append(
                ActivatorClaim(collectionName: "Leader Key", targetLayer: leaderKey.targetLayer)
            )
        }
        for collection in collections where collection.isEnabled {
            guard let activator = collection.momentaryActivator else { continue }
            // "hyper" activators are folded into the hyper hold action, not emitted
            // as standalone layer activators — they never collide in seenActivators.
            guard activator.input.lowercased() != "hyper" else { continue }
            let normalizedInput = KanataKeyConverter.convertToKanataKey(activator.input)
            let slot = ActivatorSlot(sourceLayer: activator.sourceLayer, input: normalizedInput)
            activatorClaims[slot, default: []].append(
                ActivatorClaim(collectionName: collection.name, targetLayer: activator.targetLayer)
            )

            // Activator-vs-mapping conflict: this activator occupies its key's slot
            // on its source layer (buildCollectionBlocks places the tap-hold there),
            // but another collection maps the same key on that layer. The generator
            // emits both and silently keeps one (e.g. Home Row Arrows' `f` activator
            // shadowing Home Row Mods' hold-`f`). Surface it. Activator-vs-activator
            // is handled by the redundant-aware pass below; leader collisions via the
            // leader injection above — neither is in `mappingOwners`, so no double-report.
            let mappingSlot = InputKey(input: normalizedInput, layer: activator.sourceLayer)
            let otherMappers = (mappingOwners[mappingSlot] ?? []).subtracting([collection.name]).sorted()
            if !otherMappers.isEmpty {
                conflicts.append(KeyPathError.MappingConflictInfo(
                    inputKey: normalizedInput,
                    layer: activator.sourceLayer.displayName,
                    conflictingCollections: [collection.name] + otherMappers,
                    holdDescriptions: ["\(collection.name): activates \(activator.targetLayer.displayName)"]
                        + otherMappers.map { "\($0): maps \(normalizedInput)" }
                ))
            }
        }
        for (slot, claims) in activatorClaims where claims.count > 1 {
            // Only a conflict if the activators disagree on which layer to activate.
            let distinctTargets = Set(claims.map(\.targetLayer))
            guard distinctTargets.count > 1 else { continue }
            conflicts.append(KeyPathError.MappingConflictInfo(
                inputKey: slot.input,
                layer: slot.sourceLayer.displayName,
                conflictingCollections: claims.map(\.collectionName),
                holdDescriptions: claims.map { "\($0.collectionName): activates \($0.targetLayer.displayName)" }
            ))
        }

        // Within-collection chord group conflicts: two chord groups sharing keys
        // produces duplicate aliases that kanata rejects.
        for collection in collections where collection.isEnabled {
            if case let .chordGroups(config) = collection.configuration {
                // Duplicate group names (#464): each group renders to a
                // `(defchords <name> …)` block keyed by its name, so two groups
                // sharing a name produce duplicate blocks that kanata rejects.
                for duplicate in config.detectDuplicateGroupNames() {
                    conflicts.append(KeyPathError.MappingConflictInfo(
                        inputKey: duplicate.name,
                        layer: collection.targetLayer.displayName,
                        conflictingCollections: Array(
                            repeating: "chord group '\(duplicate.name)'",
                            count: duplicate.count
                        ),
                        holdDescriptions: [
                            "\(duplicate.count) chord groups share the name '\(duplicate.name)' — chord group names must be unique"
                        ]
                    ))
                }

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

        // Alias-name collisions (#462): generated alias names are
        // `{prefix}_{layer}_{sanitized-input}`, and sanitization maps `-`/space (and,
        // for device switches, any non-alphanumeric) to `_`. Two distinct input keys
        // can therefore collapse to the same alias name (e.g. `caps-lock` and
        // `caps_lock` → `beh_base_caps_lock`), which kanata rejects. These keys don't
        // collide as defsrc inputs, so the key-overlap pass above misses them.
        struct AliasOrigin {
            let collectionName: String
            let rawInput: String
            let layer: String
        }
        var aliasOrigins: [String: [AliasOrigin]] = [:]
        for collection in collections where collection.isEnabled {
            for mapping in KanataConfiguration.effectiveMappings(for: collection) {
                // Chord inputs (space-separated) render to defchordsv2, not aliases.
                guard !mapping.input.contains(" ") else { continue }
                for aliasName in KanataConfiguration.generatedAliasNames(
                    for: mapping, layer: collection.targetLayer
                ) {
                    aliasOrigins[aliasName, default: []].append(AliasOrigin(
                        collectionName: collection.name,
                        rawInput: mapping.input,
                        layer: collection.targetLayer.displayName
                    ))
                }
            }
        }
        for (aliasName, origins) in aliasOrigins {
            // Only a collision when *different* input keys produce the same alias.
            // Same input across collections is already a key-overlap conflict above.
            let distinctInputs = Set(origins.map(\.rawInput))
            guard distinctInputs.count > 1 else { continue }
            conflicts.append(KeyPathError.MappingConflictInfo(
                inputKey: distinctInputs.sorted().joined(separator: " / "),
                layer: origins.first?.layer ?? RuleCollectionLayer.base.displayName,
                conflictingCollections: Array(Set(origins.map(\.collectionName))).sorted(),
                holdDescriptions: ["keys \(distinctInputs.sorted().joined(separator: ", ")) all generate the alias '\(aliasName)'"]
            ))
        }

        // Total ordering (inputKey, then layer, then explanation) so output is
        // deterministic even when two conflicts share an inputKey — e.g. the same
        // pair of keys colliding on two different alias prefixes at once.
        return conflicts.sorted { lhs, rhs in
            if lhs.inputKey != rhs.inputKey { return lhs.inputKey < rhs.inputKey }
            if lhs.layer != rhs.layer { return lhs.layer < rhs.layer }
            return lhs.holdDescriptions.joined() < rhs.holdDescriptions.joined()
        }
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
