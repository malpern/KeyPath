import Foundation
import KeyPathCore

/// Service for searching QMK keyboards using a bundled index of 3,700+ keyboards.
///
/// Architecture:
/// - **Search**: Instant, local-only. Uses a bundled `qmk-keyboard-index.json` (77KB)
///   containing all QMK keyboard paths, plus `qmk-keyboard-metadata.json` (~400KB)
///   with human-readable names and manufacturers. No network calls during search.
/// - **Ranking**: Prefix matches on vendor/board name score highest, word-boundary
///   matches next, substring matches lowest. Bundled keyboards always first.
/// - **Bundled popular keyboards**: `popular-keyboards.json` contains ~18 curated keyboards
///   with full layout data inline. These are prioritized in search results.
/// - **On-demand fetch**: When a user selects a keyboard from search results, the full
///   `info.json` is fetched from `keyboards.qmk.fm` and cached to disk.
/// - **Disk cache**: Fetched layouts are stored in `~/Library/Caches/KeyPath/qmk/`
///   to avoid re-downloading.
actor QMKKeyboardDatabase {
    static let shared = QMKKeyboardDatabase()

    /// QMK API base URL for fetching individual keyboard info
    private let qmkAPIBase = "https://keyboards.qmk.fm/v1/keyboards"

    /// URLSession with 15-second timeout for QMK API and GitHub fetches.
    /// Shorter than the 60s default to fail fast and fall back to alternative strategies.
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// Bundled index: all QMK keyboard paths (loaded once from qmk-keyboard-index.json)
    private var indexEntries: [IndexEntry]?

    /// Metadata lookup: keyboard_name and manufacturer from qmk-keyboard-metadata.json
    private var metadataLookup: [String: KeyboardMeta]?

    /// Bundled popular keyboards with full layout data
    private var bundledKeyboards: [KeyboardMetadata]?

    /// Bundled keyboard layout JSON data by path (avoids network fetch for popular keyboards)
    private var bundledKeyboardData: [String: Data] = [:]

    /// Set of bundled keyboard IDs for quick lookup
    private var bundledIds: Set<String> = []

    /// QMK paths that map to built-in PhysicalLayout IDs.
    /// When a search result matches one of these, selecting it activates the
    /// built-in layout directly instead of importing from QMK.
    static let qmkToBuiltInLayout: [String: String] = [
        // Corne (crkbd) variants
        "crkbd": "corne",
        "crkbd/rev1": "corne",
        "crkbd/r2g": "corne",
        "crkbd/rev4_0/standard": "corne",
        "crkbd/rev4_1/standard": "corne",
        // Sofle variants
        "sofle": "sofle",
        "sofle/rev1": "sofle",
        "sofle/keyhive": "sofle",
        // Ferris Sweep
        "ferris/sweep": "ferris-sweep",
        // HHKB variants
        "hhkb": "hhkb",
        "hhkb/ansi/32u2": "hhkb",
        "hhkb/ansi/32u4": "hhkb",
        "hhkb/yang": "hhkb",
    ]

    /// Disk cache directory for fetched keyboard layouts
    private let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("KeyPath/qmk", isDirectory: true)
    }()

    /// For test injection: override the full search index
    private var seededIndex: [IndexEntry]?

    /// For test injection: override metadata
    private var seededMetadata: [String: KeyboardMeta]?

    private init() {}

    // MARK: - Types

    /// Lightweight entry from the QMK keyboard index (path only, no layout data)
    struct IndexEntry: Sendable {
        /// Full QMK path (e.g., "crkbd/rev1", "mode/m65s", "keychron/q1/ansi")
        let path: String

        /// Path components split for matching (e.g., ["crkbd", "rev1"])
        let components: [String]

        /// First path component (vendor/brand, e.g., "crkbd", "mode", "keychron")
        let vendor: String

        init(path: String) {
            self.path = path
            components = path.split(separator: "/").map(String.init)
            vendor = components.first ?? path
        }
    }

    /// Compact metadata from the bundled metadata index
    struct KeyboardMeta: Sendable {
        let name: String? // e.g., "Corne", "GMMK Pro ANSI"
        let manufacturer: String? // e.g., "foostan", "Glorious"
    }

    // MARK: - Index Loading

    /// Load the bundled QMK keyboard index (3,700+ paths, ~77KB)
    private func loadIndex() -> [IndexEntry] {
        if let cached = indexEntries { return cached }
        if let seeded = seededIndex { return seeded }

        guard let url = KeyPathAppKitResources.url(forResource: "qmk-keyboard-index", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] qmk-keyboard-index.json not found in bundle")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] Failed to read qmk-keyboard-index.json")
            return []
        }

        struct QMKIndex: Decodable {
            let keyboards: [String]
        }

        do {
            let index = try JSONDecoder().decode(QMKIndex.self, from: data)
            let entries = index.keyboards.map { IndexEntry(path: $0) }
            indexEntries = entries
            AppLogger.shared.info("✅ [QMKDatabase] Loaded \(entries.count) keyboards from bundled index")
            return entries
        } catch {
            AppLogger.shared.error("❌ [QMKDatabase] Failed to parse keyboard index: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Metadata Loading

    /// Load the bundled metadata index (keyboard_name + manufacturer for all keyboards)
    private func loadMetadata() -> [String: KeyboardMeta] {
        if let cached = metadataLookup { return cached }
        if let seeded = seededMetadata { return seeded }

        guard let url = KeyPathAppKitResources.url(forResource: "qmk-keyboard-metadata", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] qmk-keyboard-metadata.json not found in bundle")
            return [:]
        }

        guard let data = try? Data(contentsOf: url) else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] Failed to read qmk-keyboard-metadata.json")
            return [:]
        }

        // Compact format: {"keyboards": {"path": {"n": "name", "m": "manufacturer"}}}
        struct MetadataIndex: Decodable {
            let keyboards: [String: MetadataEntry]
        }
        struct MetadataEntry: Decodable {
            let n: String? // keyboard_name
            let m: String? // manufacturer
        }

        do {
            let index = try JSONDecoder().decode(MetadataIndex.self, from: data)
            let lookup = index.keyboards.reduce(into: [String: KeyboardMeta]()) { result, pair in
                result[pair.key] = KeyboardMeta(name: pair.value.n, manufacturer: pair.value.m)
            }
            metadataLookup = lookup
            AppLogger.shared.info("✅ [QMKDatabase] Loaded metadata for \(lookup.count) keyboards")
            return lookup
        } catch {
            AppLogger.shared.error("❌ [QMKDatabase] Failed to parse keyboard metadata: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Build a display name for an index entry using metadata + smart formatting fallback
    private func displayName(for entry: IndexEntry, meta: KeyboardMeta?) -> String {
        // If metadata has a real keyboard_name that differs from the path, use it
        if let name = meta?.name, !name.isEmpty {
            let pathDerived = entry.components.last ?? entry.path
            // Only use the metadata name if it adds value over the path
            if name.lowercased() != pathDerived.lowercased() {
                return name
            }
        }

        // Smart path formatting: capitalize components, filter noise
        return Self.formatPath(entry.components)
    }

    /// Format path components into a readable display name.
    /// Filters out revision/variant noise and capitalizes meaningfully.
    static func formatPath(_ components: [String]) -> String {
        // Filter out pure revision components when there's a meaningful name
        let meaningful = components.filter { component in
            let lower = component.lowercased()
            // Keep the component if it's not just a revision/variant marker
            let isRevision = lower.hasPrefix("rev") && lower.count <= 6
            let isVersion = lower.hasPrefix("v") && lower.dropFirst().allSatisfy(\.isNumber)
            let isMicrocontroller = ["promicro", "elite_c", "rp2040", "splinky_3", "stemcell"].contains(lower)
            return !isRevision && !isVersion && !isMicrocontroller
        }

        return (meaningful.isEmpty ? components : meaningful)
            .map { component in
                // Capitalize first letter, preserve rest (handles "ErgoDox", "GMMK" etc.)
                if component == component.lowercased() {
                    return component.prefix(1).uppercased() + component.dropFirst()
                }
                return component
            }
            .joined(separator: " ")
    }

    // MARK: - Bundled Popular Keyboards

    /// Load bundled popular keyboards with full layout data (instant, no network)
    private func loadBundledKeyboards() -> [KeyboardMetadata] {
        if let cached = bundledKeyboards { return cached }

        guard let url = KeyPathAppKitResources.url(forResource: "popular-keyboards", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] popular-keyboards.json not found in bundle")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] Failed to read popular-keyboards.json")
            return []
        }

        struct BundledKeyboardInfo: Decodable {
            let manufacturer: String?
            let url: String?
            let maintainer: String?
            let features: QMKLayoutParser.QMKFeatures?
        }

        struct BundledKeyboard: Decodable {
            let path: String
            let display_name: String?
            let info: BundledKeyboardInfo
        }

        struct BundledDatabase: Decodable {
            let version: String
            let keyboards: [BundledKeyboard]
        }

        do {
            let bundle = try JSONDecoder().decode(BundledDatabase.self, from: data)

            // Also parse with JSONSerialization to extract full info objects (preserves layouts)
            let rawJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let rawKeyboards = rawJSON?["keyboards"] as? [[String: Any]] ?? []

            let keyboards = bundle.keyboards.enumerated().compactMap { index, bundled -> KeyboardMetadata? in
                let displayName = bundled.display_name ?? bundled.path
                let apiURL = URL(string: "\(qmkAPIBase)/\(bundled.path)/info.json")

                // Cache the full info JSON so fetchKeyboardData can use it without network
                if index < rawKeyboards.count,
                   let infoObj = rawKeyboards[index]["info"],
                   let infoData = try? JSONSerialization.data(withJSONObject: infoObj)
                {
                    bundledKeyboardData[bundled.path] = infoData
                }

                return KeyboardMetadata(
                    id: bundled.path,
                    name: displayName,
                    manufacturer: bundled.info.manufacturer,
                    url: bundled.info.url,
                    maintainer: bundled.info.maintainer,
                    tags: bundled.info.features?.tags ?? [],
                    infoJsonURL: apiURL,
                    isBundled: true,
                    builtInLayoutId: Self.qmkToBuiltInLayout[bundled.path]
                )
            }
            bundledKeyboards = keyboards
            bundledIds = Set(keyboards.map(\.id))
            AppLogger.shared.info("✅ [QMKDatabase] Loaded \(keyboards.count) bundled popular keyboards")
            return keyboards
        } catch {
            AppLogger.shared.error("❌ [QMKDatabase] Failed to parse bundled keyboards: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Search

    /// Search keyboards by query. Purely local — no network calls.
    /// Results are ranked: prefix matches on vendor/name score highest.
    /// Bundled keyboards (with full layout data) are prioritized in results.
    ///
    /// - Parameter query: Search query (case-insensitive)
    /// - Returns: Array of matching keyboards (bundled first, ranked by relevance, max 50)
    func searchKeyboards(_ query: String) async throws -> [KeyboardMetadata] {
        let bundled = loadBundledKeyboards()
        let index = loadIndex()
        let metadata = loadMetadata()

        guard !query.isEmpty else {
            // Empty query: return bundled keyboards only (they have curated names/metadata)
            return Array(bundled.prefix(50))
        }

        let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        let queryWords = lowerQuery.split(separator: " ").map(String.init)

        // 1. Score and filter bundled keyboards
        let scoredBundled: [(KeyboardMetadata, Int)] = bundled.compactMap { keyboard in
            let score = Self.multiWordScore(
                words: queryWords,
                name: keyboard.name.lowercased(),
                id: keyboard.id.lowercased(),
                manufacturer: keyboard.manufacturer?.lowercased()
            )
            return score > 0 ? (keyboard, score + 1000) : nil // +1000 to always rank bundled first
        }

        // 2. Score and filter index entries (excluding bundled)
        let bundledPaths = bundledIds
        let scoredIndex: [(KeyboardMetadata, Int)] = index.compactMap { entry in
            guard !bundledPaths.contains(entry.path) else { return nil }

            let meta = metadata[entry.path]
            let name = displayName(for: entry, meta: meta)
            let searchName = (meta?.name ?? name).lowercased()
            let searchMfg = meta?.manufacturer?.lowercased()

            let score = Self.multiWordScore(
                words: queryWords,
                name: searchName,
                id: entry.path.lowercased(),
                manufacturer: searchMfg
            )
            guard score > 0 else { return nil }

            let kb = KeyboardMetadata(
                id: entry.path,
                name: name,
                manufacturer: meta?.manufacturer ?? Self.formatPath([entry.vendor]),
                infoJsonURL: URL(string: "\(qmkAPIBase)/\(entry.path)/info.json"),
                isBundled: false,
                builtInLayoutId: Self.qmkToBuiltInLayout[entry.path]
            )
            return (kb, score)
        }

        // 3. Combine, sort by score descending, deduplicate by display name, cap at 50
        let allScored = scoredBundled + scoredIndex
        let sorted = allScored.sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        var results: [KeyboardMetadata] = []
        for (keyboard, _) in sorted {
            let key = "\(keyboard.name.lowercased())|\(keyboard.manufacturer?.lowercased() ?? "")"
            if seen.insert(key).inserted {
                results.append(keyboard)
                if results.count >= 50 { break }
            }
        }
        return results
    }

    /// Score a keyboard against a search query. Returns 0 for no match.
    ///
    /// Scoring:
    /// - Exact match on any path component: 100
    /// - Prefix match on vendor or board name: 80
    /// - Word-boundary match (query at start of a slash-separated segment): 60
    /// - Substring match on name or manufacturer: 40
    /// - Substring match on full path: 20
    static func searchScore(query: String, name: String, id: String, manufacturer: String?) -> Int {
        let pathComponents = id.split(separator: "/").map { $0.lowercased() }

        // Exact match on any component
        if pathComponents.contains(where: { $0 == query }) {
            return 100
        }

        // Prefix match on any component
        if pathComponents.contains(where: { $0.hasPrefix(query) }) {
            return 80
        }

        // Name contains query (metadata name like "Corne", "GMMK Pro ANSI")
        if name.hasPrefix(query) {
            return 75
        }
        if name.contains(query) {
            return 50
        }

        // Manufacturer match
        if let mfg = manufacturer {
            if mfg.hasPrefix(query) { return 70 }
            if mfg.contains(query) { return 45 }
        }

        // Substring match on full path
        if id.contains(query) {
            return 20
        }

        return 0
    }

    /// Score a keyboard against a multi-word query. All words must match somewhere.
    /// The final score is the minimum per-word score (weakest link), so results
    /// that match all words well rank highest.
    static func multiWordScore(words: [String], name: String, id: String, manufacturer: String?) -> Int {
        guard !words.isEmpty else { return 0 }

        // Single word: delegate directly
        if words.count == 1 {
            return searchScore(query: words[0], name: name, id: id, manufacturer: manufacturer)
        }

        // Multi-word: every word must match, take minimum score
        var minScore = Int.max
        for word in words {
            let score = searchScore(query: word, name: name, id: id, manufacturer: manufacturer)
            if score == 0 { return 0 } // All words must match
            minScore = min(minScore, score)
        }
        return minScore
    }

    // MARK: - On-Demand Fetch

    /// Fetch the full keyboard info.json for a specific keyboard.
    /// Checks disk cache first, then fetches from QMK API.
    /// The QMK API wraps data in `{"keyboards": {"path": {<info>}}}`.
    ///
    /// - Parameter keyboard: The keyboard metadata (must have a valid infoJsonURL)
    /// - Returns: Raw JSON data suitable for QMKLayoutParser
    /// - Throws: QMKDatabaseError on network or parse failure
    func fetchKeyboardData(_ keyboard: KeyboardMetadata) async throws -> Data {
        // Check bundled data first (popular keyboards have full layout data inline)
        if keyboard.isBundled {
            // Ensure bundled data is loaded
            _ = loadBundledKeyboards()
            if let bundled = bundledKeyboardData[keyboard.id] {
                AppLogger.shared.info("✅ [QMKDatabase] Using bundled data for '\(keyboard.id)'")
                return bundled
            }
        }

        // Check disk cache first
        if let cached = readFromDiskCache(keyboardPath: keyboard.id) {
            AppLogger.shared.info("✅ [QMKDatabase] Cache hit for '\(keyboard.id)'")
            return cached
        }

        guard let infoURL = keyboard.infoJsonURL else {
            throw QMKDatabaseError.invalidURL("Keyboard '\(keyboard.id)' has no info URL")
        }

        AppLogger.shared.info("🌐 [QMKDatabase] Fetching '\(keyboard.id)' from QMK API...")

        let (data, response) = try await urlSession.data(from: infoURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw QMKDatabaseError.networkError("HTTP \(code) fetching \(keyboard.id)")
        }

        // QMK API wraps data: {"keyboards": {"path": {<info>}}, "last_updated": "..."}
        // We need to unwrap to just the inner keyboard object for our parser.
        let unwrapped = try unwrapQMKAPIResponse(data, keyboardPath: keyboard.id)

        // Cache to disk
        writeToDiskCache(keyboardPath: keyboard.id, data: unwrapped)

        return unwrapped
    }

    // MARK: - QMK API Response Unwrapping

    /// Unwrap QMK API response from `{"keyboards": {"path": {...}}}` to just the inner object.
    /// The inner object is what our QMKLayoutParser expects (has `layouts`, `keyboard_name`, etc.).
    private func unwrapQMKAPIResponse(_ data: Data, keyboardPath: String) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyboards = json["keyboards"] as? [String: Any]
        else {
            // Not wrapped — might be raw info.json from GitHub, return as-is
            return data
        }

        // Find the keyboard entry — try exact path match first, then first entry
        let keyboardData: Any
        if let exact = keyboards[keyboardPath] {
            keyboardData = exact
        } else if let first = keyboards.values.first {
            keyboardData = first
        } else {
            throw QMKDatabaseError.parseError("No keyboard data found in QMK API response for '\(keyboardPath)'")
        }

        return try JSONSerialization.data(withJSONObject: keyboardData)
    }

    // MARK: - Disk Cache

    private func cacheFilePath(for keyboardPath: String) -> URL {
        // Replace slashes with dashes for flat cache directory
        let safeName = keyboardPath.replacingOccurrences(of: "/", with: "--")
        return cacheDirectory.appendingPathComponent("\(safeName).json")
    }

    private func readFromDiskCache(keyboardPath: String) -> Data? {
        let path = cacheFilePath(for: keyboardPath)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try? Data(contentsOf: path)
    }

    private func writeToDiskCache(keyboardPath: String, data: Data) {
        let path = cacheFilePath(for: keyboardPath)
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
            AppLogger.shared.debug("💾 [QMKDatabase] Cached '\(keyboardPath)' to disk")
        } catch {
            AppLogger.shared.debug("⚠️ [QMKDatabase] Failed to cache '\(keyboardPath)': \(error.localizedDescription)")
        }
    }

    private func deleteFromDiskCache(keyboardPath: String) {
        let path = cacheFilePath(for: keyboardPath)
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - Default Keymap Fetch

    /// Fetch the default keymap for a keyboard from the QMK firmware GitHub repo.
    /// Tries keymap.c first, then keymap.json as fallback.
    /// parseBaseLayer handles both C and JSON formats.
    /// Returns the parsed base layer keycodes, or nil if fetch/parse fails.
    /// This is a best-effort operation — failure is expected for some keyboards.
    /// Note: only tries the canonical `keymaps/default/` path. Keyboards without
    /// this folder (e.g. via-only boards) will return nil and fall back to position-based parsing.
    func fetchDefaultKeymap(keyboardPath: String) async -> [String]? {
        // Check disk cache first (keymap files are cached separately with a "-keymap" suffix)
        let cacheKey = "\(keyboardPath)-keymap"
        if let cached = readFromDiskCache(keyboardPath: cacheKey),
           let source = String(data: cached, encoding: .utf8),
           let keycodes = QMKKeymapParser.parseBaseLayer(from: source)
        {
            return keycodes
        }

        // Try fetching keymap files from GitHub — keymap.c first, then keymap.json as fallback
        let baseURL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"
        let keymapFiles = ["keymap.c", "keymap.json"]

        for keymapFile in keymapFiles {
            guard let url = URL(string: "\(baseURL)/\(keyboardPath)/keymaps/default/\(keymapFile)") else {
                continue
            }

            do {
                let (data, response) = try await urlSession.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else { continue }

                if httpResponse.statusCode == 429 {
                    AppLogger.shared.info("⚠️ [QMKDatabase] GitHub rate limited fetching keymap for '\(keyboardPath)' — falling back to position-based parsing")
                    return nil
                }

                guard httpResponse.statusCode == 200,
                      let source = String(data: data, encoding: .utf8),
                      let keycodes = QMKKeymapParser.parseBaseLayer(from: source)
                else {
                    continue // Try next file format
                }

                // Cache the raw keymap for future use
                writeToDiskCache(keyboardPath: cacheKey, data: data)
                return keycodes
            } catch {
                AppLogger.shared.debug("⚠️ [QMKDatabase] Failed to fetch \(keymapFile) for '\(keyboardPath)': \(error.localizedDescription)")
                continue // Try next file format
            }
        }

        return nil
    }

    /// Invalidate the cached keymap for a specific keyboard path, forcing a fresh fetch.
    func invalidateKeymapCache(keyboardPath: String) {
        let cacheKey = "\(keyboardPath)-keymap"
        deleteFromDiskCache(keyboardPath: cacheKey)
    }

    // MARK: - Cache Management

    /// Invalidate the in-memory caches (force reload on next request)
    func invalidateCache() {
        indexEntries = nil
        metadataLookup = nil
        bundledKeyboards = nil
        bundledIds = []
    }

    /// Clear the disk cache of fetched keyboard layouts
    func clearDiskCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        AppLogger.shared.info("🗑️ [QMKDatabase] Disk cache cleared")
    }

    #if DEBUG
        /// Seed the index with test data (prevents loading from bundle)
        func seedIndex(with entries: [IndexEntry]) {
            seededIndex = entries
            indexEntries = nil
        }

        /// Seed metadata for testing
        func seedMetadata(with metadata: [String: KeyboardMeta]) {
            seededMetadata = metadata
            metadataLookup = nil
        }

        /// Seed bundled keyboards for testing
        func seedBundledKeyboards(with keyboards: [KeyboardMetadata]) {
            bundledKeyboards = keyboards
            bundledIds = Set(keyboards.map(\.id))
        }

        /// Legacy compatibility: seed the cache so old tests continue to pass
        func seedCache(with keyboards: [KeyboardMetadata]) {
            bundledKeyboards = keyboards
            bundledIds = Set(keyboards.map(\.id))
        }
    #endif
}

/// Errors for QMK keyboard database operations
enum QMKDatabaseError: LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(message):
            "Invalid URL: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        case let .parseError(message):
            "Parse error: \(message)"
        }
    }
}
