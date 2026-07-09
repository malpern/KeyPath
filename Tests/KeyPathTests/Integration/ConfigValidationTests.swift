@testable import KeyPathAppKit
import KeyPathCore
import KeyPathRulesCore
import XCTest

/// Tests that generated kanata configs are syntactically valid by running
/// them through the real kanata binary with --check.
///
/// These catch config generation bugs that lightweight parsing misses:
/// undefined aliases, invalid S-expression nesting, unsupported key names,
/// missing deflayer entries, etc.
///
/// Requires: a current KeyPath kanata binary, preferably via
/// KEYPATH_KANATA_PATH, the repo-built fork, or the app-bundled fork.
final class ConfigValidationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Per-pack assertions in testEachPackProducesValidConfigIndividually
        // should all run even when one pack fails. Without this, XCTest stops
        // at the first failure and later packs aren't tested.
        continueAfterFailure = true
    }

    private func findKanataBinary() -> String? {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["KEYPATH_KANATA_PATH"],
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Integration
                .deletingLastPathComponent() // KeyPathTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("External/kanata/target/aarch64-apple-darwin/release/kanata")
                .path,
            "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
            "/opt/homebrew/bin/kanata"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
        let rule = CustomRule(input: "a", action: .keystroke(key: "b"))
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
        // With continueAfterFailure = true (see setUp), every pack runs even
        // if one fails; each assertion failure names the offending pack.
        for pack in PackRegistry.starterKit where !pack.visualOnly {
            guard let collectionID = pack.associatedCollectionID else { continue }
            let config = MatrixTestHelpers.enabledCollectionConfig(collectionID)
            let result = try await validateWithKanata(config)
            XCTAssertTrue(
                result.isValid,
                "Pack '\(pack.name)' (\(pack.id)) produced invalid kanata config. Errors: \(result.errors)"
            )
        }
    }

    // MARK: - Per-Catalog-Family Kanata Syntax Validation

    //
    // One assertion per catalog family. With continueAfterFailure = true,
    // every family is exercised even when one fails — so a regression in a
    // single family doesn't hide regressions in the others.

    @MainActor
    func testEveryCatalogFamilyProducesValidKanataConfig() async throws {
        // Excludes families that are already covered by dedicated tests above
        // (capsLockRemap, homeRowMods) to avoid double-work in the kanata
        // validation loop, which is the slowest part of the suite.
        let families: [(name: String, id: UUID)] = [
            ("Vim Navigation", RuleCollectionIdentifier.vimNavigation),
            ("Neovim Terminal", RuleCollectionIdentifier.neovimTerminal),
            ("Mission Control", RuleCollectionIdentifier.missionControl),
            ("Window Snapping", RuleCollectionIdentifier.windowSnapping),
            ("macOS Function Keys", RuleCollectionIdentifier.macFunctionKeys),
            ("Backup Caps Lock", RuleCollectionIdentifier.backupCapsLock),
            ("Escape", RuleCollectionIdentifier.escapeRemap),
            ("Delete Enhancement", RuleCollectionIdentifier.deleteRemap),
            ("Leader Key", RuleCollectionIdentifier.leaderKey),
            ("Home Row Layer Toggles", RuleCollectionIdentifier.homeRowLayerToggles),
            ("Chord Groups", RuleCollectionIdentifier.chordGroups),
            ("Sequences", RuleCollectionIdentifier.sequences),
            ("Numpad", RuleCollectionIdentifier.numpadLayer),
            ("Symbol Layer", RuleCollectionIdentifier.symbolLayer),
            ("Function Layer", RuleCollectionIdentifier.funLayer),
            ("Auto Shift Symbols", RuleCollectionIdentifier.autoShiftSymbols),
            ("Fast Navigation", RuleCollectionIdentifier.keyRepeatControl),
            ("Home Row Arrows", RuleCollectionIdentifier.homeRowArrows),
            ("Ben Vallack Nav", RuleCollectionIdentifier.vallackNavigation),
            ("Quick Launcher", RuleCollectionIdentifier.launcher)
        ]

        for family in families {
            let config = MatrixTestHelpers.enabledCollectionConfig(family.id)
            let result = try await validateWithKanata(config)
            XCTAssertTrue(
                result.isValid,
                "Family '\(family.name)' produced invalid kanata config. Errors: \(result.errors)"
            )
        }
    }
}
