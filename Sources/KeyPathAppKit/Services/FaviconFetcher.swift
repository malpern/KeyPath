import AppKit
import Foundation
import KeyPathCore

/// Service for fetching and caching website favicons
///
/// Features:
/// - Automatic favicon fetching from URLs
/// - Two-tier caching (memory + disk) for fast loading
/// - Graceful fallback to nil on fetch failures
/// - Prevents duplicate concurrent fetches
@MainActor
final class FaviconFetcher {
    static let shared = FaviconFetcher()

    // MARK: - Cache Configuration

    /// Directory where favicons are cached on disk
    private let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let faviconDir = appSupport.appendingPathComponent("KeyPath/Favicons", isDirectory: true)
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: faviconDir, withIntermediateDirectories: true)
        return faviconDir
    }()

    /// In-memory cache for instant access
    private var memoryCache: [String: NSImage] = [:]

    /// Track in-progress fetches to prevent duplicates
    private var pendingFetches: [String: Task<NSImage?, Never>] = [:]

    /// Timeout for network requests (3 seconds)
    private let networkTimeout: TimeInterval = 3.0

    // MARK: - Public API

    /// Fetch favicon for a URL (returns cached if available)
    /// - Parameter url: The URL to fetch favicon for (e.g., "github.com", "https://example.com")
    /// - Returns: NSImage if favicon found, nil if fetch failed or URL invalid
    func fetchFavicon(for url: String) async -> NSImage? {
        let domain = extractDomain(from: url)

        // 1. Check memory cache first (instant)
        if let cached = memoryCache[domain] {
            AppLogger.shared.debug("🖼️ [FaviconFetcher] Memory cache HIT for \(domain)")
            return cached
        }

        // 2. Check disk cache (fast, ~1ms)
        if let diskCached = loadFromDiskCache(domain: domain) {
            AppLogger.shared.debug("🖼️ [FaviconFetcher] Disk cache HIT for \(domain)")
            memoryCache[domain] = diskCached
            return diskCached
        }

        // 3. Check if fetch is already in progress
        if let existingTask = pendingFetches[domain] {
            AppLogger.shared.debug("🖼️ [FaviconFetcher] Waiting for existing fetch of \(domain)")
            return await existingTask.value
        }

        // 4. Start new fetch
        let fetchTask = Task<NSImage?, Never> {
            await performFetch(for: domain, fullURL: url)
        }

        pendingFetches[domain] = fetchTask
        let result = await fetchTask.value
        pendingFetches[domain] = nil

        return result
    }

    /// Clear all cached favicons (memory + disk)
    func clearCache() {
        memoryCache.removeAll()

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try? FileManager.default.removeItem(at: fileURL)
            }
            AppLogger.shared.log("🧹 [FaviconFetcher] Cleared all favicon cache")
        } catch {
            AppLogger.shared.error("❌ [FaviconFetcher] Failed to clear disk cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Extract domain from URL (e.g., "github.com" from "https://github.com/user/repo")
    private func extractDomain(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return cleaned.components(separatedBy: "/").first ?? url
    }

    /// Perform actual network fetch for favicon
    private func performFetch(for domain: String, fullURL: String) async -> NSImage? {
        AppLogger.shared.debug("🌐 [FaviconFetcher] Fetching favicon for \(domain)")

        // Try strategy 1: /favicon.ico (most common)
        if let image = await fetchFaviconDirect(domain: domain) {
            cacheImage(image, forDomain: domain)
            return image
        }

        // Try strategy 2: Parse HTML for <link rel="icon"> (fallback)
        if let image = await fetchFaviconFromHTML(url: fullURL) {
            cacheImage(image, forDomain: domain)
            return image
        }

        // Failed to fetch - cache the failure to avoid repeated attempts
        AppLogger.shared.log("⚠️ [FaviconFetcher] Failed to fetch favicon for \(domain)")
        return nil
    }

    /// Strategy 1: Try to fetch /favicon.ico directly
    private func fetchFaviconDirect(domain: String) async -> NSImage? {
        guard let url = URL(string: "https://\(domain)/favicon.ico") else {
            return nil
        }

        return await fetchImage(from: url)
    }

    /// Strategy 2: Parse HTML to find <link rel="icon"> or <link rel="shortcut icon">
    private func fetchFaviconFromHTML(url: String) async -> NSImage? {
        // Ensure URL has scheme
        let fullURL: String = if url.hasPrefix("http://") || url.hasPrefix("https://") {
            url
        } else {
            "https://\(url)"
        }

        guard let htmlURL = URL(string: fullURL) else {
            return nil
        }

        // Fetch HTML
        var request = URLRequest(url: htmlURL, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse for favicon link (very basic regex parsing)
            // Pattern: <link rel="icon" href="..." or <link rel="shortcut icon" href="..."
            let pattern = #"<link[^>]*rel=["\'](?:shortcut )?icon["\'][^>]*href=["\']([^"\']+)["\']"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let hrefRange = Range(match.range(at: 1), in: html)
            {
                let iconPath = String(html[hrefRange])

                // Resolve relative URLs
                let iconURL: URL? = if iconPath.hasPrefix("http://") || iconPath.hasPrefix("https://") {
                    URL(string: iconPath)
                } else if iconPath.hasPrefix("/") {
                    // Absolute path
                    htmlURL.deletingLastPathComponent().appendingPathComponent(iconPath)
                } else {
                    // Relative path
                    htmlURL.deletingLastPathComponent().appendingPathComponent(iconPath)
                }

                if let iconURL {
                    return await fetchImage(from: iconURL)
                }
            }
        } catch {
            AppLogger.shared.debug("🌐 [FaviconFetcher] HTML fetch failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Fetch image from URL with timeout
    private func fetchImage(from url: URL) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200
            {
                AppLogger.shared.debug("🌐 [FaviconFetcher] HTTP \(httpResponse.statusCode) for \(url)")
                return nil
            }

            // Try to create image
            if let image = NSImage(data: data) {
                // Resize to standard size (32x32)
                image.size = NSSize(width: 32, height: 32)
                return image
            }
        } catch {
            AppLogger.shared.debug("🌐 [FaviconFetcher] Network error: \(error.localizedDescription)")
        }

        return nil
    }

    /// Cache image in memory and disk
    private func cacheImage(_ image: NSImage, forDomain domain: String) {
        // Memory cache
        memoryCache[domain] = image

        // Disk cache
        saveToDiskCache(image: image, domain: domain)

        AppLogger.shared.debug("💾 [FaviconFetcher] Cached favicon for \(domain)")
    }

    /// Save image to disk cache as PNG
    private func saveToDiskCache(image: NSImage, domain: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(domain).png")

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            AppLogger.shared.error("❌ [FaviconFetcher] Failed to convert image to PNG for \(domain)")
            return
        }

        do {
            try pngData.write(to: fileURL)
        } catch {
            AppLogger.shared.error("❌ [FaviconFetcher] Failed to save to disk: \(error.localizedDescription)")
        }
    }

    /// Load image from disk cache
    private func loadFromDiskCache(domain: String) -> NSImage? {
        let fileURL = cacheDirectory.appendingPathComponent("\(domain).png")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return NSImage(contentsOf: fileURL)
    }

    // MARK: - Init

    private init() {
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        AppLogger.shared.log("🖼️ [FaviconFetcher] Initialized with cache at \(cacheDirectory.path)")
    }
}
