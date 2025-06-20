import Testing
import Foundation
@testable import KeyPath

@Suite("Service Layer Tests")
struct ServiceLayerTests {

    @Suite("SimpleKanataConfigManager Tests")
    struct SimpleKanataConfigManagerTests {

        @Test("Generate config with no rules")
        func generateConfigWithNoRules() {
            let manager = SimpleKanataConfigManager()

            let result = try? manager.generateConfig(with: [])

            #expect(result != nil)
            #expect(result?.contains("defcfg") == true)
        }

        @Test("Generate config with single rule")
        func generateConfigWithSingleRule() {
            let manager = SimpleKanataConfigManager()
            let behavior = KanataBehavior.simpleRemap(from: "a", toKey: "b")
            let visualization = EnhancedRemapVisualization(
                behavior: behavior,
                title: "Test Rule",
                description: "Test mapping"
            )
            let rule = KanataRule(
                visualization: visualization,
                kanataRule: "(defsrc a)\n(deflayer default b)",
                confidence: .high,
                explanation: "Test rule"
            )

            let result = try? manager.generateConfig(with: [rule])

            #expect(result != nil)
            #expect(result?.contains("defcfg") == true)
            #expect(result?.contains("defsrc a") == true)
        }
    }

    @Suite("SoundManager Tests")
    struct SoundManagerTests {

        @Test("SoundManager shared instance exists")
        func soundManagerSharedInstance() {
            let soundManager = SoundManager.shared

            // Basic existence test - SoundManager is a class, so always exists
            #expect(type(of: soundManager) == SoundManager.self)
        }

        @Test("SoundManager sound types have file names")
        func soundManagerSoundTypes() {
            #expect(SoundManager.SoundType.success.fileName == "Ping")
            #expect(SoundManager.SoundType.deactivation.fileName == "Pop")
        }
    }

    @Suite("SecurityManager Tests")
    struct SecurityManagerTests {

        @Test("SecurityManager can be initialized")
        func securityManagerInitialization() {
            _ = SecurityManager()

            // Basic existence test - SecurityManager is a struct, so always exists
            #expect(Bool(true)) // Just test that initialization doesn't crash
        }
    }

    @Suite("KanataValidationError Tests")
    struct KanataValidationErrorTests {

        @Test("Validation error has description")
        func validationErrorDescription() {
            let error = KanataValidationError.validationFailed("Test error")

            #expect(!error.localizedDescription.isEmpty)
            #expect(error.localizedDescription.contains("Test error"))
        }

        @Test("Config directory not found error has description")
        func configDirectoryNotFoundErrorDescription() {
            let error = KanataValidationError.configDirectoryNotFound

            #expect(!error.localizedDescription.isEmpty)
            #expect(error.localizedDescription.contains("configuration directory"))
        }
    }
}
