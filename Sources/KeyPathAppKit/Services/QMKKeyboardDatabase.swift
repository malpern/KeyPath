import Foundation
import KeyPathCore

/// Service for searching and caching QMK keyboard metadata from GitHub
actor QMKKeyboardDatabase {
    static let shared = QMKKeyboardDatabase()

    private var cachedKeyboardList: [KeyboardMetadata]?
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    private let baseURL = "https://api.github.com/repos/qmk/qmk_firmware/contents/keyboards"
    private let rawBaseURL = "https://raw.githubusercontent.com/qmk/qmk_firmware/master/keyboards"

    private init() {}

    /// Load bundled popular keyboards (instant, no network)
    private func loadBundledKeyboards() -> [KeyboardMetadata] {
        guard let url = Bundle.module.url(forResource: "popular-keyboards", withExtension: "json") else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] popular-keyboards.json not found in bundle")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            AppLogger.shared.warn("⚠️ [QMKDatabase] Failed to read popular-keyboards.json")
            return []
        }

        struct BundledKeyboard: Decodable {
            let path: String
            let display_name: String?
            let info: QMKLayoutParser.QMKKeyboardInfo
        }

        struct BundledDatabase: Decodable {
            let version: String
            let keyboards: [BundledKeyboard]
        }

        do {
            let bundle = try JSONDecoder().decode(BundledDatabase.self, from: data)
            let keyboards = bundle.keyboards.compactMap { bundled -> KeyboardMetadata? in
                // Extract directory name from path (last component)
                let directoryName = bundled.path.split(separator: "/").last.map(String.init) ?? bundled.path
                let infoJsonURL = URL(string: "\(rawBaseURL)/\(bundled.path)/info.json")!

                // Use display_name from bundle if available, otherwise derive from info
                let displayName = bundled.display_name ?? bundled.info.name

                return KeyboardMetadata(
                    id: directoryName,
                    name: displayName,
                    manufacturer: bundled.info.manufacturer,
                    url: bundled.info.url,
                    maintainer: bundled.info.maintainer,
                    tags: bundled.info.features?.tags ?? [],
                    infoJsonURL: infoJsonURL
                )
            }
            AppLogger.shared.info("✅ [QMKDatabase] Loaded \(keyboards.count) keyboards from bundle")
            return keyboards
        } catch {
            AppLogger.shared.error("❌ [QMKDatabase] Failed to parse bundled keyboards: \(error.localizedDescription)")
            return []
        }
    }

    /// Refresh the keyboard list from GitHub API
    /// - Returns: Array of keyboard metadata
    /// - Throws: QMKDatabaseError
    func refreshKeyboardList() async throws -> [KeyboardMetadata] {
        AppLogger.shared.info("🔍 [QMKDatabase] Refreshing keyboard list from GitHub...")

        guard let url = URL(string: baseURL) else {
            throw QMKDatabaseError.invalidURL("Invalid GitHub API URL")
        }

        // Fetch keyboard directories
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QMKDatabaseError.networkError("Invalid response type")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw QMKDatabaseError.networkError("HTTP \(httpResponse.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
        }

        // Parse GitHub API response (array of directory entries)
        struct GitHubContent: Decodable {
            let name: String
            let type: String
            let path: String
        }

        let contents: [GitHubContent]
        do {
            contents = try JSONDecoder().decode([GitHubContent].self, from: data)
        } catch {
            throw QMKDatabaseError.parseError("Failed to parse GitHub API response: \(error.localizedDescription)")
        }

        // Filter to directories only
        let keyboardDirs = contents.filter { $0.type == "dir" }
        AppLogger.shared.info("📦 [QMKDatabase] Found \(keyboardDirs.count) keyboard directories")

        // Fetch info.json for each keyboard (with concurrency limit)
        // Limit to first 100 keyboards for initial load (can expand later)
        let maxKeyboards = min(keyboardDirs.count, 100)
        AppLogger.shared.info("📦 [QMKDatabase] Processing first \(maxKeyboards) of \(keyboardDirs.count) keyboards")

        var keyboards: [KeyboardMetadata] = []

        // Process in batches to limit concurrent requests
        let batchSize = 20
        for i in stride(from: 0, to: maxKeyboards, by: batchSize) {
            let batch = Array(keyboardDirs[i ..< min(i + batchSize, maxKeyboards)])

            await withTaskGroup(of: KeyboardMetadata?.self) { group in
                for dir in batch {
                    group.addTask {
                        await self.fetchKeyboardMetadata(directoryName: dir.name, path: dir.path)
                    }
                }

                for await keyboard in group {
                    if let keyboard {
                        keyboards.append(keyboard)
                    }
                }
            }

            // Log progress
            AppLogger.shared.info("📊 [QMKDatabase] Progress: \(keyboards.count)/\(maxKeyboards) keyboards loaded")
        }

        AppLogger.shared.info("✅ [QMKDatabase] Loaded \(keyboards.count) keyboards")

        // Update cache
        cachedKeyboardList = keyboards
        cacheTimestamp = Date()

        return keyboards
    }

    /// Fetch metadata for a single keyboard
    private func fetchKeyboardMetadata(directoryName: String, path: String) async -> KeyboardMetadata? {
        let infoJsonURL = URL(string: "\(rawBaseURL)/\(path)/info.json")!

        do {
            let (data, response) = try await URLSession.shared.data(from: infoJsonURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                return nil // Skip keyboards without valid info.json
            }

            // Parse QMK info.json
            let info: QMKLayoutParser.QMKKeyboardInfo
            do {
                info = try JSONDecoder().decode(QMKLayoutParser.QMKKeyboardInfo.self, from: data)
            } catch {
                AppLogger.shared.debug("⚠️ [QMKDatabase] Failed to parse info.json for \(directoryName): \(error.localizedDescription)")
                return nil
            }

            return KeyboardMetadata(
                directoryName: directoryName,
                info: info,
                infoJsonURL: infoJsonURL
            )
        } catch {
            // Silently skip keyboards that fail to load
            return nil
        }
    }

    /// Get keyboard list: bundled first (instant), then cached, then network
    func getKeyboardList() async throws -> [KeyboardMetadata] {
        // Always start with bundled keyboards (instant)
        var keyboards = loadBundledKeyboards()
        let bundledIds = Set(keyboards.map(\.id))

        // Check cache for additional keyboards
        if let cached = cachedKeyboardList,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheTTL
        {
            // Add network keyboards that aren't in bundle
            let additional = cached.filter { !bundledIds.contains($0.id) }
            keyboards.append(contentsOf: additional)
            AppLogger.shared.info("✅ [QMKDatabase] Using \(keyboards.count) keyboards (\(bundledIds.count) bundled + \(additional.count) cached)")
            return keyboards
        }

        // Refresh from network (adds to bundled list)
        AppLogger.shared.info("🔄 [QMKDatabase] Cache expired, refreshing from network...")
        let networkKeyboards = try await refreshKeyboardList()

        // Combine: bundled + network (deduplicated by ID)
        let additionalNetwork = networkKeyboards.filter { !bundledIds.contains($0.id) }
        keyboards.append(contentsOf: additionalNetwork)

        AppLogger.shared.info("✅ [QMKDatabase] Total: \(keyboards.count) keyboards (\(bundledIds.count) bundled + \(additionalNetwork.count) network)")
        return keyboards
    }

    /// Search keyboards by query (searches name, manufacturer, tags)
    /// Prioritizes bundled keyboards in results
    /// - Parameter query: Search query (case-insensitive)
    /// - Returns: Filtered array of keyboards (bundled first)
    func searchKeyboards(_ query: String) async throws -> [KeyboardMetadata] {
        AppLogger.shared.info("🔍 [QMKDatabase] searchKeyboards called with query: '\(query)'")
        let allKeyboards = try await getKeyboardList()
        let bundledIds = Set(loadBundledKeyboards().map(\.id))
        AppLogger.shared.info("📦 [QMKDatabase] Got \(allKeyboards.count) keyboards (\(bundledIds.count) bundled)")

        guard !query.isEmpty else {
            // Return bundled keyboards first, then others
            let bundled = allKeyboards.filter { bundledIds.contains($0.id) }
            let others = allKeyboards.filter { !bundledIds.contains($0.id) }
            let top50 = Array((bundled + others).prefix(50))
            AppLogger.shared.info("📦 [QMKDatabase] Empty query, returning top \(top50.count) keyboards (\(bundled.count) bundled)")
            return top50
        }

        let lowerQuery = query.lowercased()
        let matching = allKeyboards.filter { keyboard in
            keyboard.name.lowercased().contains(lowerQuery) ||
                keyboard.manufacturer?.lowercased().contains(lowerQuery) == true ||
                keyboard.tags.contains { $0.lowercased().contains(lowerQuery) }
        }

        // Prioritize bundled keyboards
        let bundledMatches = matching.filter { bundledIds.contains($0.id) }
        let otherMatches = matching.filter { !bundledIds.contains($0.id) }
        let filtered = Array((bundledMatches + otherMatches).prefix(50))

        AppLogger.shared.info("✅ [QMKDatabase] Filtered to \(filtered.count) keyboards matching '\(query)' (\(bundledMatches.count) bundled)")
        return filtered
    }

    /// Invalidate the cache (force refresh on next request)
    func invalidateCache() {
        cachedKeyboardList = nil
        cacheTimestamp = nil
    }
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
