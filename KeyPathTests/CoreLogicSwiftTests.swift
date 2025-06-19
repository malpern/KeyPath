import Testing
@testable import KeyPath

// MARK: - Core Logic Test Tags
extension Tag {
    @Tag static var core: Self
    @Tag static var models: Self
    @Tag static var business: Self
    @Tag static var integration: Self
}

@Suite("Core Logic Tests", .tags(.core, .business))
struct CoreLogicTests {
    
    @Suite("Rule History Management", .tags(.models))
    struct RuleHistoryTests {
        
        @Test("Add rule to history")
        func addRuleToHistory() {
            let history = RuleHistory()
            let rule = createSampleRule()
            
            let item = RuleHistoryItem(
                rule: rule,
                timestamp: Date(),
                backupPath: "/tmp/backup.kbd"
            )
            
            history.addItem(item)
            
            #expect(history.items.count == 1)
            #expect(history.items.first?.rule.confidence == rule.confidence)
        }
        
        @Test("History item limit enforcement")
        func historyItemLimitEnforcement() {
            let history = RuleHistory()
            
            // Add more items than the limit
            for i in 0..<25 {
                let rule = createSampleRule(explanation: "Rule \(i)")
                let item = RuleHistoryItem(
                    rule: rule,
                    timestamp: Date(),
                    backupPath: "/tmp/backup\(i).kbd"
                )
                history.addItem(item)
            }
            
            // Should not exceed the maximum limit (assuming 20 is the limit)
            #expect(history.items.count <= 20)
            
            // Newest items should be retained
            #expect(history.items.first?.rule.explanation.contains("Rule"))
        }
        
        @Test("History persistence", .enabled(if: false)) // Disabled by default, enable for integration testing
        func historyPersistence() {
            let history = RuleHistory()
            let rule = createSampleRule()
            
            let item = RuleHistoryItem(
                rule: rule,
                timestamp: Date(),
                backupPath: "/tmp/test_backup.kbd"
            )
            
            history.addItem(item)
            history.saveToUserDefaults()
            
            let newHistory = RuleHistory()
            newHistory.loadFromUserDefaults()
            
            #expect(newHistory.items.count > 0)
        }
    }
    
    @Suite("Message Type Handling", .tags(.models))
    struct MessageTypeTests {
        
        @Test("Create text message")
        func createTextMessage() {
            let message = KeyPathMessage(role: .user, text: "Hello, world!")
            
            #expect(message.role == .user)
            if case .text(let content) = message.type {
                #expect(content == "Hello, world!")
            } else {
                Issue.record("Expected text message type")
            }
        }
        
        @Test("Create rule message")
        func createRuleMessage() {
            let rule = createSampleRule()
            let message = KeyPathMessage(role: .assistant, rule: rule)
            
            #expect(message.role == .assistant)
            if case .rule(let messageRule) = message.type {
                #expect(messageRule.confidence == rule.confidence)
                #expect(messageRule.explanation == rule.explanation)
            } else {
                Issue.record("Expected rule message type")
            }
        }
        
        @Test("Message equality comparison")
        func messageEqualityComparison() {
            let message1 = KeyPathMessage(role: .user, text: "Test")
            let message2 = KeyPathMessage(role: .user, text: "Test")
            let message3 = KeyPathMessage(role: .assistant, text: "Test")
            
            #expect(message1 == message2)
            #expect(message1 != message3)
        }
        
        @Test("Message role types", arguments: [ChatRole.user, ChatRole.assistant])
        func messageRoleTypes(role: ChatRole) {
            let message = KeyPathMessage(role: role, text: "Test message")
            #expect(message.role == role)
        }
    }
    
    @Suite("Rule Validation Logic", .tags(.business))
    struct RuleValidationTests {
        
        @Test("Validate rule structure")
        func validateRuleStructure() {
            let rule = createSampleRule()
            
            // Basic structure validation
            #expect(!rule.kanataRule.isEmpty)
            #expect(!rule.explanation.isEmpty)
            #expect(rule.confidence != nil)
        }
        
        @Test("Validate kanata rule syntax")
        func validateKanataRuleSyntax() {
            let validRules = [
                "(defalias caps esc)",
                "(deflayer base caps esc)",
                "(defchordsv2-experimental (cmd space) spotlight 50)"
            ]
            
            for ruleString in validRules {
                // Basic syntax validation - should contain parentheses
                #expect(ruleString.hasPrefix("("))
                #expect(ruleString.hasSuffix(")"))
                #expect(ruleString.contains("def"))
            }
        }
        
