@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class PackOwnershipTests: XCTestCase {
    private var originalInstalledPacks: [InstalledPackRecord] = []

    override func setUp() async throws {
        try await super.setUp()
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
            if !(await InstalledPackTracker.shared.isInstalled(packID: record.packID)) {
                try await InstalledPackTracker.shared.upsert(record)
            }
        }
        try await super.tearDown()
    }

    // MARK: - managedCollectionIDs

    func testManagedCollectionIDsSinglePack() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.home-row-mods")!
        XCTAssertEqual(pack.managedCollectionIDs, [RuleCollectionIdentifier.homeRowMods])
    }

    func testManagedCollectionIDsVallack() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.vallack-system")!
        let ids = Set(pack.managedCollectionIDs)
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.vallackNavigation))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(ids.contains(RuleCollectionIdentifier.homeRowLayerToggles))
    }

    func testManagedCollectionIDsVisualOnly() {
        let pack = PackRegistry.pack(id: "com.keypath.pack.kindavim")!
        XCTAssertTrue(pack.managedCollectionIDs.isEmpty)
    }

    // MARK: - packManagingCollection

    func testPackManagingCollectionWhenInstalled() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.home-row-mods",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let owner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        XCTAssertNotNil(owner)
        XCTAssertEqual(owner?.packName, "Home Row Mods")
    }

    func testPackManagingCollectionWhenNotInstalled() async throws {
        if await InstalledPackTracker.shared.isInstalled(packID: "com.keypath.pack.chord-groups") {
            try await InstalledPackTracker.shared.remove(packID: "com.keypath.pack.chord-groups")
        }

        let owner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNil(owner)
    }

    func testVallackOwnsAllThreeCollections() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.vallack-system",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let navOwner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.vallackNavigation
        )
        let hrmOwner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        let togglesOwner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.homeRowLayerToggles
        )

        XCTAssertEqual(navOwner?.packName, "Ben Vallack Approach")
        XCTAssertEqual(hrmOwner?.packName, "Ben Vallack Approach")
        XCTAssertEqual(togglesOwner?.packName, "Ben Vallack Approach")
    }

    // MARK: - Self-managed badge filtering

    func testSelfManagedPackShouldNotShowBadge() async throws {
        let packID = "com.keypath.pack.key-repeat-control"
        let record = InstalledPackRecord(packID: packID, version: "1.0.0")
        try await InstalledPackTracker.shared.upsert(record)

        let collectionID = RuleCollectionIdentifier.keyRepeatControl
        let owner = await InstalledPackTracker.shared.packManagingCollection(collectionID)
        XCTAssertNotNil(owner, "Pack should report owning its collection")

        let pack = PackRegistry.pack(id: owner!.packID)
        XCTAssertEqual(
            pack?.associatedCollectionID, collectionID,
            "Fast Navigation's associatedCollectionID should match its own collection — badge must be hidden"
        )
    }

    func testVallackExternallyManagedCollectionShouldShowBadge() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.vallack-system",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let owner = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.homeRowMods
        )
        XCTAssertNotNil(owner)

        let pack = PackRegistry.pack(id: owner!.packID)!
        XCTAssertNotEqual(
            pack.associatedCollectionID, RuleCollectionIdentifier.homeRowMods,
            "Vallack's associatedCollectionID is vallackNavigation, not homeRowMods — badge should show"
        )
    }

    func testAllPacksWithAssociatedCollectionAreSelfManaged() {
        for pack in PackRegistry.starterKit where pack.associatedCollectionID != nil {
            XCTAssertTrue(
                pack.managedCollectionIDs.contains(pack.associatedCollectionID!),
                "\(pack.name) manages collections \(pack.managedCollectionIDs) but its associatedCollectionID \(pack.associatedCollectionID!) is missing"
            )
        }
    }

    func testOwnershipClearsOnUninstall() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let before = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNotNil(before)

        try await InstalledPackTracker.shared.remove(packID: "com.keypath.pack.chord-groups")

        let after = await InstalledPackTracker.shared.packManagingCollection(
            RuleCollectionIdentifier.chordGroups
        )
        XCTAssertNil(after)
    }

    // MARK: - CLI facade blocks managed collections

    func testCollectionsFacadeBlocksEnableOnManagedCollection() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let facade = CollectionsFacade()
        do {
            _ = try await facade.enableCollection(nameOrId: "Chord Groups")
            XCTFail("Should throw PackManagedCollectionError")
        } catch is PackManagedCollectionError {
            // expected
        }
    }

    func testCollectionsFacadeBlocksDisableOnManagedCollection() async throws {
        let record = InstalledPackRecord(
            packID: "com.keypath.pack.chord-groups",
            version: "1.0.0"
        )
        try await InstalledPackTracker.shared.upsert(record)

        let facade = CollectionsFacade()
        do {
            _ = try await facade.disableCollection(nameOrId: "Chord Groups")
            XCTFail("Should throw PackManagedCollectionError")
        } catch is PackManagedCollectionError {
            // expected
        }
    }
}
