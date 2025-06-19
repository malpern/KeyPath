import XCTest
import SwiftUI
@testable import KeyPath

final class ViewComponentTests: XCTestCase {
    
    // MARK: - KanataBehavior Tests
    
    func testKanataBehaviorPrimaryKey() {
        let behaviors: [KanataBehavior] = [
            .simpleRemap(from: "caps", toKey: "esc"),
            .tapHold(key: "fn", tap: "f1", hold: "brightness_up"),
            .tapDance(key: "a", actions: []),
            .sequence(trigger: "jk", sequence: ["j", "k"]),
            .combo(keys: ["a", "s"], result: "esc"),
            .layer(key: "fn", layerName: "function", mappings: [:])
        ]
        
        let expectedKeys = [
            "caps",
            "fn", 
            "a",
            "jk",
            "a + s",
            "fn"
        ]
        
        for (behavior, expectedKey) in zip(behaviors, expectedKeys) {
            XCTAssertEqual(behavior.primaryKey, expectedKey)
        }
    }
    
    func testKanataBehaviorBehaviorType() {
        let behaviors: [KanataBehavior] = [
            .simpleRemap(from: "caps", toKey: "esc"),
            .tapHold(key: "fn", tap: "f1", hold: "brightness_up"),
            .tapDance(key: "a", actions: []),
            .sequence(trigger: "jk", sequence: ["j", "k"]),
            .combo(keys: ["a", "s"], result: "esc"),
            .layer(key: "fn", layerName: "function", mappings: [:])
        ]
        
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
    
    // MARK: - EnhancedRemapVisualization Tests
    
    func testEnhancedRemapVisualizationCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Visualization",
            description: "Test description"
        )
        
        XCTAssertEqual(visualization.title, "Test Visualization")
        XCTAssertEqual(visualization.description, "Test description")
        
