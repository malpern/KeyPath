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

    private let cacheVersion = 2

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
        let cleaned = URLMappingFormatter.decodeFromPushMessage(url)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return cleaned.components(separatedBy: "/").first ?? url
    }

    /// Perform actual network fetch for favicon
    private func performFetch(for domain: String, fullURL: String) async -> NSImage? {
        AppLogger.shared.debug("🌐 [FaviconFetcher] Fetching favicon for \(domain)")

        // Try strategy 1: /favicon.ico (most common)
        let directImage = await fetchFaviconDirect(domain: domain)
        if let directImage, isAcceptableFavicon(directImage) {
            return finalizeAndCache(directImage, forDomain: domain)
        }

        // Try strategy 2: Parse HTML for <link rel="icon"> (fallback)
        if let htmlImage = await fetchFaviconFromHTML(url: fullURL) {
            return finalizeAndCache(htmlImage, forDomain: domain)
        }

        if let directImage {
            return finalizeAndCache(directImage, forDomain: domain)
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

            let candidateLinks = parseFaviconLinks(from: html)
            let resolvedCandidates = candidateLinks.compactMap { link -> URL? in
                let href = link.href
                if href.hasPrefix("http://") || href.hasPrefix("https://") {
                    return URL(string: href)
                }
                if href.hasPrefix("/") {
                    return htmlURL.deletingLastPathComponent().appendingPathComponent(href)
                }
                return htmlURL.deletingLastPathComponent().appendingPathComponent(href)
            }

            let sortedCandidates = resolvedCandidates.uniqued().prefix(5)
            var bestImage: NSImage?
            var bestScore: CGFloat = 0

            for iconURL in sortedCandidates {
                if let image = await fetchImage(from: iconURL) {
                    let score = faviconScore(image)
                    if score > bestScore {
                        bestScore = score
                        bestImage = image
                    }
                }
            }

            if let bestImage {
                return bestImage
            }
        } catch {
            AppLogger.shared.debug("🌐 [FaviconFetcher] HTML fetch failed: \(error.localizedDescription)")
        }

        return nil
    }

    private func isAcceptableFavicon(_ image: NSImage) -> Bool {
        let size = faviconPixelSize(for: image)
        let minSide = min(size.width, size.height)
        return minSide >= 48
    }

    private func faviconScore(_ image: NSImage) -> CGFloat {
        let size = faviconPixelSize(for: image)
        let minSide = min(size.width, size.height)
        let aspectRatio = size.width / max(size.height, 1)
        let aspectPenalty = abs(aspectRatio - 1.0) * 10.0
        return minSide - aspectPenalty
    }

    private func parseFaviconLinks(from html: String) -> [(href: String, size: CGFloat?)] {
        let pattern = #"<link[^>]*rel=["\']([^"\']*)["\'][^>]*href=["\']([^"\']+)["\'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        var results: [(href: String, size: CGFloat?)] = []

        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match else { return }
            guard let relRange = Range(match.range(at: 1), in: html),
                  let hrefRange = Range(match.range(at: 2), in: html)
            else {
                return
            }

            let rel = html[relRange].lowercased()
            guard rel.contains("icon") else { return }

            let href = String(html[hrefRange])
            let size = parseIconSize(from: match.range, in: html)
            results.append((href: href, size: size))
        }

        results.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        return results
    }

    private func parseIconSize(from linkRange: NSRange, in html: String) -> CGFloat? {
        guard let range = Range(linkRange, in: html) else { return nil }
        let linkTag = String(html[range])
        let sizePattern = #"sizes=["\'](\d+)x(\d+)["\']"#
        guard let regex = try? NSRegularExpression(pattern: sizePattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: linkTag, range: NSRange(linkTag.startIndex..., in: linkTag)),
              let wRange = Range(match.range(at: 1), in: linkTag),
              let hRange = Range(match.range(at: 2), in: linkTag)
        else {
            return nil
        }

        let w = CGFloat(Double(linkTag[wRange]) ?? 0)
        let h = CGFloat(Double(linkTag[hRange]) ?? 0)
        return min(w, h)
    }

    /// Fetch image from URL with timeout
    private func fetchImage(from url: URL) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                AppLogger.shared.debug("🌐 [FaviconFetcher] HTTP \(httpResponse.statusCode) for \(url)")
                return nil
            }

            // Try to create image
            if let image = NSImage(data: data) {
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

    private func finalizeAndCache(_ image: NSImage, forDomain domain: String) -> NSImage {
        let normalized = normalizedFaviconImage(image)
        cacheImage(normalized, forDomain: domain)
        return normalized
    }

    /// Save image to disk cache as PNG
    private func saveToDiskCache(image: NSImage, domain: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(domain)-v\(cacheVersion).png")

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
        let fileURL = cacheDirectory.appendingPathComponent("\(domain)-v\(cacheVersion).png")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        return normalizedFaviconImage(image)
    }

    /// Normalize favicon into a square bitmap to avoid odd rendering artifacts.
    private func normalizedFaviconImage(_ image: NSImage, size: CGFloat = 64) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let normalized = NSImage(size: targetSize)
        normalized.lockFocus()

        if let context = NSGraphicsContext.current {
            context.imageInterpolation = .high
        }

        let rep = bestFaviconRepresentation(for: image)
        let sourceSize: NSSize = if let rep, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            image.size
        }
        let scale = min(targetSize.width / max(1, sourceSize.width), targetSize.height / max(1, sourceSize.height))
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawOrigin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )
        let drawRect = NSRect(origin: drawOrigin, size: drawSize)
        if let rep {
            rep.draw(in: drawRect)
        } else {
            image.draw(
                in: drawRect,
                from: NSRect(origin: .zero, size: sourceSize),
                operation: .copy,
                fraction: 1.0
            )
        }
        normalized.unlockFocus()
        return normalized
    }

    private func bestFaviconRepresentation(for image: NSImage) -> NSImageRep? {
        let bitmapReps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        let squareish = bitmapReps.filter { rep in
            let width = CGFloat(max(1, rep.pixelsWide))
            let height = CGFloat(max(1, rep.pixelsHigh))
            let ratio = max(width, height) / max(1, min(width, height))
            return ratio <= 1.3
        }
        let candidateReps = squareish.isEmpty ? bitmapReps : squareish
        if let bestBitmap = candidateReps.max(by: { lhs, rhs in
            let lhsScore = max(1, lhs.pixelsWide) * max(1, lhs.pixelsHigh) * max(1, lhs.bitsPerPixel)
            let rhsScore = max(1, rhs.pixelsWide) * max(1, rhs.pixelsHigh) * max(1, rhs.bitsPerPixel)
            return lhsScore < rhsScore
        }) {
            return bestBitmap
        }

        let proposedRect = NSRect(origin: .zero, size: image.size)
        return image.bestRepresentation(for: proposedRect, context: nil, hints: nil)
    }

    private func faviconPixelSize(for image: NSImage) -> CGSize {
        if let rep = bestFaviconRepresentation(for: image) {
            return CGSize(width: max(1, rep.pixelsWide), height: max(1, rep.pixelsHigh))
        }
        return CGSize(width: max(1, image.size.width), height: max(1, image.size.height))
    }

    // MARK: - Init

    private init() {
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        AppLogger.shared.log("🖼️ [FaviconFetcher] Initialized with cache at \(cacheDirectory.path)")
    }
}

private extension [URL] {
    func uniqued() -> [URL] {
        var seen: Set<URL> = []
        return filter { seen.insert($0).inserted }
    }
}
