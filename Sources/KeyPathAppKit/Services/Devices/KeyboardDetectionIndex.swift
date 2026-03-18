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
    }

    private struct IndexFile: Codable {
        let version: String
        let generated: String
        let exactEntries: [Record]
        let vendorFallbackEntries: [Record]
    }

    private struct OverridesFile: Codable {
        struct OverrideExactEntry: Codable {
            let vendorId: String
            let productId: String
            let displayName: String
            let qmkPath: String?
            let builtInLayoutId: String?
        }

        let version: String
        let exactEntries: [OverrideExactEntry]
    }

    private struct Cache: Sendable {
        let exactEntries: [String: Record]
        let vendorFallbackEntries: [String: Record]
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: Cache?

    #if DEBUG
        nonisolated(unsafe) private static var seededExactEntries: [Record]?
        nonisolated(unsafe) private static var seededVendorFallbackEntries: [Record]?

        static func seedIndex(exactEntries: [Record], vendorFallbackEntries: [Record] = []) {
            cacheLock.lock()
            defer { cacheLock.unlock() }
            seededExactEntries = exactEntries
            seededVendorFallbackEntries = vendorFallbackEntries
            cached = nil
        }

        static func resetCache() {
            cacheLock.lock()
            defer { cacheLock.unlock() }
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
            return Match(record: record)
        }

        let vidKey = formatVIDKey(vendorID: vendorID)
        if let record = cache.vendorFallbackEntries[vidKey] {
            return Match(record: record)
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
        cacheLock.lock()
        defer { cacheLock.unlock() }

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
            let overrideEntries = loadOverrideEntries()
            var exactEntries = Dictionary(uniqueKeysWithValues: file.exactEntries.map { ($0.matchKey, $0) })
            for overrideEntry in overrideEntries {
                exactEntries[overrideEntry.matchKey] = overrideEntry
            }
            let cache = Cache(
                exactEntries: exactEntries,
                vendorFallbackEntries: Dictionary(uniqueKeysWithValues: file.vendorFallbackEntries.map { ($0.matchKey, $0) })
            )
            cached = cache
            AppLogger.shared.log(
                "🔌 [KeyboardDetectionIndex] Loaded \(exactEntries.count) exact and \(file.vendorFallbackEntries.count) vendor fallback entries (v\(file.version))"
            )
            return cache
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Failed to load keyboard-detection-index.json: \(error)")
            let empty = Cache(exactEntries: [:], vendorFallbackEntries: [:])
            cached = empty
            return empty
        }
    }

    private static func loadOverrideEntries() -> [Record] {
        guard let url = KeyPathAppKitResources.url(forResource: "keyboard-detection-overrides", withExtension: "json") else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(OverridesFile.self, from: data)
            return file.exactEntries.compactMap { entry in
                guard let vendorID = parseHex(entry.vendorId),
                      let productID = parseHex(entry.productId)
                else {
                    AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Skipping invalid override entry \(entry.vendorId):\(entry.productId)")
                    return nil
                }

                return Record(
                    matchKey: formatKey(vendorID: vendorID, productID: productID),
                    matchType: .exactVIDPID,
                    source: .override,
                    confidence: .high,
                    displayName: entry.displayName,
                    manufacturer: nil,
                    qmkPath: entry.qmkPath,
                    builtInLayoutId: entry.builtInLayoutId
                )
            }
        } catch {
            AppLogger.shared.warn("⚠️ [KeyboardDetectionIndex] Failed to load keyboard-detection-overrides.json: \(error)")
            return []
        }
    }

    private static func parseHex(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        return Int(normalized, radix: 16)
    }
}
