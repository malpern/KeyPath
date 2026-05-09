@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Tests that generated kanata configs are syntactically valid by running
/// them through the real kanata binary with --check.
///
/// These catch config generation bugs that lightweight parsing misses:
/// undefined aliases, invalid S-expression nesting, unsupported key names,
/// missing deflayer entries, etc.
///
/// Requires: kanata binary at /usr/local/bin/kanata or the bundled app path.
final class ConfigValidationTests: XCTestCase {

    private func findKanataBinary() -> String? {
        // Only use the bundled binary — it matches the version KeyPath ships.
        // System-installed kanata (e.g., homebrew v1.10) may be too old and
        // reject features like defhands or tap-hold-require-prior-idle.
        let bundled = "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        return nil
    }

    @MainActor
    private func validateWithKanata(_ config: String) async throws -> (isValid: Bool, errors: [String]) {
        guard let binary = findKanataBinary() else {
            throw XCTSkip("Kanata binary not found — skipping CLI validation")
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanata-test-\(UUID().uuidString).kbd")
        try config.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--cfg", tempFile.path, "--check"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return (true, [])
        } else {
            let errors = output.components(separatedBy: .newlines)
                .filter { $0.contains("[ERROR]") || $0.contains("help:") }
            return (false, errors)
        }
    }

    // MARK: - Default Config Validation

    @MainActor
    func testDefaultConfigIsValidKanata() async throws {
        let collections = RuleCollectionCatalog().defaultCollections()
        let config = KanataConfiguration.generateFromCollections(collections)

        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Default config should be valid kanata. Errors: \(result.errors)")
    }

    // MARK: - Per-Pack Config Validation

    @MainActor
    func testCapsLockRemapConfigIsValid() async throws {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Caps Lock Remap config should be valid. Errors: \(result.errors)")
    }

    @MainActor
    func testHomeRowModsConfigIsValid() async throws {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Home Row Mods config should be valid. Errors: \(result.errors)")
    }

    @MainActor
    func testVimNavigationConfigIsValid() async throws {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.vim-navigation"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Vim navigation pack not found")
        }

        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[idx].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Vim Navigation config should be valid. Errors: \(result.errors)")
    }

    @MainActor
    func testWindowSnappingConfigIsValid() async throws {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.window-snapping"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Window snapping pack not found")
        }

        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[idx].isEnabled = true
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Window Snapping config should be valid. Errors: \(result.errors)")
    }

    // MARK: - Custom Rule Config Validation

    @MainActor
    func testSimpleRemapCustomRuleConfigIsValid() async throws {
        let rule = CustomRule(input: "a", output: "b")
        let ruleCollections = [rule].compactMap { $0.asRuleCollection() }
        var collections = RuleCollectionCatalog().defaultCollections()
        collections.append(contentsOf: ruleCollections)

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Simple remap custom rule should produce valid config. Errors: \(result.errors)")
    }

    @MainActor
    func testMultiplePacksEnabledConfigIsValid() async throws {
        var collections = RuleCollectionCatalog().defaultCollections()

        // Enable Caps Lock Remap + Vim Navigation simultaneously
        for i in collections.indices {
            if collections[i].id == RuleCollectionIdentifier.capsLockRemap {
                collections[i].isEnabled = true
            }
            if let pack = PackRegistry.pack(id: "com.keypath.pack.vim-navigation"),
               collections[i].id == pack.associatedCollectionID
            {
                collections[i].isEnabled = true
            }
        }

        let config = KanataConfiguration.generateFromCollections(collections)
        let result = try await validateWithKanata(config)
        XCTAssertTrue(result.isValid, "Multiple packs enabled should produce valid config. Errors: \(result.errors)")
    }

    // MARK: - All Packs Validation

    @MainActor
    func testEachPackProducesValidConfigIndividually() async throws {
        let catalog = RuleCollectionCatalog().defaultCollections()

        for pack in PackRegistry.starterKit where !pack.visualOnly {
            guard let collectionID = pack.associatedCollectionID else { continue }

            var collections = catalog
            for i in collections.indices {
                collections[i].isEnabled = collections[i].id == collectionID
                    || collections[i].isSystemDefault
            }

            let config = KanataConfiguration.generateFromCollections(collections)
            let result = try await validateWithKanata(config)
            XCTAssertTrue(
                result.isValid,
                "Pack '\(pack.name)' should produce valid config. Errors: \(result.errors)"
            )
        }
    }
}
