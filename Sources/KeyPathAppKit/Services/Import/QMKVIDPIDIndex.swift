import Foundation
import KeyPathCore

/// Looks up QMK keyboard paths by USB Vendor ID and Product ID.
///
/// Uses a bundled `qmk-vid-pid-index.json` that maps VID:PID pairs to QMK keyboard paths.
/// Supports exact VID:PID match and vendor-only fallback.
enum QMKVIDPIDIndex {
    enum MatchType: Sendable, Equatable {
        case exactVIDPID
        case vidOnly
    }

    struct Match: Sendable {
        let keyboardPaths: [String]
        let matchType: MatchType
    }

    // MARK: - Index Structure

    private struct IndexFile: Codable {
        let version: String
        let generated: String
        let entries: [String: [String]]
    }

    // MARK: - Cached Index

    // Single-threaded access (called from MainActor context via lookup or tests)
    nonisolated(unsafe) private static var cachedEntries: [String: [String]]?

    /// For testing: inject index entries directly
    #if DEBUG
        nonisolated(unsafe) static var seededEntries: [String: [String]]?

        static func resetCache() {
            cachedEntries = nil
            seededEntries = nil
        }
    #endif

    // MARK: - Lookup

    /// Look up QMK keyboard paths for a given vendor/product ID pair.
    /// Tries exact VID:PID first, falls back to VID-only.
    static func lookup(vendorID: Int, productID: Int) -> Match? {
        let entries = loadEntries()
        guard !entries.isEmpty else { return nil }

        let vidPidKey = formatKey(vendorID: vendorID, productID: productID)
        if let paths = entries[vidPidKey], !paths.isEmpty {
            return Match(keyboardPaths: paths, matchType: .exactVIDPID)
        }

        let vidKey = formatVIDKey(vendorID: vendorID)
        if let paths = entries[vidKey], !paths.isEmpty {
            return Match(keyboardPaths: paths, matchType: .vidOnly)
        }

        return nil
    }

    // MARK: - Key Formatting

    /// Format a VID:PID lookup key, e.g. "4653:0001"
    static func formatKey(vendorID: Int, productID: Int) -> String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    /// Format a VID-only lookup key, e.g. "4653"
    static func formatVIDKey(vendorID: Int) -> String {
        String(format: "%04X", vendorID)
    }

    // MARK: - Loading

    private static func loadEntries() -> [String: [String]] {
        if let cached = cachedEntries { return cached }

        #if DEBUG
            if let seeded = seededEntries {
                cachedEntries = seeded
                return seeded
            }
        #endif

        guard let url = KeyPathAppKitResources.url(forResource: "qmk-vid-pid-index", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [QMKVIDPIDIndex] qmk-vid-pid-index.json not found in bundle")
            cachedEntries = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let indexFile = try JSONDecoder().decode(IndexFile.self, from: data)
            cachedEntries = indexFile.entries
            AppLogger.shared.log("🔌 [QMKVIDPIDIndex] Loaded \(indexFile.entries.count) VID:PID entries (v\(indexFile.version))")
            return indexFile.entries
        } catch {
            AppLogger.shared.warn("⚠️ [QMKVIDPIDIndex] Failed to load VID:PID index: \(error)")
            cachedEntries = [:]
            return [:]
        }
    }
}
