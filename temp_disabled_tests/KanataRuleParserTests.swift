import XCTest
@testable import KeyPath

final class KanataRuleParserTests: XCTestCase {

    // MARK: - Enhanced Format Tests

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

    func testParseEnhancedTapHoldWithAlternativeKeys() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "tapHold",
                    "data": {
                        "key": "caps",
                        "tapAction": "esc",
                        "holdAction": "ctrl"
                    }
                },
                "title": "Tap-Hold",
                "description": "Alternative key names"
            },
            "kanata_rule": "(defalias caps (tap-hold 200 200 esc lctrl))",
            "confidence": "high",
            "explanation": "Using alternative key names"
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
    }

    func testParseEnhancedTapDance() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "tapDance",
                    "data": {
                        "key": "a",
                        "actions": [
                            {
                                "tapCount": 1,
                                "action": "a",
                                "description": "Single tap: 'a'"
                            },
                            {
                                "tapCount": 2,
                                "action": "A",
                                "description": "Double tap: 'A'"
                            },
                            {
                                "tapCount": 3,
                                "action": "@",
                                "description": "Triple tap: '@'"
                            }
                        ]
                    }
                },
                "title": "Tap Dance",
                "description": "Different actions based on tap count"
            },
            "kanata_rule": "(defalias a (tap-dance 200 (a A @)))",
            "confidence": "high",
            "explanation": "Tap dance configuration for 'a' key"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .tapDance(let key, let actions) = rule?.visualization.behavior else {
            XCTFail("Expected tapDance behavior")
            return
        }

        XCTAssertEqual(key, "a")
        XCTAssertEqual(actions.count, 3)

        XCTAssertEqual(actions[0].tapCount, 1)
        XCTAssertEqual(actions[0].action, "a")
        XCTAssertEqual(actions[0].description, "Single tap: 'a'")

        XCTAssertEqual(actions[1].tapCount, 2)
        XCTAssertEqual(actions[1].action, "A")
        XCTAssertEqual(actions[1].description, "Double tap: 'A'")

        XCTAssertEqual(actions[2].tapCount, 3)
        XCTAssertEqual(actions[2].action, "@")
        XCTAssertEqual(actions[2].description, "Triple tap: '@'")
    }

    func testParseEnhancedSequence() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "sequence",
                    "data": {
                        "trigger": "j",
                        "sequence": ["j", "k"]
                    }
                },
                "title": "Sequence",
                "description": "Type 'jk' quickly to trigger"
            },
            "kanata_rule": "(defalias jk (seq j k))",
            "confidence": "medium",
            "explanation": "Sequence trigger for jk"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .sequence(let trigger, let sequence) = rule?.visualization.behavior else {
            XCTFail("Expected sequence behavior")
            return
        }

        XCTAssertEqual(trigger, "j")
        XCTAssertEqual(sequence, ["j", "k"])
    }

    func testParseEnhancedCombo() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "combo",
                    "data": {
                        "keys": ["a", "s"],
                        "result": "esc"
                    }
                },
                "title": "Combo",
                "description": "Press a+s together for Escape"
            },
            "kanata_rule": "(defalias as-combo (chord a s esc))",
            "confidence": "high",
            "explanation": "Combo for a+s to produce Escape"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .combo(let keys, let result) = rule?.visualization.behavior else {
            XCTFail("Expected combo behavior")
            return
        }

        XCTAssertEqual(keys, ["a", "s"])
        XCTAssertEqual(result, "esc")
    }

    func testParseEnhancedLayer() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "layer",
                    "data": {
                        "key": "fn",
                        "layerName": "function",
                        "mappings": {
                            "1": "f1",
                            "2": "f2",
                            "3": "f3"
                        }
                    }
                },
                "title": "Layer",
                "description": "Function layer activated by fn key"
            },
            "kanata_rule": "(deflayer function ...)",
            "confidence": "high",
            "explanation": "Layer configuration for function keys"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .layer(let key, let layerName, let mappings) = rule?.visualization.behavior else {
            XCTFail("Expected layer behavior")
            return
        }

        XCTAssertEqual(key, "fn")
        XCTAssertEqual(layerName, "function")
        XCTAssertEqual(mappings["1"], "f1")
        XCTAssertEqual(mappings["2"], "f2")
        XCTAssertEqual(mappings["3"], "f3")
    }

    // MARK: - Old Format Tests

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

    // MARK: - Error Cases

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

    func testParseNoCodeBlock() {
        let text = "This is just plain text without any JSON code block"

        let rule = KanataRule.parseEnhanced(from: text)
        XCTAssertNil(rule)
    }

    func testParseEmptyCodeBlock() {
        let json = """
        ```json
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNil(rule)
    }

    func testParseUnknownBehaviorType() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "unknownType",
                    "data": {
                        "key": "test"
                    }
                },
                "title": "Unknown",
                "description": "Unknown behavior type"
            },
            "kanata_rule": "(unknown rule)",
            "confidence": "low",
            "explanation": "Unknown behavior"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .simpleRemap(let from, let toKey) = rule?.visualization.behavior else {
            XCTFail("Expected fallback to simpleRemap for unknown type")
            return
        }

        XCTAssertEqual(from, "Unknown")
        XCTAssertEqual(toKey, "Unknown")
    }

    func testParseAlternativeToKeyName() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "simpleRemap",
                    "data": {
                        "from": "a",
                        "to": "b"
                    }
                },
                "title": "Simple Remap",
                "description": "Using 'to' instead of 'toKey'"
            },
            "kanata_rule": "(defalias a b)",
            "confidence": "high",
            "explanation": "Alternative key name test"
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
    }

    // MARK: - Edge Cases

    func testParseMissingRequiredFields() {
        let json = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "simpleRemap",
                    "data": {}
                },
                "title": "Empty Data",
                "description": "Missing required fields"
            },
            "kanata_rule": "(empty)",
            "confidence": "low",
            "explanation": "Test missing fields"
        }
        ```
        """

        let rule = KanataRule.parseEnhanced(from: json)
        XCTAssertNotNil(rule)

        guard case .simpleRemap(let from, let toKey) = rule?.visualization.behavior else {
            XCTFail("Expected simpleRemap behavior")
            return
        }

        XCTAssertEqual(from, "")
        XCTAssertEqual(toKey, "")
    }

    func testParseConfidenceLevels() {
        let confidenceLevels: [(String, KanataRule.Confidence)] = [
            ("high", .high),
            ("medium", .medium),
            ("low", .low)
        ]

        for (jsonConfidence, expectedConfidence) in confidenceLevels {
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
                    "title": "Test",
                    "description": "Testing confidence"
                },
                "kanata_rule": "(test)",
                "confidence": "\(jsonConfidence)",
                "explanation": "Testing confidence level"
            }
            ```
            """

            let rule = KanataRule.parseEnhanced(from: json)
            XCTAssertNotNil(rule)
            XCTAssertEqual(rule?.confidence, expectedConfidence)
        }
    }
}
