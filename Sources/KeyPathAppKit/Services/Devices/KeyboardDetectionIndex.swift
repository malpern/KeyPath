import Foundation
import KeyPathCore

/// Looks up known keyboards by USB Vendor ID and Product ID using a normalized
/// detection index generated from VIA, QMK, and local overrides.
enum KeyboardDetectionIndex {
    enum MatchType: String, Codable, Sendable, Equatable {
        case exactVIDPID
        case vendorOnly
    }

    enum Source: String, Codable, Sendable, Equatable {
        case override
        case via
        case qmk
    }

    enum Confidence: String, Codable, Sendable, Equatable {
        case high
        case low
    }

    struct Record: Codable, Sendable, Equatable {
        let matchKey: String
        let matchType: MatchType
        let source: Source
        let confidence: Confidence
        let displayName: String
        let manufacturer: String?
        let qmkPath: String?
        let builtInLayoutId: String?
    }

    struct Match: Sendable, Equatable {
        let record: Record
        let matchType: MatchType
    }

    private struct IndexFile: Codable {
        let version: String
        let generated: String
        let exactEntries: [Record]
        let vendorFallbackEntries: [Record]
    }

    private struct Cache: Sendable {
        let exactEntries: [String: Record]
        let vendorFallbackEntries: [String: Record]
    }

    nonisolated(unsafe) private static var cached: Cache?

    #if DEBUG
        nonisolated(unsafe) private static var seededExactEntries: [Record]?
        nonisolated(unsafe) private static var seededVendorFallbackEntries: [Record]?

        static func seedIndex(exactEntries: [Record], vendorFallbackEntries: [Record] = []) {
            seededExactEntries = exactEntries
            seededVendorFallbackEntries = vendorFallbackEntries
            cached = nil
        }

        static func resetCache() {
            cached = nil
            seededExactEntries = nil
            seededVendorFallbackEntries = nil
        }
    #endif

    static func lookup(vendorID: Int, productID: Int) -> Match? {
        let cache = loadCache()
        guard !cache.exactEntries.isEmpty || !cache.vendorFallbackEntries.isEmpty else {
            return nil
        }

        let vidPidKey = formatKey(vendorID: vendorID, productID: productID)
        if let record = cache.exactEntries[vidPidKey] {
            return Match(record: record, matchType: .exactVIDPID)
        }

        let vidKey = formatVIDKey(vendorID: vendorID)
        if let record = cache.vendorFallbackEntries[vidKey] {
            return Match(record: record, matchType: .vendorOnly)
        }

        return nil
    }

    static func formatKey(vendorID: Int, productID: Int) -> String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    static func formatVIDKey(vendorID: Int) -> String {
        String(format: "%04X", vendorID)
    }

    private static func loadCache() -> Cache {
        if let cached { return cached }

        #if DEBUG
            if let seededExactEntries {
                let cache = Cache(
                    exactEntries: Dictionary(uniqueKeysWithValues: seededExactEntries.map { ($0.matchKey, $0) }),
                    vendorFallbackEntries: Dictionary(uniqueKeysWithValues: (seededVendorFallbackEntries ?? []).map { ($0.matchKey, $0) })
                )
                cached = cache
                return cache
            }
        #endif

        guard let url = KeyPathAppKitResources.url(forResource: "keyboard-detection-index", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] keyboard-detection-index.json not found in bundle")
            let empty = Cache(exactEntries: [:], vendorFallbackEntries: [:])
            cached = empty
            return empty
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(IndexFile.self, from: data)
            let cache = Cache(
                exactEntries: Dictionary(uniqueKeysWithValues: file.exactEntries.map { ($0.matchKey, $0) }),
                vendorFallbackEntries: Dictionary(uniqueKeysWithValues: file.vendorFallbackEntries.map { ($0.matchKey, $0) })
            )
            cached = cache
            AppLogger.shared.log(
                "🔌 [KeyboardDetectionIndex] Loaded \(file.exactEntries.count) exact and \(file.vendorFallbackEntries.count) vendor fallback entries (v\(file.version))"
            )
            return cache
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Failed to load keyboard-detection-index.json: \(error)")
            let empty = Cache(exactEntries: [:], vendorFallbackEntries: [:])
            cached = empty
            return empty
        }
    }
}
