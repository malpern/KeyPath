import XCTest
import SwiftUI
@testable import KeyPath

final class VisualizerComponentTests: XCTestCase {
    
    // MARK: - CompactRuleVisualizer Logic Tests
    
    func testCompactRuleVisualizerInitialization() {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        
        // Test without code toggle
        let visualizer1 = CompactRuleVisualizer(
            behavior: behavior,
            explanation: "Test explanation"
        )
        
        // We can't directly test SwiftUI view properties, but we can test the initialization doesn't crash
        XCTAssertNotNil(visualizer1)
        
        // Test with code toggle
        var toggleCalled = false
        let visualizer2 = CompactRuleVisualizer(
            behavior: behavior,
            explanation: "Test explanation",
            showCodeToggle: true,
            onCodeToggle: { toggleCalled = true }
        )
        
        XCTAssertNotNil(visualizer2)
        // Note: We can't easily test the toggle callback in SwiftUI unit tests
        // but we verified the initializer accepts the callback
        _ = toggleCalled // Suppress warning
    }
    
    // MARK: - Behavior-Specific Visualization Tests
    
    func testSimpleRemapVisualization() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        
        XCTAssertEqual(behavior.primaryKey, "caps")
        XCTAssertEqual(behavior.behaviorType, "Simple Remap")
        
