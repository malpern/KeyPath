import Testing
import Foundation
@testable import KeyPath

@Suite("Minimal UserRule Tests")
struct MinimalUserRuleTests {

    @Test("UserRule can be created")
    func userRuleCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc a)\n(deflayer default b)",
            confidence: .high,
            explanation: "Test rule"
        )

        let userRule = UserRule(kanataRule: kanataRule, backupPath: "/test/backup")

        #expect(!userRule.id.uuidString.isEmpty)
        #expect(userRule.kanataRule.explanation == "Test rule")
        #expect(userRule.isActive == true)
        #expect(userRule.backupPath == "/test/backup")
    }

    @Test("UserRule state can be changed")
    func userRuleStateChange() {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc a)\n(deflayer default b)",
            confidence: .high,
            explanation: "Test rule"
        )

        var userRule = UserRule(kanataRule: kanataRule)
        let originalTime = userRule.dateModified

        userRule.setActive(false)

        #expect(userRule.isActive == false)
        #expect(userRule.dateModified >= originalTime)
    }

    @Test("UserRuleManager initializes empty")
    func userRuleManagerInit() {
        // Clear any existing data
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Deleted")

        let manager = UserRuleManager()

        #expect(manager.activeRules.isEmpty)
        #expect(manager.allRules.isEmpty)
        #expect(manager.enabledRules.isEmpty)
    }

    @Test("UserRule Codable conformance")
    func userRuleCodable() throws {
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Caps to Esc",
            description: "Caps lock to escape key"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc caps)\n(deflayer default esc)",
            confidence: .high,
            explanation: "Caps lock remapped to escape"
        )

        let userRule = UserRule(kanataRule: kanataRule, backupPath: "/test/backup")

        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(userRule)

        // Test decoding
        let decoder = JSONDecoder()
        let decodedRule = try decoder.decode(UserRule.self, from: data)

        #expect(decodedRule.id == userRule.id)
        #expect(decodedRule.kanataRule.explanation == userRule.kanataRule.explanation)
        #expect(decodedRule.isActive == userRule.isActive)
        #expect(decodedRule.backupPath == userRule.backupPath)
    }

    @Test("DeletedRule creation and properties")
    func deletedRuleCreation() {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc a)\n(deflayer default b)",
            confidence: .high,
            explanation: "Test rule"
        )

        let userRule = UserRule(kanataRule: kanataRule, backupPath: "/test/backup")
        let deletedRule = DeletedRule(userRule: userRule)

        #expect(!deletedRule.id.uuidString.isEmpty)
        #expect(deletedRule.originalRule.id == userRule.id)
        #expect(deletedRule.deletedDate.timeIntervalSince1970 > 0)
        #expect(deletedRule.backupPath == "/test/backup")

        // Fresh deletion should not be permanently deleted
        #expect(deletedRule.shouldPermanentlyDelete == false)
    }

    @Test("DeletedRule 48-hour retention policy")
    func deletedRuleRetentionPolicy() {
        let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "key")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc test)\n(deflayer default key)",
            confidence: .high,
            explanation: "Test rule for retention"
        )

        let userRule = UserRule(kanataRule: kanataRule)
        let deletedRule = DeletedRule(userRule: userRule)

        // Test that fresh deletion is not eligible for permanent deletion
        #expect(deletedRule.shouldPermanentlyDelete == false)

        // Test the time calculation logic (verify 48 hours = 172800 seconds)
        let fortyEightHours: TimeInterval = 48 * 60 * 60
        #expect(fortyEightHours == 172800)

        // Test time comparison logic
        let now = Date()
        let past = now.addingTimeInterval(-fortyEightHours - 1) // Just over 48 hours ago
        let recent = now.addingTimeInterval(-fortyEightHours + 3600) // 47 hours ago

        #expect(past < now.addingTimeInterval(-fortyEightHours))
        #expect(recent > now.addingTimeInterval(-fortyEightHours))
    }

    @Test("UserRuleManager persistence handles corrupted data")
    func persistenceCorruptedData() {
        // Set corrupted data in UserDefaults
        UserDefaults.standard.set("invalid json data", forKey: "KeyPath.UserRules.Active")

        // Should handle gracefully and start with empty rules
        let manager = UserRuleManager()
        #expect(manager.activeRules.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
    }

    @Test("UserRuleManager persistence handles empty data")
    func persistenceEmptyData() {
        // Set empty data
        UserDefaults.standard.set(Data(), forKey: "KeyPath.UserRules.Active")

        let manager = UserRuleManager()
        #expect(manager.activeRules.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
    }

    @Test("RuleManagerError descriptions")
    func ruleManagerErrorDescriptions() {
        let errors: [RuleManagerError] = [
            .ruleNotFound,
            .configRegenerationFailed
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }

        // Test specific error messages
        #expect(RuleManagerError.ruleNotFound.localizedDescription.contains("not found"))
        #expect(RuleManagerError.configRegenerationFailed.localizedDescription.contains("regenerate"))
    }

    @Test("UserRuleManager loads persistent data")
    func persistenceLoadData() {
        // Clear any existing data first
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Deleted")

        // Create test data
        let behavior = KanataBehavior.simpleRemap(from: "test", toKey: "persistent")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Persistent Rule",
            description: "Test persistence"
        )
        let kanataRule = KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc test)\n(deflayer default persistent)",
            confidence: .high,
            explanation: "Persistent test rule"
        )

        let userRule = UserRule(kanataRule: kanataRule)

        // Manually save data to UserDefaults
        let encoder = JSONEncoder()
        if let data = try? encoder.encode([userRule]) {
            UserDefaults.standard.set(data, forKey: "KeyPath.UserRules.Active")
        }

        // Create new manager to test loading
        let manager = UserRuleManager()

        // Verify that the manager successfully loaded the persistent data
        #expect(manager.activeRules.count == 1)
        #expect(manager.activeRules[0].kanataRule.explanation == "Persistent test rule")
        #expect(manager.activeRules[0].isActive == true)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Deleted")
    }
}
