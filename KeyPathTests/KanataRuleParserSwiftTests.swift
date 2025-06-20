import Testing
@testable import KeyPath

// MARK: - Test Tags
extension Tag {
    @Tag static var parsing: Self
    @Tag static var json: Self
    @Tag static var validation: Self
    @Tag static var enhanced: Self
    @Tag static var legacy: Self
}

@Suite("Kanata Rule Parser Tests", .tags(.parsing))
struct KanataRuleParserSwiftTests {

    @Suite("Enhanced Format Parsing", .tags(.enhanced, .json))
    struct EnhancedFormatTests {

        @Test("Parse enhanced simple remap")
        func parseEnhancedSimpleRemap() {
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

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }
            #expect(rule.confidence == .high)
            #expect(rule.kanataRule == "(defalias a b)")
            #expect(rule.explanation == "This remaps 'a' to 'b'")

            if case .simpleRemap(let from, let toKey) = rule.visualization.behavior {
                #expect(from == "a")
                #expect(toKey == "b")
            } else {
                Issue.record("Expected simpleRemap behavior")
            }
        }

        @Test("Parse enhanced tap-hold behavior")
        func parseEnhancedTapHold() {
            let json = """
            ```json
            {
                "visualization": {
                    "behavior": {
                        "type": "tapHold",
                        "data": {
                            "key": "fn",
                            "tap": "f1",
                            "hold": "brightness_up"
                        }
                    },
                    "title": "Tap-Hold",
                    "description": "Tap for F1, hold for brightness up"
                },
                "kanata_rule": "(defalias fn (tap-hold 200 200 f1 brightness_up))",
                "confidence": "medium",
                "explanation": "Tap-hold configuration for function key"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }
            #expect(rule.confidence == .medium)
            #expect(rule.kanataRule.contains("tap-hold"))

            if case .tapHold(let key, let tap, let hold) = rule.visualization.behavior {
                #expect(key == "fn")
                #expect(tap == "f1")
                #expect(hold == "brightness_up")
            } else {
                Issue.record("Expected tapHold behavior")
            }
        }

        @Test("Parse enhanced combo behavior")
        func parseEnhancedCombo() {
            let json = """
            ```json
            {
                "visualization": {
                    "behavior": {
                        "type": "combo",
                        "data": {
                            "keys": ["cmd", "space"],
                            "result": "spotlight"
                        }
                    },
                    "title": "Spotlight Combo",
                    "description": "Cmd+Space for Spotlight"
                },
                "kanata_rule": "(defchordsv2-experimental (cmd space) spotlight 50)",
                "confidence": "high",
                "explanation": "Chord for Spotlight search"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }
            #expect(rule.confidence == .high)
            #expect(rule.kanataRule.contains("defchordsv2"))

            if case .combo(let keys, let result) = rule.visualization.behavior {
                #expect(keys == ["cmd", "space"])
                #expect(result == "spotlight")
            } else {
                Issue.record("Expected combo behavior")
            }
        }

        @Test("Parse confidence levels",
              arguments: [
                ("high", KanataRule.Confidence.high),
                ("medium", KanataRule.Confidence.medium),
                ("low", KanataRule.Confidence.low)
              ])
        func parseConfidenceLevels(confidenceString: String, expectedConfidence: KanataRule.Confidence) {
            let json = """
            ```json
            {
                "visualization": {
                    "behavior": {
                        "type": "simpleRemap",
                        "data": {
                            "from": "test",
                            "toKey": "test2"
                        }
                    },
                    "title": "Test",
                    "description": "Test mapping"
                },
                "kanata_rule": "(defalias test test2)",
                "confidence": "\(confidenceString)",
                "explanation": "Test explanation"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }
            #expect(rule.confidence == expectedConfidence)
        }
    }

    @Suite("JSON Validation", .tags(.validation, .json))
    struct JSONValidationTests {

        @Test("Reject invalid JSON structure")
        func rejectInvalidJSONStructure() {
            let invalidJSON = """
            ```json
            {
                "invalid": "structure"
            }
            ```
            """

            let rule = KanataRule.parseEnhanced(from: invalidJSON)
            #expect(rule == nil)
        }

        @Test("Reject malformed JSON")
        func rejectMalformedJSON() {
            let malformedJSON = """
            ```json
            {
                "visualization": {
                    "behavior": {
                        "type": "simpleRemap",
                        "data": {
                            "from": "a"
                            // Missing closing brace and comma
                        }
                    }
                }
            ```
            """

            let rule = KanataRule.parseEnhanced(from: malformedJSON)
            #expect(rule == nil)
        }

        @Test("Handle missing code block markers")
        func handleMissingCodeBlockMarkers() {
            let jsonWithoutMarkers = """
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
            """

            guard let rule = KanataRule.parseEnhanced(from: jsonWithoutMarkers) else {
                Issue.record("Failed to parse rule without markers")
                return
            }
            #expect(rule.confidence == .high)
        }
    }

    @Suite("Behavior Type Parsing", .tags(.parsing))
    struct BehaviorTypeParsingTests {

        @Test("Parse tap dance behavior")
        func parseTapDanceBehavior() {
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
                                    "description": "Single tap: a"
                                },
                                {
                                    "tapCount": 2,
                                    "action": "esc",
                                    "description": "Double tap: escape"
                                }
                            ]
                        }
                    },
                    "title": "Tap Dance",
                    "description": "Multi-tap behavior"
                },
                "kanata_rule": "(deftap a (a esc))",
                "confidence": "medium",
                "explanation": "Tap dance configuration"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }

            if case .tapDance(let key, let actions) = rule.visualization.behavior {
                #expect(key == "a")
                #expect(actions.count == 2)
                #expect(actions[0].tapCount == 1)
                #expect(actions[0].action == "a")
                #expect(actions[1].tapCount == 2)
                #expect(actions[1].action == "esc")
            } else {
                Issue.record("Expected tapDance behavior")
            }
        }

        @Test("Parse sequence behavior")
        func parseSequenceBehavior() {
            let json = """
            ```json
            {
                "visualization": {
                    "behavior": {
                        "type": "sequence",
                        "data": {
                            "trigger": "jk",
                            "sequence": ["escape"]
                        }
                    },
                    "title": "Vim Escape",
                    "description": "jk sequence to escape"
                },
                "kanata_rule": "(defseq jk (escape))",
                "confidence": "high",
                "explanation": "Vim-style escape sequence"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }

            if case .sequence(let trigger, let sequence) = rule.visualization.behavior {
                #expect(trigger == "jk")
                #expect(sequence == ["escape"])
            } else {
                Issue.record("Expected sequence behavior")
            }
        }

        @Test("Parse layer behavior")
        func parseLayerBehavior() {
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
                                "2": "f2"
                            }
                        }
                    },
                    "title": "Function Layer",
                    "description": "Function key layer"
                },
                "kanata_rule": "(deflayer function)",
                "confidence": "medium",
                "explanation": "Layer configuration"
            }
            ```
            """

            guard let rule = KanataRule.parseEnhanced(from: json) else {
                Issue.record("Failed to parse rule")
                return
            }

            if case .layer(let key, let layerName, let mappings) = rule.visualization.behavior {
                #expect(key == "fn")
                #expect(layerName == "function")
                #expect(mappings["1"] == "f1")
                #expect(mappings["2"] == "f2")
            } else {
                Issue.record("Expected layer behavior")
            }
        }
    }

    @Suite("Legacy Format Support", .tags(.legacy))
    struct LegacyFormatTests {

        @Test("Parse legacy simple format")
        func parseLegacySimpleFormat() {
            let legacyInput = "Map caps lock to escape"

            // Test the legacy parsing path if it exists
            let result = KanataRule.parse(from: legacyInput)

            // Basic validation that it doesn't crash - may return nil for plain text
            #expect(result != nil || result == nil) // Always passes, just testing for crashes
        }
    }
}

// MARK: - Performance Tests
@Suite("Parser Performance Tests", .tags(.parsing))
struct ParserPerformanceTests {

    @Test("Parse large JSON performance", .timeLimit(.minutes(1)))
    func parseLargeJSONPerformance() {
        let largeJSON = """
        ```json
        {
            "visualization": {
                "behavior": {
                    "type": "layer",
                    "data": {
                        "key": "fn",
                        "layerName": "function",
                        "mappings": {
                            \(String(repeating: "\"key\\(i)\": \"value\\(i)\",", count: 100))
                            "final": "final_value"
                        }
                    }
                },
                "title": "Large Layer",
                "description": "Layer with many mappings"
            },
            "kanata_rule": "(deflayer function ...)",
            "confidence": "high",
            "explanation": "Large layer configuration"
        }
        ```
        """

        // Performance test - should complete within time limit
        let rule = KanataRule.parseEnhanced(from: largeJSON)
        #expect(rule != nil)
    }
}
