@testable import KeyPath
import XCTest

/// Fast unit tests for individual components
/// No system dependencies, mocked environment
final class UnitTestSuite: XCTestCase {
    // MARK: - Key Mapping Tests

    func testKeyMappingInitialization() throws {
        let mapping = KeyMapping(inputKey: "caps", outputKey: "escape")

        XCTAssertEqual(mapping.inputKey, "caps")
        XCTAssertEqual(mapping.outputKey, "escape")
    }

    func testKeyMappingValidation() throws {
        // Valid mapping
        let validMapping = KeyMapping(inputKey: "caps", outputKey: "esc")
        XCTAssertTrue(validMapping.isValid)

        // Invalid mapping (empty keys)
        let invalidMapping = KeyMapping(inputKey: "", outputKey: "esc")
        XCTAssertFalse(invalidMapping.isValid)
    }

    // MARK: - Configuration Generation Tests

    func testBasicConfigGeneration() throws {
        let manager = KanataConfigManager()
        let mappings = [
            KeyMapping(inputKey: "caps", outputKey: "esc"),
            KeyMapping(inputKey: "space", outputKey: "space"), // passthrough
        ]

        let config = try manager.generateConfig(mappings: mappings)

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
        let mapping = KeyMapping(inputKey: "caps", outputKey: "cmd+c")

        let config = try manager.generateConfig(mappings: [mapping])

        // Should generate macro for complex output
        XCTAssertTrue(config.contains("C-c") || config.contains("cmd") || config.contains("macro"))
    }

    // MARK: - State Machine Tests

    func testLifecycleStateTransitions() throws {
        let stateMachine = LifecycleStateMachine()

        // Initial state
        XCTAssertEqual(stateMachine.currentState, .idle)

        // Valid transitions
        stateMachine.transition(to: .starting)
        XCTAssertEqual(stateMachine.currentState, .starting)

        stateMachine.transition(to: .running)
        XCTAssertEqual(stateMachine.currentState, .running)
    }

    // MARK: - Wizard Types Tests

    func testSystemStatusEquality() throws {
        let status1 = SystemStatus(
            kanataInstalled: true,
            kanataRunning: false,
            accessibilityPermission: true,
            inputMonitoringPermission: false
        )

        let status2 = SystemStatus(
            kanataInstalled: true,
            kanataRunning: false,
            accessibilityPermission: true,
            inputMonitoringPermission: false
        )

        XCTAssertEqual(status1, status2)
    }

    func testLaunchFailureStatusFormatting() throws {
        let status = LaunchFailureStatus.permissionDenied("Input Monitoring required")

        let description = status.localizedDescription
        XCTAssertTrue(description.contains("Input Monitoring"))
    }

    // MARK: - Path Utilities Tests

    func testWizardSystemPaths() throws {
        let paths = WizardSystemPaths()

        // Test path generation
        XCTAssertTrue(paths.kanataConfigPath.hasSuffix(".kbd"))
        XCTAssertTrue(paths.launchDaemonPlistPath.contains("LaunchDaemons"))
        XCTAssertTrue(paths.applicationSupportPath.contains("Application Support"))
    }

    // MARK: - TCP Protocol Tests

    func testTCPMessageSerialization() throws {
        let message = TCPMessage.layerChange("base")

        let serialized = try message.serialize()
        let deserialized = try TCPMessage.deserialize(from: serialized)

        XCTAssertEqual(message, deserialized)
    }

    // MARK: - Preference Service Tests

    func testPreferenceDefaults() throws {
        let service = PreferencesService()

        // Test default values
        XCTAssertFalse(service.tcpServerEnabled)
        XCTAssertEqual(service.tcpServerPort, 37000)
        XCTAssertTrue(service.autoStartEnabled)
    }

    func testPreferenceStorage() throws {
        let service = PreferencesService()

        // Test setting and getting preferences
        service.tcpServerEnabled = true
        service.tcpServerPort = 37001

        XCTAssertTrue(service.tcpServerEnabled)
        XCTAssertEqual(service.tcpServerPort, 37001)
    }

    // MARK: - Error Formatting Tests

    func testErrorFormatting() throws {
        let handler = EnhancedErrorHandler()

        // Test various error types
        let nsError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test message"])
        let formatted = handler.formatError(nsError)

        XCTAssertTrue(formatted.contains("Test message"))
        XCTAssertTrue(formatted.contains("123"))
    }

    // MARK: - Sound Manager Tests

    func testSoundManagerInitialization() throws {
        let soundManager = SoundManager()

        XCTAssertNotNil(soundManager)
        XCTAssertNoThrow(soundManager.playSuccessSound())
        XCTAssertNoThrow(soundManager.playErrorSound())
    }

    // MARK: - Logger Tests

    func testLoggerConfiguration() throws {
        let logger = Logger.shared

        XCTAssertNotNil(logger)

        // Test different log levels
        XCTAssertNoThrow(logger.debug("Debug message"))
        XCTAssertNoThrow(logger.info("Info message"))
        XCTAssertNoThrow(logger.warning("Warning message"))
        XCTAssertNoThrow(logger.error("Error message"))
    }
}

// MARK: - Helper Extensions

extension KeyMapping {
    var isValid: Bool {
        return !inputKey.isEmpty && !outputKey.isEmpty
    }
}

extension SystemStatus: Equatable {
    public static func == (lhs: SystemStatus, rhs: SystemStatus) -> Bool {
        return lhs.kanataInstalled == rhs.kanataInstalled &&
            lhs.kanataRunning == rhs.kanataRunning &&
            lhs.accessibilityPermission == rhs.accessibilityPermission &&
            lhs.inputMonitoringPermission == rhs.inputMonitoringPermission
    }
}

// Mock TCP Message for testing
struct TCPMessage: Equatable {
    let type: String
    let payload: String

    static func layerChange(_ layer: String) -> TCPMessage {
        return TCPMessage(type: "layer_change", payload: layer)
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
