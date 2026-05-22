@testable import KeyPathAppKit
import XCTest

final class PacksFacadeTests: XCTestCase {

    // MARK: - resolvePack: by full ID

    func testResolvePack_FullID_ReturnsExactMatch() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "com.keypath.pack.caps-lock-to-escape")
        XCTAssertEqual(pack?.id, "com.keypath.pack.caps-lock-to-escape")
    }

    func testResolvePack_FullID_UnknownReturnsNil() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "com.keypath.pack.nonexistent")
        XCTAssertNil(pack)
    }

    // MARK: - resolvePack: by slug

    func testResolvePack_Slug_MatchesSlugPortion() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "caps-lock-to-escape")
        XCTAssertEqual(pack?.id, "com.keypath.pack.caps-lock-to-escape")
    }

    func testResolvePack_Slug_CaseInsensitive() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "Caps-Lock-To-Escape")
        XCTAssertEqual(pack?.id, "com.keypath.pack.caps-lock-to-escape")
    }

    // MARK: - resolvePack: by name

    func testResolvePack_ExactName_ReturnsMatch() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "Caps Lock Remap")
        XCTAssertEqual(pack?.id, "com.keypath.pack.caps-lock-to-escape")
    }

    func testResolvePack_ExactName_CaseInsensitive() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "caps lock remap")
        XCTAssertEqual(pack?.id, "com.keypath.pack.caps-lock-to-escape")
    }

    // MARK: - resolvePack: by substring

    func testResolvePack_SubstringUnique_ReturnsMatch() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "Vallack")
        XCTAssertEqual(pack?.id, "com.keypath.pack.vallack-system")
    }

    func testResolvePack_SubstringAmbiguous_ThrowsAmbiguousMatch() {
        let facade = PacksFacade()
        XCTAssertThrowsError(try facade.resolvePack(nameOrId: "Nav")) { error in
            XCTAssertTrue(error is AmbiguousPackMatch)
        }
    }

    func testResolvePack_NoMatch_ReturnsNil() throws {
        let facade = PacksFacade()
        let pack = try facade.resolvePack(nameOrId: "ZZZZZZNOTAPACK")
        XCTAssertNil(pack)
    }

    // MARK: - CLIPack Codable

    func testCLIPack_CodableRoundTrip() throws {
        let pack = CLIPack(
            id: "test",
            name: "Test Pack",
            version: "1.0.0",
            category: "Test",
            tagline: "A test pack",
            isInstalled: true,
            installedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try JSONEncoder().encode(pack)
        let decoded = try JSONDecoder().decode(CLIPack.self, from: data)
        XCTAssertEqual(decoded.id, "test")
        XCTAssertEqual(decoded.name, "Test Pack")
        XCTAssertTrue(decoded.isInstalled)
    }

    // MARK: - CLIPackDetail

    func testCLIPackDetail_FromPack_CapturesAllFields() {
        let pack = PackRegistry.homeRowMods
        let record = InstalledPackRecord(
            packID: pack.id,
            version: "1.0.0",
            quickSettingValues: ["holdTimeout": 200]
        )
        let detail = CLIPackDetail(from: pack, record: record)

        XCTAssertEqual(detail.id, pack.id)
        XCTAssertEqual(detail.name, pack.name)
        XCTAssertTrue(detail.isInstalled)
        XCTAssertFalse(detail.visualOnly)
        XCTAssertFalse(detail.bindings.isEmpty)
        XCTAssertFalse(detail.quickSettings.isEmpty)
        XCTAssertEqual(detail.quickSettingValues["holdTimeout"], 200)
    }

    func testCLIPackDetail_FromPack_NoRecord_NotInstalled() {
        let pack = PackRegistry.capsLockToEscape
        let detail = CLIPackDetail(from: pack, record: nil)

        XCTAssertFalse(detail.isInstalled)
        XCTAssertNil(detail.installedAt)
        XCTAssertTrue(detail.quickSettingValues.isEmpty)
    }

    func testCLIPackDetail_VisualOnlyPack() {
        let pack = PackRegistry.kindaVim
        let detail = CLIPackDetail(from: pack, record: nil)
        XCTAssertTrue(detail.visualOnly)
        XCTAssertTrue(detail.bindings.isEmpty)
    }

    // MARK: - CLIPackQuickSetting

    func testCLIPackQuickSetting_FromPackQuickSetting() {
        let setting = PackQuickSetting(
            id: "holdTimeout",
            label: "Hold timing",
            kind: .slider(defaultValue: 180, min: 120, max: 300, step: 20, unitSuffix: " ms")
        )
        let cliSetting = CLIPackQuickSetting(from: setting)

        XCTAssertEqual(cliSetting.id, "holdTimeout")
        XCTAssertEqual(cliSetting.label, "Hold timing")
        XCTAssertEqual(cliSetting.defaultValue, 180)
        XCTAssertEqual(cliSetting.min, 120)
        XCTAssertEqual(cliSetting.max, 300)
        XCTAssertEqual(cliSetting.step, 20)
        XCTAssertEqual(cliSetting.unitSuffix, " ms")
    }

    // MARK: - CLIPackDep

    func testCLIPackDep_FromPackDependency() {
        let dep = PackDependency(
            packID: "com.keypath.pack.vim-navigation",
            kind: .enhancedBy,
            description: "Better with Vim Nav"
        )
        let cliDep = CLIPackDep(from: dep)

        XCTAssertEqual(cliDep.packID, "com.keypath.pack.vim-navigation")
        XCTAssertEqual(cliDep.kind, "enhancedBy")
        XCTAssertEqual(cliDep.description, "Better with Vim Nav")
    }

    // MARK: - Error types

    func testCLIPackNotFound_Description() {
        let err = CLIPackNotFound(query: "my-pack")
        XCTAssertTrue(err.description.contains("my-pack"))
    }

    func testCLIPackSettingError_WithValidKeys() {
        let err = CLIPackSettingError(
            packName: "Home Row Mods",
            settingKey: "badKey",
            validKeys: ["holdTimeout"]
        )
        XCTAssertTrue(err.description.contains("badKey"))
        XCTAssertTrue(err.description.contains("holdTimeout"))
    }

    func testCLIPackSettingError_NoQuickSettings() {
        let err = CLIPackSettingError(
            packName: "Caps Lock Remap",
            settingKey: "anyKey",
            validKeys: []
        )
        XCTAssertTrue(err.description.contains("no quick settings"))
    }

    func testAmbiguousPackMatch_Description() {
        let err = AmbiguousPackMatch(
            query: "Nav",
            matches: [
                .init(name: "Vim Navigation", id: "com.keypath.pack.vim-navigation"),
                .init(name: "Ben Vallack Nav", id: "com.keypath.pack.vallack-system")
            ]
        )
        XCTAssertTrue(err.description.contains("2 packs"))
        XCTAssertTrue(err.description.contains("Vim Navigation"))
    }

    func testPackManagedCollectionError_Description() {
        let err = PackManagedCollectionError(
            collectionName: "Home Row Mods",
            packName: "Home Row Mods",
            packID: "com.keypath.pack.home-row-mods"
        )
        XCTAssertTrue(err.description.contains("managed by"))
        XCTAssertTrue(err.description.contains("keypath pack uninstall"))
    }

    // MARK: - CLIApplyResult Codable

    func testCLIApplyResult_CodableRoundTrip() throws {
        let changeset = CLIApplyChangeset(
            enabledCollections: ["Caps Lock Remap"],
            disabledCollections: ["Home Row Mods"],
            customRules: ["a → b"]
        )
        let result = CLIApplyResult(
            collectionsCount: 5,
            enabledCount: 3,
            customRulesCount: 1,
            reloadSuccess: true,
            changeset: changeset
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CLIApplyResult.self, from: data)

        XCTAssertEqual(decoded.collectionsCount, 5)
        XCTAssertEqual(decoded.enabledCount, 3)
        XCTAssertTrue(decoded.reloadSuccess)
        XCTAssertEqual(decoded.changeset?.enabledCollections, ["Caps Lock Remap"])
    }

    // MARK: - CLIValidationResult Codable

    func testCLIValidationResult_CodableRoundTrip() throws {
        let result = CLIValidationResult(
            isValid: true,
            errors: [],
            configPath: "/path/to/config",
            configBytes: 4096,
            collectionsCount: 10,
            customRulesCount: 3
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CLIValidationResult.self, from: data)

        XCTAssertTrue(decoded.isValid)
        XCTAssertTrue(decoded.errors.isEmpty)
        XCTAssertEqual(decoded.configPath, "/path/to/config")
        XCTAssertEqual(decoded.configBytes, 4096)
    }
}
