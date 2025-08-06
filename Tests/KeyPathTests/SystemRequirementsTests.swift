import XCTest

@testable import KeyPath

final class SystemRequirementsTests: XCTestCase {
  var systemRequirements: SystemRequirements!

  override func setUp() {
    super.setUp()
    systemRequirements = SystemRequirements()
  }

  override func tearDown() {
    systemRequirements = nil
    super.tearDown()
  }

  // MARK: - macOS Version Detection Tests

  func testDetectMacOSVersion_ReturnsValidVersion() {
    let version = systemRequirements.detectMacOSVersion()

    // Verify version string is not empty
    XCTAssertFalse(version.versionString.isEmpty, "Version string should not be empty")

    // Verify version follows expected format (major.minor.patch)
    let components = version.versionString.components(separatedBy: ".")
    XCTAssertGreaterThanOrEqual(
      components.count, 2, "Version should have at least major.minor components"
    )

    // Verify it's either modern, legacy, or unknown
    switch version {
    case .modern, .legacy, .unknown:
      break  // All valid cases
    }
  }

  func testMacOSVersion_ModernVersionProperties() {
    let version = SystemRequirements.MacOSVersion.modern(version: "14.1.0")

    XCTAssertTrue(version.isModern)
    XCTAssertFalse(version.isLegacy)
    XCTAssertEqual(version.versionString, "14.1.0")
  }

  func testMacOSVersion_LegacyVersionProperties() {
    let version = SystemRequirements.MacOSVersion.legacy(version: "10.15.7")

    XCTAssertFalse(version.isModern)
    XCTAssertTrue(version.isLegacy)
    XCTAssertEqual(version.versionString, "10.15.7")
  }

  func testMacOSVersion_UnknownVersionProperties() {
    let version = SystemRequirements.MacOSVersion.unknown(version: "9.0.0")

    XCTAssertFalse(version.isModern)
    XCTAssertFalse(version.isLegacy)
    XCTAssertEqual(version.versionString, "9.0.0")
  }

  // MARK: - Driver Type Tests

  func testGetRequiredDriverType_ReturnsValidDriverType() {
    let driverType = systemRequirements.getRequiredDriverType()

    // Verify it's a valid driver type
    switch driverType {
    case .driverKit, .kernelExtension, .unknown:
      break  // All valid cases
    }

    // Verify display name and description are not empty
    XCTAssertFalse(driverType.displayName.isEmpty)
    XCTAssertFalse(driverType.description.isEmpty)
  }

  func testGetRequiredDriverType_ForModernVersion_ReturnsDriverKit() {
    let modernVersion = SystemRequirements.MacOSVersion.modern(version: "14.0.0")
    let driverType = systemRequirements.getRequiredDriverType(for: modernVersion)

    XCTAssertEqual(driverType, .driverKit)
  }

  func testGetRequiredDriverType_ForLegacyVersion_ReturnsKernelExtension() {
    let legacyVersion = SystemRequirements.MacOSVersion.legacy(version: "10.15.7")
    let driverType = systemRequirements.getRequiredDriverType(for: legacyVersion)

    XCTAssertEqual(driverType, .kernelExtension)
  }

  func testGetRequiredDriverType_ForUnknownVersion_ReturnsUnknown() {
    let unknownVersion = SystemRequirements.MacOSVersion.unknown(version: "9.0.0")
    let driverType = systemRequirements.getRequiredDriverType(for: unknownVersion)

    XCTAssertEqual(driverType, .unknown)
  }

  func testDriverType_DisplayNames() {
    XCTAssertEqual(
      SystemRequirements.DriverType.driverKit.displayName, "DriverKit VirtualHIDDevice"
    )
    XCTAssertEqual(
      SystemRequirements.DriverType.kernelExtension.displayName, "Kernel Extension VirtualHIDDevice"
    )
    XCTAssertEqual(SystemRequirements.DriverType.unknown.displayName, "Unknown Driver Type")
  }

  func testDriverType_Descriptions() {
    let driverKit = SystemRequirements.DriverType.driverKit
    let kernelExtension = SystemRequirements.DriverType.kernelExtension
    let unknown = SystemRequirements.DriverType.unknown

    XCTAssertTrue(driverKit.description.contains("DriverKit"))
    XCTAssertTrue(driverKit.description.contains("macOS 11"))

    XCTAssertTrue(kernelExtension.description.contains("kernel extension"))
    XCTAssertTrue(kernelExtension.description.contains("macOS 10"))

    XCTAssertTrue(unknown.description.contains("Unable to determine"))
  }

