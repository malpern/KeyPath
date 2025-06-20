import Testing
import Foundation
@testable import KeyPath

@Suite("Model Tests")
struct ModelTests {

    @Suite("KanataBehavior Tests")
    struct KanataBehaviorTests {

        @Test("Simple remap behavior properties")
        func simpleRemapBehaviorProperties() {
            let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
            
            #expect(behavior.primaryKey == "caps")
            #expect(behavior.behaviorType == "Simple Remap")
            #expect(behavior.description.contains("caps"))
            #expect(behavior.description.contains("esc"))
        }

        @Test("Tap-hold behavior properties")
        func tapHoldBehaviorProperties() {
            let behavior = KanataBehavior.tapHold(key: "space", tap: "space", hold: "cmd")
            
            #expect(behavior.primaryKey == "space")
            #expect(behavior.behaviorType == "Tap-Hold")
            #expect(behavior.description.contains("space"))
            #expect(behavior.description.contains("tap"))
            #expect(behavior.description.contains("hold"))
        }

        @Test("Combo behavior properties")
        func comboBehaviorProperties() {
            let behavior = KanataBehavior.combo(keys: ["cmd", "space"], result: "spotlight")
            
            #expect(behavior.primaryKey == "cmd + space")
            #expect(behavior.behaviorType == "Combo")
            #expect(behavior.description.contains("cmd"))
            #expect(behavior.description.contains("space"))
            #expect(behavior.description.contains("spotlight"))
        }

        @Test("Tap dance behavior properties")
        func tapDanceBehaviorProperties() {
            let actions = [
                TapDanceAction(tapCount: 1, action: "a", description: "Single tap"),
                TapDanceAction(tapCount: 2, action: "esc", description: "Double tap")
            ]
            let behavior = KanataBehavior.tapDance(key: "a", actions: actions)
            
            #expect(behavior.primaryKey == "a")
            #expect(behavior.behaviorType == "Tap Dance")
            #expect(behavior.description.contains("a"))
            #expect(behavior.description.contains("tap dance"))
        }

        @Test("Sequence behavior properties")
        func sequenceBehaviorProperties() {
            let behavior = KanataBehavior.sequence(trigger: "jk", sequence: ["escape"])
            
            #expect(behavior.primaryKey == "jk")
            #expect(behavior.behaviorType == "Sequence")
            #expect(behavior.description.contains("jk"))
            #expect(behavior.description.contains("escape"))
        }

        @Test("Layer behavior properties")
        func layerBehaviorProperties() {
            let mappings = ["1": "f1", "2": "f2"]
            let behavior = KanataBehavior.layer(key: "fn", layerName: "function", mappings: mappings)
            
            #expect(behavior.primaryKey == "fn")
            #expect(behavior.behaviorType == "Layer")
            #expect(behavior.description.contains("fn"))
            #expect(behavior.description.contains("function"))
            #expect(behavior.description.contains("2 mappings"))
        }
    }

    @Suite("TapDanceAction Tests")
    struct TapDanceActionTests {

        @Test("TapDanceAction equality")
        func tapDanceActionEquality() {
            let action1 = TapDanceAction(tapCount: 1, action: "a", description: "Test")
            let action2 = TapDanceAction(tapCount: 1, action: "a", description: "Test")
            let action3 = TapDanceAction(tapCount: 2, action: "a", description: "Test")
            
            #expect(action1 == action2)
            #expect(action1 != action3)
        }

        @Test("TapDanceAction codable")
        func tapDanceActionCodable() throws {
            let action = TapDanceAction(tapCount: 2, action: "esc", description: "Double tap escape")
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(action)
            
            let decoder = JSONDecoder()
            let decodedAction = try decoder.decode(TapDanceAction.self, from: data)
            
            #expect(decodedAction == action)
        }
    }

    @Suite("EnhancedRemapVisualization Tests")
    struct EnhancedRemapVisualizationTests {

        @Test("Enhanced visualization codable")
        func enhancedVisualizationCodable() throws {
            let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "example")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Visualization",
                description: "Test description"
            )
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(visualization)
            
