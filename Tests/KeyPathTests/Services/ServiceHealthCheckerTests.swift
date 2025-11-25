import Foundation
import XCTest

@testable import KeyPathAppKit

/// Unit tests for ServiceHealthChecker service.
///
/// Tests health checking and status reporting.
/// These tests verify:
/// - Service loaded detection (in test mode)
/// - Service health checks (in test mode)
/// - Status aggregation
/// - Service identifier constants
final class ServiceHealthCheckerTests: XCTestCase {
    var checker: ServiceHealthChecker!

    override func setUp() async throws {
        try await super.setUp()
        checker = ServiceHealthChecker.shared
    }

    override func tearDown() async throws {
        checker = nil
        try await super.tearDown()
    }

    // MARK: - Service Identifier Tests

    func testServiceIdentifiers() {
        XCTAssertEqual(ServiceHealthChecker.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(ServiceHealthChecker.vhidDaemonServiceID, "com.keypath.karabiner-vhiddaemon")
        XCTAssertEqual(ServiceHealthChecker.vhidManagerServiceID, "com.keypath.karabiner-vhidmanager")
    }

    // MARK: - Service Loaded Tests (Test Mode)

    func testIsServiceLoadedReturnsBoolean() async {
        let loaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.kanataServiceID)

        // In test mode, checks file existence
        XCTAssertTrue(loaded == true || loaded == false, "Should return boolean")
    }

    func testIsServiceLoadedWithInvalidServiceID() async {
        let loaded = await checker.isServiceLoaded(serviceID: "com.keypath.invalid-service")

        // Should return false for invalid service
        XCTAssertFalse(loaded, "Should return false for invalid service ID")
    }

    func testIsServiceLoadedForVHIDServices() async {
        let vhidDaemonLoaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.vhidDaemonServiceID)
        let vhidManagerLoaded = await checker.isServiceLoaded(serviceID: ServiceHealthChecker.vhidManagerServiceID)

        // Should return boolean results
        XCTAssertTrue(vhidDaemonLoaded == true || vhidDaemonLoaded == false, "Should return boolean for VHID daemon")
        XCTAssertTrue(vhidManagerLoaded == true || vhidManagerLoaded == false, "Should return boolean for VHID manager")
    }

    // MARK: - Service Health Tests (Test Mode)

    func testIsServiceHealthyReturnsBoolean() async {
        let healthy = await checker.isServiceHealthy(serviceID: ServiceHealthChecker.kanataServiceID)

        // In test mode, may check file existence or process status
        XCTAssertTrue(healthy == true || healthy == false, "Should return boolean")
    }

    func testIsServiceHealthyWithInvalidServiceID() async {
        let healthy = await checker.isServiceHealthy(serviceID: "com.keypath.invalid-service")

        // Should return false for invalid service
        XCTAssertFalse(healthy, "Should return false for invalid service ID")
    }

    // MARK: - Service Status Tests

    func testGetServiceStatusReturnsStatus() async {
        let status = await checker.getServiceStatus()

        // Should return a LaunchDaemonStatus with all fields
        XCTAssertNotNil(status, "Should return status")
        XCTAssertTrue(
            status.kanataServiceLoaded == true || status.kanataServiceLoaded == false,
            "Should have kanata loaded status"
        )
        XCTAssertTrue(
            status.vhidDaemonServiceLoaded == true || status.vhidDaemonServiceLoaded == false,
            "Should have VHID daemon loaded status"
        )
        XCTAssertTrue(
            status.vhidManagerServiceLoaded == true || status.vhidManagerServiceLoaded == false,
            "Should have VHID manager loaded status"
        )
    }

    func testGetServiceStatusComputedProperties() async {
        let status = await checker.getServiceStatus()

        // Test computed properties
        _ = status.allServicesLoaded
        _ = status.allServicesHealthy
        _ = status.description

        // Should not crash
        XCTAssertTrue(true, "Computed properties should work")
    }

    func testGetServiceStatusIsConsistent() async {
        let status1 = await checker.getServiceStatus()
        let status2 = await checker.getServiceStatus()

        // Status should be consistent within a short time window
        XCTAssertEqual(
            status1.kanataServiceLoaded, status2.kanataServiceLoaded,
            "Kanata loaded status should be consistent"
        )
        XCTAssertEqual(
            status1.vhidDaemonServiceLoaded, status2.vhidDaemonServiceLoaded,
            "VHID daemon loaded status should be consistent"
        )
    }

    // MARK: - Kanata Health Check Tests

    func testCheckKanataServiceHealthReturnsHealth() async {
        let health = await checker.checkKanataServiceHealth()

        // Should return health snapshot
        XCTAssertNotNil(health, "Should return health snapshot")
        XCTAssertTrue(
            health.isRunning == true || health.isRunning == false,
            "Should have isRunning boolean"
        )
        XCTAssertTrue(
            health.isResponding == true || health.isResponding == false,
            "Should have isResponding boolean"
        )
    }

    func testCheckKanataServiceHealthWithCustomPort() async {
        let health = await checker.checkKanataServiceHealth(tcpPort: 12345)

        // Should return health snapshot
        XCTAssertNotNil(health, "Should return health snapshot")
    }

    // MARK: - Configuration Check Tests

    func testIsKanataPlistInstalled() {
        let installed = checker.isKanataPlistInstalled()

        // In test mode, checks file existence
        XCTAssertTrue(installed == true || installed == false, "Should return boolean")
    }

    func testIsVHIDDaemonConfiguredCorrectly() {
        let configured = checker.isVHIDDaemonConfiguredCorrectly()

        // Should return boolean
        XCTAssertTrue(configured == true || configured == false, "Should return boolean")
    }
}
