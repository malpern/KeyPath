import CryptoKit
import Foundation

struct HelpManifest: Codable, Sendable {
    let schema: Int
    let appVersion: String
    let revision: String
    let files: [String: String]

    func validate(for version: String) throws {
        guard schema == 1, appVersion == version, Self.isHash(revision),
              !files.isEmpty, files.count <= 512, files["assets/help-theme.css"] != nil,
              files.keys.contains(where: { $0.hasPrefix("articles/") }) else { throw HelpContentError.invalidPackage }
        for (path, hash) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, ["articles", "assets"].contains(parts[0]),
                  !parts[1].isEmpty, parts[1] != ".", parts[1] != "..",
                  parts[1].utf8.allSatisfy({ (45 ... 57).contains($0) && $0 != 47 || (65 ... 90).contains($0) || (97 ... 122).contains($0) || $0 == 95 }),
                  ["html", "css", "png", "jpg", "jpeg", "webp", "gif", "svg"].contains((path as NSString).pathExtension),
                  Self.isHash(hash) else { throw HelpContentError.invalidPackage }
        }
    }

    static func isHash(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
    }
}

enum HelpContentError: Error { case invalidPackage, unavailable }

struct LocalHelpArticle: Sendable {
    let url: URL
    let root: URL
}

/// Reads local content first. A failed or incomplete refresh never replaces a usable copy.
/// Generations stay immutable while WebKit may still be reading their assets.
actor OfflineHelpStore {
    static let shared = OfflineHelpStore(
        bundledRoot: (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("OfflineHelp"),
        storageRoot: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyPath/Help"),
        appVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            .split(separator: ".").prefix(2).joined(separator: "."),
        updateBase: URL(string: "https://malpern.github.io/KeyPath/offline-help/")!
    )

    typealias Fetch = @Sendable (URL) async throws -> Data
    private let bundledRoot: URL
    private let storageRoot: URL
    private let appVersion: String
    private let updateBase: URL
    private let fetch: Fetch
    private let fm = FileManager.default
    private var current: (URL, HelpManifest)?
    private var didLoad = false
    private var refreshing = false
    private var lastAttempt = Date.distantPast
    private var lastRefreshSucceeded = false

    init(bundledRoot: URL, storageRoot: URL, appVersion: String, updateBase: URL,
         fetch: @escaping Fetch = { try await OfflineHelpStore.fetchURL($0) })
    {
        self.bundledRoot = bundledRoot
        self.storageRoot = storageRoot.appendingPathComponent(appVersion)
        self.appVersion = appVersion
        self.updateBase = updateBase.appendingPathComponent(appVersion)
        self.fetch = fetch
    }

    func article(for webURL: URL) -> LocalHelpArticle? {
        loadCurrentIfNeeded()
        guard webURL.scheme == "https", webURL.host == "malpern.github.io",
              webURL.path.hasPrefix("/KeyPath/guides/") else { return nil }
        let resource = webURL.lastPathComponent
        guard !resource.isEmpty, !resource.contains("."), !resource.contains("%") else { return nil }
        let path = "articles/\(resource).html"
        // A partial/corrupted downloaded copy must not hide the bundled baseline.
        for root in [current?.0, bundledRoot].compactMap({ $0 }) {
            if fm.fileExists(atPath: root.appendingPathComponent(path).path) {
                return LocalHelpArticle(url: root.appendingPathComponent(path), root: root)
            }
        }
        return nil
    }

    /// Called when Help opens; successful checks are daily, failed checks retry after five minutes.
    func refreshIfNeeded(force: Bool = false) async {
        guard !refreshing, force || Date().timeIntervalSince(lastAttempt) >= (lastRefreshSucceeded ? 86400 : 300) else { return }
        refreshing = true
        lastAttempt = Date()
        lastRefreshSucceeded = false
        defer { refreshing = false }
        do {
            loadCurrentIfNeeded()
            let data = try await fetch(updateBase.appendingPathComponent("manifest.json"))
            guard data.count <= 256 * 1024 else { throw HelpContentError.invalidPackage }
            let manifest = try JSONDecoder().decode(HelpManifest.self, from: data)
            try manifest.validate(for: appVersion)
            let baseline = try readManifest(bundledRoot)
            let required = Set(baseline.files.keys.filter { $0.hasPrefix("articles/") })
            guard required.isSubset(of: Set(manifest.files.keys)) else { throw HelpContentError.invalidPackage }
            if manifest.revision == (current?.1.revision ?? baseline.revision) {
                lastRefreshSucceeded = true
                return
            }
            try fm.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            let generation = UUID().uuidString
            let staging = storageRoot.appendingPathComponent(generation)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var installed = false
            defer { if !installed { try? fm.removeItem(at: staging) } }
            var totalBytes = 0
            for (path, hash) in manifest.files.sorted(by: { $0.key < $1.key }) {
                let destination = staging.appendingPathComponent(path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let candidates = [(current?.0, current?.1.files[path]), (Optional(bundledRoot), baseline.files[path])]
                if let source = candidates.first(where: { $0.0 != nil && $0.1 == hash })?.0,
                   let contents = try? Data(contentsOf: source.appendingPathComponent(path)), Self.hash(contents) == hash
                {
                    totalBytes += contents.count
                    try contents.write(to: destination)
                } else {
                    let contents = try await fetch(updateBase.appendingPathComponent(manifest.revision).appendingPathComponent(path))
                    guard contents.count <= 20 * 1024 * 1024, Self.hash(contents) == hash else { throw HelpContentError.invalidPackage }
                    totalBytes += contents.count
                    try contents.write(to: destination)
                }
                guard totalBytes <= 120 * 1024 * 1024 else { throw HelpContentError.invalidPackage }
            }
            try data.write(to: staging.appendingPathComponent("manifest.json"))
            // This single atomic pointer is the commit; failed downloads leave it untouched.
            try Data(generation.utf8).write(to: storageRoot.appendingPathComponent("current"), options: .atomic)
            current = (staging, manifest)
            installed = true
            lastRefreshSucceeded = true
        } catch {
            // Help remains usable offline. Update failures are not user-facing errors.
        }
    }

    private func loadCurrentIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let name = try? String(contentsOf: storageRoot.appendingPathComponent("current"), encoding: .utf8),
           UUID(uuidString: name) != nil
        {
            let root = storageRoot.appendingPathComponent(name)
            if let manifest = try? readManifest(root), manifest.files.allSatisfy({ path, hash in
                guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { return false }
                return Self.hash(data) == hash
            }) { current = (root, manifest) }
        }
        // Only prune at first use in a new process, before any WebKit page has opened.
        for old in (try? fm.contentsOfDirectory(at: storageRoot, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: old.lastPathComponent) != nil, old.lastPathComponent != current?.0.lastPathComponent { try? fm.removeItem(at: old) }
        }
    }

    private func readManifest(_ root: URL) throws -> HelpManifest {
        let manifest = try JSONDecoder().decode(HelpManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        try manifest.validate(for: appVersion)
        return manifest
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fetchURL(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard (size?.intValue ?? Int.max) <= 20 * 1024 * 1024 else { throw HelpContentError.invalidPackage }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == url.host else { throw HelpContentError.unavailable }
        return try Data(contentsOf: file)
    }
}