            let decoder = JSONDecoder()
            let decodedVisualization = try decoder.decode(EnhancedRemapVisualization.self, from: data)
            
            #expect(decodedVisualization.title == visualization.title)
            #expect(decodedVisualization.description == visualization.description)
        }
    }

    @Suite("KanataRule Tests")
    struct KanataRuleTests {

        @Test("KanataRule complete config property")
        func kanataRuleCompleteConfig() {
            let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "sample")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Rule",
                description: "Test description"
            )
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(defsrc test)\n(deflayer default sample)",
                confidence: .high,
                explanation: "Test explanation"
            )
            
            #expect(rule.completeKanataConfig == rule.kanataRule)
        }

        @Test("KanataRule display rule extraction")
        func kanataRuleDisplayRule() {
            let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "sample")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Rule",
                description: "Test description"
            )
            
            // Test with defalias
            let rule1 = KanataRule(
                visualization: visualization,
                kanataRule: "(defalias test sample)",
                confidence: .high,
                explanation: "Test explanation"
            )
            #expect(rule1.displayRule.contains("defalias"))
            
            // Test with arrow format
            let rule2 = KanataRule(
                visualization: visualization,
                kanataRule: "test -> sample",
                confidence: .high,
                explanation: "Test explanation"
            )
            #expect(rule2.displayRule == "test -> sample")
        }

        @Test("KanataRule confidence levels")
        func kanataRuleConfidenceLevels() {
            let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "sample")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Rule",
                description: "Test description"
            )
            
            let highRule = KanataRule(
                visualization: visualization,
                kanataRule: "test rule",
                confidence: .high,
                explanation: "High confidence"
            )
            
            let mediumRule = KanataRule(
                visualization: visualization,
                kanataRule: "test rule",
                confidence: .medium,
                explanation: "Medium confidence"
            )
            
            let lowRule = KanataRule(
                visualization: visualization,
                kanataRule: "test rule",
                confidence: .low,
                explanation: "Low confidence"
            )
            
            #expect(highRule.confidence == .high)
            #expect(mediumRule.confidence == .medium)
            #expect(lowRule.confidence == .low)
        }
    }

    @Suite("ChatRole Tests")
    struct ChatRoleTests {

        @Test("ChatRole types")
        func chatRoleTypes() {
            let userRole = ChatRole.user
            let assistantRole = ChatRole.assistant
            
            #expect(userRole == .user)
            #expect(assistantRole == .assistant)
            #expect(userRole != assistantRole)
        }
    }

    @Suite("KeyPathMessage Tests")  
    struct KeyPathMessageTests {

        @Test("Text message creation")
        func textMessageCreation() {
            let message = KeyPathMessage(role: .user, text: "Test message")
            
            #expect(message.role == .user)
            #expect(!message.id.uuidString.isEmpty)
            #expect(message.timestamp <= Date())
            
            if case .text(let content) = message.type {
                #expect(content == "Test message")
            } else {
                Issue.record("Expected text message type")
            }
        }

        @Test("Rule message creation")
        func ruleMessageCreation() {
            let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "sample")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Rule",
                description: "Test description"
            )
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "test rule",
                confidence: .high,
                explanation: "Test explanation"
            )
            let message = KeyPathMessage(role: .assistant, rule: rule)
            
            #expect(message.role == .assistant)
            
            if case .rule(let messageRule) = message.type {
                #expect(messageRule.explanation == "Test explanation")
            } else {
                Issue.record("Expected rule message type")
            }
        }

        @Test("Message equality")
        func messageEquality() {
            let message1 = KeyPathMessage(role: .user, text: "Same text")
            let message2 = KeyPathMessage(role: .user, text: "Same text")
            let message3 = KeyPathMessage(role: .assistant, text: "Same text")
            
            // Note: Messages with same content but different IDs are not equal
            #expect(message1.role == message2.role)
            #expect(message1.role != message3.role)
        }
    }
}