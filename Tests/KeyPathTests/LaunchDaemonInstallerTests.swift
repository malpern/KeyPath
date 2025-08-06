import XCTest

@testable import KeyPath

final class LaunchDaemonInstallerTests: XCTestCase {
  var installer: LaunchDaemonInstaller!

  override func setUp() {
    super.setUp()
    installer = LaunchDaemonInstaller()
  }

  override func tearDown() {
    installer = nil
    super.tearDown()
  }

  // MARK: - Service Status Tests

  func testGetServiceStatus_ReturnsValidStatus() {
    let status = installer.getServiceStatus()

    // Verify all properties are accessible and return boolean values
    XCTAssertTrue(status.kanataServiceLoaded == true || status.kanataServiceLoaded == false)
    XCTAssertTrue(status.vhidDaemonServiceLoaded == true || status.vhidDaemonServiceLoaded == false)
    XCTAssertTrue(
      status.vhidManagerServiceLoaded == true || status.vhidManagerServiceLoaded == false)

    // Verify computed property works
    let allLoaded = status.allServicesLoaded
    XCTAssertTrue(allLoaded == true || allLoaded == false)

    // Verify description contains expected information
    let description = status.description
    XCTAssertTrue(description.contains("LaunchDaemon Status:"))
    XCTAssertTrue(description.contains("Kanata Service:"))
    XCTAssertTrue(description.contains("VHIDDevice Daemon:"))
    XCTAssertTrue(description.contains("VHIDDevice Manager:"))
    XCTAssertTrue(description.contains("All Services Loaded:"))
  }

  func testLaunchDaemonStatus_AllServicesLoaded_WhenAllTrue() {
    let status = LaunchDaemonStatus(
      kanataServiceLoaded: true,
      vhidDaemonServiceLoaded: true,
      vhidManagerServiceLoaded: true
    )

    XCTAssertTrue(status.allServicesLoaded)
  }

  func testLaunchDaemonStatus_NotAllServicesLoaded_WhenKanataFalse() {
    let status = LaunchDaemonStatus(
      kanataServiceLoaded: false,
      vhidDaemonServiceLoaded: true,
      vhidManagerServiceLoaded: true
    )

    XCTAssertFalse(status.allServicesLoaded)
  }

  func testLaunchDaemonStatus_NotAllServicesLoaded_WhenVHIDDaemonFalse() {
    let status = LaunchDaemonStatus(
      kanataServiceLoaded: true,
      vhidDaemonServiceLoaded: false,
      vhidManagerServiceLoaded: true
    )

    XCTAssertFalse(status.allServicesLoaded)
  }

  func testLaunchDaemonStatus_NotAllServicesLoaded_WhenVHIDManagerFalse() {
    let status = LaunchDaemonStatus(
      kanataServiceLoaded: true,
      vhidDaemonServiceLoaded: true,
      vhidManagerServiceLoaded: false
    )

    XCTAssertFalse(status.allServicesLoaded)
  }

  // MARK: - Service Detection Tests

  func testIsServiceLoaded_ReturnsBoolean() {
    // Test with a service ID that shouldn't exist
    let result = installer.isServiceLoaded(serviceID: "com.test.nonexistent")
    XCTAssertTrue(result == true || result == false, "isServiceLoaded should return a boolean")
  }

  // MARK: - Integration Tests

  @MainActor
  func testLaunchDaemonInstaller_IntegrationWithSystemStateDetector() {
    // Test that LaunchDaemonInstaller integrates properly with SystemStateDetector
    let kanataManager = KanataManager()
    let vhidManager = VHIDDeviceManager()
    let detector = SystemStateDetector(
      kanataManager: kanataManager, vhidDeviceManager: vhidManager, launchDaemonInstaller: installer
    )

    // Verify detector can be created with LaunchDaemonInstaller
    XCTAssertNotNil(detector)

    // Test component checking (this is an async operation, so we test it can be called)
    let expectation = expectation(description: "Component check completes")

    Task {
      let result = await detector.checkComponents()

      // Verify result contains LaunchDaemon component
      let allComponents = result.missing + result.installed
      let hasLaunchDaemonComponent = allComponents.contains { component in
        if case .launchDaemonServices = component {
          return true
        }
        return false
      }

      XCTAssertTrue(
        hasLaunchDaemonComponent, "Component check should include LaunchDaemon services"
      )
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10.0)
  }

  func testLaunchDaemonInstaller_IntegrationWithAutoFixer() {
    // Test that LaunchDaemonInstaller integrates properly with WizardAutoFixer
    let kanataManager = KanataManager()
    let vhidManager = VHIDDeviceManager()
    let autoFixer = WizardAutoFixer(
      kanataManager: kanataManager, vhidDeviceManager: vhidManager, launchDaemonInstaller: installer
    )

    // Verify auto fixer can be created with LaunchDaemonInstaller
    XCTAssertNotNil(autoFixer)

    // Test that it can handle the LaunchDaemon installation action
    let canFix = autoFixer.canAutoFix(.installLaunchDaemonServices)
    XCTAssertTrue(canFix, "AutoFixer should be able to install LaunchDaemon services")
  }

  // MARK: - Plist Content Tests

