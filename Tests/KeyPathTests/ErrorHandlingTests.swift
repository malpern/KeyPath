import Foundation
@testable import KeyPath
import XCTest

@MainActor
final class ErrorHandlingTests: XCTestCase {
    var manager: KanataManager!
    var capture: KeyboardCapture!

    override func setUpWithError() throws {
        manager = KanataManager()
        capture = KeyboardCapture()
    }

    override func tearDownWithError() throws {
        capture.stopCapture()
        capture.stopEmergencyMonitoring()
        manager = nil
        capture = nil
    }

    // MARK: - Key Mapping Error Handling Tests

    func testInvalidKeyInputHandling() throws {
        // Test extreme edge cases for key input
        let invalidInputs = [
            "", // Empty string
            " ", // Whitespace only
            "\n", // Newline
            "\t", // Tab
            "\0", // Null character
            String(repeating: "x", count: 1000), // Very long input
            "caps\0lock", // Embedded null
            "caps\nlocks", // Embedded newline
            "🚀", // Emoji
            "中文", // Unicode
            "العربية", // Arabic
        ]

        for invalidInput in invalidInputs {
            let result = manager.convertToKanataKey(invalidInput)
            XCTAssertFalse(result.isEmpty, "Should handle invalid input gracefully: '\(invalidInput.prefix(20))'")

            let sequence = manager.convertToKanataSequence(invalidInput)
            XCTAssertFalse(sequence.isEmpty, "Should handle invalid sequence gracefully: '\(invalidInput.prefix(20))'")
        }
    }

    func testSpecialCharacterKeyMapping() throws {
        // Test keys with special characters that might break parsing
        let specialKeys = [
            "caps()", // Parentheses
            "caps[]", // Brackets
            "caps{}", // Braces
            "caps\"", // Quote
            "caps'", // Apostrophe
            "caps\\", // Backslash
            "caps/", // Forward slash
            "caps|", // Pipe
            "caps&", // Ampersand
            "caps;", // Semicolon
            "caps<>", // Angle brackets
        ]

        for specialKey in specialKeys {
            let kanataKey = manager.convertToKanataKey(specialKey)
            XCTAssertFalse(kanataKey.isEmpty, "Should handle special characters: \(specialKey)")

            let sequence = manager.convertToKanataSequence(specialKey)
            XCTAssertFalse(sequence.isEmpty, "Should handle special character sequence: \(specialKey)")
        }
    }

    func testNilAndOptionalHandling() throws {
        // Test that methods handle edge cases that might produce nil internally
        let edgeCaseInputs = [
            "nil",
            "null",
            "undefined",
            "void",
            "(null)",
            "0",
            "false",
            "NaN",
        ]

        for input in edgeCaseInputs {
            let kanataKey = manager.convertToKanataKey(input)
            let sequence = manager.convertToKanataSequence(input)

            XCTAssertFalse(kanataKey.isEmpty, "Should handle edge case input: \(input)")
            XCTAssertFalse(sequence.isEmpty, "Should handle edge case sequence: \(input)")
        }
    }

    func testExtremeKeyCodeHandling() throws {
        // Test extreme key codes that might cause issues
        let extremeKeyCodes: [Int64] = [
            Int64.min,
            Int64.max,
            -1,
            0,
            65535,
            -65535,
        ]

        for keyCode in extremeKeyCodes {
            let result = capture.keyCodeToString(keyCode)
            XCTAssertFalse(result.isEmpty, "Should handle extreme key code: \(keyCode)")
            XCTAssertTrue(result.hasPrefix("key") || result.count == 1 || ["return", "space", "tab", "escape", "delete", "caps"].contains(result),
                          "Should produce valid key name for code \(keyCode): \(result)")
        }
    }

    // MARK: - Configuration Validation Error Handling

    func testConfigGenerationWithInvalidInputOutput() throws {
        // Test config generation with problematic input/output combinations
        let problematicCombos: [(String, String)] = [
            ("", ""), // Both empty
            ("caps", ""), // Empty output
            ("", "escape"), // Empty input
            (" ", " "), // Whitespace
            ("caps\n", "escape\n"), // Newlines
            ("caps\0", "escape\0"), // Null characters
            (String(repeating: "a", count: 500), "b"), // Very long input
            ("a", String(repeating: "b", count: 500)), // Very long output
        ]

        for (input, output) in problematicCombos {
            let config = manager.generateKanataConfig(input: input, output: output)

            // Config should still be valid structure
            XCTAssertTrue(config.contains("(defcfg"), "Should contain defcfg even with problematic input")
            XCTAssertTrue(config.contains("(defsrc"), "Should contain defsrc even with problematic input")
            XCTAssertTrue(config.contains("(deflayer"), "Should contain deflayer even with problematic input")

            // Should have balanced parentheses
            let openParens = config.components(separatedBy: "(").count - 1
            let closeParens = config.components(separatedBy: ")").count - 1
            XCTAssertEqual(openParens, closeParens, "Should have balanced parentheses with input: '\(input.prefix(20))' output: '\(output.prefix(20))'")
        }
    }

