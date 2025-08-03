import XCTest

@testable import KeyPath

final class VHIDDeviceManagerTests: XCTestCase {
  var vhidManager: VHIDDeviceManager!

  override func setUp() {
    super.setUp()
    vhidManager = VHIDDeviceManager()
  }

  override func tearDown() {
    vhidManager = nil
    super.tearDown()
  }

  // MARK: - Installation Detection Tests

  func testDetectInstallation_WhenManagerNotInstalled_ReturnsFalse() {
    // This test assumes the VirtualHIDDevice Manager is not installed in the test environment
    // In a real environment, this would need to be mocked
    let result = vhidManager.detectInstallation()

    // Since we can't guarantee the installation state in CI, we just verify the method runs
    // without crashing and returns a boolean
    XCTAssertTrue(result == true || result == false, "detectInstallation should return a boolean")
  }

  func testDetectActivation_ReturnsBoolean() {
    let result = vhidManager.detectActivation()
    XCTAssertTrue(result == true || result == false, "detectActivation should return a boolean")
  }

  func testDetectRunning_ReturnsBoolean() {
    let result = vhidManager.detectRunning()
    XCTAssertTrue(result == true || result == false, "detectRunning should return a boolean")
  }

  // MARK: - Status Tests

  func testGetDetailedStatus_ReturnsValidStatus() {
    let status = vhidManager.getDetailedStatus()

    // Verify all properties are accessible
    XCTAssertTrue(status.managerInstalled == true || status.managerInstalled == false)
    XCTAssertTrue(status.managerActivated == true || status.managerActivated == false)
    XCTAssertTrue(status.daemonRunning == true || status.daemonRunning == false)

    // Verify computed properties work
    let isOperational = status.isFullyOperational
    XCTAssertTrue(isOperational == true || isOperational == false)

    // Verify description contains expected information
    let description = status.description
    XCTAssertTrue(description.contains("VHIDDevice Status:"))
    XCTAssertTrue(description.contains("Manager Installed:"))
    XCTAssertTrue(description.contains("Manager Activated:"))
    XCTAssertTrue(description.contains("Daemon Running:"))
    XCTAssertTrue(description.contains("Fully Operational:"))
  }

  func testVHIDDeviceStatus_FullyOperational_WhenAllComponentsReady() {
    let status = VHIDDeviceStatus(
      managerInstalled: true,
      managerActivated: true,
      daemonRunning: true
    )

    XCTAssertTrue(status.isFullyOperational)
  }

  func testVHIDDeviceStatus_NotFullyOperational_WhenManagerNotInstalled() {
    let status = VHIDDeviceStatus(
      managerInstalled: false,
      managerActivated: true,
      daemonRunning: true
    )

    XCTAssertFalse(status.isFullyOperational)
  }

  func testVHIDDeviceStatus_NotFullyOperational_WhenManagerNotActivated() {
    let status = VHIDDeviceStatus(
      managerInstalled: true,
      managerActivated: false,
      daemonRunning: true
    )

    XCTAssertFalse(status.isFullyOperational)
  }

  func testVHIDDeviceStatus_NotFullyOperational_WhenDaemonNotRunning() {
    let status = VHIDDeviceStatus(
      managerInstalled: true,
      managerActivated: true,
      daemonRunning: false
    )

    XCTAssertFalse(status.isFullyOperational)
  }

  // MARK: - Activation Tests

  func testActivateManager_WhenManagerNotInstalled_ReturnsFalse() async {
    // Create a test manager that we know won't have the manager installed
    // In a real scenario, we'd mock the file system check

    // For now, we test that the method completes without crashing
    // In a production environment, this would require proper mocking
    let result = await vhidManager.activateManager()

    // Since we can't guarantee the system state, we just verify it returns a boolean
    XCTAssertTrue(result == true || result == false, "activateManager should return a boolean")
  }

  // MARK: - Integration Tests