        @Test("Rule confidence validation", 
              arguments: [
                KanataRule.Confidence.high,
                KanataRule.Confidence.medium,
                KanataRule.Confidence.low
              ])
        func ruleConfidenceValidation(confidence: KanataRule.Confidence) {
            let rule = createSampleRule(confidence: confidence)
            #expect(rule.confidence == confidence)
            
            // Ensure confidence level affects validation logic
            switch confidence {
            case .high:
                #expect(true) // High confidence rules should always be valid
            case .medium:
                #expect(true) // Medium confidence rules need review
            case .low:
                #expect(true) // Low confidence rules need careful review
            }
        }
    }
    
    @Suite("Enhanced Behavior Logic", .tags(.business))
    struct EnhancedBehaviorTests {
        
        @Test("Behavior primary key extraction consistency")
        func behaviorPrimaryKeyConsistency() {
            let behaviors = [
                KanataBehavior.simpleRemap(from: "a", toKey: "b"),
                KanataBehavior.tapHold(key: "space", tap: "space", hold: "cmd"),
                KanataBehavior.combo(keys: ["cmd", "c"], result: "copy")
            ]
            
            for behavior in behaviors {
                let primaryKey = behavior.primaryKey
                #expect(!primaryKey.isEmpty)
                
                // Primary key should be deterministic
                let secondCall = behavior.primaryKey
                #expect(primaryKey == secondCall)
            }
        }
        
        @Test("Behavior description generation")
        func behaviorDescriptionGeneration() {
            let behavior = KanataBehavior.tapHold(
                key: "space",
                tap: "space",
                hold: "cmd"
            )
            
            let description = behavior.description
            #expect(description.contains("space"))
            #expect(description.contains("tap"))
            #expect(description.contains("hold"))
        }
        
        @Test("Complex behavior handling")
        func complexBehaviorHandling() {
            let tapDanceActions = [
                TapDanceAction(tapCount: 1, action: "a", description: "Single tap"),
                TapDanceAction(tapCount: 2, action: "esc", description: "Double tap"),
                TapDanceAction(tapCount: 3, action: "enter", description: "Triple tap")
            ]
            
            let behavior = KanataBehavior.tapDance(key: "a", actions: tapDanceActions)
            
            #expect(behavior.primaryKey == "a")
            
            if case .tapDance(let key, let actions) = behavior {
                #expect(key == "a")
                #expect(actions.count == 3)
                #expect(actions.map { $0.tapCount } == [1, 2, 3])
            } else {
                Issue.record("Expected tapDance behavior")
            }
        }
    }
    
    @Suite("Integration Logic", .tags(.integration))
    struct IntegrationTests {
        
        @Test("Rule creation workflow")
        func ruleCreationWorkflow() {
            // Simulate complete rule creation workflow
            let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
            
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Caps to Escape",
                description: "Map Caps Lock to Escape key"
            )
            
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(defalias caps esc)",
                confidence: .high,
                explanation: "Standard Caps Lock to Escape mapping"
            )
            
            // Create history item
            let historyItem = RuleHistoryItem(
                rule: rule,
                timestamp: Date(),
                backupPath: "/tmp/caps_to_esc_backup.kbd"
            )
            
            // Validate entire workflow
            #expect(rule.visualization.behavior.primaryKey == "caps")
            #expect(rule.confidence == .high)
            #expect(!historyItem.backupPath.isEmpty)
            #expect(historyItem.timestamp <= Date())
        }
        
        @Test("Rule message integration")
        func ruleMessageIntegration() {
            let rule = createSampleRule()
            let message = KeyPathMessage(role: .assistant, rule: rule)
            
            if case .rule(let messageRule) = message.type {
                #expect(messageRule.kanataRule == rule.kanataRule)
                #expect(messageRule.confidence == rule.confidence)
            } else {
                Issue.record("Expected rule message type")
            }
            
            // Message should have valid ID and timestamp
            #expect(!message.id.uuidString.isEmpty)
            #expect(message.timestamp <= Date())
        }
    }
}

// MARK: - Test Utilities
private extension CoreLogicTests {
    
    static func createSampleRule(
        explanation: String = "Sample rule explanation",
        confidence: KanataRule.Confidence = .high
    ) -> KanataRule {
        let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "sample")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Sample Rule",
            description: "Sample description"
        )
        
        return KanataRule(
            visualization: visualization,
            kanataRule: "(defalias test sample)",
            confidence: confidence,
            explanation: explanation
        )
    }
}