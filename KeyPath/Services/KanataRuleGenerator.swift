import Foundation

// ⚠️ ARCHITECTURE WARNING: LLM-First Design
// This file contains hardcoded key mappings that should be migrated to LLM-powered recognition.
// DO NOT add new hardcoded mappings without explicit approval.
// See ARCHITECTURE.md for guidelines.
// COMPLETED: Replaced normalizeKeyName() with KanataKeyValidator LLM logic

/// Generates complete Kanata configuration rules from behaviors
class KanataRuleGenerator {
    private let keyValidator: KanataKeyValidator
    
    init(llmProvider: AnthropicModelProvider? = nil) {
        self.keyValidator = KanataKeyValidator(llmProvider: llmProvider)
    }

    /// Generates a complete Kanata rule from a behavior
    func generateCompleteRule(from behavior: KanataBehavior) async -> String {
        switch behavior {
        case .simpleRemap(let from, let toKey):
            return await generateSimpleRemapRule(from: from, to: toKey)

        case .tapHold(let key, let tap, let hold):
            return await generateTapHoldRule(key: key, tap: tap, hold: hold)

        case .tapDance(let key, let actions):
            return await generateTapDanceRule(key: key, actions: actions)

        case .sequence(let trigger, let sequence):
            return await generateSequenceRule(trigger: trigger, sequence: sequence)

        case .combo(let keys, let result):
            return await generateComboRule(keys: keys, result: result)

        case .layer(let key, let layerName, let mappings):
            return await generateLayerRule(key: key, layerName: layerName, mappings: mappings)
        }
    }

    private func generateSimpleRemapRule(from: String, to: String) async -> String {
        let fromKey = await normalizeKeyName(from)
        let toKey = await normalizeKeyName(to)

        // For simple remaps, we don't need defalias, just defsrc and deflayer
        return """
        (defsrc
          \(fromKey)
        )

        (deflayer default
          \(toKey)
        )
        """
    }

    private func generateTapHoldRule(key: String, tap: String, hold: String) async -> String {
        let keyName = await normalizeKeyName(key)
        let tapKey = await normalizeKeyName(tap)
        let holdKey = await normalizeKeyName(hold)

        return """
        (defalias
          th_\(keyName) (tap-hold 200 200 \(tapKey) \(holdKey))
        )

        (defsrc
          \(keyName)
        )

        (deflayer default
          @th_\(keyName)
        )
        """
    }

    private func generateTapDanceRule(key: String, actions: [TapDanceAction]) async -> String {
        let keyName = await normalizeKeyName(key)
        var actionKeys: [String] = []
        for action in actions {
            actionKeys.append(await normalizeKeyName(action.action))
        }
        let actionKeysString = actionKeys.joined(separator: " ")

        return """
        (defalias
          td_\(keyName) (tap-dance 200 \(actionKeysString))
        )

        (defsrc
          \(keyName)
        )

        (deflayer default
          @td_\(keyName)
        )
        """
    }

    private func generateSequenceRule(trigger: String, sequence: [String]) async -> String {
        let triggerKey = await normalizeKeyName(trigger)
        var sequenceKeys: [String] = []
        for key in sequence {
            sequenceKeys.append(await normalizeKeyName(key))
        }
        let sequenceKeysString = sequenceKeys.joined(separator: " ")

        return """
        (defalias
          seq_\(triggerKey) (macro \(sequenceKeysString))
        )

        (defsrc
          \(triggerKey)
        )

        (deflayer default
          @seq_\(triggerKey)
        )
        """
    }

    private func generateComboRule(keys: [String], result: String) async -> String {
        var comboKeys: [String] = []
        for key in keys {
            comboKeys.append(await normalizeKeyName(key))
        }
        let comboKeysString = comboKeys.joined(separator: " ")
        let resultAction = await normalizeKeyName(result)

        // Combos are handled differently - they use defchords
        let sourceKeys = comboKeys

        return """
        (defsrc
          \(sourceKeys.joined(separator: " "))
        )

        (defchords default 50
          (\(comboKeysString)) \(resultAction)
        )

        (deflayer default
          \(sourceKeys.joined(separator: " "))
        )
        """
    }

    private func generateLayerRule(key: String, layerName: String, mappings: [String: String]) async -> String {
        let triggerKey = await normalizeKeyName(key)
        let layerNameLower = layerName.lowercased().replacingOccurrences(of: " ", with: "_")

        // Get all unique keys that need to be in defsrc
        var sourceKeys = Set<String>()
        sourceKeys.insert(triggerKey)
        for (from, _) in mappings {
            sourceKeys.insert(await normalizeKeyName(from))
        }

        // Process layer mappings
        var layerMappings: [String] = []
        for (_, to) in mappings {
            layerMappings.append(await normalizeKeyName(to))
        }

        return """
        (defalias
          layer_\(layerNameLower) (layer-while-held \(layerNameLower))
        )

        (defsrc
          \(sourceKeys.sorted().joined(separator: " "))
        )

        (deflayer default
          @layer_\(layerNameLower) \(mappings.keys.map { _ in "_" }.joined(separator: " "))
        )

        (deflayer \(layerNameLower)
          _ \(layerMappings.joined(separator: " "))
        )
        """
    }

    /// Normalizes friendly key names to Kanata key names using LLM intelligence
    private func normalizeKeyName(_ name: String) async -> String {
        // Use our enhanced KanataKeyValidator for intelligent key recognition
        if keyValidator.isValidKeyName(name) {
            // Already a valid Kanata key name
            return name.lowercased()
        }
        
        // Try to get a suggestion from the validator
        let suggestion = keyValidator.suggestKeyCorrection(name)
        if !suggestion.isEmpty {
            return suggestion
        }
        
        // Fallback: return the name as-is (lowercased, spaces removed)
        // The LLM will handle edge cases we haven't seen before
        return name.lowercased().replacingOccurrences(of: " ", with: "")
    }
}
