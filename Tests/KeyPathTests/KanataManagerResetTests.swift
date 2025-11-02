import XCTest
@testable import KeyPath

@MainActor
final class KanataManagerResetTests: XCTestCase {
    func testResetWritesDefaultConfig() async throws {
        // Given a fresh manager and temp HOME (run-tests-safe.sh sets HOME)
        let manager = KanataManager()

        // When: reset to default config
        try await manager.resetToDefaultConfig()

        // Then: the default config file should exist and match generated content
        let path = NSHomeDirectory() + "/.config/keypath/keypath.kbd"
        let written = try String(contentsOfFile: path, encoding: .utf8)

        let expected = KanataConfiguration.generateFromMappings([
            KeyMapping(input: "caps", output: "escape")
        ])

        XCTAssertEqual(
            written.trimmingCharacters(in: .whitespacesAndNewlines),
            expected.trimmingCharacters(in: .whitespacesAndNewlines),
            "resetToDefaultConfig should write the known-good default config"
        )
    }
}