        if case .simpleRemap(let from, let toKey) = visualization.behavior {
            XCTAssertEqual(from, "caps")
            XCTAssertEqual(toKey, "esc")
        } else {
            XCTFail("Expected simpleRemap behavior")
        }
    }
    
    // MARK: - RemapVisualization Tests
    
    func testRemapVisualizationEnhancedConversion() {
        let oldVisualization = RemapVisualization(from: "a", toKey: "b")
        let enhanced = oldVisualization.enhanced
        
        XCTAssertEqual(enhanced.title, "Simple Remap")
        XCTAssertEqual(enhanced.description, "Maps a to b")
        
        if case .simpleRemap(let from, let toKey) = enhanced.behavior {
            XCTAssertEqual(from, "a")
            XCTAssertEqual(toKey, "b")
        } else {
            XCTFail("Expected simpleRemap behavior")
        }
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
    
    // MARK: - KanataRule Tests
    
    func testKanataRuleCreation() {
        let behavior = KanataBehavior.tapHold(key: "caps", tap: "esc", hold: "ctrl")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Caps Lock Enhancement",
            description: "Tap for Escape, hold for Control"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps (tap-hold 200 200 esc lctrl))",
            confidence: .high,
            explanation: "Enhanced Caps Lock functionality"
        )
        
        XCTAssertEqual(rule.confidence, .high)
        XCTAssertEqual(rule.kanataRule, "(defalias caps (tap-hold 200 200 esc lctrl))")
        XCTAssertEqual(rule.explanation, "Enhanced Caps Lock functionality")
        XCTAssertEqual(rule.visualization.title, "Caps Lock Enhancement")
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
        let behavior = KanataBehavior.combo(keys: ["a", "s"], result: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Combo Test",
            description: "Test combo encoding"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias combo (chord a s esc))",
            confidence: .medium,
            explanation: "Test combo rule"
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
        let message = KeyPathMessage(role: .user, text: "Hello, world!")
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.displayText, "Hello, world!")
        XCTAssertFalse(message.isRule)
        XCTAssertNil(message.rule)
        
        if case .text(let text) = message.type {
            XCTAssertEqual(text, "Hello, world!")
        } else {
            XCTFail("Expected text message type")
        }
    }
    
    func testKeyPathMessageRuleCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule Message",
            description: "Testing rule message creation"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Test rule explanation"
        )
        
        let message = KeyPathMessage(role: .assistant, rule: rule)
        
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.displayText, "Test rule explanation")
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
        
        // Messages should be equal only if they have the same ID
        XCTAssertNotEqual(message1, message2) // Different IDs
        XCTAssertEqual(message1, message1) // Same instance
    }
    
    // MARK: - KeyPathMessageType Tests
    
    func testKeyPathMessageTypeCodable() throws {
        // Test text type
        let textType = KeyPathMessageType.text("Hello")
        let textEncoder = JSONEncoder()
        let textData = try textEncoder.encode(textType)
        let textDecoder = JSONDecoder()
        let decodedTextType = try textDecoder.decode(KeyPathMessageType.self, from: textData)
        
        if case .text(let decodedText) = decodedTextType {
            XCTAssertEqual(decodedText, "Hello")
        } else {
            XCTFail("Expected decoded text type")
        }
        
        // Test rule type
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test",
            description: "Test codable"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(test)",
            confidence: .low,
            explanation: "Test"
        )
        
        let ruleType = KeyPathMessageType.rule(rule)
        let ruleEncoder = JSONEncoder()
        let ruleData = try ruleEncoder.encode(ruleType)
        let ruleDecoder = JSONDecoder()
        let decodedRuleType = try ruleDecoder.decode(KeyPathMessageType.self, from: ruleData)
        
        if case .rule(let decodedRule) = decodedRuleType {
            XCTAssertEqual(decodedRule.kanataRule, rule.kanataRule)
            XCTAssertEqual(decodedRule.explanation, rule.explanation)
        } else {
            XCTFail("Expected decoded rule type")
        }
    }
    
    // MARK: - ChatRole and ChatMessage Tests
    
    func testChatMessageCreation() {
        let message = ChatMessage(role: .user, text: "Test chat message")
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.text, "Test chat message")
        XCTAssertNotNil(message.id)
    }
    
    func testChatMessageEquality() {
        let message1 = ChatMessage(role: .user, text: "Test")
        let message2 = ChatMessage(role: .user, text: "Test")
        
        // Messages should be equal only if they have the same ID
        XCTAssertNotEqual(message1, message2) // Different IDs
        XCTAssertEqual(message1, message1) // Same instance
    }
    
    // MARK: - Integration Tests
    
    func testCompleteRuleWorkflow() {
        // Test creating a complete rule workflow
        let tapDanceActions = [
            TapDanceAction(tapCount: 1, action: "a", description: "Single tap"),
            TapDanceAction(tapCount: 2, action: "A", description: "Double tap"),
            TapDanceAction(tapCount: 3, action: "@", description: "Triple tap")
        ]
        
        let behavior = KanataBehavior.tapDance(key: "a", actions: tapDanceActions)
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Advanced A Key",
            description: "Multi-function A key with tap dance"
        )
        
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a (tap-dance 200 (a A @)))",
            confidence: .high,
            explanation: "Advanced A key functionality with multiple tap options"
        )
        
        let message = KeyPathMessage(role: .assistant, rule: rule)
        
        // Verify the complete workflow
        XCTAssertTrue(message.isRule)
        XCTAssertEqual(message.displayText, rule.explanation)
        XCTAssertEqual(rule.visualization.behavior.primaryKey, "a")
        XCTAssertEqual(rule.visualization.behavior.behaviorType, "Tap Dance")
        
        if case .tapDance(let key, let actions) = rule.visualization.behavior {
            XCTAssertEqual(key, "a")
            XCTAssertEqual(actions.count, 3)
            XCTAssertEqual(actions[0].tapCount, 1)
            XCTAssertEqual(actions[1].action, "A")
            XCTAssertEqual(actions[2].description, "Triple tap")
        } else {
            XCTFail("Expected tap dance behavior")
        }
    }
}