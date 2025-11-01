import XCTest
@testable import KeyPath

final class VHIDDeviceManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        // Reset test seam to avoid leaking into other tests
        VHIDDeviceManager.testPIDProvider = nil
    }

    func testDetectRunning_UnhealthyWithDuplicates() {
        // Provide two PIDs to simulate duplicate daemons
        VHIDDeviceManager.testPIDProvider = { ["123", "456"] }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.detectRunning(), "Duplicate daemons should be considered unhealthy")
    }

    func testDetectRunning_HealthySingleInstance() {
        VHIDDeviceManager.testPIDProvider = { ["123"] }
        let mgr = VHIDDeviceManager()
        XCTAssertTrue(mgr.detectRunning(), "Single daemon should be healthy")
    }

    func testDetectRunning_NotRunning() {
        VHIDDeviceManager.testPIDProvider = { [] }
        let mgr = VHIDDeviceManager()
        XCTAssertFalse(mgr.detectRunning(), "No daemon should be reported as not running")
    }
}