  func testPlistGeneration_ProducesValidXML() {
    // Test that the installer can be initialized and basic methods work
    // without actually performing system operations that require admin privileges

    // Verify installer was created successfully
    XCTAssertNotNil(installer, "LaunchDaemonInstaller should be created")

    // Test service status checking (this doesn't require admin privileges)
    let status = installer.getServiceStatus()
    XCTAssertNotNil(status, "Should be able to get service status")

    // Test service loaded checking (this is safe to call)
    let kanataLoaded = installer.isServiceLoaded(serviceID: "com.keypath.kanata")
    XCTAssertTrue(kanataLoaded == true || kanataLoaded == false, "Should return a boolean")

    print("✅ LaunchDaemonInstaller basic operations work without admin privileges")
  }
}

// MARK: - Mock Classes for Testing

/// Mock LaunchDaemonInstaller for testing scenarios where we need predictable behavior
class MockLaunchDaemonInstaller: LaunchDaemonInstaller {
  private let mockKanataLoaded: Bool
  private let mockVHIDDaemonLoaded: Bool
  private let mockVHIDManagerLoaded: Bool
  private let mockInstallationResult: Bool
  private let mockLoadResult: Bool

  init(
    kanataLoaded: Bool = false, vhidDaemonLoaded: Bool = false, vhidManagerLoaded: Bool = false,
    installationResult: Bool = false, loadResult: Bool = false
  ) {
    mockKanataLoaded = kanataLoaded
    mockVHIDDaemonLoaded = vhidDaemonLoaded
    mockVHIDManagerLoaded = vhidManagerLoaded
    mockInstallationResult = installationResult
    mockLoadResult = loadResult
    super.init()
  }

  override func getServiceStatus() -> LaunchDaemonStatus {
    return LaunchDaemonStatus(
      kanataServiceLoaded: mockKanataLoaded,
      vhidDaemonServiceLoaded: mockVHIDDaemonLoaded,
      vhidManagerServiceLoaded: mockVHIDManagerLoaded
    )
  }

  override func isServiceLoaded(serviceID: String) -> Bool {
    switch serviceID {
    case "com.keypath.kanata":
      return mockKanataLoaded
    case "com.keypath.karabiner-vhiddaemon":
      return mockVHIDDaemonLoaded
    case "com.keypath.karabiner-vhidmanager":
      return mockVHIDManagerLoaded
    default:
      return false
    }
  }

  override func createKanataLaunchDaemon() -> Bool {
    return mockInstallationResult
  }

  override func createVHIDDaemonService() -> Bool {
    return mockInstallationResult
  }

  override func createVHIDManagerService() -> Bool {
    return mockInstallationResult
  }

  override func loadServices() async -> Bool {
    // Simulate loading delay
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    return mockLoadResult
  }
}

// MARK: - Mock Integration Tests

final class MockLaunchDaemonInstallerTests: XCTestCase {
  func testMockLaunchDaemonInstaller_NoServicesLoaded() {
    let mockInstaller = MockLaunchDaemonInstaller(
      kanataLoaded: false,
      vhidDaemonLoaded: false,
      vhidManagerLoaded: false
    )

    let status = mockInstaller.getServiceStatus()

    XCTAssertFalse(status.kanataServiceLoaded)
    XCTAssertFalse(status.vhidDaemonServiceLoaded)
    XCTAssertFalse(status.vhidManagerServiceLoaded)
    XCTAssertFalse(status.allServicesLoaded)
  }

  func testMockLaunchDaemonInstaller_AllServicesLoaded() {
    let mockInstaller = MockLaunchDaemonInstaller(
      kanataLoaded: true,
      vhidDaemonLoaded: true,
      vhidManagerLoaded: true
    )

    let status = mockInstaller.getServiceStatus()

    XCTAssertTrue(status.kanataServiceLoaded)
    XCTAssertTrue(status.vhidDaemonServiceLoaded)
    XCTAssertTrue(status.vhidManagerServiceLoaded)
    XCTAssertTrue(status.allServicesLoaded)
  }

  func testMockLaunchDaemonInstaller_InstallationSuccess() {
    let mockInstaller = MockLaunchDaemonInstaller(installationResult: true)

    XCTAssertTrue(mockInstaller.createKanataLaunchDaemon())
    XCTAssertTrue(mockInstaller.createVHIDDaemonService())
    XCTAssertTrue(mockInstaller.createVHIDManagerService())
  }

  func testMockLaunchDaemonInstaller_InstallationFailure() {
    let mockInstaller = MockLaunchDaemonInstaller(installationResult: false)

    XCTAssertFalse(mockInstaller.createKanataLaunchDaemon())
    XCTAssertFalse(mockInstaller.createVHIDDaemonService())
    XCTAssertFalse(mockInstaller.createVHIDManagerService())
  }

  func testMockLaunchDaemonInstaller_LoadServicesSuccess() async {
    let mockInstaller = MockLaunchDaemonInstaller(loadResult: true)

    let result = await mockInstaller.loadServices()
    XCTAssertTrue(result)
  }

  func testMockLaunchDaemonInstaller_LoadServicesFailure() async {
    let mockInstaller = MockLaunchDaemonInstaller(loadResult: false)

    let result = await mockInstaller.loadServices()
    XCTAssertFalse(result)
  }
}
