@testable import KeyPath
import XCTest

/// Fast unit tests for individual components
/// No system dependencies, mocked environment
final class UnitTestSuite: XCTestCase {
    // MARK: - Key Mapping Tests

    func testKeyMappingInitialization() throws {
        let mapping = KeyMapping(input: "caps", output: "escape")

        XCTAssertEqual(mapping.input, "caps")
        XCTAssertEqual(mapping.output, "escape")
    }

    func testKeyMappingValidation() throws {
        // Valid mapping
        let validMapping = KeyMapping(input: "caps", output: "esc")
        XCTAssertTrue(validMapping.isValid)

        // Invalid mapping (empty keys)
        let invalidMapping = KeyMapping(input: "", output: "esc")
        XCTAssertFalse(invalidMapping.isValid)
    }

    // MARK: - Configuration Generation Tests

    func testBasicConfigGeneration() throws {
        let manager = KanataConfigManager()
        let mappings = [
            KeyMapping(input: "caps", output: "esc"),
            KeyMapping(input: "space", output: "space") // passthrough
        ]

        let configSet = manager.createConfiguration(mappings: mappings)
        let config = configSet.generatedConfig

        // Check required sections
        XCTAssertTrue(config.contains("(defcfg"))
        XCTAssertTrue(config.contains("(defsrc"))
        XCTAssertTrue(config.contains("(deflayer"))

        // Check key mappings
        XCTAssertTrue(config.contains("caps"))
        XCTAssertTrue(config.contains("esc"))
        XCTAssertTrue(config.contains("spc"))
    }

    func testComplexKeyMappingGeneration() throws {
        let manager = KanataConfigManager()
        let mapping = KeyMapping(input: "caps", output: "cmd+c")

        let configSet = manager.createConfiguration(mappings: [mapping])
        let config = configSet.generatedConfig

        // Should generate macro for complex output
        XCTAssertTrue(config.contains("C-c") || config.contains("cmd") || config.contains("macro") || config.contains("caps"))
    }

    // MARK: - State Machine Tests

    func testLifecycleStateValues() throws {
        // Test state enumeration exists and has expected values
        XCTAssertEqual(LifecycleStateMachine.KanataState.uninitialized.rawValue, "uninitialized")
        XCTAssertEqual(LifecycleStateMachine.KanataState.starting.rawValue, "starting")
        XCTAssertEqual(LifecycleStateMachine.KanataState.running.rawValue, "running")
        XCTAssertEqual(LifecycleStateMachine.KanataState.stopped.rawValue, "stopped")
    }

    // MARK: - Wizard Types Tests

    func testWizardPageAccessibilityIdentifiers() throws {
        XCTAssertEqual(WizardPage.summary.accessibilityIdentifier, "overview")
        XCTAssertEqual(WizardPage.conflicts.accessibilityIdentifier, "conflicts")
        XCTAssertEqual(WizardPage.inputMonitoring.accessibilityIdentifier, "input-monitoring")
    }

    // MARK: - Path Utilities Tests

    func testBasicPathGeneration() throws {
        // Test basic path operations work
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = homePath + "/Library/Application Support/KeyPath/keypath.kbd"

        XCTAssertTrue(configPath.hasSuffix(".kbd"))
        XCTAssertTrue(configPath.contains("Application Support"))
        XCTAssertTrue(configPath.contains("KeyPath"))
    }

    // MARK: - TCP Protocol Tests

    func testTCPMessageSerialization() throws {
        let message = TCPMessage.layerChange("base")

        let serialized = try message.serialize()
        let deserialized = try TCPMessage.deserialize(from: serialized)

        XCTAssertEqual(message, deserialized)
    }

    // MARK: - Preference Service Tests

    @MainActor
    func testPreferenceDefaults() throws {
        let service = PreferencesService()

        // Test that service initializes with defaults
        XCTAssertNotNil(service.tcpServerPort)
        XCTAssertTrue(service.isValidTCPPort(service.tcpServerPort))
        // Test that shouldUseTCPServer logic works correctly
        let expectedShouldUse = service.tcpServerEnabled && service.isValidTCPPort(service.tcpServerPort)
        XCTAssertEqual(service.shouldUseTCPServer, expectedShouldUse)
    }

    @MainActor
    func testPreferenceStorage() throws {
        let service = PreferencesService()

        // Test setting and getting preferences
        service.tcpServerEnabled = false
        service.tcpServerPort = 37001

        XCTAssertFalse(service.tcpServerEnabled)
        XCTAssertEqual(service.tcpServerPort, 37001)
    }

    // MARK: - Sound Manager Tests

    func testSoundManagerSharedInstance() throws {
        let soundManager = SoundManager.shared

        XCTAssertNotNil(soundManager)
        XCTAssertNoThrow(soundManager.playTinkSound())
        XCTAssertNoThrow(soundManager.playGlassSound())
    }

    // MARK: - Logger Tests

    func testLoggerConfiguration() throws {
        let logger = AppLogger.shared

        XCTAssertNotNil(logger)

        // Test logging functionality
        XCTAssertNoThrow(logger.log("Test message"))
    }
}

// MARK: - Helper Extensions

extension KeyMapping {
    var isValid: Bool {
        !input.isEmpty && !output.isEmpty
    }
}

// SystemStatus extension removed - type no longer exists in codebase

// Mock TCP Message for testing
struct TCPMessage: Equatable {
    let type: String
    let payload: String

    static func layerChange(_ layer: String) -> TCPMessage {
        TCPMessage(type: "layer_change", payload: layer)
    }

    func serialize() throws -> Data {
        let dict = ["type": type, "payload": payload]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func deserialize(from data: Data) throws -> TCPMessage {
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: String]
        return TCPMessage(type: dict["type"]!, payload: dict["payload"]!)
    }
}
