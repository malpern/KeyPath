import XCTest
import SwiftUI
@testable import KeyPath

final class UIComponentTests: XCTestCase {
    
    // MARK: - Text Formatting Tests
    
    func testFormatTextWithBulletsEmpty() {
        let result = formatTextWithBullets("")
        // Empty string gets split into an array with one empty element
        XCTAssertEqual(result.count, 1)
    }
    
    func testFormatTextWithBulletsSimpleText() {
        let input = "This is a simple line of text."
        let result = formatTextWithBullets(input)
        
        XCTAssertEqual(result.count, 1)
        // We can't easily test the actual view content, but we can test structure
    }
    
    func testFormatTextWithBulletsBulletPoints() {
        let input = """
        Introduction text
        - First bullet point
        - Second bullet point
        - Third bullet point
        """
        let result = formatTextWithBullets(input)
        
        XCTAssertEqual(result.count, 4) // 1 intro + 3 bullets
    }
    
    func testFormatTextWithBulletsEmptyLines() {
        let input = """
        First line
        
        Second line after empty
        
        - Bullet after empty
        """
        let result = formatTextWithBullets(input)
        
        XCTAssertEqual(result.count, 5) // First line + spacer + second line + spacer + bullet
    }
    
    func testFormatTextWithBulletsMarkdown() {
        let input = "This is **bold** and *italic* text."
        let result = formatTextWithBullets(input)
        
        XCTAssertEqual(result.count, 1)
        // The markdown should be parsed into AttributedString
    }
    
    func testFormatTextWithBulletsMixedContent() {
        let input = """
        **Welcome to KeyPath!**
        
        Features:
        - Simple remapping like 'a to b'
        - **Tap-hold** functionality
        - *Advanced* key sequences
        
        Get started now!
        """
        let result = formatTextWithBullets(input)
        
        XCTAssertEqual(result.count, 8) // title + spacer + features + 3 bullets + spacer + conclusion
    }
    
    // MARK: - KanataBehavior Tests
    
    func testKanataBehaviorPrimaryKeys() {
        let behaviors: [(KanataBehavior, String)] = [
            (.simpleRemap(from: "a", toKey: "b"), "a"),
            (.tapHold(key: "space", tap: "spc", hold: "shift"), "space"),
            (.tapDance(key: "f", actions: []), "f"),
            (.sequence(trigger: "jk", sequence: ["escape"]), "jk"),
            (.combo(keys: ["ctrl", "alt"], result: "del"), "ctrl + alt"),
            (.layer(key: "fn", layerName: "function", mappings: [:]), "fn")
        ]
        
        for (behavior, expectedKey) in behaviors {
            XCTAssertEqual(behavior.primaryKey, expectedKey, "Primary key mismatch for \(behavior)")
        }
    }
    
    func testKanataBehaviorTypeNames() {
        let behaviors: [(KanataBehavior, String)] = [
            (.simpleRemap(from: "a", toKey: "b"), "Simple Remap"),
            (.tapHold(key: "space", tap: "spc", hold: "shift"), "Tap-Hold"),
            (.tapDance(key: "f", actions: []), "Tap Dance"),
            (.sequence(trigger: "jk", sequence: ["escape"]), "Sequence"),
            (.combo(keys: ["ctrl", "alt"], result: "del"), "Combo"),
            (.layer(key: "fn", layerName: "function", mappings: [:]), "Layer")
        ]
        
        for (behavior, expectedType) in behaviors {
            XCTAssertEqual(behavior.behaviorType, expectedType, "Behavior type mismatch for \(behavior)")
        }
    }
    
    func testKanataBehaviorComboKeysFormatting() {
        let combo = KanataBehavior.combo(keys: ["a", "s", "d"], result: "hello")
        XCTAssertEqual(combo.primaryKey, "a + s + d")
        
        let singleKeyCombo = KanataBehavior.combo(keys: ["a"], result: "hello")
        XCTAssertEqual(singleKeyCombo.primaryKey, "a")
        
        let emptyCombo = KanataBehavior.combo(keys: [], result: "hello")
        XCTAssertEqual(emptyCombo.primaryKey, "")
    }
    
    // MARK: - TapDanceAction Tests
    
