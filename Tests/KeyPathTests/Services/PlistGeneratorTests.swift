@testable import KeyPathAppKit
@preconcurrency import XCTest

/// Unit tests for PlistGenerator service.
///
/// Tests pure functions that generate launchd plist XML content.
/// These tests verify:
/// - Correct XML structure
/// - Required keys and values
/// - Argument building logic
/// - Service identifiers
final class PlistGeneratorTests: XCTestCase {
    // MARK: - Service Identifier Tests

    func testServiceIdentifiers() {
        XCTAssertEqual(PlistGenerator.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(PlistGenerator.vhidDaemonServiceID, "com.keypath.karabiner-vhiddaemon")
        XCTAssertEqual(PlistGenerator.vhidManagerServiceID, "com.keypath.karabiner-vhidmanager")
        XCTAssertEqual(PlistGenerator.logRotationServiceID, "com.keypath.logrotate")
    }

    func testExecutablePaths() {
        XCTAssertTrue(PlistGenerator.vhidDaemonPath.contains("Karabiner-VirtualHIDDevice-Daemon"))
        XCTAssertTrue(PlistGenerator.vhidManagerPath.contains("Karabiner-VirtualHIDDevice-Manager"))
    }

    // MARK: - Argument Building Tests

    func testBuildKanataPlistArgumentsBasic() {
        let args = PlistGenerator.buildKanataPlistArguments(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001,
            verboseLogging: false
        )

        XCTAssertEqual(args[0], "/usr/local/bin/kanata")
        XCTAssertEqual(args[1], "--cfg")
        XCTAssertEqual(args[2], "/tmp/test.kbd")
        XCTAssertEqual(args[3], "--port")
        XCTAssertEqual(args[4], "37001")
        XCTAssertEqual(args[5], "--debug")
        XCTAssertEqual(args[6], "--log-layer-changes")
    }

    func testBuildKanataPlistArgumentsVerbose() {
        let args = PlistGenerator.buildKanataPlistArguments(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 5829,
            verboseLogging: true
        )

        XCTAssertTrue(args.contains("--trace"))
        XCTAssertFalse(args.contains("--debug"))
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains("5829"))
    }

    func testBuildKanataPlistArgumentsCustomPort() {
        let args = PlistGenerator.buildKanataPlistArguments(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 12345
        )

        let portIndex = args.firstIndex(of: "--port")
        XCTAssertNotNil(portIndex)
        if let index = portIndex, index + 1 < args.count {
            XCTAssertEqual(args[index + 1], "12345")
        }
    }

    // MARK: - Kanata Plist Generation Tests

    func testGenerateKanataPlistContainsRequiredKeys() {
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001
        )

        // Check for required plist keys
        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("<key>ProgramArguments</key>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(plist.contains("<key>StandardOutPath</key>"))
        XCTAssertTrue(plist.contains("<key>StandardErrorPath</key>"))
    }

    func testGenerateKanataPlistContainsServiceID() {
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd"
        )

