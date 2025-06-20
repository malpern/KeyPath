import Foundation

/// Generates complete Kanata configuration rules from behaviors
class KanataRuleGenerator {
    
    /// Generates a complete Kanata rule from a behavior
    static func generateCompleteRule(from behavior: KanataBehavior) -> String {
        switch behavior {
        case .simpleRemap(let from, let toKey):
            return generateSimpleRemapRule(from: from, to: toKey)
            
        case .tapHold(let key, let tap, let hold):
            return generateTapHoldRule(key: key, tap: tap, hold: hold)
            
        case .tapDance(let key, let actions):
            return generateTapDanceRule(key: key, actions: actions)
            
        case .sequence(let trigger, let sequence):
            return generateSequenceRule(trigger: trigger, sequence: sequence)
            
        case .combo(let keys, let result):
            return generateComboRule(keys: keys, result: result)
            
        case .layer(let key, let layerName, let mappings):
            return generateLayerRule(key: key, layerName: layerName, mappings: mappings)
        }
    }
    
    private static func generateSimpleRemapRule(from: String, to: String) -> String {
        let fromKey = normalizeKeyName(from)
        let toKey = normalizeKeyName(to)
        
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
    
    private static func generateTapHoldRule(key: String, tap: String, hold: String) -> String {
        let keyName = normalizeKeyName(key)
        let tapKey = normalizeKeyName(tap)
        let holdKey = normalizeKeyName(hold)
        
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
    
    private static func generateTapDanceRule(key: String, actions: [TapDanceAction]) -> String {
        let keyName = normalizeKeyName(key)
        let actionKeys = actions.map { normalizeKeyName($0.action) }.joined(separator: " ")
        
        return """
        (defalias
          td_\(keyName) (tap-dance 200 \(actionKeys))
        )
        
        (defsrc
          \(keyName)
        )
        
        (deflayer default
          @td_\(keyName)
        )
        """
    }
    
    private static func generateSequenceRule(trigger: String, sequence: [String]) -> String {
        let triggerKey = normalizeKeyName(trigger)
        let sequenceKeys = sequence.map { normalizeKeyName($0) }.joined(separator: " ")
        
        return """
        (defalias
          seq_\(triggerKey) (macro \(sequenceKeys))
        )
        
        (defsrc
          \(triggerKey)
        )
        
        (deflayer default
          @seq_\(triggerKey)
        )
        """
    }
    
    private static func generateComboRule(keys: [String], result: String) -> String {
        let comboKeys = keys.map { normalizeKeyName($0) }.joined(separator: " ")
        let resultAction = normalizeKeyName(result)
        
        // Combos are handled differently - they use defchords
        let sourceKeys = keys.map { normalizeKeyName($0) }
        
        return """
        (defsrc
          \(sourceKeys.joined(separator: " "))
        )
        
        (defchords default 50
          (\(comboKeys)) \(resultAction)
        )
        
        (deflayer default
          \(sourceKeys.joined(separator: " "))
        )
        """
    }
    
    private static func generateLayerRule(key: String, layerName: String, mappings: [String: String]) -> String {
        let triggerKey = normalizeKeyName(key)
        let layerNameLower = layerName.lowercased().replacingOccurrences(of: " ", with: "_")
        
        // Get all unique keys that need to be in defsrc
        var sourceKeys = Set<String>()
        sourceKeys.insert(triggerKey)
        for (from, _) in mappings {
            sourceKeys.insert(normalizeKeyName(from))
        }
        
        _ = mappings.map { (from, to) in
            "  \(normalizeKeyName(to))"
        }.joined(separator: "\n")
        
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
          _ \(mappings.values.map { normalizeKeyName($0) }.joined(separator: " "))
        )
        """
    }
    
    /// Normalizes friendly key names to Kanata key names
    private static func normalizeKeyName(_ name: String) -> String {
        let normalized = name.lowercased()
        
        // Common key mappings
        let keyMappings: [String: String] = [
            "caps lock": "caps",
            "capslock": "caps",
            "escape": "esc",
            "control": "lctl",
            "ctrl": "lctl",
            "left control": "lctl",
            "right control": "rctl",
            "shift": "lsft",
            "left shift": "lsft",
            "right shift": "rsft",
            "command": "lmet",
            "cmd": "lmet",
            "left command": "lmet",
            "right command": "rmet",
            "option": "lalt",
            "alt": "lalt",
            "left option": "lalt",
            "right option": "ralt",
            "space": "spc",
            "spacebar": "spc",
            "return": "ret",
            "enter": "ret",
            "backspace": "bspc",
            "delete": "del",
            "tab": "tab",
            "up": "up",
            "down": "down",
            "left": "left",
            "right": "right",
            "home": "home",
            "end": "end",
            "page up": "pgup",
            "page down": "pgdn"
        ]
        
        // Check if we have a mapping for this key
        if let kanataKey = keyMappings[normalized] {
            return kanataKey
        }
        
        // Handle function keys
        if normalized.hasPrefix("f") && normalized.count <= 3 {
            return normalized // f1, f2, etc.
        }
        
        // Handle single letters and numbers
        if normalized.count == 1 {
            return normalized
        }
        
        // Default: return the normalized version
        return normalized.replacingOccurrences(of: " ", with: "")
    }
}