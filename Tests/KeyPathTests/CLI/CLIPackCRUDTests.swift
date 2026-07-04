@testable import KeyPathAppKit
import KeyPathCore
@preconcurrency import XCTest

@MainActor
final class CLIPackCRUDTests: XCTestCase {
    private var facade: PacksFacade!
    private var tempDir: URL!
    private var originalInstalledPacks: [InstalledPackRecord] = []

    // Use a pack that's unlikely to be installed in the user's environment
    private let testPackSlug = "chord-groups"
    private let testPackID = "com.keypath.pack.chord-groups"
    private let testPackName = "Chord Groups"

    override func setUp() async throws {
        try await super.setUp()
        TestEnvironment.forceTestMode = true

        // Hermetic manager: temp-backed stores + config dir so install/configure
        // never touch the real ~/.config/keypath or shared stores. On the CI
        // runner's persistent HOME, the shared-store path fails config regen
        // ("could not enable associated rule collection") — see #953.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-pack-crud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir

        let collectionStore = RuleCollectionStore(
            fileURL: dir.appendingPathComponent("RuleCollections.json")
        )
        let customStore = CustomRulesStore(
            fileURL: dir.appendingPathComponent("CustomRules.json")
        )
        facade = PacksFacade(managerFactory: {
            let manager = RuleCollectionsManager(
                ruleCollectionStore: collectionStore,
                customRulesStore: customStore,
                configurationService: ConfigurationService(configDirectory: dir.path)
            )
            manager.ruleCollections = await RuleCollectionDeduplicator.dedupe(
                collectionStore.loadCollections()
            )
            manager.customRules = await customStore.loadRules()
            return manager
        })

        originalInstalledPacks = await InstalledPackTracker.shared.allInstalled()
    }

    override func tearDown() async throws {
        let current = await InstalledPackTracker.shared.allInstalled()
        for record in current {
            if !originalInstalledPacks.contains(where: { $0.packID == record.packID }) {
                try await InstalledPackTracker.shared.remove(packID: record.packID)
            }
        }
        for record in originalInstalledPacks {
            if await !(InstalledPackTracker.shared.isInstalled(packID: record.packID)) {
                try await InstalledPackTracker.shared.upsert(record)
            }
        }
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        TestEnvironment.forceTestMode = false
        try await super.tearDown()
    }

    private func ensureUninstalled(_ packID: String) async throws {
        if await InstalledPackTracker.shared.isInstalled(packID: packID) {
            try await InstalledPackTracker.shared.remove(packID: packID)
        }
    }

    // MARK: - listPacks

    func testListPacksReturnsAllStarterKitPacks() async {
        let packs = await facade.listPacks()
        XCTAssertEqual(packs.count, PackRegistry.starterKit.count)
    }

    func testListPacksShowsInstalledStatus() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await InstalledPackTracker.shared.upsert(record)

