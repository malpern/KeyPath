import XCTest
@testable import KeyPath

final class RuleHistoryTests: XCTestCase {
    var ruleHistory: RuleHistory!
    
    override func setUp() {
        super.setUp()
        ruleHistory = RuleHistory()
        // Clear any existing history for clean tests
        ruleHistory.items.removeAll()
    }
    
    override func tearDown() {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
        ruleHistory = nil
        super.tearDown()
    }
    
    // MARK: - RuleHistoryItem Tests
    
    func testRuleHistoryItemCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .high,
            explanation: "Test rule"
        )
        
        let timestamp = Date()
        let item = RuleHistoryItem(
            rule: rule,
            timestamp: timestamp,
            backupPath: "/path/to/backup"
        )
        
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.rule.kanataRule, "(defalias a b)")
        XCTAssertEqual(item.timestamp, timestamp)
        XCTAssertEqual(item.backupPath, "/path/to/backup")
    }
    
    func testRuleHistoryItemCodable() throws {
        let behavior = KanataBehavior.tapHold(key: "caps", tap: "esc", hold: "ctrl")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Enhanced Caps",
            description: "Tap/hold caps lock"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps (tap-hold 200 200 esc lctrl))",
            confidence: .high,
            explanation: "Enhanced caps lock functionality"
        )
        
        let item = RuleHistoryItem(
            rule: rule,
            timestamp: Date(),
            backupPath: "/test/backup/path"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(item)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedItem = try decoder.decode(RuleHistoryItem.self, from: data)
        
        XCTAssertEqual(decodedItem.id, item.id)
        XCTAssertEqual(decodedItem.rule.kanataRule, item.rule.kanataRule)
        XCTAssertEqual(decodedItem.backupPath, item.backupPath)
        XCTAssertEqual(decodedItem.timestamp.timeIntervalSince1970, item.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testRuleHistoryItemIdentifiable() {
        let rule = createTestRule()
        let item1 = RuleHistoryItem(rule: rule, timestamp: Date(), backupPath: "/path1")
        let item2 = RuleHistoryItem(rule: rule, timestamp: Date(), backupPath: "/path2")
        
        XCTAssertNotEqual(item1.id, item2.id)
    }
    
    // MARK: - RuleHistory Tests
    
    func testRuleHistoryInitialization() {
        XCTAssertTrue(ruleHistory.items.isEmpty)
    }
    
    func testAddSingleRule() {
        let rule = createTestRule()
        
        ruleHistory.addRule(rule, backupPath: "/test/backup")
        
        XCTAssertEqual(ruleHistory.items.count, 1)
        XCTAssertEqual(ruleHistory.items[0].rule.kanataRule, rule.kanataRule)
        XCTAssertEqual(ruleHistory.items[0].backupPath, "/test/backup")
    }
    
    func testAddMultipleRules() {
        let rule1 = createTestRule(explanation: "First rule")
        let rule2 = createTestRule(explanation: "Second rule")
        let rule3 = createTestRule(explanation: "Third rule")
        
        ruleHistory.addRule(rule1, backupPath: "/backup1")
        ruleHistory.addRule(rule2, backupPath: "/backup2")
        ruleHistory.addRule(rule3, backupPath: "/backup3")
        
        XCTAssertEqual(ruleHistory.items.count, 3)
        
        // Most recent should be first
        XCTAssertEqual(ruleHistory.items[0].rule.explanation, "Third rule")
        XCTAssertEqual(ruleHistory.items[1].rule.explanation, "Second rule")
        XCTAssertEqual(ruleHistory.items[2].rule.explanation, "First rule")
    }
    
    func testGetLastRule() {
        // Empty history
        XCTAssertNil(ruleHistory.getLastRule())
        
        // Add one rule
        let rule = createTestRule()
        ruleHistory.addRule(rule, backupPath: "/test/backup")
        
        let lastRule = ruleHistory.getLastRule()
        XCTAssertNotNil(lastRule)
        XCTAssertEqual(lastRule?.rule.kanataRule, rule.kanataRule)
        XCTAssertEqual(lastRule?.backupPath, "/test/backup")
    }
    
    func testRemoveLastRule() {
        // Try removing from empty history
        ruleHistory.removeLastRule()
        XCTAssertTrue(ruleHistory.items.isEmpty)
        
        // Add rules and remove
        let rule1 = createTestRule(explanation: "First")
        let rule2 = createTestRule(explanation: "Second")
        
        ruleHistory.addRule(rule1, backupPath: "/backup1")
        ruleHistory.addRule(rule2, backupPath: "/backup2")
        
        XCTAssertEqual(ruleHistory.items.count, 2)
        
        // Remove last (most recent)
        ruleHistory.removeLastRule()
        XCTAssertEqual(ruleHistory.items.count, 1)
        XCTAssertEqual(ruleHistory.items[0].rule.explanation, "First")
        
        // Remove remaining
        ruleHistory.removeLastRule()
        XCTAssertTrue(ruleHistory.items.isEmpty)
    }
    
    func testHistoryLimit() {
        // Add more than the maximum (20) rules
        for i in 1...25 {
            let rule = createTestRule(explanation: "Rule \(i)")
            ruleHistory.addRule(rule, backupPath: "/backup\(i)")
        }
        
        // Should be limited to 20 items
        XCTAssertEqual(ruleHistory.items.count, 20)
        
        // Most recent should be first
        XCTAssertEqual(ruleHistory.items[0].rule.explanation, "Rule 25")
        XCTAssertEqual(ruleHistory.items[19].rule.explanation, "Rule 6")
    }
    
    func testTimestampOrdering() {
        let rule1 = createTestRule(explanation: "First")
        let rule2 = createTestRule(explanation: "Second")
        
        ruleHistory.addRule(rule1, backupPath: "/backup1")
        
        // Wait a tiny bit to ensure different timestamps
        usleep(1000) // 1ms
        
        ruleHistory.addRule(rule2, backupPath: "/backup2")
        
        // Second rule should be first (most recent)
        XCTAssertEqual(ruleHistory.items[0].rule.explanation, "Second")
        XCTAssertEqual(ruleHistory.items[1].rule.explanation, "First")
        
        // Verify timestamps are ordered
        XCTAssertTrue(ruleHistory.items[0].timestamp > ruleHistory.items[1].timestamp)
    }
    
    // MARK: - Persistence Tests
    
    func testPersistenceAfterAddingRule() {
        let rule = createTestRule()
        ruleHistory.addRule(rule, backupPath: "/test/backup")
        
        // Create new instance to test loading
        let newRuleHistory = RuleHistory()
        
        XCTAssertEqual(newRuleHistory.items.count, 1)
        XCTAssertEqual(newRuleHistory.items[0].rule.kanataRule, rule.kanataRule)
        XCTAssertEqual(newRuleHistory.items[0].backupPath, "/test/backup")
    }
    
    func testPersistenceAfterRemovingRule() {
        // Add two rules
        let rule1 = createTestRule(explanation: "First")
        let rule2 = createTestRule(explanation: "Second")
        
        ruleHistory.addRule(rule1, backupPath: "/backup1")
        ruleHistory.addRule(rule2, backupPath: "/backup2")
        
        // Remove one
        ruleHistory.removeLastRule()
        
        // Create new instance to test persistence
        let newRuleHistory = RuleHistory()
        
        XCTAssertEqual(newRuleHistory.items.count, 1)
        XCTAssertEqual(newRuleHistory.items[0].rule.explanation, "First")
    }
    
    func testPersistenceWithComplexRules() {
        // Test persistence with various rule types
        let tapDanceActions = [
            TapDanceAction(tapCount: 1, action: "a", description: "Single"),
            TapDanceAction(tapCount: 2, action: "A", description: "Double"),
            TapDanceAction(tapCount: 3, action: "@", description: "Triple")
        ]
        
        let behaviors: [KanataBehavior] = [
            .simpleRemap(from: "caps", toKey: "esc"),
            .tapHold(key: "space", tap: "spc", hold: "shift"),
            .tapDance(key: "a", actions: tapDanceActions),
            .sequence(trigger: "jk", sequence: ["escape"]),
            .combo(keys: ["ctrl", "alt"], result: "del"),
            .layer(key: "fn", layerName: "function", mappings: ["1": "f1", "2": "f2"])
        ]
        
        for (index, behavior) in behaviors.enumerated() {
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Rule \(index + 1)",
                description: "Test rule \(index + 1)"
            )
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(test-rule-\(index + 1))",
                confidence: .high,
                explanation: "Test rule \(index + 1)"
            )
            
            ruleHistory.addRule(rule, backupPath: "/backup\(index + 1)")
        }
        
        // Create new instance to test persistence
        let newRuleHistory = RuleHistory()
        
        XCTAssertEqual(newRuleHistory.items.count, 6)
        
        // Verify all rule types persisted correctly
        for (index, item) in newRuleHistory.items.enumerated() {
            let expectedIndex = 6 - index // Reverse order (most recent first)
            XCTAssertEqual(item.rule.explanation, "Test rule \(expectedIndex)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testCorruptedPersistenceData() {
        // Simulate corrupted data in UserDefaults
        UserDefaults.standard.set("invalid json data", forKey: "KeyPath.RuleHistory")
        
        // Should handle gracefully and start with empty history
        let newRuleHistory = RuleHistory()
        XCTAssertTrue(newRuleHistory.items.isEmpty)
    }
    
    func testEmptyPersistenceData() {
        // Simulate empty data
        UserDefaults.standard.set(Data(), forKey: "KeyPath.RuleHistory")
        
        let newRuleHistory = RuleHistory()
        XCTAssertTrue(newRuleHistory.items.isEmpty)
    }
    
    func testNilPersistenceData() {
        // Remove any existing data
        UserDefaults.standard.removeObject(forKey: "KeyPath.RuleHistory")
        
        let newRuleHistory = RuleHistory()
        XCTAssertTrue(newRuleHistory.items.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    private func createTestRule(explanation: String = "Test rule") -> KanataRule {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        return KanataRule(
            visualization: visualization,
            kanataRule: "(defalias a b)",
            confidence: .high,
            explanation: explanation
        )
    }
}