import Foundation

// Mock data for demo
struct MockRule: Identifiable {
    let id = UUID()
    var name: String
    let behavior: KanataBehavior
    let explanation: String
    let kanataCode: String
    var isActive: Bool
}

struct MockRuleData {
    static let sampleRules: [MockRule] = [
        MockRule(
            name: "Caps to Escape",
            behavior: .simpleRemap(from: "Caps Lock", toKey: "Escape"),
            explanation: "Map Caps Lock to Escape for modal editing",
            kanataCode: "(defsrc caps) (deflayer base esc)",
            isActive: true
        ),
        MockRule(
            name: "Space Shift",
            behavior: .tapHold(key: "Space", tap: "Space", hold: "Shift"),
            explanation: "Space acts as Shift when held",
            kanataCode: "(defsrc spc) (deflayer base (tap-hold 200 200 spc lsft))",
            isActive: true
        ),
        MockRule(
            name: "F Multi-Tap",
            behavior: .tapDance(key: "F", actions: [
                TapDanceAction(tapCount: 1, action: "F", description: ""),
                TapDanceAction(tapCount: 2, action: "Ctrl+F", description: ""),
                TapDanceAction(tapCount: 3, action: "Cmd+F", description: "")
            ]),
            explanation: "F key with multiple tap actions",
            kanataCode: "(defsrc f) (deflayer base (tap-dance 200 (f (lctl f) (lgui f))))",
            isActive: false
        ),
        MockRule(
            name: "Email Expander",
            behavior: .sequence(trigger: "email", sequence: ["j", "o", "h", "n", "@", "e", "x", "a", "m", "p", "l", "e", ".", "c", "o", "m"]),
            explanation: "Type 'email' to expand to email address",
            kanataCode: "(defseq email (macro john@example.com))",
            isActive: true
        ),
        MockRule(
            name: "Hello Chord",
            behavior: .combo(keys: ["A", "S", "D"], result: "Hello World"),
            explanation: "Chord typing for quick text expansion",
            kanataCode: "(defchords base 50 (a s d) (macro \"Hello World\"))",
            isActive: true
        ),
        MockRule(
            name: "Gaming Layer",
            behavior: .layer(key: "Fn", layerName: "Gaming", mappings: ["W": "↑", "A": "←", "S": "↓", "D": "→"]),
            explanation: "Gaming layer with arrow key mappings",
            kanataCode: "(deflayer gaming up left down right)",
            isActive: false
        ),
        MockRule(
            name: "Right Cmd Enter",
            behavior: .simpleRemap(from: "Right Cmd", toKey: "Enter"),
            explanation: "Right Command as Enter key",
            kanataCode: "(defsrc rcmd) (deflayer base ret)",
            isActive: true
        ),
        MockRule(
            name: "Tab Control",
            behavior: .tapHold(key: "Tab", tap: "Tab", hold: "Ctrl"),
            explanation: "Tab key doubles as Control when held",
            kanataCode: "(defsrc tab) (deflayer base (tap-hold 200 200 tab lctl))",
            isActive: false
        ),
        MockRule(
            name: "Address Shortcut",
            behavior: .sequence(trigger: "addr", sequence: ["1", "2", "3", " ", "M", "a", "i", "n", " ", "S", "t"]),
            explanation: "Quick address expansion",
            kanataCode: "(defseq addr (macro \"123 Main St\"))",
            isActive: true
        ),
        MockRule(
            name: "KeyPath Combo",
            behavior: .combo(keys: ["Cmd", "Shift", "K"], result: "KeyPath Rocks!"),
            explanation: "Special KeyPath combo",
            kanataCode: "(defchords base 50 (lgui lsft k) (macro \"KeyPath Rocks!\"))",
            isActive: true
        )
    ]
}