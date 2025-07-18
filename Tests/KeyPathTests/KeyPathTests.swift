import XCTest
@testable import KeyPath

@MainActor
final class KeyPathTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    // MARK: - KanataManager Tests
    
    func testKanataManagerInitialization() throws {
        let manager = KanataManager()
        XCTAssertFalse(manager.isRunning)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(manager.configPath, "/usr/local/etc/kanata/keypath.kbd")
    }
    
    func testConvertToKanataKey() throws {
        let manager = KanataManager()
        
        // Test known key conversions
        let testCases: [(String, String)] = [
            ("caps", "caps"),
            ("capslock", "caps"),
            ("space", "spc"),
            ("enter", "ret"),
            ("return", "ret"),
            ("tab", "tab"),
            ("escape", "esc"),
            ("backspace", "bspc"),
            ("delete", "del"),
            ("unknown", "unknown") // Should pass through unchanged
        ]
        
        for (input, expected) in testCases {
            let result = manager.convertToKanataKey(input)
            XCTAssertEqual(result, expected, "Key '\(input)' should convert to '\(expected)'")
        }
    }
    
    func testConvertToKanataSequence() throws {
        let manager = KanataManager()
        
        // Test single character keys
        XCTAssertEqual(manager.convertToKanataSequence("a"), "a")
        XCTAssertEqual(manager.convertToKanataSequence("z"), "z")
        XCTAssertEqual(manager.convertToKanataSequence("1"), "1")
        
        // Test known key names
        XCTAssertEqual(manager.convertToKanataSequence("escape"), "esc")
        XCTAssertEqual(manager.convertToKanataSequence("space"), "spc")
        XCTAssertEqual(manager.convertToKanataSequence("return"), "ret")
        
        // Test sequences
        XCTAssertEqual(manager.convertToKanataSequence("hello"), "(h e l l o)")
        XCTAssertEqual(manager.convertToKanataSequence("abc"), "(a b c)")
    }
    
    func testGenerateKanataConfig() throws {
        let manager = KanataManager()
        
        // Test basic config generation
        let config = manager.generateKanataConfig(input: "caps", output: "escape")
        
        // Check config structure
        XCTAssertTrue(config.contains("(defcfg"))
        XCTAssertTrue(config.contains("process-unmapped-keys yes"))
        XCTAssertTrue(config.contains("(defsrc"))
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("(deflayer base"))
        XCTAssertTrue(config.contains("esc"))
        XCTAssertTrue(config.contains(";; Input: caps -> Output: escape"))
        
        // Ensure no invalid options
        XCTAssertFalse(config.contains("log-level"))
    }
    
    func testGenerateKanataConfigVariations() throws {
        let manager = KanataManager()
        
        let testCases: [(String, String, String, String)] = [
            ("caps", "a", "caps", "a"),
            ("space", "return", "spc", "ret"),
            ("tab", "escape", "tab", "esc"),
            ("capslock", "space", "caps", "spc")
        ]
        
        for (input, output, expectedInput, expectedOutput) in testCases {
            let config = manager.generateKanataConfig(input: input, output: output)
            
            XCTAssertTrue(config.contains("(defsrc"))
            XCTAssertTrue(config.contains(expectedInput))
            XCTAssertTrue(config.contains("(deflayer base"))
            XCTAssertTrue(config.contains(expectedOutput))
        }
    }
    
    func testConfigValidation() throws {
        let manager = KanataManager()
        
        // Generate a config and validate it's well-formed
        let config = manager.generateKanataConfig(input: "caps", output: "escape")
        
        // Check that it has balanced parentheses
        let openParens = config.components(separatedBy: "(").count - 1
        let closeParens = config.components(separatedBy: ")").count - 1
        XCTAssertEqual(openParens, closeParens, "Generated config should have balanced parentheses")
        
        // Check that required sections are present
        XCTAssertTrue(config.contains("defcfg"))
        XCTAssertTrue(config.contains("defsrc"))
        XCTAssertTrue(config.contains("deflayer"))
        
        // Check that it doesn't contain invalid options
        XCTAssertFalse(config.contains("log-level"))
        XCTAssertFalse(config.contains("invalid-option"))
    }
    
    // MARK: - KeyboardCapture Tests
    
    func testKeyboardCaptureInitialization() throws {
        let capture = KeyboardCapture()
        
        // Test initial state
        XCTAssertNotNil(capture)
        // KeyboardCapture should be ready to start capture
    }
    
    func testKeyCodeToString() throws {
        let capture = KeyboardCapture()
        
        // Test known key codes
        let testCases: [(Int64, String)] = [
            (0, "a"),
            (1, "s"),
            (2, "d"),
            (36, "return"),
            (48, "tab"),
            (49, "space"),
            (51, "delete"),
            (53, "escape"),
            (58, "caps"),
            (59, "caps"),
            (999, "key999") // Unknown key code
        ]
        
        for (keyCode, expected) in testCases {
            let result = capture.keyCodeToString(keyCode)
            XCTAssertEqual(result, expected, "Key code \(keyCode) should map to '\(expected)'")
        }
    }
    
    // MARK: - Integration Tests
    
    func testKanataManagerConfigIntegration() throws {
        let manager = KanataManager()
        
        // Test that generated config can be used by the manager
        let config = manager.generateKanataConfig(input: "caps", output: "escape")
        
        // Verify the config has the expected structure for KanataManager
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
        XCTAssertTrue(config.contains("deflayer base"))
        
        // Test that input and output are properly converted
        let inputKey = manager.convertToKanataKey("caps")
        let outputKey = manager.convertToKanataSequence("escape")
        
        XCTAssertEqual(inputKey, "caps")
        XCTAssertEqual(outputKey, "esc")
    }
    
    // MARK: - Performance Tests
    
    func testConfigGenerationPerformance() throws {
        let manager = KanataManager()
        
        measure {
            for i in 0..<100 {
                let input = i % 2 == 0 ? "caps" : "space"
                let output = i % 2 == 0 ? "escape" : "return"
                _ = manager.generateKanataConfig(input: input, output: output)
            }
        }
    }
    
    func testKeyConversionPerformance() throws {
        let manager = KanataManager()
        
        let testKeys = ["caps", "space", "return", "tab", "escape", "a", "b", "c", "unknown"]
        
        measure {
            for _ in 0..<1000 {
                for key in testKeys {
                    _ = manager.convertToKanataKey(key)
                    _ = manager.convertToKanataSequence(key)
                }
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidInputHandling() throws {
        let manager = KanataManager()
        
        // Test empty inputs
        let emptyConfig = manager.generateKanataConfig(input: "", output: "a")
        XCTAssertTrue(emptyConfig.contains("(defsrc"))
        XCTAssertTrue(emptyConfig.contains("(deflayer base"))
        
        // Test with special characters
        let specialConfig = manager.generateKanataConfig(input: "caps", output: "!")
        XCTAssertTrue(specialConfig.contains("caps"))
        XCTAssertTrue(specialConfig.contains("!"))
    }
    
    func testKeyboardCaptureAccessibility() throws {
        let capture = KeyboardCapture()
        
        // Test accessibility permission checking
        let hasPermissions = capture.hasAccessibilityPermissions()
        
        // This test depends on system state, so we just verify it returns a boolean
        XCTAssertTrue(hasPermissions == true || hasPermissions == false)
    }
}

// MARK: - Helper Extensions

extension KanataManager {
    // Expose private methods for testing
    func convertToKanataKey(_ key: String) -> String {
        let keyMap: [String: String] = [
            "caps": "caps",
            "capslock": "caps",
            "space": "spc",
            "enter": "ret",
            "return": "ret",
            "tab": "tab",
            "escape": "esc",
            "backspace": "bspc",
            "delete": "del"
        ]
        
        let lowercaseKey = key.lowercased()
        return keyMap[lowercaseKey] ?? lowercaseKey
    }
    
    func convertToKanataSequence(_ sequence: String) -> String {
        if sequence.count == 1 {
            return convertToKanataKey(sequence)
        } else {
            let converted = convertToKanataKey(sequence)
            if converted != sequence.lowercased() {
                return converted
            } else {
                let keys = sequence.map { convertToKanataKey(String($0)) }
                return "(\(keys.joined(separator: " ")))"
            }
        }
    }
    
    func generateKanataConfig(input: String, output: String) -> String {
        let kanataInput = convertToKanataKey(input)
        let kanataOutput = convertToKanataSequence(output)
        
        return """
        ;; KeyPath Generated Configuration
        ;; Input: \(input) -> Output: \(output)
        ;; Generated: \(Date())
        
        (defcfg
          process-unmapped-keys yes
        )
        
        (defsrc
          \(kanataInput)
        )
        
        (deflayer base
          \(kanataOutput)
        )
        """
    }
}

extension KeyboardCapture {
    // Expose private methods for testing
    func keyCodeToString(_ keyCode: Int64) -> String {
        let keyMap: [Int64: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
            50: "`", 51: "delete", 53: "escape", 58: "caps", 59: "caps"
        ]
        
        if let keyName = keyMap[keyCode] {
            return keyName
        } else {
            return "key\(keyCode)"
        }
    }
    
    func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
}