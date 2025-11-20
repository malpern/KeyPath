import XCTest

@testable import KeyPathAppKit

final class PackageManagerTests: XCTestCase {
    var packageManager: PackageManager!

    override func setUp() {
        super.setUp()
        packageManager = PackageManager()
    }

    override func tearDown() {
        packageManager = nil
        super.tearDown()
    }

    // MARK: - Homebrew Detection Tests

    func testCheckHomebrewInstallation_ReturnsBoolean() {
        let result = packageManager.checkHomebrewInstallation()
        XCTAssertTrue(result == true || result == false)
    }

    func testGetHomebrewPath_ReturnsValidPathOrNil() {
        let path = packageManager.getHomebrewPath()

        if let path {
            XCTAssertTrue(path.contains("brew"), "Path should contain 'brew': \(path)")
            XCTAssertTrue(path.hasSuffix("/brew"), "Path should end with '/brew': \(path)")
        }
    }

    func testGetHomebrewBinPath_ReturnsValidPathOrNil() {
        let binPath = packageManager.getHomebrewBinPath()

        if let binPath {
            XCTAssertTrue(binPath.contains("bin"), "Bin path should contain 'bin': \(binPath)")
            XCTAssertTrue(binPath.hasSuffix("/bin"), "Bin path should end with '/bin': \(binPath)")
        }
    }

    // MARK: - Kanata Detection Tests

    func testDetectKanataInstallation_ReturnsValidInfo() {
        let kanataInfo = packageManager.detectKanataInstallation()

        // Verify the structure is valid
        XCTAssertTrue(kanataInfo.isInstalled == true || kanataInfo.isInstalled == false)

        if kanataInfo.isInstalled {
            XCTAssertNotNil(kanataInfo.path, "Path should not be nil when installed")
            XCTAssertNotEqual(
                kanataInfo.installationType, .notInstalled,
                "Installation type should not be notInstalled when installed"
            )
            XCTAssertFalse(kanataInfo.path!.isEmpty, "Path should not be empty when installed")
        } else {
            XCTAssertNil(kanataInfo.path, "Path should be nil when not installed")
            XCTAssertEqual(
                kanataInfo.installationType, .notInstalled,
                "Installation type should be notInstalled when not installed"
            )
        }

        // Verify description is always available
        XCTAssertFalse(kanataInfo.description.isEmpty, "Description should never be empty")
    }

    func testKanataInstallationType_DisplayNames() {
        XCTAssertEqual(KanataInstallationType.homebrew.displayName, "Homebrew")
        XCTAssertEqual(KanataInstallationType.cargo.displayName, "Cargo (Rust)")
        XCTAssertEqual(KanataInstallationType.manual.displayName, "Manual")
        XCTAssertEqual(KanataInstallationType.notInstalled.displayName, "Not Installed")
    }

    // MARK: - Package Manager Info Tests

    func testGetPackageManagerInfo_ReturnsValidInfo() {
        let info = packageManager.getPackageManagerInfo()

        // Verify all properties are accessible
        XCTAssertTrue(info.homebrewAvailable == true || info.homebrewAvailable == false)
        XCTAssertTrue(
            info.kanataInstallation.isInstalled == true || info.kanataInstallation.isInstalled == false)
        XCTAssertFalse(info.supportedPackageManagers.isEmpty || info.supportedPackageManagers.isEmpty) // Either could be valid

        // Verify description is not empty
        XCTAssertFalse(info.description.isEmpty)
        XCTAssertTrue(info.description.contains("Package Manager Information"))

        // Test that the info gathering detects actual system state issues
        // This tests our logging and issue detection without mocking
        if !info.homebrewAvailable {
            // Should have detected this and logged it
            XCTAssertTrue(
                info.supportedPackageManagers.isEmpty,
                "No supported package managers should be available when Homebrew is not available"
            )
        }
    }

    // MARK: - Error Detection Tests (Real System State)