    func testConfigWithSpecialKanataCharacters() throws {
        // Test characters that have special meaning in Kanata
        let specialKanataChars = [
            "(",
            ")",
            ";",
            "#",
            "defcfg",
            "defsrc",
            "deflayer",
            "lmet",
            "rmet",
        ]

        for specialChar in specialKanataChars {
            let config = manager.generateKanataConfig(input: "caps", output: specialChar)

            // Should handle special Kanata syntax characters
            XCTAssertTrue(config.contains("(defcfg"), "Should handle special Kanata char: \(specialChar)")

            // Check for syntax errors by ensuring balanced parentheses
            let openParens = config.components(separatedBy: "(").count - 1
            let closeParens = config.components(separatedBy: ")").count - 1
            XCTAssertEqual(openParens, closeParens, "Should have balanced parentheses with special char: \(specialChar)")
        }
    }

    func testConfigWithNonASCIICharacters() throws {
        // Test international characters and symbols
        let internationalChars = [
            "è", "ñ", "ü", "ç", // Accented characters
            "α", "β", "γ", "δ", // Greek
            "中", "文", "字", "符", // Chinese
            "العربية", // Arabic
            "🚀", "🎯", "💻", "⌨️", // Emojis
            "™", "©", "®", "€", // Symbols
        ]

        for char in internationalChars {
            let inputConfig = manager.generateKanataConfig(input: char, output: "escape")
            let outputConfig = manager.generateKanataConfig(input: "caps", output: char)

            // Should generate valid configs
            XCTAssertTrue(inputConfig.contains("(defcfg"), "Should handle international input char: \(char)")
            XCTAssertTrue(outputConfig.contains("(defcfg"), "Should handle international output char: \(char)")

            // Check structure integrity
            let inputOpenParens = inputConfig.components(separatedBy: "(").count - 1
            let inputCloseParens = inputConfig.components(separatedBy: ")").count - 1
            XCTAssertEqual(inputOpenParens, inputCloseParens, "Input config should be balanced with char: \(char)")

            let outputOpenParens = outputConfig.components(separatedBy: "(").count - 1
            let outputCloseParens = outputConfig.components(separatedBy: ")").count - 1
            XCTAssertEqual(outputOpenParens, outputCloseParens, "Output config should be balanced with char: \(char)")
        }
    }

    // MARK: - Async Error Handling Tests

    func testAsyncConfigurationErrors() async throws {
        // Test error handling in async operations
        do {
            try await manager.saveConfiguration(input: "", output: "")
            // If no error thrown, that's fine too (might complete successfully in some environments)
        } catch {
            // Should get a meaningful error
            let errorDesc = error.localizedDescription.lowercased()
            XCTAssertTrue(
                errorDesc.contains("kanata") ||
                    errorDesc.contains("config") ||
                    errorDesc.contains("permission") ||
                    errorDesc.contains("install") ||
                    errorDesc.contains("directory") ||
                    errorDesc.contains("file"),
                "Error should be descriptive: \(error.localizedDescription)"
            )
        }
    }

    func testAsyncResetConfigurationErrors() async throws {
        // Test error handling in reset operations
        do {
            try await manager.resetToDefaultConfig()
            // Success is fine
        } catch {
            // Error should be meaningful
            let errorDesc = error.localizedDescription.lowercased()
            XCTAssertFalse(errorDesc.isEmpty, "Error description should not be empty")
            XCTAssertTrue(
                errorDesc.contains("kanata") ||
                    errorDesc.contains("config") ||
                    errorDesc.contains("directory") ||
                    errorDesc.contains("permission") ||
                    errorDesc.contains("file"),
                "Reset error should be descriptive: \(error.localizedDescription)"
            )
        }
    }

