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

    /// Maximum number of retry attempts for rate-limited requests
    private let maxRetryAttempts = 3

    private init() {}

    // MARK: - Rate Limit Handling

    /// Check if an HTTP response indicates a GitHub API rate limit
    /// - Returns: The reset timestamp if rate-limited, nil otherwise
    private func rateLimitResetDate(from response: HTTPURLResponse) -> Date? {
        guard response.statusCode == 403 || response.statusCode == 429 else {
            return nil
        }

        // Check X-RateLimit-Remaining header
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remainingCount = Int(remaining), remainingCount > 0
        {
            return nil // Not rate-limited, some other 403 reason
        }

        // Parse X-RateLimit-Reset header (Unix timestamp)
        if let resetString = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = TimeInterval(resetString)
        {
            return Date(timeIntervalSince1970: resetTimestamp)
        }

        // No reset header, use a default backoff of 60 seconds
        return Date(timeIntervalSinceNow: 60)
    }

    /// Perform a URL request with retry and exponential backoff for rate limits
    /// - Parameters:
    ///   - url: The URL to fetch
    ///   - attempt: Current attempt number (0-based)
    /// - Returns: Tuple of data and HTTP response
    /// - Throws: QMKDatabaseError if all retries are exhausted
    private func fetchWithRateLimitRetry(url: URL, attempt: Int = 0) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QMKDatabaseError.networkError("Invalid response type")
        }

        // Check for rate limiting
        if let resetDate = rateLimitResetDate(from: httpResponse) {
            let waitSeconds = max(resetDate.timeIntervalSinceNow, 1)

            if attempt >= maxRetryAttempts {
                AppLogger.shared.warn("⚠️ [QMKDatabase] Rate limit exceeded after \(maxRetryAttempts) retries, giving up")
                throw QMKDatabaseError.rateLimited(retryAfter: resetDate)
            }

            // Wait until the rate-limit window resets, capped at 120 seconds
            let backoff = min(waitSeconds, 120)
            AppLogger.shared.info("⏳ [QMKDatabase] Rate limited (attempt \(attempt + 1)/\(maxRetryAttempts)). Waiting \(String(format: "%.1f", backoff))s until reset")

            try await Task.sleep(for: .seconds(backoff))

            return try await fetchWithRateLimitRetry(url: url, attempt: attempt + 1)
        }

        return (data, httpResponse)
    }

    // MARK: - Bundled Keyboards

    /// Load bundled popular keyboards (instant, no network)
    private func loadBundledKeyboards() -> [KeyboardMetadata] {
        guard let url = KeyPathAppKitResources.url(forResource: "popular-keyboards", withExtension: "json") else {
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

    // MARK: - Network Refresh

    /// Refresh the keyboard list from GitHub API
    /// - Returns: Array of keyboard metadata
    /// - Throws: QMKDatabaseError
    func refreshKeyboardList() async throws -> [KeyboardMetadata] {
        AppLogger.shared.info("🔍 [QMKDatabase] Refreshing keyboard list from GitHub...")

        guard let url = URL(string: baseURL) else {
            throw QMKDatabaseError.invalidURL("Invalid GitHub API URL")
        }

        // Fetch keyboard directories with rate limit retry
        let (data, httpResponse): (Data, HTTPURLResponse)
        do {
            (data, httpResponse) = try await fetchWithRateLimitRetry(url: url)
        } catch let error as QMKDatabaseError {
            if case .rateLimited = error {
                AppLogger.shared.warn("⚠️ [QMKDatabase] Rate limited during refresh, falling back to bundled/cached keyboards")
                return cachedKeyboardList ?? loadBundledKeyboards()
            }
            throw error
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

    // MARK: - Keyboard List Access

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
        do {
            let networkKeyboards = try await refreshKeyboardList()

            // Combine: bundled + network (deduplicated by ID)
            let additionalNetwork = networkKeyboards.filter { !bundledIds.contains($0.id) }
            keyboards.append(contentsOf: additionalNetwork)

            AppLogger.shared.info("✅ [QMKDatabase] Total: \(keyboards.count) keyboards (\(bundledIds.count) bundled + \(additionalNetwork.count) network)")
        } catch {
            // Gracefully degrade: if network fails, return bundled keyboards
            AppLogger.shared.warn("⚠️ [QMKDatabase] Network refresh failed, using bundled keyboards only: \(error.localizedDescription)")
        }

        return keyboards
    }

    // MARK: - Search

    /// Search keyboards by query (searches name, manufacturer, tags)
    /// Also includes matching custom layouts from CustomLayoutStore
    /// Prioritizes bundled keyboards in results
    /// - Parameter query: Search query (case-insensitive)
    /// - Returns: Filtered array of keyboards (custom layouts first, then bundled, then others)
    func searchKeyboards(_ query: String) async throws -> [KeyboardMetadata] {
        AppLogger.shared.info("🔍 [QMKDatabase] searchKeyboards called with query: '\(query)'")
        let allKeyboards = try await getKeyboardList()
        let bundledIds = Set(loadBundledKeyboards().map(\.id))

        // Load custom layouts and convert to KeyboardMetadata for unified search
        let customLayouts = CustomLayoutStore.load().layouts
        let customMetadata: [KeyboardMetadata] = customLayouts.compactMap { stored in
            KeyboardMetadata(
                id: "custom-\(stored.id)",
                name: stored.name,
                manufacturer: nil,
                url: stored.sourceURL,
                maintainer: nil,
                tags: ["custom"],
                infoJsonURL: stored.sourceURL.flatMap { URL(string: $0) }
            )
        }

        AppLogger.shared.info("📦 [QMKDatabase] Got \(allKeyboards.count) keyboards (\(bundledIds.count) bundled) + \(customMetadata.count) custom layouts")

        guard !query.isEmpty else {
            // Return custom layouts first, then bundled keyboards, then others
            let bundled = allKeyboards.filter { bundledIds.contains($0.id) }
            let others = allKeyboards.filter { !bundledIds.contains($0.id) }
            let combined = customMetadata + bundled + others
            let top50 = Array(combined.prefix(50))
            AppLogger.shared.info("📦 [QMKDatabase] Empty query, returning top \(top50.count) keyboards (\(customMetadata.count) custom, \(bundled.count) bundled)")
            return top50
        }

        let lowerQuery = query.lowercased()

        // Search custom layouts
        let matchingCustom = customMetadata.filter { layout in
            layout.name.lowercased().contains(lowerQuery)
        }

        // Search QMK keyboards
        let matchingQMK = allKeyboards.filter { keyboard in
            keyboard.name.lowercased().contains(lowerQuery) ||
                keyboard.manufacturer?.lowercased().contains(lowerQuery) == true ||
                keyboard.tags.contains { $0.lowercased().contains(lowerQuery) }
        }

        // Prioritize: custom matches, then bundled matches, then other matches
        let bundledMatches = matchingQMK.filter { bundledIds.contains($0.id) }
        let otherMatches = matchingQMK.filter { !bundledIds.contains($0.id) }
        let filtered = Array((matchingCustom + bundledMatches + otherMatches).prefix(50))

        AppLogger.shared.info("✅ [QMKDatabase] Filtered to \(filtered.count) keyboards matching '\(query)' (\(matchingCustom.count) custom, \(bundledMatches.count) bundled)")
        return filtered
    }

    /// Invalidate the cache (force refresh on next request)
    func invalidateCache() {
        cachedKeyboardList = nil
        cacheTimestamp = nil
    }

    /// Seed the cache with pre-loaded keyboards (for testing or offline use).
    /// Prevents network calls from `getKeyboardList()` until the cache expires.
    func seedCache(with keyboards: [KeyboardMetadata]) {
        cachedKeyboardList = keyboards
        cacheTimestamp = Date()
    }
}

/// Errors for QMK keyboard database operations
enum QMKDatabaseError: LocalizedError {
    case invalidURL(String)
    case networkError(String)
    case parseError(String)
    case rateLimited(retryAfter: Date)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(message):
            "Invalid URL: \(message)"
        case let .networkError(message):
            "Network error: \(message)"
        case let .parseError(message):
            "Parse error: \(message)"
        case let .rateLimited(retryAfter):
            "GitHub API rate limit exceeded. Resets at \(retryAfter.formatted())"
        }
    }
}