    func testTapDanceActionCreation() {
        let action = TapDanceAction(
            tapCount: 2,
            action: "A",
            description: "Double tap for uppercase A"
        )
        
        XCTAssertEqual(action.tapCount, 2)
        XCTAssertEqual(action.action, "A")
        XCTAssertEqual(action.description, "Double tap for uppercase A")
    }
    
    func testTapDanceActionCodable() throws {
        let action = TapDanceAction(
            tapCount: 3,
            action: "@",
            description: "Triple tap for @ symbol"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(action)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedAction = try decoder.decode(TapDanceAction.self, from: data)
        
        XCTAssertEqual(decodedAction.tapCount, action.tapCount)
        XCTAssertEqual(decodedAction.action, action.action)
        XCTAssertEqual(decodedAction.description, action.description)
    }
    
    // MARK: - EnhancedRemapVisualization Tests
    
    func testEnhancedRemapVisualizationCreation() {
        let behavior = KanataBehavior.tapHold(key: "caps", tap: "esc", hold: "ctrl")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Enhanced Caps Lock",
            description: "Tap for Escape, hold for Control"
        )
        
        XCTAssertEqual(visualization.title, "Enhanced Caps Lock")
        XCTAssertEqual(visualization.description, "Tap for Escape, hold for Control")
        
        if case .tapHold(let key, let tap, let hold) = visualization.behavior {
            XCTAssertEqual(key, "caps")
            XCTAssertEqual(tap, "esc")
            XCTAssertEqual(hold, "ctrl")
        } else {
            XCTFail("Expected tapHold behavior")
        }
    }
    
    func testEnhancedRemapVisualizationWithTapDance() {
        let actions = [
            TapDanceAction(tapCount: 1, action: "f", description: "Single tap"),
            TapDanceAction(tapCount: 2, action: "F", description: "Double tap"),
            TapDanceAction(tapCount: 3, action: "ctrl+f", description: "Triple tap")
        ]
        
        let behavior = KanataBehavior.tapDance(key: "f", actions: actions)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Multi-function F Key",
            description: "Tap dance for f/F/Ctrl+F"
        )
        
        XCTAssertEqual(visualization.title, "Multi-function F Key")
        XCTAssertEqual(visualization.description, "Tap dance for f/F/Ctrl+F")
        