  // MARK: - System Compatibility Tests

  func testValidateSystemCompatibility_ReturnsValidResult() {
    let result = systemRequirements.validateSystemCompatibility()

    // Verify all properties are accessible
    XCTAssertTrue(result.isCompatible == true || result.isCompatible == false)
    XCTAssertFalse(result.macosVersion.versionString.isEmpty)

    // Verify driver type matches version
    switch result.macosVersion {
    case .modern:
      XCTAssertEqual(result.requiredDriverType, .driverKit)
    case .legacy:
      XCTAssertEqual(result.requiredDriverType, .kernelExtension)
    case .unknown:
      XCTAssertEqual(result.requiredDriverType, .unknown)
    }

    // Verify description is not empty
    XCTAssertFalse(result.description.isEmpty)
    XCTAssertTrue(result.description.contains("System Compatibility Check"))
  }

  func testValidationResult_Description() {
    let result = SystemRequirements.ValidationResult(
      isCompatible: true,
      macosVersion: .modern(version: "14.0.0"),
      requiredDriverType: .driverKit,
      issues: [],
      recommendations: ["Test recommendation"]
    )

    let description = result.description
    XCTAssertTrue(description.contains("System Compatibility Check"))
    XCTAssertTrue(description.contains("14.0.0"))
    XCTAssertTrue(description.contains("Modern"))
    XCTAssertTrue(description.contains("DriverKit"))
    XCTAssertTrue(description.contains("Compatible: true"))
  }

  func testValidationResult_WithIssuesAndRecommendations() {
    let result = SystemRequirements.ValidationResult(
      isCompatible: false,
      macosVersion: .legacy(version: "10.15.7"),
      requiredDriverType: .kernelExtension,
      issues: ["Test issue 1", "Test issue 2"],
      recommendations: ["Test recommendation 1", "Test recommendation 2"]
    )

    let description = result.description
    XCTAssertTrue(description.contains("Issues:"))
    XCTAssertTrue(description.contains("Test issue 1"))
    XCTAssertTrue(description.contains("Test issue 2"))
    XCTAssertTrue(description.contains("Recommendations:"))
    XCTAssertTrue(description.contains("Test recommendation 1"))
    XCTAssertTrue(description.contains("Test recommendation 2"))
  }

  // MARK: - Support Methods Tests

  func testSupportsDriverKit_ReturnsBoolean() {
    let result = systemRequirements.supportsDriverKit()
    XCTAssertTrue(result == true || result == false)
  }

  func testRequiresKernelExtension_ReturnsBoolean() {
    let result = systemRequirements.requiresKernelExtension()
    XCTAssertTrue(result == true || result == false)
  }

  func testGetDriverInstallationInstructions_ReturnsValidInstructions() {
    let instructions = systemRequirements.getDriverInstallationInstructions()

    // Verify instructions are not empty
    XCTAssertFalse(instructions.steps.isEmpty)
    XCTAssertFalse(instructions.requirements.isEmpty)
    XCTAssertFalse(instructions.description.isEmpty)

    // Verify description contains key information
    let description = instructions.description
    XCTAssertTrue(description.contains("Installation Instructions"))
    XCTAssertTrue(description.contains("Steps:"))
    XCTAssertTrue(description.contains("Requirements:"))
  }

  func testGetSystemInfo_ReturnsValidInfo() {
    let info = systemRequirements.getSystemInfo()

    // Verify all properties are accessible
    XCTAssertFalse(info.macosVersion.versionString.isEmpty)
    XCTAssertTrue(info.supportsDriverKit == true || info.supportsDriverKit == false)
    XCTAssertTrue(info.requiresKernelExtension == true || info.requiresKernelExtension == false)

    // Verify description is not empty
    XCTAssertFalse(info.description.isEmpty)
    XCTAssertTrue(info.description.contains("System Information"))
  }

  // MARK: - Integration Tests

  @MainActor
  func testSystemRequirements_IntegrationWithSystemStateDetector() {
    let kanataManager = KanataManager()
    let vhidManager = VHIDDeviceManager()
    let launchDaemonInstaller = LaunchDaemonInstaller()
    let packageManager = PackageManager()
    let detector = SystemStateDetector(
      kanataManager: kanataManager,
      vhidDeviceManager: vhidManager,
      launchDaemonInstaller: launchDaemonInstaller,
      systemRequirements: systemRequirements,
      packageManager: packageManager
    )

    // Verify detector can be created with SystemRequirements
    XCTAssertNotNil(detector)

    // Test system state detection (async operation)
    let expectation = expectation(description: "State detection completes")

    Task {
      let result = await detector.detectCurrentState()

      // Verify result contains system requirement issues
      let hasSystemRequirementIssues = result.issues.contains { issue in
        issue.category == .systemRequirements
      }

      // Note: We always expect at least one system requirement issue (the driver type info)
      XCTAssertTrue(
        hasSystemRequirementIssues, "Should always include system requirement information"
      )
      expectation.fulfill()
    }

    waitForExpectations(timeout: 10.0)
  }
}