        let packs = await facade.listPacks()
        let found = packs.first(where: { $0.id == testPackID })
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.isInstalled == true)
    }

    // MARK: - showPack

    func testShowPackByExactName() async throws {
        let detail = try await facade.showPack(nameOrId: "Vim Navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    func testShowPackBySlug() async throws {
        let detail = try await facade.showPack(nameOrId: "vim-navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    func testShowPackByFullID() async throws {
        let detail = try await facade.showPack(nameOrId: "com.keypath.pack.vim-navigation")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.name, "Vim Navigation")
    }

    func testShowPackNotFoundReturnsNil() async throws {
        let detail = try await facade.showPack(nameOrId: "nonexistent-pack-zzz")
        XCTAssertNil(detail)
    }

    func testShowPackBySubstringUnique() async throws {
        let detail = try await facade.showPack(nameOrId: "Chord")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.chord-groups")
    }

    func testShowPackIncludesQuickSettings() async throws {
        let detail = try await facade.showPack(nameOrId: "home-row-mods")
        XCTAssertNotNil(detail)
        XCTAssertFalse(detail!.quickSettings.isEmpty)
        XCTAssertEqual(detail!.quickSettings.first?.id, "holdTimeout")
    }

    func testShowPackIncludesDependencies() async throws {
        let detail = try await facade.showPack(nameOrId: "delete-enhancement")
        XCTAssertNotNil(detail)
        XCTAssertFalse(detail!.dependencies.isEmpty)
    }

    // MARK: - Name Resolution Edge Cases

    func testResolvePackAmbiguousThrows() async throws {
        // "Navigation" matches both "Vim Navigation" and "Fast Navigation"
        do {
            _ = try await facade.showPack(nameOrId: "Navigation")
            XCTFail("Should throw AmbiguousPackMatch")
        } catch is AmbiguousPackMatch {
            // expected
        }
    }

    func testResolvePackCaseInsensitive() async throws {
        let detail = try await facade.showPack(nameOrId: "VIM NAVIGATION")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.id, "com.keypath.pack.vim-navigation")
    }

    // MARK: - installPack / uninstallPack

    func testInstallAndUninstallRoundTrip() async throws {
        try await ensureUninstalled(testPackID)

        let installResult = try await facade.installPack(nameOrId: testPackSlug)
        XCTAssertEqual(installResult.action, "installed")
        XCTAssertEqual(installResult.packName, testPackName)

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: testPackID)
        XCTAssertTrue(isInstalled)

        let uninstallResult = try await facade.uninstallPack(nameOrId: testPackSlug)
        XCTAssertEqual(uninstallResult.action, "uninstalled")

        let stillInstalled = await InstalledPackTracker.shared.isInstalled(packID: testPackID)
        XCTAssertFalse(stillInstalled)
    }

    func testInstallAlreadyInstalledReturnsAlreadyInstalled() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await InstalledPackTracker.shared.upsert(record)

        let result = try await facade.installPack(nameOrId: testPackSlug)
        XCTAssertEqual(result.action, "already-installed")
    }

    func testUninstallNotInstalledReturnsNotInstalled() async throws {
        try await ensureUninstalled(testPackID)

        let result = try await facade.uninstallPack(nameOrId: testPackSlug)
        XCTAssertEqual(result.action, "not-installed")
    }

    func testInstallDryRun() async throws {
        try await ensureUninstalled(testPackID)

        let result = try await facade.installPack(nameOrId: testPackSlug, dryRun: true)
        XCTAssertEqual(result.action, "would-install")

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: testPackID)
        XCTAssertFalse(isInstalled)
    }

    func testUninstallDryRun() async throws {
        let record = InstalledPackRecord(packID: testPackID, version: "1.0.0")
        try await InstalledPackTracker.shared.upsert(record)

        let result = try await facade.uninstallPack(nameOrId: testPackSlug, dryRun: true)
        XCTAssertEqual(result.action, "would-uninstall")

        let stillInstalled = await InstalledPackTracker.shared.isInstalled(packID: testPackID)
        XCTAssertTrue(stillInstalled)
    }

    func testInstallNotFoundThrows() async throws {
        do {
            _ = try await facade.installPack(nameOrId: "nonexistent-zzz")
            XCTFail("Should throw CLIPackNotFound")
        } catch is CLIPackNotFound {
            // expected
        }
    }

    func testInstallWithInvalidSettingKeyThrows() async throws {
        // Use a pack that's not installed and has no quick settings
        try await ensureUninstalled(testPackID)

        do {
            _ = try await facade.installPack(
                nameOrId: testPackSlug,
                settingValues: ["bogusKey": 999]
            )
            XCTFail("Should throw CLIPackSettingError")
        } catch is CLIPackSettingError {
            // expected
        }
    }

    func testInstallWithValidQuickSettings() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        let result = try await facade.installPack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 200]
        )
        XCTAssertEqual(result.action, "installed")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 200)
    }

    func testInstallRejectsOutOfRangeQuickSetting() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        do {
            _ = try await facade.installPack(
                nameOrId: "home-row-mods",
                settingValues: ["holdTimeout": 999],
                dryRun: true
            )
            XCTFail("Should throw CLIPackSettingValueError")
        } catch let error as CLIPackSettingValueError {
            XCTAssertEqual(error.settingKey, "holdTimeout")
            XCTAssertTrue(error.description.contains("between 120 ms and 300 ms"))
        }
    }

    // MARK: - configurePack

    func testConfigurePackUpdatesSettings() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 250]
        )
        XCTAssertEqual(result.action, "configured")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 250)
    }

    func testConfigurePackDryRun() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 300],
            dryRun: true
        )
        XCTAssertEqual(result.action, "would-configure")
        XCTAssertEqual(result.quickSettingValues["holdTimeout"], 300)

        // Verify actual value unchanged
        let current = await InstalledPackTracker.shared.record(for: "com.keypath.pack.home-row-mods")
        XCTAssertEqual(current?.quickSettingValues["holdTimeout"], 200)
    }

    func testConfigurePackRejectsOutOfRangeQuickSetting() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        do {
            _ = try await facade.configurePack(
                nameOrId: "home-row-mods",
                settingValues: ["holdTimeout": 999],
                dryRun: true
            )
            XCTFail("Should throw CLIPackSettingValueError")
        } catch let error as CLIPackSettingValueError {
            XCTAssertEqual(error.settingKey, "holdTimeout")
            XCTAssertTrue(error.description.contains("between 120 ms and 300 ms"))
        }
    }

    func testConfigurePackNotInstalledReturnsNotInstalled() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")

        let result = try await facade.configurePack(
            nameOrId: "home-row-mods",
            settingValues: ["holdTimeout": 250]
        )
        XCTAssertEqual(result.action, "not-installed")
    }

    func testConfigurePackInvalidSettingThrows() async throws {
        try await ensureUninstalled("com.keypath.pack.home-row-mods")
        _ = try await facade.installPack(nameOrId: "home-row-mods", settingValues: ["holdTimeout": 200])

        do {
            _ = try await facade.configurePack(
                nameOrId: "home-row-mods",
                settingValues: ["bogus": 123]
            )
            XCTFail("Should throw CLIPackSettingError")
        } catch is CLIPackSettingError {
            // expected
        }
    }
}
