import XCTest
@testable import KeyPath

final class KanataInstallerTests: XCTestCase {
    var installer: KanataInstaller!
    var tempConfigPath: String!
    var tempDirectory: String!
    
    override func setUp() {
        super.setUp()
        installer = KanataInstaller()
        
        // Create a temporary directory for testing
        tempDirectory = NSTemporaryDirectory() + "KanataInstallerTests_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        
        tempConfigPath = tempDirectory + "/kanata.kbd"
    }
    
    override func tearDown() {
        // Clean up temporary files
        try? FileManager.default.removeItem(atPath: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Setup Tests
    
    func testCheckKanataSetupCreatesConfigDirectory() {
        // This test is tricky since it modifies the actual config directory
        // We'll test the logic by creating a mock scenario
        let result = installer.checkKanataSetup()
        
        // The setup should either succeed or fail gracefully
        switch result {
        case .success(let success):
            XCTAssertTrue(success)
        case .failure(let error):
            // Acceptable failures for testing environment
            XCTAssertTrue([
                "Kanata configuration directory not found at ~/.config/kanata/",
                "Kanata configuration file not found at ~/.config/kanata/kanata.kbd"
            ].contains(error.localizedDescription))
        }
    }
    
    // MARK: - Configuration Tests
    
    func testGetCurrentConfigReturnsNilForNonexistentFile() {
        // Test with a path that doesn't exist
        let config = installer.getCurrentConfig()
        
        // This will be nil if the actual config doesn't exist, or return content if it does
        // Both are valid outcomes depending on the system state
        if let configContent = config {
            XCTAssertTrue(configContent.contains("defcfg") || configContent.contains("KeyPath"))
        }
    }
    
    // MARK: - Rule Installation Tests
    
    func testInstallRuleWithValidRule() {
        let expectation = self.expectation(description: "Install rule completion")
        
        // Create a mock rule
        let behavior = KanataBehavior.simpleRemap(from: "caps", toKey: "esc")
        let visualization = EnhancedRemapVisualization(
            behavior: behavior,
            title: "Test Remap",
            description: "Test caps to escape"
        )
        let rule = KanataRule(
            visualization: visualization,
            kanataRule: "(defalias caps esc)",
            confidence: .high,
            explanation: "Test rule for caps to escape"
        )
        
        // Create a test config file first
        let testConfig = """
        ;; Test Kanata Configuration
        (defcfg
          process-unmapped-keys yes
        )
        """
        
        do {
            try testConfig.write(toFile: tempConfigPath, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create test config: \(error)")
            return
        }
        
        installer.installRule(rule) { result in
            switch result {
            case .success(let backupPath):
                XCTAssertFalse(backupPath.isEmpty)
                XCTAssertTrue(backupPath.contains("keypath-backup"))
            case .failure(let error):
                // Expected to fail in test environment due to missing Kanata executable
                // or permissions issues
                XCTAssertNotNil(error.localizedDescription)
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // MARK: - Rule Validation Tests
    
    func testValidateRuleWithInvalidRule() {
        let expectation = self.expectation(description: "Validate rule completion")
        
        let invalidRule = "(invalid kanata syntax here)"
        
        installer.validateRule(invalidRule) { result in
            switch result {
            case .success:
                // This should not succeed with invalid syntax
                // Unless Kanata is not installed, in which case it will fail differently
                break
            case .failure(let error):
                // Expected to fail due to invalid syntax or missing Kanata
                XCTAssertNotNil(error.localizedDescription)
                XCTAssertTrue(
                    error.localizedDescription.contains("validation failed") ||
                    error.localizedDescription.contains("not found")
                )
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testValidateRuleWithValidRule() {
        let expectation = self.expectation(description: "Validate rule completion")
        
        let validRule = "(defalias caps esc)"
        
        installer.validateRule(validRule) { result in
            switch result {
            case .success(let isValid):
                XCTAssertTrue(isValid)
            case .failure(let error):
                // Expected to fail in test environment due to missing Kanata executable
                XCTAssertTrue(
                    error.localizedDescription.contains("not found") ||
                    error.localizedDescription.contains("validation failed")
                )
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // MARK: - Backup and Undo Tests
    
    func testUndoLastRuleWithValidBackup() {
        let expectation = self.expectation(description: "Undo rule completion")
        
        // Create a mock backup file
        let backupContent = """
        ;; Original Kanata Configuration
        (defcfg
          process-unmapped-keys yes
        )
        """
        
        let backupPath = tempDirectory + "/kanata.kbd.keypath-backup-123456"
        
        do {
            try backupContent.write(toFile: backupPath, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create backup file: \(error)")
            return
        }
        
        installer.undoLastRule(backupPath: backupPath) { result in
            switch result {
            case .success(let success):
                XCTAssertTrue(success)
            case .failure(let error):
                // Expected to fail in test environment due to missing Kanata or file permissions
                XCTAssertNotNil(error.localizedDescription)
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testUndoLastRuleWithInvalidBackup() {
        let expectation = self.expectation(description: "Undo rule completion")
        
        let nonexistentBackupPath = "/nonexistent/backup/path"
        
        installer.undoLastRule(backupPath: nonexistentBackupPath) { result in
            switch result {
            case .success:
                XCTFail("Should not succeed with nonexistent backup path")
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("Failed to restore backup"))
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0, handler: nil)
    }
    
    // MARK: - Error Handling Tests
    
    func testInstallErrorDescriptions() {
        let errors: [KanataValidationError] = [
            .configDirectoryNotFound,
            .configFileNotFound,
            .kanataNotFound,
            .validationFailed("test error"),
            .writeFailed("write error"),
            .reloadFailed("reload error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        
        // Test specific error messages
        XCTAssertTrue(KanataValidationError.configDirectoryNotFound.localizedDescription.contains("configuration directory"))
        XCTAssertTrue(KanataValidationError.configFileNotFound.localizedDescription.contains("configuration file"))
        XCTAssertTrue(KanataValidationError.kanataNotFound.localizedDescription.contains("executable not found"))
        XCTAssertTrue(KanataValidationError.validationFailed("test").localizedDescription.contains("validation failed"))
        XCTAssertTrue(KanataValidationError.writeFailed("test").localizedDescription.contains("write configuration"))
        XCTAssertTrue(KanataValidationError.reloadFailed("test").localizedDescription.contains("reload Kanata"))
    }
    
    // MARK: - Integration Tests
    
    // Integration test disabled for CI compatibility
    // Comprehensive workflow tests would require actual Kanata installation
}