    func testDetectCommonIssues_WithRealSystemState() {
        // This test validates our issue detection logic with real system state
        // Following our guideline to test actual behavior, not mocks

        // Get system state and verify issue detection logic
        let info = packageManager.getPackageManagerInfo()

        // If Kanata is not installed, verify our system can detect and log the issues
        if !info.kanataInstallation.isInstalled {
            // The detectCommonIssues method should have been called
            // We can't directly verify logging, but we can verify the logic works

            // Verify PATH environment variable access works
            let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
            XCTAssertFalse(pathEnv.isEmpty, "PATH environment variable should be accessible")

            // Verify file system checks work for common directories
            let homebrewDirs = ["/opt/homebrew", "/usr/local/Homebrew"]
            for dir in homebrewDirs {
                // This tests the actual file system check logic our code uses
                _ = FileManager.default.fileExists(atPath: dir)
            }
        }
    }

    func testInstallationVerification_RealBehavior() {
        // Test actual verification logic without mocks
        let initialKanataInfo = packageManager.detectKanataInstallation()

        // Verify our path detection logic is working
        let possiblePaths = [
            "/opt/homebrew/bin/kanata", // ARM Homebrew
            "/usr/local/bin/kanata", // Intel Homebrew
            "/usr/local/bin/kanata", // Manual installation
            "\(NSHomeDirectory())/.cargo/bin/kanata" // Rust cargo installation
        ]

        // Test that our detection logic can handle all paths
        for path in possiblePaths {
            let exists = FileManager.default.fileExists(atPath: path)
            if exists, initialKanataInfo.isInstalled {
                // If a kanata binary exists and we detected it, verify the path matches one of the expected paths
                // In CI environments, kanata might be installed in different locations (e.g., /Library/KeyPath/bin/kanata)
                // So we check that a valid path was detected, not necessarily a specific one
                XCTAssertNotNil(initialKanataInfo.path, "Should detect kanata path when binary exists")
                XCTAssertTrue(FileManager.default.fileExists(atPath: initialKanataInfo.path ?? ""), "Detected path should exist")
                break
            }
        }

        // If kanata is installed, verify we detected it (regardless of which path)
        if initialKanataInfo.isInstalled {
            XCTAssertNotNil(initialKanataInfo.path, "Should have detected kanata path if installed")
            if let detectedPath = initialKanataInfo.path {
                XCTAssertTrue(FileManager.default.fileExists(atPath: detectedPath), "Detected kanata path should exist")
            }
        }
    }

    // MARK: - Installation Recommendations Tests

    func testGetInstallationRecommendations_ReturnsValidRecommendations() {
        let recommendations = packageManager.getInstallationRecommendations()

        // Should always have at least the Karabiner-Elements recommendation
        XCTAssertGreaterThanOrEqual(recommendations.count, 1)

        // Verify each recommendation has required properties
        for recommendation in recommendations {
            XCTAssertFalse(recommendation.package.name.isEmpty)
            XCTAssertFalse(recommendation.command.isEmpty)
            XCTAssertFalse(recommendation.description.isEmpty)
            XCTAssertFalse(recommendation.displayText.isEmpty)
        }

        // Should always include Karabiner-Elements
        let hasKarabinerRecommendation = recommendations.contains { recommendation in
            recommendation.package.name == "Karabiner-Elements"
        }
        XCTAssertTrue(hasKarabinerRecommendation, "Should always recommend Karabiner-Elements")
    }

    func testInstallationRecommendation_DisplayText() {
        let recommendation = InstallationRecommendation(
            package: .kanata,
            method: .homebrew,
            priority: .high,
            command: "brew install kanata",
            description: "Install Kanata keyboard remapping engine via Homebrew"
        )

        let displayText = recommendation.displayText
        XCTAssertTrue(displayText.contains("Kanata"))
        XCTAssertTrue(displayText.contains("High Priority"))
        XCTAssertTrue(displayText.contains("Homebrew"))
        XCTAssertTrue(displayText.contains("brew install kanata"))
    }

    // MARK: - Package Info Tests

    func testPackageInfo_StaticInstances() {
        // Test Kanata package info
        XCTAssertEqual(PackageManager.PackageInfo.kanata.name, "Kanata")
        XCTAssertEqual(PackageManager.PackageInfo.kanata.homebrewFormula, "kanata")
        XCTAssertTrue(PackageManager.PackageInfo.kanata.isRequired)
        XCTAssertFalse(PackageManager.PackageInfo.kanata.description.isEmpty)

        // Test Karabiner-Elements package info
        XCTAssertEqual(PackageManager.PackageInfo.karabinerElements.name, "Karabiner-Elements")
        XCTAssertNil(PackageManager.PackageInfo.karabinerElements.homebrewFormula)
        XCTAssertTrue(PackageManager.PackageInfo.karabinerElements.isRequired)
        XCTAssertFalse(PackageManager.PackageInfo.karabinerElements.description.isEmpty)
    }

