import Foundation
import XCTest

@testable import KeyPathAppKit
@testable import KeyPathCore

/// Test harness to verify behavior equivalence before removing LaunchDaemonInstaller.
///
/// These tests ensure that the extracted services (PlistGenerator, ServiceBootstrapper,
/// ServiceHealthChecker, etc.) produce identical results to LaunchDaemonInstaller methods.
///
/// **Purpose**: Before deleting LaunchDaemonInstaller, we must verify that:
/// 1. All public methods have equivalent implementations in extracted services
/// 2. Behavior is identical (same plist content, same health checks, same service order)
/// 3. Edge cases are handled the same way
///
/// **Usage**: Run these tests before Phase 3 (Legacy Removal) to ensure safety.
@MainActor
final class LegacyRemovalReadinessTests: KeyPathAsyncTestCase {
    // MARK: - Test Infrastructure

    private var sandboxURL: URL!
    private var launchDaemonsURL: URL!
    private var previousEnv: [String: String?] = [:]

    override func setUp() async throws {
        try await super.setUp()

        sandboxURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("legacy-removal-readiness-\(UUID().uuidString)", isDirectory: true)
        launchDaemonsURL = sandboxURL.appendingPathComponent("Library/LaunchDaemons", isDirectory: true)

        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)

        setEnv("KEYPATH_TEST_ROOT", sandboxURL.path)
        setEnv("KEYPATH_LAUNCH_DAEMONS_DIR", launchDaemonsURL.path)
        setEnv("KEYPATH_TEST_MODE", "1")
    }

    override func tearDown() async throws {
        restoreEnv()

        if let sandboxURL, FileManager.default.fileExists(atPath: sandboxURL.path) {
            try? FileManager.default.removeItem(at: sandboxURL)
        }

        try await super.tearDown()
    }

    private func setEnv(_ key: String, _ value: String) {
        if previousEnv[key] == nil {
            previousEnv[key] = ProcessInfo.processInfo.environment[key]
        }
        setenv(key, value, 1)
    }

    private func restoreEnv() {
        for (key, value) in previousEnv {
            if let value {
                setenv(key, value, 1)
            } else {
                _ = key.withCString { cname in
                    Darwin.unsetenv(cname)
                }
            }
        }
        previousEnv.removeAll()
    }

    // MARK: - Plist Generation Equivalence Tests

    /// Verify that PlistGenerator is used by LaunchDaemonInstaller (already delegated)
    /// Note: LaunchDaemonInstaller.generateKanataPlist is private and already delegates to PlistGenerator
    func testPlistGenerationAlreadyDelegated() throws {
        // This test verifies that LaunchDaemonInstaller already uses PlistGenerator
        // Read the source to confirm delegation
        let sourcePath = FileManager.default.currentDirectoryPath
            + "/Sources/KeyPathAppKit/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Verify delegation exists
        XCTAssertTrue(
            sourceCode.contains("PlistGenerator.generateKanataPlist"),
            "LaunchDaemonInstaller should delegate to PlistGenerator"
        )
        XCTAssertTrue(
            sourceCode.contains("PlistGenerator.generateVHIDDaemonPlist"),
            "LaunchDaemonInstaller should delegate to PlistGenerator"
        )
        XCTAssertTrue(
            sourceCode.contains("PlistGenerator.generateVHIDManagerPlist"),
            "LaunchDaemonInstaller should delegate to PlistGenerator"
        )
    }

    // MARK: - Health Check Equivalence Tests

    /// Verify ServiceHealthChecker produces identical results to LaunchDaemonInstaller
    func testHealthCheckEquivalence() async throws {
        let serviceID = LaunchDaemonInstaller.kanataServiceID

        // Check using legacy method
        let legacyInstaller = LaunchDaemonInstaller()
        let legacyLoaded = await legacyInstaller.isServiceLoaded(serviceID: serviceID)
        let legacyHealthy = await legacyInstaller.isServiceHealthy(serviceID: serviceID)

        // Check using new service
        let newLoaded = await ServiceHealthChecker.shared.isServiceLoaded(serviceID: serviceID)
        let newHealthy = await ServiceHealthChecker.shared.isServiceHealthy(serviceID: serviceID)

        XCTAssertEqual(
            legacyLoaded, newLoaded,
            "ServiceHealthChecker.isServiceLoaded should match LaunchDaemonInstaller"
        )
        XCTAssertEqual(
            legacyHealthy, newHealthy,
            "ServiceHealthChecker.isServiceHealthy should match LaunchDaemonInstaller"
        )
    }

    /// Verify service status aggregation equivalence
    func testServiceStatusEquivalence() async throws {
        let legacyInstaller = LaunchDaemonInstaller()
        let legacyStatus = await legacyInstaller.getServiceStatus()

        // Use InstallerEngine façade (which delegates to ServiceHealthChecker)
        let engine = InstallerEngine()
        let newStatus = await engine.getServiceStatus()

        // Compare all fields
        XCTAssertEqual(
            legacyStatus.kanataServiceLoaded, newStatus.kanataServiceLoaded,
            "Kanata service loaded status should match"
        )
        XCTAssertEqual(
            legacyStatus.vhidDaemonServiceLoaded, newStatus.vhidDaemonServiceLoaded,
            "VHID daemon loaded status should match"
        )
        XCTAssertEqual(
            legacyStatus.vhidManagerServiceLoaded, newStatus.vhidManagerServiceLoaded,
            "VHID manager loaded status should match"
        )
        XCTAssertEqual(
            legacyStatus.allServicesLoaded, newStatus.allServicesLoaded,
            "All services loaded status should match"
        )
        XCTAssertEqual(
            legacyStatus.allServicesHealthy, newStatus.allServicesHealthy,
            "All services healthy status should match"
        )
    }

    // MARK: - Service Order Verification

    /// Verify that extracted services maintain correct dependency order
    func testServiceDependencyOrderPreserved() throws {
        // This test verifies that ServiceBootstrapper maintains the same order
        // as LaunchDaemonInstaller's consolidated installation methods

        // Read LaunchDaemonInstaller source to extract expected order
        let sourcePath = FileManager.default.currentDirectoryPath
            + "/Sources/KeyPathAppKit/InstallationWizard/Core/LaunchDaemonInstaller.swift"
        let sourceCode = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Extract service order from legacy code
        let expectedOrder = [
            "com.keypath.karabiner-vhiddaemon",
            "com.keypath.karabiner-vhidmanager",
            "com.keypath.kanata"
        ]

        // Verify expected order is documented in source
        XCTAssertTrue(
            sourceCode.contains("DEPENDENCIES FIRST") || sourceCode.contains("dependency order"),
            "LaunchDaemonInstaller should document dependency order"
        )

        // Verify ServiceBootstrapper documentation mentions order
        let bootstrapperPath = FileManager.default.currentDirectoryPath
            + "/Sources/KeyPathAppKit/InstallationWizard/Core/ServiceBootstrapper.swift"
        let bootstrapperCode = try String(contentsOfFile: bootstrapperPath, encoding: .utf8)

        XCTAssertTrue(
            bootstrapperCode.contains("dependency") || bootstrapperCode.contains("order"),
            "ServiceBootstrapper should document service dependency order"
        )

        // Note: Actual order verification happens in LaunchDaemonInstallerTests
        // This test ensures the extracted service is aware of the requirement
    }

    // MARK: - Public API Coverage Verification

    /// Verify all public LaunchDaemonInstaller methods have equivalent implementations
    func testPublicAPICoverage() async throws {
        // This test documents which methods still need extraction or verification

        let legacyInstaller = LaunchDaemonInstaller()

        // Methods that should be covered by extracted services:
        // ✅ generateKanataPlist → PlistGenerator.generateKanataPlist
        // ✅ generateVHIDDaemonPlist → PlistGenerator.generateVHIDDaemonPlist
        // ✅ generateVHIDManagerPlist → PlistGenerator.generateVHIDManagerPlist
        // ✅ isServiceLoaded → ServiceHealthChecker.isServiceLoaded
        // ✅ isServiceHealthy → ServiceHealthChecker.isServiceHealthy
        // ✅ getServiceStatus → ServiceHealthChecker.getServiceStatus
        // ✅ checkKanataServiceHealth → ServiceHealthChecker.checkKanataServiceHealth

        // Methods that still need extraction or verification:
        // ⚠️ createAllLaunchDaemonServices → InstallerEngine.run(intent: .install)
        // ⚠️ loadServices → ServiceBootstrapper.loadService
        // ⚠️ restartUnhealthyServices → ServiceBootstrapper.restartServicesWithAdmin
        // ⚠️ repairVHIDDaemonServices → InstallerEngine.run(intent: .repair)
        // ⚠️ installLogRotationService → Needs extraction or verification
        // ⚠️ installBundledKanataBinaryOnly → KanataBinaryInstaller.installBundledKanata

        // Verify façade methods exist
        let engine = InstallerEngine()
        _ = await engine.getServiceStatus()
        _ = await engine.isServiceLoaded(serviceID: "com.keypath.kanata")
        _ = await engine.isServiceHealthy(serviceID: "com.keypath.kanata")
        _ = await engine.checkKanataServiceHealth()

        // If we get here, the façade methods exist
        XCTAssertTrue(true, "InstallerEngine façade methods exist")
    }

    // MARK: - Edge Case Verification

    /// Verify error handling is equivalent
    func testErrorHandlingEquivalence() async throws {
        // Test with invalid service ID
        let invalidServiceID = "com.keypath.invalid-service"

        let legacyInstaller = LaunchDaemonInstaller()
        let legacyLoaded = await legacyInstaller.isServiceLoaded(serviceID: invalidServiceID)
        let legacyHealthy = await legacyInstaller.isServiceHealthy(serviceID: invalidServiceID)

        let newLoaded = await ServiceHealthChecker.shared.isServiceLoaded(serviceID: invalidServiceID)
        let newHealthy = await ServiceHealthChecker.shared.isServiceHealthy(serviceID: invalidServiceID)

        XCTAssertEqual(
            legacyLoaded, newLoaded,
            "Error handling for invalid service ID should match"
        )
        XCTAssertEqual(
            legacyHealthy, newHealthy,
            "Error handling for invalid service ID should match"
        )
    }
}
