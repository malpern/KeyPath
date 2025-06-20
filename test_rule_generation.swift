import Foundation

// Test the KanataRuleGenerator

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

// Test simple remap
let simpleRemap = KanataBehavior.simpleRemap(from: "A", toKey: "B")
print("Simple Remap A -> B:")
print(KanataRuleGenerator.generateCompleteRule(from: simpleRemap))
print("\n---\n")

// Test tap-hold
let tapHold = KanataBehavior.tapHold(key: "Space", tap: "Space", hold: "Shift")
print("Tap-Hold Space/Shift:")
print(KanataRuleGenerator.generateCompleteRule(from: tapHold))
print("\n---\n")

// Test tap-dance
let tapDance = KanataBehavior.tapDance(
    key: "F",
    actions: [
        TapDanceAction(tapCount: 1, action: "F", description: ""),
        TapDanceAction(tapCount: 2, action: "Ctrl+F", description: ""),
        TapDanceAction(tapCount: 3, action: "Cmd+F", description: "")
    ]
)
print("Tap-Dance F key:")
print(KanataRuleGenerator.generateCompleteRule(from: tapDance))
print("\n---\n")