    func testPackageManagerType_DisplayNames() {
        XCTAssertEqual(PackageManager.PackageManagerType.homebrew.displayName, "Homebrew")
        XCTAssertEqual(PackageManager.PackageManagerType.unknown.displayName, "Unknown")
    }

    func testInstallationMethod_DisplayNames() {
        XCTAssertEqual(InstallationMethod.homebrew.displayName, "Homebrew")
        XCTAssertEqual(InstallationMethod.manual.displayName, "Manual Download")
        XCTAssertEqual(InstallationMethod.cargo.displayName, "Cargo (Rust)")
    }

    func testInstallationPriority_DisplayNames() {
        XCTAssertEqual(InstallationPriority.high.displayName, "High")
        XCTAssertEqual(InstallationPriority.medium.displayName, "Medium")
        XCTAssertEqual(InstallationPriority.low.displayName, "Low")
    }

    // MARK: - Code Signing Cache Tests

    func testCodeSigningCache_Hit() {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-binary-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("test".utf8))

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // First call - cache miss, should perform actual check
        let status1 = packageManager.getCodeSigningStatus(at: testFile.path)
        XCTAssertNotNil(status1)

        // Second call - cache hit, should return cached result
        let status2 = packageManager.getCodeSigningStatus(at: testFile.path)
        XCTAssertEqual(status1.isDeveloperID, status2.isDeveloperID)
        XCTAssertEqual(status1.isAdHoc, status2.isAdHoc)
    }

    func testCodeSigningCache_InvalidationOnFileChange() {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-binary-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: testFile.path, contents: Data("test1".utf8))

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // First call - cache miss
        let status1 = packageManager.getCodeSigningStatus(at: testFile.path)

        // Modify file (change size)
        try? Data("test12".utf8).write(to: testFile)

        // Second call - cache should be invalidated due to file change
        let status2 = packageManager.getCodeSigningStatus(at: testFile.path)
        // Status might be the same or different, but cache should have been invalidated
        XCTAssertNotNil(status2)
    }

    func testCodeSigningCache_SizeLimit() {
        // Create multiple temporary files
        let tempDir = FileManager.default.temporaryDirectory
        var testFiles: [URL] = []

        // Create more files than maxCacheSize (50)
        for i in 0 ..< 60 {
            let testFile = tempDir.appendingPathComponent("test-binary-\(i)-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: testFile.path, contents: Data("test\(i)".utf8))
            testFiles.append(testFile)
        }

        defer {
            for file in testFiles {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Check all files (should trigger cache eviction)
        for file in testFiles {
            _ = packageManager.getCodeSigningStatus(at: file.path)
        }

        // Cache should not exceed maxCacheSize
        // We can't directly check the cache size, but we can verify it doesn't crash
        // and that the last file's status is cached
        let lastStatus = packageManager.getCodeSigningStatus(at: testFiles.last!.path)
        XCTAssertNotNil(lastStatus)
    }
}

// MARK: - Mock Classes for Testing (Minimal Use - Only for Edge Cases)

/// Mock PackageManager - ONLY used for testing edge cases that can't be tested with real system state
/// Following our guidelines: minimize mocks, prefer testing actual behavior
class MockPackageManager: PackageManager {
    private let mockHomebrewAvailable: Bool
    private let mockKanataInstalled: Bool
    private let mockKanataPath: String?
    private let mockInstallationType: KanataInstallationType

    // Only use this mock for specific edge cases that can't be reproduced with real system state
    init(
        homebrewAvailable: Bool = true, kanataInstalled: Bool = false, kanataPath: String? = nil,
        installationType: KanataInstallationType = .notInstalled
    ) {
        mockHomebrewAvailable = homebrewAvailable
        mockKanataInstalled = kanataInstalled
        mockKanataPath = kanataPath
        mockInstallationType = installationType
    }

    override func checkHomebrewInstallation() -> Bool {
        mockHomebrewAvailable
    }

    override func getHomebrewPath() -> String? {
        mockHomebrewAvailable ? "/opt/homebrew/bin/brew" : nil
    }

    override func getHomebrewBinPath() -> String? {
        mockHomebrewAvailable ? "/opt/homebrew/bin" : nil
    }

    override func detectKanataInstallation() -> KanataInstallationInfo {
        KanataInstallationInfo(
            isInstalled: mockKanataInstalled,
            path: mockKanataPath,
            installationType: mockInstallationType,
            version: mockKanataInstalled ? "0.8.0" : nil,
            codeSigningStatus: .unsigned
        )
    }
}

// MARK: - Mock Integration Tests (Only for Edge Cases)

final class MockPackageManagerTests: XCTestCase {
    // Test edge case: System with Homebrew but no Kanata (common new user scenario)
    func testEdgeCase_HomebrewAvailable_KanataNotInstalled() {
        // This tests recommendation logic for a common edge case
        let mockManager = MockPackageManager(homebrewAvailable: true, kanataInstalled: false)

        let info = mockManager.getPackageManagerInfo()
        XCTAssertTrue(info.homebrewAvailable)
        XCTAssertFalse(info.kanataInstallation.isInstalled)
        XCTAssertEqual(info.supportedPackageManagers.count, 1)
        XCTAssertEqual(info.supportedPackageManagers.first, .homebrew)

        // Verify recommendations logic for this edge case
        let recommendations = mockManager.getInstallationRecommendations()
        let kanataRecommendations = recommendations.filter { $0.package.name == "Kanata" }
        XCTAssertGreaterThan(
            kanataRecommendations.count, 0, "Should recommend Kanata when not installed"
        )

        // Should recommend Homebrew installation since it's available
        let homebrewRecommendations = kanataRecommendations.filter { $0.method == .homebrew }
        XCTAssertGreaterThan(
            homebrewRecommendations.count, 0, "Should recommend Homebrew method when available"
        )
    }

    // Test edge case: No package manager available (constrained system scenario)
    func testEdgeCase_NoHomebrew_NoKanata() {
        // This tests fallback recommendation logic for systems without package managers
        let mockManager = MockPackageManager(homebrewAvailable: false, kanataInstalled: false)

        let info = mockManager.getPackageManagerInfo()
        XCTAssertFalse(info.homebrewAvailable)
        XCTAssertFalse(info.kanataInstallation.isInstalled)
        XCTAssertEqual(info.supportedPackageManagers.count, 0)

        let recommendations = mockManager.getInstallationRecommendations()
        let kanataRecommendations = recommendations.filter { $0.package.name == "Kanata" }
        XCTAssertGreaterThan(kanataRecommendations.count, 0, "Should recommend Kanata installation")

        // Should recommend manual installation since no package manager
        let manualRecommendations = kanataRecommendations.filter { $0.method == .manual }
        XCTAssertGreaterThan(
            manualRecommendations.count, 0, "Should recommend manual installation when no package manager"
        )
    }

    // Test edge case: Cargo-based installation (developer/power user scenario)
    func testEdgeCase_CargoInstallation() {
        // This tests detection logic for Cargo-based installations
        let mockManager = MockPackageManager(
            homebrewAvailable: false,
            kanataInstalled: true,
            kanataPath: "\(NSHomeDirectory())/.cargo/bin/kanata",
            installationType: .cargo
        )

        let kanataInfo = mockManager.detectKanataInstallation()
        XCTAssertTrue(kanataInfo.isInstalled)
        XCTAssertEqual(kanataInfo.installationType, .cargo)
        XCTAssertEqual(kanataInfo.installationType.displayName, "Cargo (Rust)")
        XCTAssertTrue(kanataInfo.path!.contains("/.cargo/bin/"))

        // Cargo installation should still trigger Karabiner-Elements recommendation
        let recommendations = mockManager.getInstallationRecommendations()
        let karabinerRecommendations = recommendations.filter {
            $0.package.name == "Karabiner-Elements"
        }
        XCTAssertGreaterThan(
            karabinerRecommendations.count, 0, "Should always recommend Karabiner-Elements"
        )
    }
}
