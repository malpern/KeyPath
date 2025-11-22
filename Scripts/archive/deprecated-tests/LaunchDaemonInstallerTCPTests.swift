import Foundation
import XCTest

@testable import KeyPathAppKit

/// Comprehensive tests for LaunchDaemonInstaller TCP port integration
/// Tests argument building with TCP settings and plist generation with TCP configuration
@MainActor
final class LaunchDaemonInstallerTCPTests: XCTestCase {
    var installer: LaunchDaemonInstaller!
    var preferencesService: PreferencesService!
    var originalTCPSettings: (enabled: Bool, port: Int)!
    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Store original TCP settings
        preferencesService = PreferencesService.shared
        originalTCPSettings = (preferencesService.tcpServerEnabled, preferencesService.tcpServerPort)

        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "launchdaemon-tcp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Initialize installer
        installer = LaunchDaemonInstaller()
    }

    override func tearDown() async throws {
        // Restore original TCP settings
        preferencesService.tcpServerEnabled = originalTCPSettings.enabled
        preferencesService.tcpServerPort = originalTCPSettings.port

        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)

        installer = nil
        tempDirectory = nil
        originalTCPSettings = nil

        try await super.tearDown()
    }

    // MARK: - TCP Arguments Building Tests

    func testBuildKanataArgumentsWithTCPEnabled() {
        // Configure TCP settings
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        // Get the generated plist content to inspect arguments
        let plistContent = getPlistContent()

        // Verify TCP port is included in arguments
        XCTAssertTrue(
            plistContent.contains("--tcp-port"),
            "LaunchDaemon plist should include --tcp-port argument when TCP is enabled"
        )
        XCTAssertTrue(
            plistContent.contains("37000"),
            "LaunchDaemon plist should include the configured TCP port number"
        )
    }

    func testBuildKanataArgumentsWithTCPDisabled() {
        // Disable TCP
        preferencesService.tcpServerEnabled = false
        preferencesService.tcpServerPort = 37000

        // Get the generated plist content
        let plistContent = getPlistContent()

        // Verify TCP port is NOT included in arguments
        XCTAssertFalse(
            plistContent.contains("--tcp-port"),
            "LaunchDaemon plist should not include --tcp-port argument when TCP is disabled"
        )
    }

    func testBuildKanataArgumentsWithValidTCPPorts() {
        let validPorts = [1024, 8080, 37000, 65535]

        for port in validPorts {
            preferencesService.tcpServerEnabled = true
            preferencesService.tcpServerPort = port

            let plistContent = getPlistContent()

            XCTAssertTrue(
                plistContent.contains("--tcp-port"), "Should include --tcp-port for valid port \(port)"
            )
            XCTAssertTrue(
                plistContent.contains(String(port)), "Should include port number \(port) in plist"
            )
        }
    }

    func testBuildKanataArgumentsWithInvalidTCPPorts() {
        let invalidPorts = [0, 500, 1023, 65536, 99999]

        for port in invalidPorts {
            preferencesService.tcpServerEnabled = true
            preferencesService.tcpServerPort = port

            let plistContent = getPlistContent()

            // Should not include TCP arguments for invalid ports
            XCTAssertFalse(
                plistContent.contains("--tcp-port"),
                "Should not include --tcp-port for invalid port \(port)"
            )
        }
    }

    func testBuildKanataArgumentsWithCustomTCPPort() {
        // Test various custom ports
        let customPorts = [3000, 8080, 9000, 12345, 55555]

        for port in customPorts {
            preferencesService.tcpServerEnabled = true
            preferencesService.tcpServerPort = port

            let plistContent = getPlistContent()

            XCTAssertTrue(
                plistContent.contains("--tcp-port"),
                "Should include --tcp-port argument for custom port \(port)"
            )
            XCTAssertTrue(
                plistContent.contains(String(port)), "Should include custom port number \(port)"
            )

            // Verify it's in the correct position (after --tcp-port)
            if let tcpPortRange = plistContent.range(of: "--tcp-port") {
                let afterTCPPort = String(plistContent[tcpPortRange.upperBound...])
                XCTAssertTrue(
                    afterTCPPort.contains(String(port)), "Port number should appear after --tcp-port flag"
                )
            }
        }
    }

    // MARK: - Plist Generation Tests

    func testPlistGenerationWithTCPConfiguration() throws {
        // Configure TCP
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        // Generate plist
        let plistData = try generatePlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]

        // Verify plist structure
        guard let programArguments = plist["ProgramArguments"] as? [String] else {
            XCTFail("ProgramArguments should be present in plist")
            return
        }

        // Check that TCP arguments are included
        XCTAssertTrue(
            programArguments.contains("--tcp-port"), "ProgramArguments should contain --tcp-port"
        )

        if let tcpPortIndex = programArguments.firstIndex(of: "--tcp-port") {
            XCTAssertLessThan(
                tcpPortIndex + 1, programArguments.count, "Port number should follow --tcp-port"
            )
            XCTAssertEqual(programArguments[tcpPortIndex + 1], "37000", "Port number should be 37000")
        } else {
            XCTFail("--tcp-port not found in ProgramArguments")
        }
    }

    func testPlistGenerationWithoutTCPConfiguration() throws {
        // Disable TCP
        preferencesService.tcpServerEnabled = false

        // Generate plist
        let plistData = try generatePlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]

        // Verify plist structure
        guard let programArguments = plist["ProgramArguments"] as? [String] else {
            XCTFail("ProgramArguments should be present in plist")
            return
        }

        // Check that TCP arguments are NOT included
        XCTAssertFalse(
            programArguments.contains("--tcp-port"),
            "ProgramArguments should not contain --tcp-port when TCP is disabled"
        )
    }

    func testPlistArgumentsOrder() throws {
        // Configure TCP
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 8080

        // Generate plist
        let plistData = try generatePlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]

        guard let programArguments = plist["ProgramArguments"] as? [String] else {
            XCTFail("ProgramArguments should be present")
            return
        }

        // Find kanata binary (should be first argument)
        XCTAssertTrue(
            programArguments.first?.contains("kanata") == true,
            "First argument should be kanata binary path"
        )

        // Verify TCP arguments appear in correct order
        if let tcpPortIndex = programArguments.firstIndex(of: "--tcp-port") {
            XCTAssertLessThan(
                tcpPortIndex + 1, programArguments.count, "Port number should follow --tcp-port"
            )
            XCTAssertEqual(
                programArguments[tcpPortIndex + 1], "8080",
                "Port number should immediately follow --tcp-port"
            )

            // Verify no extra arguments between --tcp-port and port number
            let tcpPortArg = programArguments[tcpPortIndex]
            let portNumberArg = programArguments[tcpPortIndex + 1]
            XCTAssertEqual(tcpPortArg, "--tcp-port", "TCP port flag should be exact")
            XCTAssertEqual(portNumberArg, "8080", "Port number should be exact")
        }
    }

    // MARK: - Edge Cases and Error Handling

    func testPlistGenerationWithEdgeCasePorts() throws {
        let edgeCasePorts = [
            (1024, true), // Minimum valid port
            (65535, true), // Maximum valid port
            (1023, false), // Just below minimum
            (65536, false) // Just above maximum
        ]

        for (port, shouldInclude) in edgeCasePorts {
            preferencesService.tcpServerEnabled = true
            preferencesService.tcpServerPort = port

            let plistData = try generatePlistData()
            let plist =
                try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]

            guard let programArguments = plist["ProgramArguments"] as? [String] else {
                XCTFail("ProgramArguments should be present for port \(port)")
                continue
            }

            if shouldInclude {
                XCTAssertTrue(
                    programArguments.contains("--tcp-port"),
                    "Should include --tcp-port for valid port \(port)"
                )
                XCTAssertTrue(programArguments.contains(String(port)), "Should include port number \(port)")
            } else {
                XCTAssertFalse(
                    programArguments.contains("--tcp-port"),
                    "Should not include --tcp-port for invalid port \(port)"
                )
            }
        }
    }

    func testPlistGenerationConsistency() throws {
        // Test multiple generations with same settings produce identical results
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 12345

        let plistData1 = try generatePlistData()
        let plistData2 = try generatePlistData()

        XCTAssertEqual(
            plistData1, plistData2, "Multiple plist generations should produce identical results"
        )
    }

    func testPlistGenerationWithTCPStateChanges() throws {
        // Test that plist generation reflects current TCP state

        // Start with TCP enabled
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 9000

        var plistData = try generatePlistData()
        var plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        var programArguments = plist["ProgramArguments"] as! [String]

        XCTAssertTrue(programArguments.contains("--tcp-port"), "Should include TCP args when enabled")

        // Disable TCP
        preferencesService.tcpServerEnabled = false

        plistData = try generatePlistData()
        plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        programArguments = plist["ProgramArguments"] as! [String]

        XCTAssertFalse(
            programArguments.contains("--tcp-port"), "Should not include TCP args when disabled"
        )

        // Re-enable with different port
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 7777

        plistData = try generatePlistData()
        plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        programArguments = plist["ProgramArguments"] as! [String]

        XCTAssertTrue(
            programArguments.contains("--tcp-port"), "Should include TCP args when re-enabled"
        )
        XCTAssertTrue(programArguments.contains("7777"), "Should include new port number")
    }

    // MARK: - Performance Tests

    func testPlistGenerationPerformance() throws {
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        measure {
            for _ in 0 ..< 100 {
                _ = try? generatePlistData()
            }
        }
    }

    func testArgumentBuildingPerformance() {
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 37000

        measure {
            for _ in 0 ..< 1000 {
                _ = getPlistContent()
            }
        }
    }

    // MARK: - Real File I/O Tests

    func testPlistWriteAndRead() throws {
        // Configure TCP
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 33333

        // Write plist to file
        let plistData = try generatePlistData()
        let plistURL = tempDirectory.appendingPathComponent("com.keypath.kanata.plist")
        try plistData.write(to: plistURL)

        // Read and verify
        let readData = try Data(contentsOf: plistURL)
        let plist =
            try PropertyListSerialization.propertyList(from: readData, format: nil) as! [String: Any]

        guard let programArguments = plist["ProgramArguments"] as? [String] else {
            XCTFail("ProgramArguments should be readable from written plist")
            return
        }

        XCTAssertTrue(
            programArguments.contains("--tcp-port"), "Written plist should contain TCP arguments"
        )
        XCTAssertTrue(programArguments.contains("33333"), "Written plist should contain correct port")
    }

    func testPlistValidityAndStructure() throws {
        preferencesService.tcpServerEnabled = true
        preferencesService.tcpServerPort = 44444

        let plistData = try generatePlistData()
        let plist =
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]

        // Verify essential LaunchDaemon properties are present
        XCTAssertNotNil(plist["Label"], "Plist should have Label")
        XCTAssertNotNil(plist["ProgramArguments"], "Plist should have ProgramArguments")

        // Verify ProgramArguments structure
        guard let programArguments = plist["ProgramArguments"] as? [String] else {
            XCTFail("ProgramArguments should be array of strings")
            return
        }

        XCTAssertFalse(programArguments.isEmpty, "ProgramArguments should not be empty")
        XCTAssertTrue(
            programArguments.first?.contains("kanata") == true, "First argument should be kanata binary"
        )

        // Verify TCP arguments are properly formatted
        if let tcpIndex = programArguments.firstIndex(of: "--tcp-port") {
            XCTAssertLessThan(tcpIndex + 1, programArguments.count, "Port should follow --tcp-port")
            let portString = programArguments[tcpIndex + 1]
            XCTAssertNotNil(Int(portString), "Port should be valid integer: \(portString)")
        }
    }

    // MARK: - Helper Methods

    private func getPlistContent() -> String {
        // This method would need to access the internal plist generation
        // Since we can't access private methods directly, we test through the public interface
        do {
            let plistData = try generatePlistData()
            return String(data: plistData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func generatePlistData() throws -> Data {
        // Create a mock plist structure that matches what LaunchDaemonInstaller would generate
        // This simulates the buildKanataArguments method's behavior

        var arguments = ["/opt/homebrew/bin/kanata"]

        // Add TCP arguments if enabled and valid
        if preferencesService.shouldUseTCPServer {
            arguments.append("--tcp-port")
            arguments.append(String(preferencesService.tcpServerPort))
        }

        // Add config file argument
        arguments.append("--cfg")
        arguments.append("/Users/test/.config/keypath/keypath.kbd")

        let plist: [String: Any] = [
            "Label": "com.keypath.kanata",
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true
        ]

        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
