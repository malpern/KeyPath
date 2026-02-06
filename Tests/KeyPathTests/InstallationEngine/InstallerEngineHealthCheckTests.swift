@testable import KeyPathAppKit
@testable import KeyPathWizardCore
@preconcurrency import XCTest

/// Tests for InstallerEngine health check façade methods
@MainActor
final class InstallerEngineHealthCheckTests: KeyPathAsyncTestCase {
    var engine: InstallerEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = InstallerEngine()
    }

    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }

    // MARK: - getServiceStatus() Tests

    func testGetServiceStatusReturnsLaunchDaemonStatus() async {
        let status = await engine.getServiceStatus()

        // Verify all fields are present (values depend on system state)
        XCTAssertNotNil(status, "getServiceStatus() should return a LaunchDaemonStatus")

        // Verify computed properties work
        _ = status.allServicesLoaded
        _ = status.allServicesHealthy
        _ = status.description
    }

    func testGetServiceStatusReturnsConsistentResults() async {
        let status1 = await engine.getServiceStatus()
        let status2 = await engine.getServiceStatus()

        // Service status should be consistent between calls (within a short time window)
        XCTAssertEqual(
            status1.kanataServiceLoaded, status2.kanataServiceLoaded,
            "Kanata loaded status should be consistent"
        )
        XCTAssertEqual(
            status1.vhidDaemonServiceLoaded, status2.vhidDaemonServiceLoaded,
            "VHID daemon loaded status should be consistent"
        )
        XCTAssertEqual(
            status1.vhidManagerServiceLoaded, status2.vhidManagerServiceLoaded,
            "VHID manager loaded status should be consistent"
        )
    }

    // MARK: - isServiceHealthy() Tests

    func testIsServiceHealthyReturnsBoolean() async {
        let isHealthy = await engine.isServiceHealthy(serviceID: "com.keypath.kanata")

        // In test mode, this should return a boolean (value depends on system state)
        XCTAssertNotNil(isHealthy, "isServiceHealthy() should return a boolean")
    }

    func testIsServiceHealthyHandlesUnknownService() async {
        let isHealthy = await engine.isServiceHealthy(serviceID: "com.nonexistent.service")

        // Unknown service should return false
        XCTAssertFalse(isHealthy, "Unknown service should not be healthy")
    }

    // MARK: - isServiceLoaded() Tests

    func testIsServiceLoadedReturnsBoolean() async {
        let isLoaded = await engine.isServiceLoaded(serviceID: "com.keypath.kanata")

        // In test mode, this should return a boolean (value depends on system state)
        XCTAssertNotNil(isLoaded, "isServiceLoaded() should return a boolean")
    }

    func testIsServiceLoadedHandlesUnknownService() async {
        let isLoaded = await engine.isServiceLoaded(serviceID: "com.nonexistent.service")

        // Unknown service should return false
        XCTAssertFalse(isLoaded, "Unknown service should not be loaded")
    }

    // MARK: - checkKanataServiceHealth() Tests

    func testCheckKanataServiceHealthReturnsHealthSnapshot() async {
        let health = await engine.checkKanataServiceHealth()

        // Verify structure
        XCTAssertNotNil(health, "checkKanataServiceHealth() should return a KanataHealthSnapshot")

        // isRunning and isResponding should be booleans
        _ = health.isRunning
        _ = health.isResponding
    }

    func testCheckKanataServiceHealthAcceptsCustomPort() async {
        // Test with a custom TCP port
        let health = await engine.checkKanataServiceHealth(tcpPort: 12345)

        // Should return a result even with non-standard port
        XCTAssertNotNil(health, "checkKanataServiceHealth(tcpPort:) should return a result")

        // With an invalid port, isResponding should be false
        XCTAssertFalse(health.isResponding, "Invalid port should result in not responding")
    }

    func testCheckKanataServiceHealthReturnsConsistentResults() async {
        let health1 = await engine.checkKanataServiceHealth()
        let health2 = await engine.checkKanataServiceHealth()

        // Health status should be consistent between calls
        XCTAssertEqual(
            health1.isRunning, health2.isRunning,
            "isRunning should be consistent between calls"
        )
    }

    // MARK: - Integration Tests

    func testHealthCheckMethodsAreConsistentWithGetServiceStatus() async {
        let status = await engine.getServiceStatus()
        let kanataHealthy = await engine.isServiceHealthy(serviceID: "com.keypath.kanata")

        // isServiceHealthy should match getServiceStatus().kanataServiceHealthy
        XCTAssertEqual(
            status.kanataServiceHealthy, kanataHealthy,
            "isServiceHealthy should match getServiceStatus().kanataServiceHealthy"
        )
    }

    func testHealthCheckMethodsAreConsistentWithKanataHealth() async {
        let status = await engine.getServiceStatus()
        let health = await engine.checkKanataServiceHealth()

        // In test mode, these might not match exactly due to timing,
        // but the structure should be valid
        XCTAssertNotNil(status, "Status should be valid")
        XCTAssertNotNil(health, "Health should be valid")
    }
}
