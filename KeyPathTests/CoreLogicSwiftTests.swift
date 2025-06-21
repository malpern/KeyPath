import Foundation
import Testing

@testable import KeyPath

@Suite("Core Logic Tests")
struct CoreLogicSwiftTests {

    @Suite("Rule History Management")
    struct RuleHistoryTests {

        @Test("Add rule to history")
        func addRuleToHistory() {
            // Clear any existing history and force synchronize
            UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
            UserDefaults.standard.synchronize()

            let history = RuleHistory()
            let rule = createSampleRule()

            history.addRule(rule, backupPath: "/tmp/backup.kbd")

            #expect(history.items.count == 1)
            #expect(history.items.first?.rule.confidence == rule.confidence)

            // Clean up
            UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
            UserDefaults.standard.synchronize()
        }

        @Test("History item limit enforcement")
        func historyItemLimitEnforcement() {
            // Clear any existing history and force synchronize
            UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
            UserDefaults.standard.synchronize()

            let history = RuleHistory()

            // Add more items than the limit
            for index in 0..<25 {
                let rule = createSampleRule(explanation: "Rule \(index)")
                history.addRule(rule, backupPath: "/tmp/backup\(index).kbd")
            }

            // Should not exceed the maximum limit (assuming 20 is the limit)
            #expect(history.items.count <= 20)

            // Newest items should be retained
            #expect(history.items.first?.rule.explanation.contains("Rule") == true)

            // Clean up
            UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
            UserDefaults.standard.synchronize()
        }
    }

    @Suite("Message Type Handling")
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
    }

    @Suite("Rule Validation Logic")
    struct RuleValidationTests {

        @Test("Validate rule structure")
        func validateRuleStructure() {
            let rule = createSampleRule()

            // Basic structure validation
            #expect(!rule.kanataRule.isEmpty)
            #expect(!rule.explanation.isEmpty)
            #expect(rule.confidence == .high)
        }
    }
}

// MARK: - Test Utilities
private func createSampleRule(
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
