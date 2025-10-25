import XCTest
@testable import KeyPath

final class PreferencesServiceTCPTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kp-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        setenv("HOME", tempHome.path, 1)
        // Reset defaults touched by PreferencesService
        let keys = [
            "KeyPath.Communication.Protocol",
            "KeyPath.TCP.ServerEnabled",
            "KeyPath.TCP.ServerPort",
            "KeyPath.TCP.SessionTimeout",
            "KeyPath.Recording.ApplyMappingsDuringRecording",
        ]
        for k in keys { UserDefaults.standard.removeObject(forKey: k) }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testPortValidation() {
        let prefs = PreferencesService()
        let original = prefs.tcpServerPort
        prefs.tcpServerPort = 123 // invalid (<1024)
        XCTAssertEqual(prefs.tcpServerPort, original)
        prefs.tcpServerPort = 65536 // invalid (>65535)
        XCTAssertEqual(prefs.tcpServerPort, original)
        prefs.tcpServerPort = 45000 // valid
        XCTAssertEqual(prefs.tcpServerPort, 45000)
    }

    func testBuildTCPArgumentsIncludesPortAndOptionalTimeout() {
        // Ensure token exists to avoid log noise
        _ = CommunicationSnapshot.ensureSharedTCPToken()
        let argsDefaultTimeout = PreferencesService.buildTCPArguments(port: 37001, sessionTimeout: 1800, defaultTimeout: 1800)
        XCTAssertEqual(argsDefaultTimeout.prefix(2), ["--tcp-port", "37001"])
        XCTAssertFalse(argsDefaultTimeout.contains("--tcp-session-timeout"))

        let argsCustomTimeout = PreferencesService.buildTCPArguments(port: 37002, sessionTimeout: 60, defaultTimeout: 1800)
        XCTAssertTrue(argsCustomTimeout.contains("--tcp-session-timeout"))
    }

    func testCommunicationEnvProvidesTokenWhenAvailable() {
        let prefs = PreferencesService()
        // Ensure TCP enabled and token exists
        prefs.tcpServerEnabled = true
        _ = CommunicationSnapshot.ensureSharedTCPToken()
        let env = prefs.communicationEnvironmentVariables
        XCTAssertNotNil(env["KANATA_TCP_TOKEN"]) 
    }
}