        // Test the visualization data that would be used in the UI
        if case .simpleRemap(let from, let toKey) = behavior {
            XCTAssertEqual(from, "caps")
            XCTAssertEqual(toKey, "esc")
        } else {
            XCTFail("Expected simpleRemap behavior")
        }
    }
    
    func testTapHoldVisualization() {
        let behavior = KanataBehavior.tapHold(key: "space", tap: "spc", hold: "shift")
        
        XCTAssertEqual(behavior.primaryKey, "space")
        XCTAssertEqual(behavior.behaviorType, "Tap-Hold")
        
        if case .tapHold(let key, let tap, let hold) = behavior {
            XCTAssertEqual(key, "space")
            XCTAssertEqual(tap, "spc")
            XCTAssertEqual(hold, "shift")
        } else {
            XCTFail("Expected tapHold behavior")
        }
    }
    
    func testTapDanceVisualization() {
        let actions = [
            TapDanceAction(tapCount: 1, action: "f", description: "Single tap"),
            TapDanceAction(tapCount: 2, action: "F", description: "Double tap"),
            TapDanceAction(tapCount: 3, action: "ctrl+f", description: "Triple tap")
        ]
        
        let behavior = KanataBehavior.tapDance(key: "f", actions: actions)
        
        XCTAssertEqual(behavior.primaryKey, "f")
        XCTAssertEqual(behavior.behaviorType, "Tap Dance")
        
        if case .tapDance(let key, let tapActions) = behavior {
            XCTAssertEqual(key, "f")
            XCTAssertEqual(tapActions.count, 3)
            XCTAssertEqual(tapActions[0].tapCount, 1)
            XCTAssertEqual(tapActions[1].tapCount, 2)
            XCTAssertEqual(tapActions[2].tapCount, 3)
        } else {
            XCTFail("Expected tapDance behavior")
        }
    }
    
    func testSequenceVisualization() {
        let behavior = KanataBehavior.sequence(trigger: "jk", sequence: ["escape"])
        
        XCTAssertEqual(behavior.primaryKey, "jk")
        XCTAssertEqual(behavior.behaviorType, "Sequence")
        
        if case .sequence(let trigger, let sequence) = behavior {
            XCTAssertEqual(trigger, "jk")
            XCTAssertEqual(sequence, ["escape"])
        } else {
            XCTFail("Expected sequence behavior")
        }
    }
    
    func testComboVisualization() {
        let behavior = KanataBehavior.combo(keys: ["ctrl", "shift", "t"], result: "new_tab")
        
        XCTAssertEqual(behavior.primaryKey, "ctrl + shift + t")
        XCTAssertEqual(behavior.behaviorType, "Combo")
        
        if case .combo(let keys, let result) = behavior {
            XCTAssertEqual(keys.count, 3)
            XCTAssertTrue(keys.contains("ctrl"))
            XCTAssertTrue(keys.contains("shift"))
            XCTAssertTrue(keys.contains("t"))
            XCTAssertEqual(result, "new_tab")
        } else {
            XCTFail("Expected combo behavior")
        }
    }
    
    func testLayerVisualization() {
        let mappings = [
            "1": "f1",
            "2": "f2",
            "3": "f3",
            "4": "f4"
        ]
        
        let behavior = KanataBehavior.layer(key: "fn", layerName: "function", mappings: mappings)
        
        XCTAssertEqual(behavior.primaryKey, "fn")
        XCTAssertEqual(behavior.behaviorType, "Layer")
        
        if case .layer(let key, let layerName, let layerMappings) = behavior {
            XCTAssertEqual(key, "fn")
            XCTAssertEqual(layerName, "function")
            XCTAssertEqual(layerMappings.count, 4)
            XCTAssertEqual(layerMappings["1"], "f1")
            XCTAssertEqual(layerMappings["4"], "f4")
        } else {
            XCTFail("Expected layer behavior")
        }
    }
    
    // MARK: - EnhancedRemapVisualization Tests
    
    func testEnhancedRemapVisualizationWithAllBehaviorTypes() {
        let testCases: [(KanataBehavior, String, String)] = [
            (.simpleRemap(from: "a", toKey: "b"), "Simple Mapping", "Maps a to b"),
            (.tapHold(key: "caps", tap: "esc", hold: "ctrl"), "Enhanced Caps Lock", "Tap for escape, hold for control"),
            (.tapDance(key: "f", actions: []), "Multi-tap F", "Different actions on multiple taps"),
            (.sequence(trigger: "email", sequence: ["test@example.com"]), "Email Expansion", "Types email when 'email' is typed"),
            (.combo(keys: ["cmd", "shift", "4"], result: "screenshot"), "Screenshot Combo", "Take screenshot with three-key combo"),
            (.layer(key: "fn", layerName: "nav", mappings: [:]), "Navigation Layer", "Navigation keys when fn is held")
        ]
        
        for (behavior, title, description) in testCases {
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: title,
                description: description
            )
            
            XCTAssertEqual(visualization.title, title)
            XCTAssertEqual(visualization.description, description)
            
            // Verify behavior is preserved correctly
            switch (behavior, visualization.behavior) {
            case (.simpleRemap(let from1, let to1), .simpleRemap(let from2, let to2)):
                XCTAssertEqual(from1, from2)
                XCTAssertEqual(to1, to2)
            case (.tapHold(let key1, let tap1, let hold1), .tapHold(let key2, let tap2, let hold2)):
                XCTAssertEqual(key1, key2)
                XCTAssertEqual(tap1, tap2)
                XCTAssertEqual(hold1, hold2)
            case (.tapDance(let key1, let actions1), .tapDance(let key2, let actions2)):
                XCTAssertEqual(key1, key2)
                XCTAssertEqual(actions1.count, actions2.count)
                for (action1, action2) in zip(actions1, actions2) {
                    XCTAssertEqual(action1, action2)
                }
            case (.sequence(let trigger1, let seq1), .sequence(let trigger2, let seq2)):
                XCTAssertEqual(trigger1, trigger2)
                XCTAssertEqual(seq1, seq2)
            case (.combo(let keys1, let result1), .combo(let keys2, let result2)):
                XCTAssertEqual(keys1, keys2)
                XCTAssertEqual(result1, result2)
            case (.layer(let key1, let name1, let map1), .layer(let key2, let name2, let map2)):
                XCTAssertEqual(key1, key2)
                XCTAssertEqual(name1, name2)
                XCTAssertEqual(map1, map2)
            default:
                XCTFail("Behavior type mismatch or unhandled case")
            }
        }
    }
    
    // MARK: - Rule Type Color Logic Tests
    
    func testRuleTypeColorMapping() {
        // Test that different behavior types would get appropriate colors
        // Note: We can't test actual SwiftUI Color values, but we can test the logic
        
        let behaviors: [KanataBehavior] = [
            .simpleRemap(from: "a", toKey: "b"),
            .tapHold(key: "space", tap: "spc", hold: "shift"),
            .tapDance(key: "f", actions: []),
            .sequence(trigger: "jk", sequence: ["esc"]),
            .combo(keys: ["a", "b"], result: "c"),
            .layer(key: "fn", layerName: "nav", mappings: [:])
        ]
        
        // Each behavior type should have a consistent behaviorType string
        let expectedTypes = [
            "Simple Remap",
            "Tap-Hold", 
            "Tap Dance",
            "Sequence",
            "Combo",
            "Layer"
        ]
        
        for (behavior, expectedType) in zip(behaviors, expectedTypes) {
            XCTAssertEqual(behavior.behaviorType, expectedType)
        }
    }
    
    // MARK: - Complex Visualization Tests
    
    func testComplexTapDanceVisualization() {
        let actions = [
            TapDanceAction(tapCount: 1, action: "a", description: "Lowercase a"),
            TapDanceAction(tapCount: 2, action: "A", description: "Uppercase A"),
            TapDanceAction(tapCount: 3, action: "@", description: "At symbol"),
            TapDanceAction(tapCount: 4, action: "å", description: "A with ring above"),
            TapDanceAction(tapCount: 5, action: "α", description: "Greek alpha")
        ]
        
        let behavior = KanataBehavior.tapDance(key: "a", actions: actions)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Ultimate A Key",
            description: "Five different outputs from one key"
        )
        
        XCTAssertEqual(visualization.behavior.primaryKey, "a")
        XCTAssertEqual(visualization.behavior.behaviorType, "Tap Dance")
        
        if case .tapDance(let key, let tapActions) = visualization.behavior {
            XCTAssertEqual(key, "a")
            XCTAssertEqual(tapActions.count, 5)
            
            // Verify all actions preserved
            for (index, action) in tapActions.enumerated() {
                XCTAssertEqual(action.tapCount, index + 1)
                XCTAssertEqual(action, actions[index])
            }
        } else {
            XCTFail("Expected tapDance behavior")
        }
    }
    
    func testComplexLayerVisualization() {
        let mappings = [
            "q": "prev_tab",
            "w": "next_tab", 
            "e": "new_tab",
            "r": "reload",
            "t": "reopen_tab",
            "a": "bookmark",
            "s": "save",
            "d": "duplicate_tab",
            "f": "find",
            "g": "find_next",
            "z": "undo",
            "x": "cut",
            "c": "copy",
            "v": "paste"
        ]
        
        let behavior = KanataBehavior.layer(key: "space", layerName: "browser", mappings: mappings)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Browser Navigation Layer",
            description: "Browser shortcuts when space is held"
        )
        
        XCTAssertEqual(visualization.behavior.primaryKey, "space")
        XCTAssertEqual(visualization.behavior.behaviorType, "Layer")
        
        if case .layer(let key, let layerName, let layerMappings) = visualization.behavior {
            XCTAssertEqual(key, "space")
            XCTAssertEqual(layerName, "browser")
            XCTAssertEqual(layerMappings.count, 14)
            XCTAssertEqual(layerMappings["q"], "prev_tab")
            XCTAssertEqual(layerMappings["v"], "paste")
        } else {
            XCTFail("Expected layer behavior")
        }
    }
    
    // MARK: - Edge Cases and Error Conditions
    
    func testVisualizationWithEmptyStrings() {
        let behavior = KanataBehavior.simpleRemap(from: "", toKey: "")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "",
            description: ""
        )
        
        XCTAssertTrue(visualization.title.isEmpty)
        XCTAssertTrue(visualization.description.isEmpty)
        XCTAssertEqual(visualization.behavior.primaryKey, "")
    }
    
    func testVisualizationWithSpecialCharacters() {
        let behavior = KanataBehavior.simpleRemap(from: "←", toKey: "→")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Arrow Keys 🔄",
            description: "Left arrow to right arrow with emoji!"
        )
        
        XCTAssertEqual(visualization.title, "Arrow Keys 🔄")
        XCTAssertEqual(visualization.description, "Left arrow to right arrow with emoji!")
        XCTAssertEqual(visualization.behavior.primaryKey, "←")
    }
    
    func testVisualizationWithLongStrings() {
        let longFrom = String(repeating: "a", count: 100)
        let longTo = String(repeating: "b", count: 100)
        let longTitle = String(repeating: "Title ", count: 50)
        let longDescription = String(repeating: "This is a very long description. ", count: 20)
        
        let behavior = KanataBehavior.simpleRemap(from: longFrom, toKey: longTo)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: longTitle,
            description: longDescription
        )
        
        XCTAssertEqual(visualization.title.count, longTitle.count)
        XCTAssertEqual(visualization.description.count, longDescription.count)
        XCTAssertEqual(visualization.behavior.primaryKey, longFrom)
    }
    
    func testTapDanceWithEmptyActions() {
        let behavior = KanataBehavior.tapDance(key: "empty", actions: [])
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Empty Tap Dance",
            description: "No actions defined"
        )
        
        if case .tapDance(let key, let actions) = visualization.behavior {
            XCTAssertEqual(key, "empty")
            XCTAssertTrue(actions.isEmpty)
        } else {
            XCTFail("Expected tapDance behavior")
        }
    }
    
    func testComboWithSingleKey() {
        let behavior = KanataBehavior.combo(keys: ["a"], result: "single")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Single Key Combo",
            description: "Combo with just one key"
        )
        
        XCTAssertEqual(visualization.behavior.primaryKey, "a")
        
        if case .combo(let keys, let result) = visualization.behavior {
            XCTAssertEqual(keys.count, 1)
            XCTAssertEqual(keys[0], "a")
            XCTAssertEqual(result, "single")
        } else {
            XCTFail("Expected combo behavior")
        }
    }
    
    func testSequenceWithEmptyOutput() {
        let behavior = KanataBehavior.sequence(trigger: "nothing", sequence: [])
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Empty Sequence",
            description: "No output sequence"
        )
        
        if case .sequence(let trigger, let sequence) = visualization.behavior {
            XCTAssertEqual(trigger, "nothing")
            XCTAssertTrue(sequence.isEmpty)
        } else {
            XCTFail("Expected sequence behavior")
        }
    }
    
    // MARK: - Integration Tests
    
    func testVisualizationInCompleteRule() {
        let tapDanceActions = [
            TapDanceAction(tapCount: 1, action: "f", description: "Find"),
            TapDanceAction(tapCount: 2, action: "F", description: "Find backwards"),
            TapDanceAction(tapCount: 3, action: "ctrl+f", description: "Find in page")
        ]
        
        let behavior = KanataBehavior.tapDance(key: "f", actions: tapDanceActions)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Smart Find Key",
            description: "Different find actions based on tap count"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias f (tap-dance 200 f F ctrl+f))",
            confidence: .high,
            explanation: "Enhanced find key with tap dance functionality"
        )
        
        // Test that visualization integrates properly with rule
        XCTAssertEqual(rule.visualization.title, "Smart Find Key")
        XCTAssertEqual(rule.visualization.description, "Different find actions based on tap count")
        XCTAssertEqual(rule.visualization.behavior.primaryKey, "f")
        XCTAssertEqual(rule.visualization.behavior.behaviorType, "Tap Dance")
        
        // Test that the rule can be used in a message
        let message = KeyPathMessage(role: .assistant, rule: rule)
        XCTAssertTrue(message.isRule)
        XCTAssertEqual(message.displayText, rule.explanation)
        XCTAssertNotNil(message.rule)
    }
}