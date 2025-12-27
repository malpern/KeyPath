import AppKit

/// Loads favicons for websites using Google's favicon service.
///
/// Caches loaded favicons to avoid repeated network requests.
/// Uses LRU eviction to limit memory usage.
/// Falls back to a globe icon if favicon cannot be loaded.
actor FaviconLoader {
    /// Shared instance for favicon loading
    static let shared = FaviconLoader()

    /// Cache entry with access tracking for LRU eviction
    private struct CacheEntry {
        let image: NSImage
        var lastAccessed: Date
    }

    /// Cache for loaded favicons (domain -> entry)
    private var cache: [String: CacheEntry] = [:]

    /// Maximum number of cached favicons before eviction
    private let maxCacheSize = 100

    /// Size to request from Google's favicon service (64px for retina)
    private let iconSize = 64

    private init() {}

    /// Get favicon for a domain, loading from cache or network
    func favicon(for domain: String) async -> NSImage? {
        // Check cache first
        if var entry = cache[domain] {
            // Update access time for LRU
            entry.lastAccessed = Date()
            cache[domain] = entry
            return entry.image
        }

        // Normalize domain (remove protocol and path if present)
        let normalizedDomain = normalizeDomain(domain)

        // Try to load from Google's favicon service
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(normalizedDomain)&sz=\(iconSize)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check for valid response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return nil
            }

            if let image = NSImage(data: data) {
                // Evict oldest entries if cache is full
                evictIfNeeded()
                cache[domain] = CacheEntry(image: image, lastAccessed: Date())
                return image
            }
        } catch {
            // Silently fail - will fall back to globe icon
        }

        return nil
    }

    /// Evict least recently used entries if cache exceeds max size
    private func evictIfNeeded() {
        guard cache.count >= maxCacheSize else { return }

        // Remove oldest 20% of entries
        let entriesToRemove = maxCacheSize / 5
        let sortedKeys = cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            .prefix(entriesToRemove)
            .map(\.key)

        for key in sortedKeys {
            cache.removeValue(forKey: key)
        }
    }

    /// Preload favicons for multiple domains (e.g., on collection load)
    func preload(domains: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for domain in domains {
                group.addTask {
                    _ = await self.favicon(for: domain)
                }
            }
        }
    }

    /// Clear the favicon cache
    func clearCache() {
        cache.removeAll()
    }

    /// Normalize a domain string (remove protocol and path)
    private func normalizeDomain(_ input: String) -> String {
        var domain = input

        // Remove protocol if present
        if domain.hasPrefix("https://") {
            domain = String(domain.dropFirst(8))
        } else if domain.hasPrefix("http://") {
            domain = String(domain.dropFirst(7))
        }

        // Remove path if present
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }

        // Remove www. prefix if present
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }

        return domain
    }
}

/// Convenience extension for getting favicons for LauncherTarget
extension FaviconLoader {
    /// Get favicon for a URL target
    func favicon(for target: LauncherTarget) async -> NSImage? {
        guard case let .url(urlString) = target else {
            return nil
        }
        return await favicon(for: urlString)
    }
}
