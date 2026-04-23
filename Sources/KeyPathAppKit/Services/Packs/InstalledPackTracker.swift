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
    private var records: [String: InstalledPackRecord] = [:]
    private var hasLoaded = false

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // ~/.config/keypath/installed-packs.json
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("keypath", isDirectory: true)
                .appendingPathComponent("installed-packs.json")
        }
    }

    // MARK: - Public API

    /// Return a copy of every installed pack's record.
    public func allInstalled() async -> [InstalledPackRecord] {
        await ensureLoaded()
        return Array(records.values).sorted(by: { $0.installedAt > $1.installedAt })
    }

    /// Is this pack installed right now?
    public func isInstalled(packID: String) async -> Bool {
        await ensureLoaded()
        return records[packID] != nil
    }

    /// Return the record for a specific pack, or nil if not installed.
    public func record(for packID: String) async -> InstalledPackRecord? {
        await ensureLoaded()
        return records[packID]
    }

    /// Mark a pack as installed (or update an existing record). Persists.
    public func upsert(_ record: InstalledPackRecord) async throws {
        await ensureLoaded()
        records[record.packID] = record
        try persist()
    }

    /// Remove an installed-pack record. Persists.
    public func remove(packID: String) async throws {
        await ensureLoaded()
        records.removeValue(forKey: packID)
        try persist()
    }

    // MARK: - Persistence

    private func ensureLoaded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([String: InstalledPackRecord].self, from: data)
            records = decoded
            AppLogger.shared.log(
                "📦 [PackTracker] Loaded \(records.count) installed pack record(s)"
            )
        } catch {
            AppLogger.shared.log(
                "⚠️ [PackTracker] Failed to load installed-packs.json: \(error.localizedDescription). Starting fresh."
            )
            records = [:]
        }
    }

    private func persist() throws {
        // Ensure parent directory exists. (First run creates ~/.config/keypath/.)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)

        try data.write(to: fileURL, options: [.atomic])
        AppLogger.shared.log(
            "📦 [PackTracker] Persisted \(records.count) installed pack record(s)"
        )
    }
}