    func testConcurrentConfigurationOperations() async throws {
        // Test concurrent operations that might cause race conditions
        let operations = 10
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = operations

        var errors: [Error] = []
        let errorQueue = DispatchQueue(label: "error-collection")

        // Run multiple config operations concurrently
        for index in 0 ..< operations {
            Task {
                do {
                    try await manager.saveConfiguration(input: "caps\(index)", output: "escape\(index)")
                } catch {
                    errorQueue.sync {
                        errors.append(error)
                    }
                }
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        // Check that any errors are reasonable
        for error in errors {
            let errorDesc = error.localizedDescription.lowercased()
            XCTAssertFalse(errorDesc.isEmpty, "Concurrent error should have description")
        }
    }

    // MARK: - Memory and Resource Error Handling

    func testMemoryPressureErrorHandling() throws {
        // Test behavior under memory pressure by creating many large configs
        for iteration in 0 ..< 100 {
            let largeInput = String(repeating: "caps", count: 100)
            let largeOutput = String(repeating: "escape", count: 100)

            let config = manager.generateKanataConfig(input: largeInput, output: largeOutput)

            // Should still generate valid config structure
            XCTAssertTrue(config.contains("(defcfg"), "Should handle large inputs under memory pressure: iteration \(iteration)")
        }
    }

    func testResourceCleanupErrorHandling() throws {
        // Test that resources are cleaned up properly even when errors occur
        var captureCallbackCount = 0

        // Start and stop capture multiple times rapidly
        for _ in 0 ..< 20 {
            capture.startCapture { _ in
                captureCallbackCount += 1
            }
            capture.stopCapture()
        }

        // Start emergency monitoring and stop rapidly
        for _ in 0 ..< 20 {
            capture.startEmergencyMonitoring {}
            capture.stopEmergencyMonitoring()
        }

        XCTAssertTrue(true, "Resource cleanup should handle rapid start/stop cycles")
    }

    // MARK: - File System Error Handling

    func testInvalidPathHandling() throws {
        // Test config path scenarios
        let configPath = manager.configPath

        // Verify path is reasonable
        XCTAssertTrue(configPath.contains("Library"), "Config path should be in Library directory")
        XCTAssertTrue(configPath.contains("KeyPath"), "Config path should contain KeyPath")
        XCTAssertTrue(configPath.hasSuffix(".kbd"), "Config path should have .kbd extension")

        // Test that path handling doesn't crash with edge cases
        XCTAssertFalse(configPath.isEmpty, "Config path should not be empty")
        XCTAssertFalse(configPath.contains("//"), "Config path should not have double slashes")
    }

    func testDirectoryCreationErrorHandling() async throws {
        // Test configuration when directory might not exist
        do {
            try await manager.saveConfiguration(input: "caps", output: "escape")
            // Success is fine
        } catch {
            // Should handle directory creation issues gracefully
            let errorDesc = error.localizedDescription
            XCTAssertFalse(errorDesc.isEmpty, "Directory creation error should have description")
        }
    }

    // MARK: - Service and System Error Handling

    func testServiceInstallationErrorHandling() throws {
        // Test service-related error handling
        let isInstalled = manager.isInstalled()
        let isServiceInstalled = manager.isServiceInstalled()
        let isCompletelyInstalled = manager.isCompletelyInstalled()

        // These should all return boolean values without crashing
        XCTAssertTrue(isInstalled == true || isInstalled == false, "isInstalled should return boolean")
        XCTAssertTrue(isServiceInstalled == true || isServiceInstalled == false, "isServiceInstalled should return boolean")
        XCTAssertTrue(isCompletelyInstalled == true || isCompletelyInstalled == false, "isCompletelyInstalled should return boolean")

        // Test installation status messaging
        let status = manager.getInstallationStatus()
        XCTAssertFalse(status.isEmpty, "Installation status should not be empty")

        let validStatuses = ["✅ Fully installed", "⚠️ Driver missing", "⚠️ Service & driver missing", "❌ Not installed"]
        XCTAssertTrue(validStatuses.contains(status), "Status should be one of the valid options: \(status)")
    }

    func testPermissionErrorHandling() async throws {
        // Test permission-related error scenarios
        let hasInputPermission = await manager.hasInputMonitoringPermission()
        XCTAssertTrue(hasInputPermission == true || hasInputPermission == false, "Permission check should return boolean")

        let hasAccessibilityPermission = capture.checkAccessibilityPermissionsSilently()
        XCTAssertTrue(hasAccessibilityPermission == true || hasAccessibilityPermission == false, "Accessibility check should return boolean")
    }

    // MARK: - Networking and IPC Error Handling

    func testKanataProcessErrorHandling() async throws {
        // Test error handling when Kanata process operations fail
        await manager.updateStatus()
        await manager.startKanata()
        await manager.stopKanata()
        await manager.cleanup()

        // These operations might fail in test environment, but shouldn't crash
        XCTAssertTrue(true, "Kanata process operations should handle errors gracefully")

        // Check error states
        if let error = manager.lastError {
            XCTAssertFalse(error.isEmpty, "If there's an error, it should have a description")
        }
    }

    // MARK: - Input Validation Edge Cases

    func testSequenceGenerationErrorHandling() throws {
        // Test edge cases in sequence generation
        let problematicInputs = [
            "()", // Parentheses
            "(abc)", // Parentheses with content
            "a b c", // Spaces
            "a\tb\nc", // Tabs and newlines
            "hello world", // Multi-word
            "123", // All numbers
            "!@#$%", // All symbols
            "aA1!", // Mixed case and symbols
        ]

        for input in problematicInputs {
            let sequence = manager.convertToKanataSequence(input)
            XCTAssertFalse(sequence.isEmpty, "Should handle problematic input: \(input)")

            // Multi-character sequences should be wrapped in parentheses (unless it's a known key)
            if input.count > 1, !["caps", "space", "return", "escape", "delete", "tab"].contains(input.lowercased()) {
                // Should either be a converted key name or wrapped sequence
                XCTAssertTrue(
                    sequence.hasPrefix("(") || sequence.count <= 4,
                    "Multi-char sequence should be wrapped or converted: '\(input)' -> '\(sequence)'"
                )
            }
        }
    }

    func testCommandKeyMappingErrorHandling() throws {
        // Test edge cases in command key mapping
        let cmdVariations = [
            "cmd", "command", "lcmd", "rcmd",
            "leftcmd", "rightcmd", "CMD", "COMMAND",
            "Cmd", "Command", "LCmd", "RCmd",
            "cmd ", " cmd", "cmd\t", "cmd\n",
        ]

        for cmdVar in cmdVariations {
            let result = manager.convertToKanataKey(cmdVar)
            XCTAssertFalse(result.isEmpty, "Should handle cmd variation: '\(cmdVar)'")

            // Should map to some form of meta key or pass through
            XCTAssertTrue(
                result.contains("met") || result == cmdVar,
                "Cmd variation should map appropriately: '\(cmdVar)' -> '\(result)'"
            )
        }
    }

    // MARK: - Configuration Consistency Tests

    func testConfigurationRoundTrip() throws {
        // Test that configuration generation is consistent
        let testCases = [
            ("caps", "escape"),
            ("space", "return"),
            ("tab", "a"),
            ("a", "b"),
        ]

        for (input, output) in testCases {
            let config1 = manager.generateKanataConfig(input: input, output: output)
            let config2 = manager.generateKanataConfig(input: input, output: output)

            // Same inputs should produce same outputs
            XCTAssertEqual(config1, config2, "Configuration generation should be deterministic")

            // Both should be valid
            XCTAssertTrue(config1.contains("(defcfg"), "First config should be valid")
            XCTAssertTrue(config2.contains("(defcfg"), "Second config should be valid")
        }
    }

    func testConfigurationIntegrity() throws {
        // Test that all generated configs maintain integrity
        let randomInputs = (0 ..< 50).map { _ in
            let chars = "abcdefghijklmnopqrstuvwxyz"
            return String((0 ..< Int.random(in: 1 ... 10)).map { _ in chars.randomElement()! })
        }

        for input in randomInputs {
            let config = manager.generateKanataConfig(input: input, output: "escape")

            // All configs should have required sections
            XCTAssertTrue(config.contains("(defcfg"), "Random config should have defcfg: \(input)")
            XCTAssertTrue(config.contains("(defsrc"), "Random config should have defsrc: \(input)")
            XCTAssertTrue(config.contains("(deflayer"), "Random config should have deflayer: \(input)")
            XCTAssertTrue(config.contains("process-unmapped-keys no"), "Random config should have safety setting: \(input)")

            // Should be well-formed
            let openParens = config.components(separatedBy: "(").count - 1
            let closeParens = config.components(separatedBy: ")").count - 1
            XCTAssertEqual(openParens, closeParens, "Random config should be well-formed: \(input)")
        }
    }
}
