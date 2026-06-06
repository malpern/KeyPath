import Foundation
import KeyPathAppKit
import KeyPathCore

enum UpdateChecker {
    private static let cacheFile: String = {
        "\(KeyPathConstants.Config.directory)/.update-check"
    }()

    private static let checkInterval: TimeInterval = 86400 // 24 hours

    struct CachedResult: Codable {
        let checkedAt: Date
        let latestVersion: String?
    }

    static func checkOnce() async -> String? {
        if let cached = loadCache(), Date().timeIntervalSince(cached.checkedAt) < checkInterval {
            return nudgeIfNewer(cached.latestVersion)
        }

        let latest = await fetchLatestVersion()
        saveCache(CachedResult(checkedAt: Date(), latestVersion: latest))
        return nudgeIfNewer(latest)
    }

    private static func nudgeIfNewer(_ latest: String?) -> String? {
        guard let latest else { return nil }
        let current = CLIVersion.current
        if compareVersions(latest, isNewerThan: current) {
            return latest
        }
        return nil
    }

    private static func fetchLatestVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/malpern/KeyPath/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else { return nil }

        struct Release: Decodable { let tag_name: String }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }

        return release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst())
            : release.tag_name
    }

    static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let aParts = a.split(separator: "-", maxSplits: 1)
        let bParts = b.split(separator: "-", maxSplits: 1)
        let aNumbers = aParts[0].split(separator: ".").compactMap { Int($0) }
        let bNumbers = bParts[0].split(separator: ".").compactMap { Int($0) }

        for i in 0 ..< max(aNumbers.count, bNumbers.count) {
            let aNum = i < aNumbers.count ? aNumbers[i] : 0
            let bNum = i < bNumbers.count ? bNumbers[i] : 0
            if aNum > bNum { return true }
            if aNum < bNum { return false }
        }

        // Same numeric version — check pre-release suffix
        // No suffix beats any suffix (1.0.0 > 1.0.0-beta3)
        if aParts.count == 1, bParts.count > 1 { return true }

        return false
    }

    private static func loadCache() -> CachedResult? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cacheFile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedResult.self, from: data)
    }

    private static func saveCache(_ result: CachedResult) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result) else { return }
        let dir = (cacheFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: cacheFile), options: .atomic)
    }
}
