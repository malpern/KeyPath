import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Snapshot of managed collections' state before a pack was installed.
/// Used to restore previous configuration on uninstall.
public struct PackCollectionSnapshot: Codable, Equatable, Sendable {
    public let packID: String
    public let snapshotDate: Date
    public var entries: [Entry]

    public struct Entry: Codable, Equatable, Sendable {
        public let collectionID: UUID
        public var wasEnabled: Bool
        public var configurationJSON: Data
    }

    public init(packID: String, snapshotDate: Date = Date(), entries: [Entry]) {
        self.packID = packID
        self.snapshotDate = snapshotDate
        self.entries = entries
    }

    // MARK: - Persistence

    private static var snapshotsDirectory: URL {
        AppPaths.configDirectory
            .appendingPathComponent("pack-snapshots", isDirectory: true)
    }

    static func snapshotURL(for packID: String) -> URL {
        snapshotsDirectory.appendingPathComponent("\(packID).json")
    }

    static func save(_ snapshot: PackCollectionSnapshot) throws {
        let dir = snapshotsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL(for: snapshot.packID), options: .atomic)
    }

    static func load(for packID: String) -> PackCollectionSnapshot? {
        let url = snapshotURL(for: packID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PackCollectionSnapshot.self, from: data)
    }

    /// Mutation paths distinguish an absent legacy snapshot from unreadable data.
    static func loadForMutation(for packID: String) throws -> PackCollectionSnapshot? {
        let data: Data
        do { data = try Data(contentsOf: snapshotURL(for: packID)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        return try JSONDecoder().decode(PackCollectionSnapshot.self, from: data)
    }

    static func remove(for packID: String) {
        try? FileManager.default.removeItem(at: snapshotURL(for: packID))
    }

    // MARK: - Legacy Vallack Migration

    private static var legacyVallackURL: URL {
        AppPaths.configDirectory
            .appendingPathComponent("vallack-system-snapshot.json")
    }

    private struct LegacyVallackSnapshot: Codable {
        var homeRowModsConfig: HomeRowModsConfig?
        var homeRowModsEnabled: Bool
        var homeRowLayerTogglesConfig: HomeRowLayerTogglesConfig?
        var homeRowLayerTogglesEnabled: Bool
    }

    static func loadLegacyVallack() -> PackCollectionSnapshot? {
        try? loadLegacyVallackForMutation()
    }

    static func loadLegacyVallackForMutation() throws -> PackCollectionSnapshot? {
        let data: Data
        do { data = try Data(contentsOf: legacyVallackURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        let legacy = try JSONDecoder().decode(LegacyVallackSnapshot.self, from: data)

        var entries: [Entry] = []

        let modsConfig: RuleCollectionConfiguration = legacy.homeRowModsConfig.map {
            .homeRowMods($0)
        } ?? .homeRowMods(HomeRowModsConfig())
        let modsJSON = try JSONEncoder().encode(modsConfig)
        entries.append(Entry(
            collectionID: RuleCollectionIdentifier.homeRowMods,
            wasEnabled: legacy.homeRowModsEnabled,
            configurationJSON: modsJSON
        ))

        let togglesConfig: RuleCollectionConfiguration = legacy.homeRowLayerTogglesConfig.map {
            .homeRowLayerToggles($0)
        } ?? .homeRowLayerToggles(HomeRowLayerTogglesConfig())
        let togglesJSON = try JSONEncoder().encode(togglesConfig)
        entries.append(Entry(
            collectionID: RuleCollectionIdentifier.homeRowLayerToggles,
            wasEnabled: legacy.homeRowLayerTogglesEnabled,
            configurationJSON: togglesJSON
        ))

        return PackCollectionSnapshot(
            packID: "com.keypath.pack.vallack-system",
            snapshotDate: Date(),
            entries: entries
        )
    }

    static func removeLegacyVallack() {
        try? removeLegacyVallackIfPresent()
    }

    /// Throwing cleanup for callers that need to report a legacy-file failure.
    static func removeLegacyVallackIfPresent() throws {
        guard FileManager.default.fileExists(atPath: legacyVallackURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: legacyVallackURL)
    }
}
