import XCTest
@testable import KeyPath

final class CoreLogicTests: XCTestCase {
    
    // MARK: - KanataRuleParser Tests
    
    func testParseEnhancedSimpleRemap() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "simpleRemap",
                    "data": {
                        "from": "a",
                        "toKey": "b"
                    }
                },
                "title": "Simple Remap",
                "description": "Maps a to b"
            },
            "kanata_rule": "(defalias a b)",
            "confidence": "high",
            "explanation": "This remaps 'a' to 'b'"
        }
        ```
        """
        
        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)
        
        guard case .simpleRemap(let from, let toKey) = rule?.visualization.behavior else {
            XCTFail("Expected simpleRemap behavior")
            return
        }
        
        XCTAssertEqual(from, "a")
        XCTAssertEqual(toKey, "b")
        XCTAssertEqual(rule?.kanataRule, "(defalias a b)")
        XCTAssertEqual(rule?.confidence, .high)
        XCTAssertEqual(rule?.explanation, "This remaps 'a' to 'b'")
        XCTAssertEqual(rule?.visualization.title, "Simple Remap")
        XCTAssertEqual(rule?.visualization.description, "Maps a to b")
    }
    
    func testParseEnhancedTapHold() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "tapHold",
                    "data": {
                        "key": "caps",
                        "tap": "esc",
                        "hold": "ctrl"
                    }
                },
                "title": "Tap-Hold",
                "description": "Tap for Escape, hold for Control"
            },
            "kanata_rule": "(defalias caps (tap-hold 200 200 esc lctrl))",
            "confidence": "medium",
            "explanation": "Caps Lock becomes Escape on tap, Control on hold"
        }
        ```
        """
        
        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)
        
        guard case .tapHold(let key, let tap, let hold) = rule?.visualization.behavior else {
            XCTFail("Expected tapHold behavior")
            return
        }
        
        XCTAssertEqual(key, "caps")
        XCTAssertEqual(tap, "esc")
        XCTAssertEqual(hold, "ctrl")
        XCTAssertEqual(rule?.confidence, .medium)
    }
    
    func testParseOldFormat() {
        let json = """
        ```json
        {
            "visualization": {
                "from": "caps",
                "toKey": "esc"
            },
            "kanata_rule": "(defalias caps esc)",
            "confidence": "high",
            "explanation": "Simple caps to escape mapping"
        }
        ```
        """
        
        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)
        
        guard case .simpleRemap(let from, let toKey) = rule?.visualization.behavior else {
            XCTFail("Expected simpleRemap behavior from old format")
            return
        }
        
        XCTAssertEqual(from, "caps")
        XCTAssertEqual(toKey, "esc")
        XCTAssertEqual(rule?.kanataRule, "(defalias caps esc)")
        XCTAssertEqual(rule?.confidence, .high)
        XCTAssertEqual(rule?.visualization.title, "Simple Remap")
        XCTAssertEqual(rule?.visualization.description, "Maps caps to esc")
    }
    
    func testParseInvalidJSON() {
        let invalidJson = """
        ```json
        {
            "invalid": "json",
            missing_quotes: true
        }
        ```
        """
        
        let rule = KanataRule.parseEnhanced(from: invalidJson)
        XCTAssertNil(rule)
    }
    
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
    
    // MARK: - KanataInstaller Tests
    
    func testKanataInstallerCreation() {
        let installer = KanataInstaller()
        XCTAssertNotNil(installer)
    }
    
    func testInstallErrorDescriptions() {
        let errors: [KanataInstaller.InstallError] = [
            .configDirectoryNotFound,
            .configFileNotFound,
            .kanataNotFound,
            .validationFailed("test error"),
            .writeFailed("write error"),
            .reloadFailed("reload error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        
        // Test specific error messages
        XCTAssertTrue(KanataInstaller.InstallError.configDirectoryNotFound.localizedDescription.contains("configuration directory"))
        XCTAssertTrue(KanataInstaller.InstallError.configFileNotFound.localizedDescription.contains("configuration file"))
        XCTAssertTrue(KanataInstaller.InstallError.kanataNotFound.localizedDescription.contains("executable not found"))
        XCTAssertTrue(KanataInstaller.InstallError.validationFailed("test").localizedDescription.contains("validation failed"))
        XCTAssertTrue(KanataInstaller.InstallError.writeFailed("test").localizedDescription.contains("write configuration"))
        XCTAssertTrue(KanataInstaller.InstallError.reloadFailed("test").localizedDescription.contains("reload Kanata"))
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
        
        // Verify the complete workflow
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