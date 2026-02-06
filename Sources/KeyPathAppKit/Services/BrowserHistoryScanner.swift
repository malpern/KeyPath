import Foundation
import SQLite3

/// Scans browser history databases to suggest frequently visited websites.
///
/// **Privacy Note**: This feature is opt-in only. Data is processed locally
/// and never transmitted. Requires Full Disk Access permission to read
/// browser history databases.
actor BrowserHistoryScanner {
    /// Supported browsers and their history database locations
    enum Browser: String, CaseIterable, Sendable {
        case safari
        case chrome
        case firefox
        case arc
        case brave
        case edge
        case dia

        var displayName: String {
            switch self {
            case .safari: "Safari"
            case .chrome: "Google Chrome"
            case .firefox: "Firefox"
            case .arc: "Arc"
            case .brave: "Brave"
            case .edge: "Microsoft Edge"
            case .dia: "Dia"
            }
        }

        var historyPath: String {
            let home = NSHomeDirectory()
            switch self {
            case .safari:
                return "\(home)/Library/Safari/History.db"
            case .chrome:
                return "\(home)/Library/Application Support/Google/Chrome/Default/History"
            case .firefox:
                // Firefox uses profile directories with random names
                return "\(home)/Library/Application Support/Firefox/Profiles"
            case .arc:
                return "\(home)/Library/Application Support/Arc/User Data/Default/History"
            case .brave:
                return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"
            case .edge:
                return "\(home)/Library/Application Support/Microsoft Edge/Default/History"
            case .dia:
                return "\(home)/Library/Application Support/Dia/User Data/Default/History"
            }
        }

        var chromiumBasePath: String? {
            let home = NSHomeDirectory()
            switch self {
            case .chrome:
                return "\(home)/Library/Application Support/Google/Chrome"
            case .arc:
                return "\(home)/Library/Application Support/Arc/User Data"
            case .brave:
                return "\(home)/Library/Application Support/BraveSoftware/Brave-Browser"
            case .edge:
                return "\(home)/Library/Application Support/Microsoft Edge"
            case .dia:
                return "\(home)/Library/Application Support/Dia/User Data"
            case .safari, .firefox:
                return nil
            }
        }

        var isInstalled: Bool {
            if self == .firefox {
                // Firefox profile directory check
                return FileManager.default.fileExists(atPath: historyPath)
            }
            if isChromiumBased, let basePath = chromiumBasePath {
                return FileManager.default.fileExists(atPath: basePath)
            }
            return FileManager.default.fileExists(atPath: historyPath)
        }

        var isChromiumBased: Bool {
            switch self {
            case .chrome, .arc, .brave, .edge, .dia:
                true
            case .safari, .firefox:
                false
            }
        }
    }

    /// A visited website with aggregated statistics
    struct VisitedSite: Identifiable, Sendable {
        let id = UUID()
        let domain: String
        let visitCount: Int
        let lastVisited: Date?
    }

    /// Shared instance
    static let shared = BrowserHistoryScanner()

    private init() {}

    /// Check if Full Disk Access is granted (required to read browser history)
    func hasFullDiskAccess() async -> Bool {
        // Try multiple protected paths - don't assume any specific browser is installed
        let testPaths = [
            "\(NSHomeDirectory())/Library/Safari/History.db",
            "\(NSHomeDirectory())/Library/Mail",
            "\(NSHomeDirectory())/Library/Messages",
            "\(NSHomeDirectory())/Library/Cookies"
        ]
        return testPaths.contains { FileManager.default.isReadableFile(atPath: $0) }
    }

    /// Get installed browsers that can be scanned
    func installedBrowsers() -> [Browser] {
        Browser.allCases.filter(\.isInstalled)
    }

    /// Scan browser history and return top visited domains
    ///
    /// - Parameters:
    ///   - browsers: Browsers to scan (defaults to all installed)
    ///   - limit: Maximum number of domains to return
    /// - Returns: Array of visited sites sorted by visit count
    func scanHistory(browsers: [Browser]? = nil, limit: Int = 20) async throws -> [VisitedSite] {
        let browsersToScan = browsers ?? installedBrowsers()

        var allDomains: [String: (count: Int, lastVisit: Date?)] = [:]
        var didScan = false
        var encounteredError: Error?

        for browser in browsersToScan {
            guard browser.isInstalled else { continue }

            do {
                let sites = try await scanBrowser(browser)
                didScan = true
                for site in sites {
                    let existing = allDomains[site.domain]
                    let newCount = (existing?.count ?? 0) + site.visitCount
                    let newLastVisit = max(existing?.lastVisit, site.lastVisited)
                    allDomains[site.domain] = (count: newCount, lastVisit: newLastVisit)
                }
            } catch {
                // Continue with other browsers if one fails
                if encounteredError == nil {
                    encounteredError = error
                }
                continue
            }
        }

        if !didScan, let encounteredError {
            throw encounteredError
        }

        // Convert to array and sort by visit count
        return allDomains.map { domain, data in
            VisitedSite(domain: domain, visitCount: data.count, lastVisited: data.lastVisit)
        }
        .sorted { $0.visitCount > $1.visitCount }
        .prefix(limit)
        .map { $0 }
    }

    /// Scan a single browser's history
    private func scanBrowser(_ browser: Browser) async throws -> [VisitedSite] {
        switch browser {
        case .safari:
            return try scanSafari()
        case .firefox:
            return try scanFirefox()
        default:
            // Chromium-based browsers
            guard let basePath = browser.chromiumBasePath else {
                return []
            }
            return try scanChromiumProfiles(basePath: basePath, fallbackHistoryPath: browser.historyPath)
        }
    }

    // MARK: - Safari

    private func scanSafari() throws -> [VisitedSite] {
        let dbPath = Browser.safari.historyPath

        // Safari keeps database locked, so we need to copy it first
        let tempPath = NSTemporaryDirectory() + "safari_history_\(UUID().uuidString).db"
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ScanError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT
            domain,
            COUNT(*) as visit_count,
            MAX(visit_time) as last_visit
        FROM (
            SELECT
                SUBSTR(url, INSTR(url, '://') + 3,
                       CASE WHEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') > 0
                            THEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') - 1
                            ELSE LENGTH(SUBSTR(url, INSTR(url, '://') + 3))
                       END) as domain,
                visit_time
            FROM history_visits
            JOIN history_items ON history_visits.history_item = history_items.id
            WHERE history_items.url LIKE 'http%'
        )
        WHERE domain IS NOT NULL AND domain != ''
        GROUP BY domain
        ORDER BY visit_count DESC
        LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ScanError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var results: [VisitedSite] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let domainCString = sqlite3_column_text(statement, 0) else { continue }
            let domain = normalizeDomain(String(cString: domainCString))
            let count = Int(sqlite3_column_int(statement, 1))
            let lastVisit = safariTimestampToDate(sqlite3_column_double(statement, 2))

            if !domain.isEmpty {
                results.append(VisitedSite(domain: domain, visitCount: count, lastVisited: lastVisit))
            }
        }

        return results
    }

    // MARK: - Chromium (Chrome, Arc, Brave, Edge, Dia)

    private func scanChromiumProfiles(basePath: String, fallbackHistoryPath: String) throws -> [VisitedSite] {
        let historyPaths = chromiumHistoryPaths(basePath: basePath, fallbackHistoryPath: fallbackHistoryPath)
        guard !historyPaths.isEmpty else {
            throw ScanError.profileNotFound
        }

        var allDomains: [String: (count: Int, lastVisit: Date?)] = [:]
        for path in historyPaths {
            let sites = try scanChromium(path: path)
            for site in sites {
                let existing = allDomains[site.domain]
                let newCount = (existing?.count ?? 0) + site.visitCount
                let newLastVisit = max(existing?.lastVisit, site.lastVisited)
                allDomains[site.domain] = (count: newCount, lastVisit: newLastVisit)
            }
        }

        return allDomains.map { domain, data in
            VisitedSite(domain: domain, visitCount: data.count, lastVisited: data.lastVisit)
        }
        .sorted { $0.visitCount > $1.visitCount }
    }

    private func scanChromium(path: String) throws -> [VisitedSite] {
        // Chromium also keeps database locked
        let tempPath = NSTemporaryDirectory() + "chromium_history_\(UUID().uuidString).db"
        try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ScanError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT
            domain,
            SUM(visit_count) as total_visits,
            MAX(last_visit_time) as last_visit
        FROM (
            SELECT
                SUBSTR(url, INSTR(url, '://') + 3,
                       CASE WHEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') > 0
                            THEN INSTR(SUBSTR(url, INSTR(url, '://') + 3), '/') - 1
                            ELSE LENGTH(SUBSTR(url, INSTR(url, '://') + 3))
                       END) as domain,
                visit_count,
                last_visit_time
            FROM urls
            WHERE url LIKE 'http%'
        )
        WHERE domain IS NOT NULL AND domain != ''
        GROUP BY domain
        ORDER BY total_visits DESC
        LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ScanError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var results: [VisitedSite] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let domainCString = sqlite3_column_text(statement, 0) else { continue }
            let domain = normalizeDomain(String(cString: domainCString))
            let count = Int(sqlite3_column_int(statement, 1))
            let lastVisit = chromiumTimestampToDate(sqlite3_column_int64(statement, 2))

            if !domain.isEmpty {
                results.append(VisitedSite(domain: domain, visitCount: count, lastVisited: lastVisit))
            }
        }

        return results
    }

    // MARK: - Firefox

    private func scanFirefox() throws -> [VisitedSite] {
        let profilesPath = Browser.firefox.historyPath
        let profileDirs = firefoxProfilePaths(at: profilesPath)
        guard !profileDirs.isEmpty else {
            throw ScanError.profileNotFound
        }

        var allDomains: [String: (count: Int, lastVisit: Date?)] = [:]
        for profileDir in profileDirs {
            let sites = try scanFirefoxProfile(at: profileDir)
            for site in sites {
                let existing = allDomains[site.domain]
                let newCount = (existing?.count ?? 0) + site.visitCount
                let newLastVisit = max(existing?.lastVisit, site.lastVisited)
                allDomains[site.domain] = (count: newCount, lastVisit: newLastVisit)
            }
        }

        return allDomains.map { domain, data in
            VisitedSite(domain: domain, visitCount: data.count, lastVisited: data.lastVisit)
        }
        .sorted { $0.visitCount > $1.visitCount }
    }

    private func scanFirefoxProfile(at profileDir: String) throws -> [VisitedSite] {
        let dbPath = "\(profileDir)/places.sqlite"
        let tempPath = NSTemporaryDirectory() + "firefox_history_\(UUID().uuidString).db"
        try FileManager.default.copyItem(atPath: dbPath, toPath: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ScanError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        // Firefox stores reversed hostnames, so we need to reverse them back
        let query = """
        SELECT
            rev_host,
            SUM(visit_count) as total_visits,
            MAX(last_visit_date) as last_visit
        FROM moz_places
        WHERE rev_host IS NOT NULL AND rev_host != ''
          AND url LIKE 'http%'
        GROUP BY rev_host
        ORDER BY total_visits DESC
        LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ScanError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var results: [VisitedSite] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let revHostCString = sqlite3_column_text(statement, 0) else { continue }
            let revHost = String(cString: revHostCString)
            let domain = normalizeDomain(reverseFirefoxHost(revHost))
            let count = Int(sqlite3_column_int(statement, 1))
            let lastVisit = firefoxTimestampToDate(sqlite3_column_int64(statement, 2))

            if !domain.isEmpty {
                results.append(VisitedSite(domain: domain, visitCount: count, lastVisited: lastVisit))
            }
        }

        return results
    }

    /// Find Firefox profile directories (supports multiple profiles).
    private func firefoxProfilePaths(at profilesPath: String) -> [String] {
        let iniPath = "\(profilesPath)/profiles.ini"
        if let contents = try? String(contentsOfFile: iniPath, encoding: .utf8) {
            let lines = contents.split(whereSeparator: \.isNewline)
            var profiles: [String] = []
            var currentPath: String?
            var isRelative = true

            func commitProfile() {
                guard let currentPath else { return }
                let fullPath = isRelative ? "\(profilesPath)/\(currentPath)" : currentPath
                if FileManager.default.fileExists(atPath: "\(fullPath)/places.sqlite") {
                    profiles.append(fullPath)
                }
            }

            for line in lines {
                if line.hasPrefix("[Profile") {
                    commitProfile()
                    currentPath = nil
                    isRelative = true
                    continue
                }

                if line.hasPrefix("Path=") {
                    currentPath = line.replacingOccurrences(of: "Path=", with: "")
                    continue
                }

                if line.hasPrefix("IsRelative=") {
                    let value = line.replacingOccurrences(of: "IsRelative=", with: "")
                    isRelative = value == "1"
                }
            }

            commitProfile()

            if !profiles.isEmpty {
                return profiles
            }
        }

        return fallbackFirefoxProfilePaths(at: profilesPath)
    }

    /// Fallback: scan for .default and .default-release profiles.
    private func fallbackFirefoxProfilePaths(at profilesPath: String) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: profilesPath) else {
            return []
        }

        // Look for directories ending in .default or .default-release
        var results: [String] = []
        for dir in contents {
            if dir.hasSuffix(".default-release") || dir.hasSuffix(".default") {
                let fullPath = "\(profilesPath)/\(dir)"
                if fm.fileExists(atPath: "\(fullPath)/places.sqlite") {
                    results.append(fullPath)
                }
            }
        }

        return results
    }

    private func chromiumHistoryPaths(basePath: String, fallbackHistoryPath: String) -> [String] {
        var historyPaths: [String] = []
        let localStatePath = "\(basePath)/Local State"

        if let data = try? Data(contentsOf: URL(fileURLWithPath: localStatePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profile = json["profile"] as? [String: Any],
           let infoCache = profile["info_cache"] as? [String: Any] {
            for profileDir in infoCache.keys.sorted() {
                let path = "\(basePath)/\(profileDir)/History"
                if FileManager.default.fileExists(atPath: path) {
                    historyPaths.append(path)
                }
            }
        }

        if historyPaths.isEmpty {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath) {
                let candidateDirs = contents.filter { $0 == "Default" || $0.hasPrefix("Profile ") }
                for dir in candidateDirs {
                    let path = "\(basePath)/\(dir)/History"
                    if FileManager.default.fileExists(atPath: path) {
                        historyPaths.append(path)
                    }
                }
            }
        }

        if historyPaths.isEmpty, FileManager.default.fileExists(atPath: fallbackHistoryPath) {
            historyPaths.append(fallbackHistoryPath)
        }

        return historyPaths
    }

    /// Reverse a Firefox reversed hostname (e.g., "moc.elgoog." -> "google.com")
    private func reverseFirefoxHost(_ revHost: String) -> String {
        var host = String(revHost.reversed())
        // Firefox adds a trailing dot
        if host.hasPrefix(".") {
            host = String(host.dropFirst())
        }
        return host
    }

    // MARK: - Helpers

    /// Normalize a domain (remove www., convert to lowercase)
    private func normalizeDomain(_ domain: String) -> String {
        var normalized = domain.lowercased()
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        // Remove any auth info (user:pass@)
        if let atIndex = normalized.firstIndex(of: "@") {
            normalized = String(normalized[normalized.index(after: atIndex)...])
        }
        // Remove port if present
        if let colonIndex = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colonIndex])
        }
        return normalized
    }

    /// Convert Safari timestamp to Date (Core Data / Cocoa epoch)
    private func safariTimestampToDate(_ timestamp: Double) -> Date? {
        guard timestamp > 0 else { return nil }
        // Safari uses Core Data timestamp (seconds since 2001-01-01)
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }

    /// Convert Chromium timestamp to Date (microseconds since 1601-01-01)
    private func chromiumTimestampToDate(_ timestamp: Int64) -> Date? {
        guard timestamp > 0 else { return nil }
        // Chromium uses microseconds since Windows epoch (1601-01-01)
        let windowsEpochOffset: Int64 = 11_644_473_600_000_000 // microseconds
        let unixMicroseconds = timestamp - windowsEpochOffset
        return Date(timeIntervalSince1970: Double(unixMicroseconds) / 1_000_000)
    }

    /// Convert Firefox timestamp to Date (microseconds since Unix epoch)
    private func firefoxTimestampToDate(_ timestamp: Int64) -> Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1_000_000)
    }

    /// Compare two optional dates, returning the later one
    private func max(_ a: Date?, _ b: Date?) -> Date? {
        guard let a else { return b }
        guard let b else { return a }
        return a > b ? a : b
    }

    // MARK: - Errors

    enum ScanError: Error, LocalizedError {
        case databaseOpenFailed
        case queryFailed
        case profileNotFound
        case fullDiskAccessRequired

        var errorDescription: String? {
            switch self {
            case .databaseOpenFailed:
                "Failed to open browser history database"
            case .queryFailed:
                "Failed to query browser history"
            case .profileNotFound:
                "Could not find browser profile"
            case .fullDiskAccessRequired:
                "Full Disk Access permission is required to read browser history"
            }
        }
    }
}
