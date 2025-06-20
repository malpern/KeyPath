import Testing
import SwiftUI
@testable import KeyPath

// MARK: - Test Tags
extension Tag {
    @Tag static var viewModels: Self
    @Tag static var behavior: Self
    @Tag static var ui: Self
}

@Suite("View Component Tests", .tags(.ui, .viewModels))
struct ViewComponentSwiftTests {
    
    @Suite("KanataBehavior Tests", .tags(.behavior))
    struct KanataBehaviorTests {
        
        @Test("Behavior primary key extraction", 
              arguments: [
                (KanataBehavior.simpleRemap(from: "caps", toKey: "esc"), "caps"),
                (KanataBehavior.tapHold(key: "fn", tap: "f1", hold: "brightness_up"), "fn"),
                (KanataBehavior.tapDance(key: "a", actions: []), "a"),
                (KanataBehavior.sequence(trigger: "jk", sequence: ["j", "k"]), "jk"),
                (KanataBehavior.combo(keys: ["a", "s"], result: "esc"), "a + s"),
                (KanataBehavior.layer(key: "fn", layerName: "function", mappings: [:]), "fn")
              ])
        func behaviorPrimaryKey(behavior: KanataBehavior, expectedKey: String) {
            #expect(behavior.primaryKey == expectedKey)
        }
        
        @Test("Behavior description generation")
        func behaviorDescription() {
            let simpleRemap = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
            let tapHold = KanataBehavior.tapHold(key: "fn", tap: "f1", hold: "brightness_up")
            
            #expect(simpleRemap.description.contains("caps"))
            #expect(simpleRemap.description.contains("esc"))
            #expect(tapHold.description.contains("fn"))
            #expect(tapHold.description.contains("tap"))
            #expect(tapHold.description.contains("hold"))
        }
    }
    
    @Suite("EnhancedRemapVisualization Tests")
    struct VisualizationTests {
        
        @Test("Enhanced visualization creation")
        func enhancedVisualizationCreation() {
            let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Remap",
                description: "Maps a to b"
            )
            
            #expect(visualization.title == "Test Remap")
            #expect(visualization.description == "Maps a to b")
            #expect(visualization.behavior.primaryKey == "a")
        }
        
        @Test("Visualization behavior consistency")
        func visualizationBehaviorConsistency() {
            let behaviors: [KanataBehavior] = [
                .simpleRemap(from: "caps", toKey: "esc"),
                .tapHold(key: "fn", tap: "f1", hold: "brightness_up"),
                .combo(keys: ["cmd", "space"], result: "spotlight")
            ]
            
            for behavior in behaviors {
                let visualization = EnhancedRemapVisualization(
                    behavior: behavior,
                    title: "Test",
                    description: "Test description"
                )
                
                // The visualization should maintain the same behavior
                #expect(visualization.behavior.primaryKey == behavior.primaryKey)
            }
        }
    }
    
    @Suite("KanataRule Tests", .tags(.viewModels))
    struct KanataRuleTests {
        
        @Test("Rule creation with confidence levels", 
              arguments: [
                KanataRule.Confidence.high,
                KanataRule.Confidence.medium,
                KanataRule.Confidence.low
              ])
        func ruleCreationWithConfidence(confidence: KanataRule.Confidence) {
            let visualization = EnhancedRemapVisualization(
                behavior: .simpleRemap(from: "a", toKey: "b"),
                title: "Test",
                description: "Test rule"
            )
            
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(defalias a b)",
                confidence: confidence,
                explanation: "Maps a to b"
            )
            
            #expect(rule.confidence == confidence)
            #expect(rule.kanataRule == "(defalias a b)")
            #expect(rule.explanation == "Maps a to b")
        }
        
        @Test("Rule validation requirements")
        func ruleValidationRequirements() {
            let visualization = EnhancedRemapVisualization(
                behavior: .simpleRemap(from: "caps", toKey: "esc"),
                title: "Caps to Escape",
                description: "Maps Caps Lock to Escape"
            )
            
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(defalias caps esc)",
                confidence: .high,
                explanation: "Standard caps lock to escape mapping"
            )
            
            // Basic validation checks
            #expect(!rule.kanataRule.isEmpty)
            #expect(!rule.explanation.isEmpty)
            #expect(rule.kanataRule.contains("defalias"))
        }
    }
    
    @Suite("TapDanceAction Tests")
    struct TapDanceActionTests {
        
        @Test("Tap dance action creation")
        func tapDanceActionCreation() {
            let action = TapDanceAction(
                tapCount: 2,
                action: "esc",
                description: "Double tap for escape"
            )
            
            #expect(action.tapCount == 2)
            #expect(action.action == "esc")
            #expect(action.description == "Double tap for escape")
        }
        
        @Test("Multiple tap dance actions", 
              arguments: zip([1, 2, 3], ["a", "b", "c"]))
        func multipleTapDanceActions(tapCount: Int, action: String) {
            let tapAction = TapDanceAction(
                tapCount: tapCount,
                action: action,
                description: "Tap \(tapCount) times for \(action)"
            )
            
            #expect(tapAction.tapCount == tapCount)
            #expect(tapAction.action == action)
            #expect(tapAction.description.contains("\(tapCount)"))
            #expect(tapAction.description.contains(action))
        }
    }
}

// MARK: - Legacy XCTest Behavior Validation
@Suite("Legacy Behavior Validation")
struct LegacyBehaviorValidation {
    
    @Test("Backward compatibility with RemapVisualization")
    func backwardCompatibilityRemapVisualization() {
        let oldVisualization = RemapVisualization(from: "a", toKey: "b")
        let enhanced = oldVisualization.enhanced
        
        #expect(enhanced.title == "Simple Remap")
        #expect(enhanced.description == "Maps a to b")
        
        if case .simpleRemap(let from, let toKey) = enhanced.behavior {
            #expect(from == "a")
            #expect(toKey == "b")
        } else {
            Issue.record("Expected simpleRemap behavior")
        }
    }
}