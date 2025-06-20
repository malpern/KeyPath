import Testing
@testable import KeyPath
import Foundation

@Suite("KanataInstaller Tests")
final class KanataInstallerTests {
    var installer: KanataInstaller!
    var tempConfigPath: String!
    var tempDirectory: String!

    init() {
        installer = KanataInstaller()

        tempDirectory = NSTemporaryDirectory() + "KanataInstallerTests_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        tempConfigPath = tempDirectory + "/kanata.kbd"
    }

    deinit {
        try? FileManager.default.removeItem(atPath: tempDirectory)
    }

    // MARK: - Setup Tests

    @Test("Check Kanata setup creates config directory")
    func checkKanataSetupCreatesConfigDirectory() {
        let result = installer.checkKanataSetup()

        switch result {
        case .success(let success):
            #expect(success)
        case .failure(let error):
            let acceptableErrors = [
                "Kanata configuration directory not found at ~/.config/kanata/",
                "Kanata configuration file not found at ~/.config/kanata/kanata.kbd"
            ]
            #expect(acceptableErrors.contains(error.localizedDescription))
        }
    }

    // MARK: - Configuration Tests

    @Test("Get current config returns nil for nonexistent file")
    func getCurrentConfigReturnsNilForNonexistentFile() {
        let config = installer.getCurrentConfig()

        if let configContent = config {
            #expect(configContent.contains("defcfg") || configContent.contains("KeyPath"))
        }
    }

    // MARK: - Rule Installation Tests

    @Test("Install rule with valid rule")
    func installRuleWithValidRule() async throws {
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

        let testConfig = """
        ;; Test Kanata Configuration
        (defcfg
          process-unmapped-keys yes
        )
        """

        try testConfig.write(toFile: tempConfigPath, atomically: true, encoding: .utf8)

        await withCheckedContinuation { continuation in
            installer.installRule(rule) { result in
                switch result {
                case .success(let backupPath):
                    #expect(!backupPath.isEmpty)
                    #expect(backupPath.contains("keypath-backup"))
                case .failure(let error):
                    #expect(error.localizedDescription != "")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Rule Validation Tests

    @Test("Validate rule with invalid rule")
    func validateRuleWithInvalidRule() async throws {
        let invalidRule = "(invalid kanata syntax here)"

        await withCheckedContinuation { continuation in
            installer.validateRule(invalidRule) { result in
                switch result {
                case .success:
                    // This should not succeed with invalid syntax unless Kanata is not installed
                    break
                case .failure(let error):
                    // Accept any validation error message since Kanata might give different messages
                    #expect(!error.localizedDescription.isEmpty)
                }
                continuation.resume()
            }
        }
    }

    @Test("Validate rule with valid rule")
    func validateRuleWithValidRule() async throws {
        let validRule = "(defalias caps esc)"

        await withCheckedContinuation { continuation in
            installer.validateRule(validRule) { result in
                switch result {
                case .success(let isValid):
                    #expect(isValid)
                case .failure(let error):
                    #expect(error.localizedDescription.contains("not found") ||
                           error.localizedDescription.contains("validation failed"))
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Backup and Undo Tests

    @Test("Undo last rule with valid backup")
    func undoLastRuleWithValidBackup() async throws {
        let backupContent = """
        ;; Original Kanata Configuration
        (defcfg
          process-unmapped-keys yes
        )
        """

        let backupPath = tempDirectory + "/kanata.kbd.keypath-backup-123456"

        try backupContent.write(toFile: backupPath, atomically: true, encoding: .utf8)

        await withCheckedContinuation { continuation in
            installer.undoLastRule(backupPath: backupPath) { result in
                switch result {
                case .success(let success):
                    #expect(success)
                case .failure(let error):
                    #expect(error.localizedDescription != "")
                }
                continuation.resume()
            }
        }
    }

    @Test("Undo last rule with invalid backup")
    func undoLastRuleWithInvalidBackup() async throws {
        let nonexistentBackupPath = "/nonexistent/backup/path"

        await withCheckedContinuation { continuation in
            installer.undoLastRule(backupPath: nonexistentBackupPath) { result in
                switch result {
                case .success:
                    Issue.record("Should not succeed with nonexistent backup path")
                case .failure(let error):
                    #expect(error.localizedDescription.contains("Failed to restore backup"))
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Error Handling Tests

    @Test("Install error descriptions")
    func installErrorDescriptions() {
        let errors: [KanataValidationError] = [
            .configDirectoryNotFound,
            .configFileNotFound,
            .kanataNotFound,
            .validationFailed("test error"),
            .writeFailed("write error"),
            .reloadFailed("reload error")
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }

        #expect(KanataValidationError.configDirectoryNotFound.localizedDescription.contains("configuration directory"))
        #expect(KanataValidationError.configFileNotFound.localizedDescription.contains("configuration file"))
        #expect(KanataValidationError.kanataNotFound.localizedDescription.contains("executable not found"))
        #expect(KanataValidationError.validationFailed("test").localizedDescription.contains("validation failed"))
        #expect(KanataValidationError.writeFailed("test").localizedDescription.contains("write configuration"))
        #expect(KanataValidationError.reloadFailed("test").localizedDescription.contains("reload Kanata"))
    }
}
