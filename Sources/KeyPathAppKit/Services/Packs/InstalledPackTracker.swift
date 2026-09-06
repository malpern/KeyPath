// M1 Gallery MVP — persist which packs are installed + their current
// quick-setting values. Separate from CustomRulesStore because pack state is
// orthogonal to rules — a pack might be installed but its rules overridden by
// the user; a pack might be uninstalled with rules lingering (not in M1, but
// this keeps the door open for M2's override-precedence design).
//
// Lives at ~/.config/keypath/installed-packs.json.

import Foundation
@preconcurrency import KeyPathCore

/// Snapshot of a single installed pack's state. Persisted to disk.
public struct InstalledPackRecord: Codable, Equatable, Sendable {
    public let packID: String
    public let version: String
    public let installedAt: Date
    /// Current values of the pack's quick settings, keyed by `PackQuickSetting.id`.
    /// Only int values in M1 (sliders). M2 will widen.
    public var quickSettingValues: [String: Int]

    public init(
        packID: String,
        version: String,
        installedAt: Date = Date(),
        quickSettingValues: [String: Int] = [:]
    ) {
        self.packID = packID
        self.version = version
        self.installedAt = installedAt
        self.quickSettingValues = quickSettingValues
    }
}

/// Thread-safe store of installed-pack records. Backed by a JSON file.
public actor InstalledPackTracker {
    public static let shared = InstalledPackTracker()

    private let fileURL: URL
    private var writeFile: @Sendable (Data, URL) throws -> Void = { try RecoverableRuleWrite.durableWrite($0, $1) }
    private var lastReadableRecords: [String: InstalledPackRecord] = [:]

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if TestEnvironment.isRunningTests {
            // Intentionally NOT AppPaths.testSandboxDirectory: each tracker
            // instance gets its own UUID directory so parallel test instances
            // never see each other's records. AppPaths' shared per-process
            // sandbox would make them collide.
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("keypath-installed-packs-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("installed-packs.json")
        } else {
            // ~/.config/keypath/installed-packs.json
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("keypath", isDirectory: true)
                .appendingPathComponent("installed-packs.json")
        }
    }

    init(fileURL: URL, writeFile: @escaping @Sendable (Data, URL) throws -> Void) {
        self.fileURL = fileURL
        self.writeFile = writeFile
    }

    /// Mutating decisions cannot rely on the display-only fallback snapshot.
    /// Call under configuration admission before staging source changes.
    func validateForMutation() throws {
        lastReadableRecords = try readRecords()
    }

    var persistenceURL: URL {
        fileURL
    }

    struct RecordChange: Sendable {
        let tracker: InstalledPackTracker
        let packID: String
        let record: InstalledPackRecord?

        init(tracker: InstalledPackTracker, record: InstalledPackRecord) {
            self.tracker = tracker
            packID = record.packID
            self.record = record
        }

        init(tracker: InstalledPackTracker, removing packID: String) {
            self.tracker = tracker
            self.packID = packID
            record = nil
        }
    }

    struct PreparedRecordUpdate: Sendable {
        let tracker: InstalledPackTracker
        let fileURL: URL
        let before: Data?
        let contents: Data
        let previousRecords: [String: InstalledPackRecord]
        let records: [String: InstalledPackRecord]
        let writeFile: @Sendable (Data, URL) throws -> Void
    }

    /// Build a metadata revision without writing or notifying. The configuration
    /// transaction compares this preimage before staging it with the rule files.
    func prepareUpdate(_ change: RecordChange) throws -> PreparedRecordUpdate {
        let before: Data?
        do { before = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { before = nil }
        let previous = try decodeRecords(before)
        var updated = previous
        updated[change.packID] = change.record
        return try PreparedRecordUpdate(tracker: self, fileURL: fileURL, before: before,
                                        contents: encodedRecords(updated), previousRecords: previous,
                                        records: updated, writeFile: writeFile)
    }

    func publishCommittedUpdate(_ update: PreparedRecordUpdate) async {
        lastReadableRecords = update.records
        await postChangeNotification()
    }

    func restorePublishedUpdate(_ update: PreparedRecordUpdate) {
        lastReadableRecords = update.previousRecords
    }

    // MARK: - Public API

    /// Return a copy of every installed pack's record.
    public func allInstalled() async -> [InstalledPackRecord] {
        let records = readSnapshot()
        return Array(records.values).sorted(by: { $0.installedAt > $1.installedAt })
    }

    /// Is this pack installed right now?
    public func isInstalled(packID: String) async -> Bool {
        let records = readSnapshot()
        return records[packID] != nil
    }

    /// Return the record for a specific pack, or nil if not installed.
    public func record(for packID: String) async -> InstalledPackRecord? {
        let records = readSnapshot()
        return records[packID]
    }

    /// Returns the installed pack that manages a given collection, or nil.
    public func packManagingCollection(_ collectionID: UUID) async -> (packID: String, packName: String)? {
        let records = readSnapshot()
        // Prefer a pack that manages this collection WITHOUT it being the
        // pack's own associated collection (i.e. a parent pack like Vallack
        // managing Home Row Mods). Fall back to self-managing pack only if
        // no parent is found.
        var selfManaged: (packID: String, packName: String)?
        for (packID, _) in records {
            guard let pack = PackRegistry.pack(id: packID) else { continue }
            if pack.managedCollectionIDs.contains(collectionID) {
                if pack.associatedCollectionID == collectionID {
                    selfManaged = (packID: packID, packName: pack.name)
                } else {
                    return (packID: packID, packName: pack.name)
                }
            }
        }
        return selfManaged
    }

    /// Mark a pack as installed (or update an existing record). Persists.
    public func upsert(_ record: InstalledPackRecord) async throws {
        var records = try readRecords()
        records[record.packID] = record
        try persist(records)
        await postChangeNotification()
    }

    /// Remove an installed-pack record. Persists.
    public func remove(packID: String) async throws {
        var records = try readRecords()
        records.removeValue(forKey: packID)
        try persist(records)
        await postChangeNotification()
    }

    /// Post a foreground notification so observers (e.g. KindaVim mode
    /// monitor) can react to install/uninstall in real time. Hops to the
    /// main actor to keep the post on the main runloop.
    private func postChangeNotification() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .installedPacksChanged, object: nil)
        }
    }

    // MARK: - Persistence

    /// Query APIs refresh every time. An unreadable file retains the last known
    /// committed snapshot; a missing file or a readable replacement supersedes it.
    private func readSnapshot() -> [String: InstalledPackRecord] {
        do {
            let records = try readRecords()
            lastReadableRecords = records
            return records
        } catch {
            AppLogger.shared.log("⚠️ [PackTracker] Could not read installed-packs.json: \(error.localizedDescription)")
            return lastReadableRecords
        }
    }

    /// Writes must fail closed on unreadable metadata. Treat only a missing file
    /// as empty; malformed or inaccessible data must never be silently replaced.
    private func readRecords() throws -> [String: InstalledPackRecord] {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return [:]
        }
        return try decodeRecords(data)
    }

    private func decodeRecords(_ data: Data?) throws -> [String: InstalledPackRecord] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: InstalledPackRecord].self, from: data)
    }

    private func encodedRecords(_ records: [String: InstalledPackRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }

    private func persist(_ records: [String: InstalledPackRecord]) throws {
        // Ensure parent directory exists. (First run creates ~/.config/keypath/.)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )

        let data = try encodedRecords(records)

        try writeFile(data, fileURL)
        lastReadableRecords = records
        AppLogger.shared.log(
            "📦 [PackTracker] Persisted \(records.count) installed pack record(s)"
        )
    }
}