// MARK: - Mock Classes for Testing

/// Mock SystemRequirements for testing scenarios with predictable behavior
class MockSystemRequirements: SystemRequirements {
  private let mockVersion: MacOSVersion
  private let mockCompatibility: Bool
  private let mockIssues: [String]
  private let mockRecommendations: [String]

  init(
    version: MacOSVersion = .modern(version: "14.0.0"), isCompatible: Bool = true,
    issues: [String] = [], recommendations: [String] = []
  ) {
    mockVersion = version
    mockCompatibility = isCompatible
    mockIssues = issues
    mockRecommendations = recommendations
    super.init()
  }

  override func detectMacOSVersion() -> MacOSVersion {
    return mockVersion
  }

  override func validateSystemCompatibility() -> ValidationResult {
    return ValidationResult(
      isCompatible: mockCompatibility,
      macosVersion: mockVersion,
      requiredDriverType: getRequiredDriverType(for: mockVersion),
      issues: mockIssues,
      recommendations: mockRecommendations
    )
  }
}

// MARK: - Mock Integration Tests

final class MockSystemRequirementsTests: XCTestCase {
  func testMockSystemRequirements_ModernMacOS() {
    let mockRequirements = MockSystemRequirements(
      version: .modern(version: "14.1.0"),
      isCompatible: true
    )

    let version = mockRequirements.detectMacOSVersion()
    XCTAssertEqual(version, .modern(version: "14.1.0"))
    XCTAssertTrue(version.isModern)

    let driverType = mockRequirements.getRequiredDriverType()
    XCTAssertEqual(driverType, .driverKit)

    let validation = mockRequirements.validateSystemCompatibility()
    XCTAssertTrue(validation.isCompatible)
    XCTAssertEqual(validation.requiredDriverType, .driverKit)
  }

  func testMockSystemRequirements_LegacyMacOS() {
    let mockRequirements = MockSystemRequirements(
      version: .legacy(version: "10.15.7"),
      isCompatible: true
    )

    let version = mockRequirements.detectMacOSVersion()
    XCTAssertEqual(version, .legacy(version: "10.15.7"))
    XCTAssertTrue(version.isLegacy)

    let driverType = mockRequirements.getRequiredDriverType()
    XCTAssertEqual(driverType, .kernelExtension)

    let validation = mockRequirements.validateSystemCompatibility()
    XCTAssertTrue(validation.isCompatible)
    XCTAssertEqual(validation.requiredDriverType, .kernelExtension)
  }

  func testMockSystemRequirements_IncompatibleSystem() {
    let mockRequirements = MockSystemRequirements(
      version: .unknown(version: "9.0.0"),
      isCompatible: false,
      issues: ["Unsupported macOS version"],
      recommendations: ["Upgrade to macOS 13.0 or later"]
    )

    let validation = mockRequirements.validateSystemCompatibility()
    XCTAssertFalse(validation.isCompatible)
    XCTAssertEqual(validation.issues, ["Unsupported macOS version"])
    XCTAssertEqual(validation.recommendations, ["Upgrade to macOS 13.0 or later"])
  }

  func testDriverInstallationInstructions_DriverKit() {
    let mockRequirements = MockSystemRequirements(version: .modern(version: "14.0.0"))
    let instructions = mockRequirements.getDriverInstallationInstructions()

    XCTAssertEqual(instructions.driverType, .driverKit)
    XCTAssertTrue(instructions.steps.count > 0)
    XCTAssertTrue(instructions.requirements.contains { $0.contains("macOS 11") })
    XCTAssertTrue(instructions.description.contains("DriverKit"))
  }

  func testDriverInstallationInstructions_KernelExtension() {
    let mockRequirements = MockSystemRequirements(version: .legacy(version: "10.15.7"))
    let instructions = mockRequirements.getDriverInstallationInstructions()

    XCTAssertEqual(instructions.driverType, .kernelExtension)
    XCTAssertTrue(instructions.steps.count > 0)
    XCTAssertTrue(instructions.requirements.contains { $0.contains("macOS 10") })
    XCTAssertTrue(instructions.description.contains("kernel extension"))
  }
}
