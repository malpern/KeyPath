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
}