        XCTAssertTrue(plist.contains("com.keypath.kanata"))
    }

    func testGenerateKanataPlistContainsBinaryPath() {
        let binaryPath = "/usr/local/bin/kanata"
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: binaryPath,
            configPath: "/tmp/test.kbd"
        )

        XCTAssertTrue(plist.contains(binaryPath))
    }

    func testGenerateKanataPlistContainsConfigPath() {
        let configPath = "/tmp/test.kbd"
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: configPath
        )

        XCTAssertTrue(plist.contains(configPath))
    }

    func testGenerateKanataPlistContainsTCPPort() {
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 5829
        )

        XCTAssertTrue(plist.contains("5829"))
        XCTAssertTrue(plist.contains("--port"))
    }

    func testGenerateKanataPlistVerboseLogging() {
        let plistVerbose = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001,
            verboseLogging: true
        )

        let plistNormal = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001,
            verboseLogging: false
        )

        XCTAssertTrue(plistVerbose.contains("--trace"))
        XCTAssertTrue(plistNormal.contains("--debug"))
        XCTAssertFalse(plistVerbose.contains("--debug"))
        XCTAssertFalse(plistNormal.contains("--trace"))
    }

    func testGenerateKanataPlistValidXML() {
        let plist = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd"
        )

        // Verify it's valid XML by parsing
        guard let data = plist.data(using: .utf8),
              let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            XCTFail("Generated plist is not valid XML/plist format")
            return
        }
    }

    // MARK: - VHID Daemon Plist Tests

    func testGenerateVHIDDaemonPlistContainsRequiredKeys() {
        let plist = PlistGenerator.generateVHIDDaemonPlist()

        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("<key>ProgramArguments</key>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
    }

    func testGenerateVHIDDaemonPlistContainsServiceID() {
        let plist = PlistGenerator.generateVHIDDaemonPlist()

        XCTAssertTrue(plist.contains("com.keypath.karabiner-vhiddaemon"))
    }

    func testGenerateVHIDDaemonPlistContainsExecutablePath() {
        let plist = PlistGenerator.generateVHIDDaemonPlist()

        XCTAssertTrue(plist.contains(PlistGenerator.vhidDaemonPath))
    }

    func testGenerateVHIDDaemonPlistValidXML() {
        let plist = PlistGenerator.generateVHIDDaemonPlist()

        guard let data = plist.data(using: .utf8),
              let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            XCTFail("Generated VHID daemon plist is not valid XML/plist format")
            return
        }
    }

    // MARK: - VHID Manager Plist Tests

    func testGenerateVHIDManagerPlistContainsRequiredKeys() {
        let plist = PlistGenerator.generateVHIDManagerPlist()

        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("<key>ProgramArguments</key>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>"))
    }

    func testGenerateVHIDManagerPlistContainsServiceID() {
        let plist = PlistGenerator.generateVHIDManagerPlist()

        XCTAssertTrue(plist.contains("com.keypath.karabiner-vhidmanager"))
    }

    func testGenerateVHIDManagerPlistContainsExecutablePath() {
        let plist = PlistGenerator.generateVHIDManagerPlist()

        XCTAssertTrue(plist.contains(PlistGenerator.vhidManagerPath))
    }

    func testGenerateVHIDManagerPlistValidXML() {
        let plist = PlistGenerator.generateVHIDManagerPlist()

        guard let data = plist.data(using: .utf8),
              let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            XCTFail("Generated VHID manager plist is not valid XML/plist format")
            return
        }
    }

    // MARK: - Log Rotation Plist Tests

    func testGenerateLogRotationPlistContainsRequiredKeys() {
        let scriptPath = "/usr/local/bin/keypath-logrotate.sh"
        let plist = PlistGenerator.generateLogRotationPlist(scriptPath: scriptPath)

        XCTAssertTrue(plist.contains("<key>Label</key>"))
        XCTAssertTrue(plist.contains("<key>ProgramArguments</key>"))
        XCTAssertTrue(plist.contains("<key>StartCalendarInterval</key>"))
    }

    func testGenerateLogRotationPlistContainsServiceID() {
        let plist = PlistGenerator.generateLogRotationPlist(scriptPath: "/tmp/test.sh")

        XCTAssertTrue(plist.contains("com.keypath.logrotate"))
    }

    func testGenerateLogRotationPlistContainsScriptPath() {
        let scriptPath = "/usr/local/bin/keypath-logrotate.sh"
        let plist = PlistGenerator.generateLogRotationPlist(scriptPath: scriptPath)

        XCTAssertTrue(plist.contains(scriptPath))
    }

    func testGenerateLogRotationPlistValidXML() {
        let plist = PlistGenerator.generateLogRotationPlist(scriptPath: "/tmp/test.sh")

        guard let data = plist.data(using: .utf8),
              let _ = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            XCTFail("Generated log rotation plist is not valid XML/plist format")
            return
        }
    }

    // MARK: - Consistency Tests

    func testPlistGenerationIsDeterministic() {
        let plist1 = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001
        )

        let plist2 = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test.kbd",
            tcpPort: 37001
        )

        XCTAssertEqual(plist1, plist2, "Plist generation should be deterministic")
    }

    func testDifferentConfigsProduceDifferentPlists() {
        let plist1 = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test1.kbd",
            tcpPort: 37001
        )

        let plist2 = PlistGenerator.generateKanataPlist(
            binaryPath: "/usr/local/bin/kanata",
            configPath: "/tmp/test2.kbd",
            tcpPort: 37001
        )

        XCTAssertNotEqual(plist1, plist2, "Different config paths should produce different plists")
    }
}
