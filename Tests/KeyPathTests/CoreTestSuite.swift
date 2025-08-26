@testable import KeyPath
import XCTest

/// Core integration tests for essential system interactions
/// Tests real components with minimal mocking
final class CoreTestSuite: XCTestCase {
    // MARK: - KanataConfigManager Integration Tests

    func testConfigurationCreationAndValidation() throws {
        let manager = KanataConfigManager()
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "tab", output: "lctl"),
        ]

        let configSet = manager.createConfiguration(mappings: mappings)

        // Verify configuration structure
        XCTAssertEqual(configSet.mappings.count, 2)
        XCTAssertTrue(configSet.validationResult.isValid)
        XCTAssertFalse(configSet.validationResult.hasBlockingErrors)

        // Verify generated config contains required sections
        let config = configSet.generatedConfig
        XCTAssertTrue(config.contains("(defcfg"))
        XCTAssertTrue(config.contains("(defsrc"))
        XCTAssertTrue(config.contains("(deflayer"))
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
    }

    func testConfigurationTemplates() throws {
        let manager = KanataConfigManager()

        // Test all built-in templates
        for template in KanataConfigManager.ConfigTemplate.allCases {
            let configSet = manager.createConfigurationFromTemplate(template)

            XCTAssertTrue(configSet.validationResult.isValid,
                          "Template \(template) should generate valid config")
            XCTAssertFalse(configSet.mappings.isEmpty,
                           "Template \(template) should have mappings")
            XCTAssertTrue(configSet.generatedConfig.contains("(defcfg"),
                          "Template \(template) should generate proper Kanata config")
        }
    }

    // MARK: - LifecycleStateMachine Integration Tests

    func testLifecycleStateEnumeration() throws {
        // Test state enumeration completeness
        let allStates = LifecycleStateMachine.KanataState.allCases
        XCTAssertTrue(allStates.contains(.uninitialized))
        XCTAssertTrue(allStates.contains(.starting))
        XCTAssertTrue(allStates.contains(.running))
        XCTAssertTrue(allStates.contains(.stopped))
        XCTAssertTrue(allStates.contains(.error))

        // Test state display names
        XCTAssertFalse(LifecycleStateMachine.KanataState.starting.displayName.isEmpty)
        XCTAssertFalse(LifecycleStateMachine.KanataState.running.displayName.isEmpty)
    }

    // MARK: - PreferencesService Integration Tests

    @MainActor
    func testPreferencesServiceTCPConfiguration() throws {
        let service = PreferencesService()

        // Test that service initializes with valid defaults
        XCTAssertNotNil(service.tcpServerPort)
        XCTAssertTrue(service.isValidTCPPort(service.tcpServerPort))

        // Test TCP port validation
        XCTAssertTrue(service.isValidTCPPort(37000))
        XCTAssertTrue(service.isValidTCPPort(65535))
        XCTAssertFalse(service.isValidTCPPort(1023)) // Below valid range
        XCTAssertFalse(service.isValidTCPPort(65536)) // Above valid range

        // Test configuration changes
        service.tcpServerEnabled = false
        XCTAssertFalse(service.tcpServerEnabled)
        XCTAssertFalse(service.shouldUseTCPServer)

        service.tcpServerEnabled = true
        service.tcpServerPort = 37000
        XCTAssertTrue(service.shouldUseTCPServer)
        XCTAssertEqual(service.tcpEndpoint, "127.0.0.1:37000")
    }

    // MARK: - Sound Manager Integration Tests

    func testSoundManagerSharedInstance() throws {
        let soundManager = SoundManager.shared

        XCTAssertNotNil(soundManager)

        // Test that sound methods don't throw (even if no sound plays in test environment)
        XCTAssertNoThrow(soundManager.playTinkSound())
        XCTAssertNoThrow(soundManager.playGlassSound())
    }

    // MARK: - Key Mapping Validation Tests

    func testKeyMappingValidation() throws {
        // Test valid mappings
        let validMapping = KeyMapping(input: "caps", output: "esc")
        XCTAssertFalse(validMapping.input.isEmpty)
        XCTAssertFalse(validMapping.output.isEmpty)
        XCTAssertEqual(validMapping.input, "caps")
        XCTAssertEqual(validMapping.output, "esc")

        // Test edge cases
        let spaceMapping = KeyMapping(input: "space", output: "ctrl")
        XCTAssertEqual(spaceMapping.input, "space")
        XCTAssertEqual(spaceMapping.output, "ctrl")

        // Test complex mappings
        let complexMapping = KeyMapping(input: "semicolon", output: "colon")
        XCTAssertEqual(complexMapping.input, "semicolon")
        XCTAssertEqual(complexMapping.output, "colon")
    }
}
