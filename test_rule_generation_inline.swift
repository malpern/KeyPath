#!/usr/bin/swift

import Foundation

// Test structures
struct TapDanceAction {
    let tapCount: Int
    let action: String
    let description: String
}

enum KanataBehavior {
    case simpleRemap(from: String, toKey: String)
    case tapHold(key: String, tap: String, hold: String)
    case tapDance(key: String, actions: [TapDanceAction])
    case sequence(trigger: String, sequence: [String])
    case combo(keys: [String], result: String)
    case layer(key: String, layerName: String, mappings: [String: String])
}

// Simple implementation of rule generator
class KanataRuleGenerator {
    static func generateCompleteRule(from behavior: KanataBehavior) -> String {
        switch behavior {
        case .simpleRemap(let from, let toKey):
            let fromKey = normalizeKeyName(from)
            let toKeyNorm = normalizeKeyName(toKey)

            return """
            (defsrc
              \(fromKey)
            )

            (deflayer default
              \(toKeyNorm)
            )
            """

        case .tapHold(let key, let tap, let hold):
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

        default:
            return "// Not implemented yet"
        }
    }

    static func normalizeKeyName(_ name: String) -> String {
        let normalized = name.lowercased()

        let keyMappings: [String: String] = [
            "space": "spc",
            "shift": "lsft",
            "escape": "esc",
            "caps lock": "caps"
        ]

        if let kanataKey = keyMappings[normalized] {
            return kanataKey
        }

        return normalized
    }
}

// Test simple remap
print("Test 1: Simple Remap A -> B")
print("============================")
let simpleRemap = KanataBehavior.simpleRemap(from: "A", toKey: "B")
print(KanataRuleGenerator.generateCompleteRule(from: simpleRemap))
print("\n")

// Test tap-hold
print("Test 2: Tap-Hold Space/Shift")
print("=============================")
let tapHold = KanataBehavior.tapHold(key: "Space", tap: "Space", hold: "Shift")
print(KanataRuleGenerator.generateCompleteRule(from: tapHold))
print("\n")

// Test what was showing in the UI (defalias only)
print("Test 3: What the UI was showing before (incomplete)")
print("===================================================")
print("(defalias a b)")
print("\nThis is incomplete and won't work!")
print("\n")

print("Test 4: Complete config for caps -> esc")
print("=======================================")
let capsToEsc = KanataBehavior.simpleRemap(from: "caps lock", toKey: "escape")
print(KanataRuleGenerator.generateCompleteRule(from: capsToEsc))
