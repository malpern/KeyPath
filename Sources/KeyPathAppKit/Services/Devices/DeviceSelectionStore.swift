import Foundation
import KeyPathCore

/// Persisted selection state for a single device.
struct DeviceSelection: Codable, Sendable {
    let hash: String
    let productKey: String
    var isEnabled: Bool
    var lastSeen: Date

    /// Cleaned-up product name for display, matching `ConnectedDevice.displayName`.
    var displayName: String {
        DeviceDisplayNameFormatter.format(productKey)
    }
}

/// Thread-safe synchronous cache for device selections and connected devices,
/// used by the config generator. The generator runs synchronously and cannot
/// await actor methods, so it reads from this cache.
final class DeviceSelectionCache: @unchecked Sendable {
    static let shared = DeviceSelectionCache()

    private let lock = NSLock()
    // Lock protects all mutable state in this cache. Callers must use the public methods only.
    private var selections: [String: DeviceSelection] = [:]
    private var connectedDevices: [ConnectedDevice] = []

    /// Update the cache with the latest selections from the store.
    func update(_ newSelections: [DeviceSelection]) {
        lock.lock()
        defer { lock.unlock() }
        selections = Dictionary(newSelections.map { ($0.hash, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// Update the cached connected device list (from kanata --list).
    func updateConnectedDevices(_ devices: [ConnectedDevice]) {
        lock.lock()
        defer { lock.unlock() }
        connectedDevices = devices
    }

    /// Get the cached connected devices. Returns empty if never populated.
    func getConnectedDevices() -> [ConnectedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return connectedDevices
    }

    /// Check if a device hash is enabled. Devices not in the cache default to enabled.
    func isEnabled(hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return selections[hash]?.isEnabled ?? true
    }

    /// Get all cached selections.
    func allSelections() -> [DeviceSelection] {
        lock.lock()
        defer { lock.unlock() }
        return Array(selections.values)
    }

    /// Reset all cached state. Used in tests to avoid pollution.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        selections = [:]
        connectedDevices = []
    }
}

/// Actor-based store for device selection persistence.
/// File: `~/.config/keypath/DeviceSelection.json`
actor DeviceSelectionStore {
    static let shared = DeviceSelectionStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL
    private let fileManager: FileManager
    private let cache: DeviceSelectionCache

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = Foundation.FileManager(),
        cache: DeviceSelectionCache = .shared
    ) {
        self.fileManager = fileManager
        self.cache = cache
        let defaultDirectory = URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory, isDirectory: true
        )
        self.fileURL = fileURL ?? defaultDirectory.appendingPathComponent("DeviceSelection.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSelections() -> [DeviceSelection] {
        AppLogger.shared.log("📂 [DeviceSelectionStore] loadSelections from: \(fileURL.path)")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            AppLogger.shared.log("📂 [DeviceSelectionStore] File does not exist, returning []")
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let selections = try decoder.decode([DeviceSelection].self, from: data)
            AppLogger.shared.log("📂 [DeviceSelectionStore] Loaded \(selections.count) device selection(s)")
            return selections
        } catch {
            AppLogger.shared.log("⚠️ [DeviceSelectionStore] Failed to load selections: \(error)")
            return []
        }
    }

    func saveSelections(_ selections: [DeviceSelection]) throws {
        AppLogger.shared.log("💾 [DeviceSelectionStore] saveSelections: \(selections.count) device(s) to \(fileURL.path)")
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(selections)
        try data.write(to: fileURL, options: .atomic)
        // Sync to cache for synchronous config generator reads
        cache.update(selections)
        AppLogger.shared.log("💾 [DeviceSelectionStore] Saved \(data.count) bytes")
    }

    /// Load selections and sync to cache. Call at startup.
    func syncToCache() {
        let selections = loadSelections()
        cache.update(selections)
    }

    /// Synchronously prime the shared cache before startup tasks can regenerate config.
    static func primeSharedCacheFromDisk(fileURL: URL? = nil) {
        let fileURL = fileURL ?? URL(
            fileURLWithPath: WizardSystemPaths.userConfigDirectory,
            isDirectory: true
        ).appendingPathComponent("DeviceSelection.json")

        let fileManager = Foundation.FileManager()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            DeviceSelectionCache.shared.update([])
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: fileURL)
            let selections = try decoder.decode([DeviceSelection].self, from: data)
            DeviceSelectionCache.shared.update(selections)
            AppLogger.shared.log("📂 [DeviceSelectionStore] Primed shared cache with \(selections.count) device selection(s)")
        } catch {
            DeviceSelectionCache.shared.update([])
            AppLogger.shared.warn("⚠️ [DeviceSelectionStore] Failed to prime shared cache: \(error)")
        }
    }
}

#if DEBUG
    extension DeviceSelectionStore {
        nonisolated static func testStore(
            at url: URL,
            cache: DeviceSelectionCache = DeviceSelectionCache()
        ) -> DeviceSelectionStore {
            DeviceSelectionStore(fileURL: url, cache: cache)
        }
    }
#endif