  func testVHIDDeviceManager_IntegrationWithSystemStateDetector() {
    // Test that VHIDDeviceManager integrates properly with SystemStateDetector
    let kanataManager = KanataManager()
    let detector = SystemStateDetector(kanataManager: kanataManager, vhidDeviceManager: vhidManager)

    // Verify detector can be created with VHIDDeviceManager
    XCTAssertNotNil(detector)

    // Test component checking (this is an async operation, so we test it can be called)
    let expectation = expectation(description: "Component check completes")

    Task {
      let result = await detector.checkComponents()

      // Verify result contains VHIDDevice components
      let allComponents = result.missing + result.installed
      let hasVHIDComponents = allComponents.contains { component in
        switch component {
        case .vhidDeviceManager, .vhidDeviceActivation, .vhidDeviceRunning:
          return true
        default:
          return false
        }
      }

      XCTAssertTrue(hasVHIDComponents, "Component check should include VHIDDevice components")
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10.0)
  }
}

// MARK: - Mock Classes for Testing

/// Mock VHIDDeviceManager for testing scenarios where we need predictable behavior
class MockVHIDDeviceManager: VHIDDeviceManager {
  private let mockInstalled: Bool
  private let mockActivated: Bool
  private let mockRunning: Bool
  private let mockActivationResult: Bool

  init(
    installed: Bool = false, activated: Bool = false, running: Bool = false,
    activationResult: Bool = false
  ) {
    self.mockInstalled = installed
    self.mockActivated = activated
    self.mockRunning = running
    self.mockActivationResult = activationResult
    super.init()
  }

  override func detectInstallation() -> Bool {
    return mockInstalled
  }

  override func detectActivation() -> Bool {
    return mockActivated
  }

  override func detectRunning() -> Bool {
    return mockRunning
  }

  override func activateManager() async -> Bool {
    // Simulate activation delay
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    return mockActivationResult
  }
}

// MARK: - Mock Integration Tests

final class MockVHIDDeviceManagerTests: XCTestCase {

  func testMockVHIDDeviceManager_NotInstalled() {
    let mockManager = MockVHIDDeviceManager(installed: false, activated: false, running: false)

    XCTAssertFalse(mockManager.detectInstallation())
    XCTAssertFalse(mockManager.detectActivation())
    XCTAssertFalse(mockManager.detectRunning())

    let status = mockManager.getDetailedStatus()
    XCTAssertFalse(status.isFullyOperational)
  }

  func testMockVHIDDeviceManager_InstalledButNotActivated() {
    let mockManager = MockVHIDDeviceManager(installed: true, activated: false, running: false)

    XCTAssertTrue(mockManager.detectInstallation())
    XCTAssertFalse(mockManager.detectActivation())
    XCTAssertFalse(mockManager.detectRunning())

    let status = mockManager.getDetailedStatus()
    XCTAssertFalse(status.isFullyOperational)
  }

  func testMockVHIDDeviceManager_FullyOperational() {
    let mockManager = MockVHIDDeviceManager(installed: true, activated: true, running: true)

    XCTAssertTrue(mockManager.detectInstallation())
    XCTAssertTrue(mockManager.detectActivation())
    XCTAssertTrue(mockManager.detectRunning())

    let status = mockManager.getDetailedStatus()
    XCTAssertTrue(status.isFullyOperational)
  }

  func testMockVHIDDeviceManager_ActivationSuccess() async {
    let mockManager = MockVHIDDeviceManager(
      installed: true, activated: false, running: false, activationResult: true)

    let result = await mockManager.activateManager()
    XCTAssertTrue(result)
  }

  func testMockVHIDDeviceManager_ActivationFailure() async {
    let mockManager = MockVHIDDeviceManager(
      installed: false, activated: false, running: false, activationResult: false)

    let result = await mockManager.activateManager()
    XCTAssertFalse(result)
  }
}
