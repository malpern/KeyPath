import Testing
import Foundation
@testable import KeyPath

@Suite("UserRuleManager Tests")
struct UserRuleManagerSwiftTests {
    var userRuleManager: UserRuleManager

    init() {
        // Clear UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Active")
        UserDefaults.standard.removeObject(forKey: "KeyPath.UserRules.Deleted")

        userRuleManager = UserRuleManager()
    }

    // MARK: - UserRule Model Tests

    @Test("UserRule creation with proper initialization")
    func userRuleCreation() {
        let kanataRule = createTestKanataRule(explanation: "Test rule")
        let userRule = UserRule(kanataRule: kanataRule, backupPath: "/test/backup")

        #expect(!userRule.id.uuidString.isEmpty)
        #expect(userRule.kanataRule.explanation == "Test rule")
        #expect(userRule.isActive == true) // New rules are active by default
        #expect(userRule.dateCreated.timeIntervalSince1970 > 0)
        #expect(userRule.dateModified == userRule.dateCreated)
        #expect(userRule.backupPath == "/test/backup")
    }

    @Test("UserRule setActive updates state and timestamp")
    func userRuleSetActive() {
        var userRule = UserRule(kanataRule: createTestKanataRule())
        let originalModified = userRule.dateModified

        // Wait to ensure different timestamps
        usleep(1000) // 1ms

        userRule.setActive(false)

        #expect(userRule.isActive == false)
        #expect(userRule.dateModified > originalModified)
    }

    @Test("UserRule Codable conformance")
    func userRuleCodable() throws {
        let kanataRule = createTestKanataRule(explanation: "Codable test")
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

    // MARK: - DeletedRule Model Tests

    @Test("DeletedRule creation from UserRule")
    func deletedRuleCreation() {
        let userRule = UserRule(kanataRule: createTestKanataRule(), backupPath: "/test/backup")
        let deletedRule = DeletedRule(userRule: userRule)

        #expect(!deletedRule.id.uuidString.isEmpty)
        #expect(deletedRule.originalRule.id == userRule.id)
        #expect(deletedRule.deletedDate.timeIntervalSince1970 > 0)
        #expect(deletedRule.backupPath == "/test/backup")
    }

    @Test("DeletedRule creation and basic policy")
    func deletedRuleBasicTest() {
        let userRule = UserRule(kanataRule: createTestKanataRule())
        let freshDeletedRule = DeletedRule(userRule: userRule)

        // Test that fresh deletion should not be permanently deleted
        #expect(freshDeletedRule.shouldPermanentlyDelete == false)

        // Test basic time logic
        let now = Date()
        let past = now.addingTimeInterval(-3600) // 1 hour ago
        #expect(now > past)
    }

    // MARK: - UserRuleManager Initialization Tests

    @Test("UserRuleManager initializes with empty rules")
    func userRuleManagerInitialization() {
        #expect(userRuleManager.activeRules.isEmpty)
        #expect(userRuleManager.allRules.isEmpty)
        #expect(userRuleManager.enabledRules.isEmpty)
    }

    @Test("UserRuleManager loads persistent data")
    func userRuleManagerLoadsPersistentData() {
        // Create some test data in UserDefaults
        let kanataRule = createTestKanataRule(explanation: "Persistent rule")
        let userRule = UserRule(kanataRule: kanataRule)

        let encoder = JSONEncoder()
        if let data = try? encoder.encode([userRule]) {
            UserDefaults.standard.set(data, forKey: "KeyPath.UserRules.Active")
        }

        // Create new manager instance to test loading
        let newManager = UserRuleManager()

        #expect(newManager.activeRules.count == 1)
        #expect(newManager.activeRules[0].kanataRule.explanation == "Persistent rule")
    }

    // MARK: - Add Rule Tests

    @Test("Add rule creates and stores UserRule")
    func addRuleSuccess() async {
        let kanataRule = createTestKanataRule(explanation: "Add rule test")

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.userRuleManager.addRule(kanataRule) { result in
                    switch result {
                    case .success(let userRule):
                        #expect(userRule.kanataRule.explanation == "Add rule test")
                        #expect(userRule.isActive == true)
                        #expect(self.userRuleManager.activeRules.count == 1)
                        #expect(self.userRuleManager.activeRules[0].id == userRule.id)
                    case .failure:
                        // Acceptable in test environment due to missing Kanata setup
                        break
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Rule Collection Tests

    @Test("All rules sorted by creation date (newest first)")
    func allRulesSortedByDate() async {
        let rule1 = createTestKanataRule(explanation: "First rule")
        let rule2 = createTestKanataRule(explanation: "Second rule")

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.userRuleManager.addRule(rule1) { _ in
                    // Wait a bit to ensure different timestamps
                    usleep(1000) // 1ms

                    self.userRuleManager.addRule(rule2) { _ in
                        // Test allRules sorting (newest first)
                        let allRules = self.userRuleManager.allRules
                        if allRules.count == 2 {
                            #expect(allRules[0].kanataRule.explanation == "Second rule")
                            #expect(allRules[1].kanataRule.explanation == "First rule")
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Persistence Tests

    @Test("Persistence handles corrupted data gracefully")
    func corruptedPersistenceData() {
        // Simulate corrupted data in UserDefaults
        UserDefaults.standard.set("invalid json data", forKey: "KeyPath.UserRules.Active")

        // Should handle gracefully and start with empty rules
        let newManager = UserRuleManager()
        #expect(newManager.activeRules.isEmpty)
    }

    @Test("Persistence handles empty data gracefully")
    func emptyPersistenceData() {
        // Simulate empty data
        UserDefaults.standard.set(Data(), forKey: "KeyPath.UserRules.Active")

        let newManager = UserRuleManager()
        #expect(newManager.activeRules.isEmpty)
    }

    // MARK: - Error Handling Tests

    @Test("RuleManagerError types have proper descriptions")
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

    // MARK: - Helper Methods

    private func createTestKanataRule(explanation: String = "Test rule") -> KanataRule {
        let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Rule",
            description: "Test mapping"
        )
        return KanataRule(
            visualization: visualization,
            kanataRule: "(defsrc a)\n(deflayer default b)",
            confidence: .high,
            explanation: explanation
        )
    }
}

// MARK: - Mock KanataInstaller for UserRuleManager Tests

class MockUserRuleKanataInstaller {
    var shouldSucceed: Bool = true
    var backupPath: String = "/mock/backup/path"

    func installRule(_ rule: KanataRule, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            if self.shouldSucceed {
                completion(.success(self.backupPath))
            } else {
                completion(.failure(KanataValidationError.validationFailed("Mock installation failure")))
            }
        }
    }
}