        if case .tapDance(let key, let tapActions) = visualization.behavior {
            XCTAssertEqual(key, "f")
            XCTAssertEqual(tapActions.count, 3)
            XCTAssertEqual(tapActions[0].action, "f")
            XCTAssertEqual(tapActions[1].action, "F")
            XCTAssertEqual(tapActions[2].action, "ctrl+f")
        } else {
            XCTFail("Expected tapDance behavior")
        }
    }
    
    // MARK: - KanataRule Tests
    
    func testKanataRuleCreationWithSimpleRemap() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Caps to Escape",
            description: "Maps Caps Lock to Escape"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Simple caps lock to escape mapping"
        )
        
        XCTAssertEqual(rule.kanataRule, "(defalias caps esc)")
        XCTAssertEqual(rule.confidence, .high)
        XCTAssertEqual(rule.explanation, "Simple caps lock to escape mapping")
        XCTAssertEqual(rule.visualization.title, "Caps to Escape")
        XCTAssertEqual(rule.visualization.description, "Maps Caps Lock to Escape")
    }
    
    func testKanataRuleConfidenceLevels() {
        let confidenceLevels: [KanataRule.Confidence] = [.high, .medium, .low]
        
        for confidence in confidenceLevels {
            let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test",
                description: "Test confidence \(confidence)"
            )
            
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(test)",
                confidence: confidence,
                explanation: "Test rule"
            )
            
            XCTAssertEqual(rule.confidence, confidence)
        }
    }
    
    func testKanataRuleCodable() throws {
        let behavior = KanataBehavior.sequence(trigger: "jk", sequence: ["escape"])
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "JK Escape Sequence",
            description: "Type jk quickly to escape"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias jk-seq (macro j k (on-idle 200 esc)))",
            confidence: .medium,
            explanation: "Quick escape sequence using jk"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedRule = try decoder.decode(KanataRule.self, from: data)
        
        XCTAssertEqual(decodedRule.kanataRule, rule.kanataRule)
        XCTAssertEqual(decodedRule.confidence, rule.confidence)
        XCTAssertEqual(decodedRule.explanation, rule.explanation)
        XCTAssertEqual(decodedRule.visualization.title, rule.visualization.title)
        XCTAssertEqual(decodedRule.visualization.description, rule.visualization.description)
    }
    
    // MARK: - KeyPathMessage Tests
    
    func testKeyPathMessageTextCreation() {
        let message = KeyPathMessage(role: .user, text: "Map caps lock to escape")
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.displayText, "Map caps lock to escape")
        XCTAssertFalse(message.isRule)
        XCTAssertNil(message.rule)
        XCTAssertNotNil(message.id)
        
        if case .text(let text) = message.type {
            XCTAssertEqual(text, "Map caps lock to escape")
        } else {
            XCTFail("Expected text message type")
        }
    }
    
    func testKeyPathMessageRuleCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Caps to Escape",
            description: "Maps Caps Lock to Escape"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Maps Caps Lock to Escape key"
        )
        
        let message = KeyPathMessage(role: .assistant, rule: rule)
        
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.displayText, "Maps Caps Lock to Escape key")
        XCTAssertTrue(message.isRule)
        XCTAssertNotNil(message.rule)
        XCTAssertEqual(message.rule?.kanataRule, "(defalias caps esc)")
        
        if case .rule(let messageRule) = message.type {
            XCTAssertEqual(messageRule.explanation, rule.explanation)
        } else {
            XCTFail("Expected rule message type")
        }
    }
    
    func testKeyPathMessageEquality() {
        let message1 = KeyPathMessage(role: .user, text: "Test message")
        let message2 = KeyPathMessage(role: .user, text: "Test message")
        
        // Messages should only be equal if they have the same ID
        XCTAssertNotEqual(message1, message2) // Different IDs
        XCTAssertEqual(message1, message1) // Same instance
    }
    
    func testKeyPathMessageIdentifiable() {
        let message = KeyPathMessage(role: .user, text: "Test")
        XCTAssertNotNil(message.id)
        
        // Create another message and ensure IDs are different
        let message2 = KeyPathMessage(role: .user, text: "Test")
        XCTAssertNotEqual(message.id, message2.id)
    }
    
    // MARK: - KeyPathMessageType Tests
    
    func testKeyPathMessageTypeCodable() throws {
        // Test text type
        let textType = KeyPathMessageType.text("Hello world")
        let textEncoder = JSONEncoder()
        let textData = try textEncoder.encode(textType)
        let textDecoder = JSONDecoder()
        let decodedTextType = try textDecoder.decode(KeyPathMessageType.self, from: textData)
        
        if case .text(let decodedText) = decodedTextType {
            XCTAssertEqual(decodedText, "Hello world")
        } else {
            XCTFail("Expected decoded text type")
        }
        
        // Test rule type
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .low,
            explanation: "Test rule explanation"
        )
        
        let ruleType = KeyPathMessageType.rule(rule)
        let ruleEncoder = JSONEncoder()
        let ruleData = try ruleEncoder.encode(ruleType)
        let ruleDecoder = JSONDecoder()
        let decodedRuleType = try ruleDecoder.decode(KeyPathMessageType.self, from: ruleData)
        
        if case .rule(let decodedRule) = decodedRuleType {
            XCTAssertEqual(decodedRule.kanataRule, rule.kanataRule)
            XCTAssertEqual(decodedRule.explanation, rule.explanation)
            XCTAssertEqual(decodedRule.confidence, rule.confidence)
        } else {
            XCTFail("Expected decoded rule type")
        }
    }
    
    // MARK: - RemapVisualization (Legacy) Tests
    
    func testRemapVisualizationEnhancedConversion() {
        let oldVisualization = RemapVisualization(from: "ctrl", toKey: "cmd")
        let enhanced = oldVisualization.enhanced
        
        XCTAssertEqual(enhanced.title, "Simple Remap")
        XCTAssertEqual(enhanced.description, "Maps ctrl to cmd")
        
        if case .simpleRemap(let from, let toKey) = enhanced.behavior {
            XCTAssertEqual(from, "ctrl")
            XCTAssertEqual(toKey, "cmd")
        } else {
            XCTFail("Expected simpleRemap behavior")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteRuleWorkflowWithLayer() {
        // Test creating a complete rule workflow with layer behavior
        let mappings = [
            "1": "f1",
            "2": "f2",
            "3": "f3",
            "4": "f4"
        ]
        
        let behavior = KanataBehavior.layer(key: "fn", layerName: "function", mappings: mappings)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Function Layer",
            description: "Number keys become function keys when fn is held"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(deflayer function f1 f2 f3 f4)",
            confidence: .high,
            explanation: "Function key layer activated by fn key"
        )
        
        let message = KeyPathMessage(role: .assistant, rule: rule)
        
        // Verify the complete workflow
        XCTAssertTrue(message.isRule)
        XCTAssertEqual(message.displayText, rule.explanation)
        XCTAssertEqual(rule.visualization.behavior.primaryKey, "fn")
        XCTAssertEqual(rule.visualization.behavior.behaviorType, "Layer")
        
        if case .layer(let key, let layerName, let layerMappings) = rule.visualization.behavior {
            XCTAssertEqual(key, "fn")
            XCTAssertEqual(layerName, "function")
            XCTAssertEqual(layerMappings.count, 4)
            XCTAssertEqual(layerMappings["1"], "f1")
            XCTAssertEqual(layerMappings["4"], "f4")
        } else {
            XCTFail("Expected layer behavior")
        }
    }
    
    func testCompleteRuleWorkflowWithCombo() {
        // Test creating a complete rule workflow with combo behavior
        let behavior = KanataBehavior.combo(keys: ["ctrl", "shift", "alt"], result: "screenshot")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Screenshot Combo",
            description: "Three-key combo for screenshots"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias screenshot-combo (chord ctrl shift alt screenshot))",
            confidence: .medium,
            explanation: "Three-finger screenshot combo"
        )
        
        let message = KeyPathMessage(role: .assistant, rule: rule)
        
        // Verify the complete workflow
        XCTAssertTrue(message.isRule)
        XCTAssertEqual(message.displayText, rule.explanation)
        XCTAssertEqual(rule.visualization.behavior.primaryKey, "ctrl + shift + alt")
        XCTAssertEqual(rule.visualization.behavior.behaviorType, "Combo")
        XCTAssertEqual(rule.confidence, .medium)
        
        if case .combo(let keys, let result) = rule.visualization.behavior {
            XCTAssertEqual(keys.count, 3)
            XCTAssertTrue(keys.contains("ctrl"))
            XCTAssertTrue(keys.contains("shift"))
            XCTAssertTrue(keys.contains("alt"))
            XCTAssertEqual(result, "screenshot")
        } else {
            XCTFail("Expected combo behavior")
        }
    }
    
    // MARK: - Edge Cases and Error Conditions
    
    func testTapDanceActionWithZeroTaps() {
        let action = TapDanceAction(tapCount: 0, action: "nothing", description: "Zero taps")
        XCTAssertEqual(action.tapCount, 0)
        XCTAssertEqual(action.action, "nothing")
    }
    
    func testEmptySequenceBehavior() {
        let behavior = KanataBehavior.sequence(trigger: "empty", sequence: [])
        XCTAssertEqual(behavior.primaryKey, "empty")
        XCTAssertEqual(behavior.behaviorType, "Sequence")
        
        if case .sequence(let trigger, let sequence) = behavior {
            XCTAssertEqual(trigger, "empty")
            XCTAssertTrue(sequence.isEmpty)
        } else {
            XCTFail("Expected sequence behavior")
        }
    }
    
    func testEmptyLayerMappings() {
        let behavior = KanataBehavior.layer(key: "empty", layerName: "none", mappings: [:])
        XCTAssertEqual(behavior.primaryKey, "empty")
        XCTAssertEqual(behavior.behaviorType, "Layer")
        
        if case .layer(let key, let layerName, let mappings) = behavior {
            XCTAssertEqual(key, "empty")
            XCTAssertEqual(layerName, "none")
            XCTAssertTrue(mappings.isEmpty)
        } else {
            XCTFail("Expected layer behavior")
        }
    }
    
    func testMessageWithEmptyText() {
        let message = KeyPathMessage(role: .user, text: "")
        XCTAssertEqual(message.displayText, "")
        XCTAssertFalse(message.isRule)
        
        if case .text(let text) = message.type {
            XCTAssertTrue(text.isEmpty)
        } else {
            XCTFail("Expected text message type")
        }
    }
}