import Foundation
@testable import KeyPathAppKit
import Testing

private actor HelpTestServer {
    var files: [String: Data] = [:]
    var requests = [String]()
    func set(_ files: [String: Data]) {
        self.files = files
    }

    func fetch(_ url: URL) throws -> Data {
        requests.append(url.lastPathComponent)
        guard let data = files[url.lastPathComponent] else { throw URLError(.notConnectedToInternet) }
        return data
    }
}

@Suite("OfflineHelpStore")
struct OfflineHelpStoreTests {
    private let webURL = URL(string: "https://malpern.github.io/KeyPath/guides/tap-hold/")!

    private func fixture() throws -> (URL, URL, [String: Data]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("bundle")
        let files = ["articles/tap-hold.html": Data("Bundled guide".utf8), "assets/help-theme.css": Data("body{}".utf8)]
        try write(files, to: bundle)
        return (root, bundle, files)
    }

    private func manifest(_ files: [String: Data], version: String = "1.0", revision: String = String(repeating: "a", count: 64)) throws -> Data {
        try JSONEncoder().encode(HelpManifest(schema: 1, appVersion: version, revision: revision,
                                              files: files.mapValues(OfflineHelpStore.hash)))
    }

    private func write(_ files: [String: Data], to root: URL) throws {
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try manifest(files).write(to: root.appendingPathComponent("manifest.json"))
    }

    private func makeStore(_ bundle: URL, _ root: URL, _ server: HelpTestServer) -> OfflineHelpStore {
        OfflineHelpStore(bundledRoot: bundle, storageRoot: root.appendingPathComponent("cache"), appVersion: "1.0",
                         updateBase: URL(string: "https://example.com/help/")!, fetch: { try await server.fetch($0) })
    }

    @Test("Current setup and unlisted guide cross-links stay inside Help")
    func topicRouting() {
        #expect(HelpTopic.topic(forResource: "installation")?.resource == "installation-wizard")
        #expect(HelpTopic.topic(forResource: "driverless-caps-lock")?.resource == "driverless-caps-lock")
        #expect(HelpTopic.topic(forResource: "../../outside") == nil)
    }

    @Test("First-ever offline open uses bundled guide and assets")
    func freshOffline() async throws {
        let (root, bundle, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(bundle, root, HelpTestServer())
        await store.refreshIfNeeded(force: true)
        let article = try #require(await store.article(for: webURL))
        #expect(article.root == bundle)
        #expect(try String(contentsOf: article.url, encoding: .utf8) == "Bundled guide")
        #expect(FileManager.default.fileExists(atPath: article.root.appendingPathComponent("assets/help-theme.css").path))
        #expect(await store.article(for: URL(string: "https://evil.example/tap-hold/")!) == nil)
    }

    @Test("Complete compatible update survives an offline app restart")
    func updatedOffline() async throws {
        let (root, bundle, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = HelpTestServer()
        var newer = original
        newer["articles/tap-hold.html"] = Data("Updated guide".utf8)
        try await server.set(["manifest.json": manifest(newer, revision: String(repeating: "b", count: 64)),
                              "tap-hold.html": newer["articles/tap-hold.html"]!])
        let first = makeStore(bundle, root, server)
        let alreadyOpen = try #require(await first.article(for: webURL))
        await first.refreshIfNeeded(force: true)
        #expect(try String(contentsOf: alreadyOpen.url, encoding: .utf8) == "Bundled guide")
        let restarted = makeStore(bundle, root, HelpTestServer())
        await restarted.refreshIfNeeded(force: true)
        let article = try #require(await restarted.article(for: webURL))
        #expect(article.root != bundle)
        #expect(try String(contentsOf: article.url, encoding: .utf8) == "Updated guide")
        #expect(await server.requests == ["manifest.json", "tap-hold.html"])
    }

    @Test("Interrupted and hash-mismatched updates keep the previous working generation")
    func failedUpdate() async throws {
        let (root, bundle, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = HelpTestServer()
        let store = makeStore(bundle, root, server)
        var newer = original
        newer["articles/tap-hold.html"] = Data("Good update".utf8)
        try await server.set(["manifest.json": manifest(newer, revision: String(repeating: "b", count: 64)), "tap-hold.html": newer["articles/tap-hold.html"]!])
        await store.refreshIfNeeded(force: true)
        let good = try #require(await store.article(for: webURL))
        newer["articles/tap-hold.html"] = Data("Next update".utf8)
        // Missing download, then a response whose hash does not match its manifest.
        for response in [[:], ["tap-hold.html": Data("corrupt".utf8)]] {
            try await server.set(response.merging(["manifest.json": manifest(newer, revision: String(repeating: "c", count: 64))]) { _, new in new })
            await store.refreshIfNeeded(force: true)
            #expect(await store.article(for: webURL)?.url == good.url)
            #expect(try String(contentsOf: good.url, encoding: .utf8) == "Good update")
        }
        let restarted = makeStore(bundle, root, HelpTestServer())
        #expect(await restarted.article(for: webURL)?.url == good.url)
    }

    @Test("Incompatible versions and unsafe manifest paths are rejected")
    func invalidUpdates() async throws {
        let (root, bundle, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = HelpTestServer()
        let store = makeStore(bundle, root, server)
        var invalid = files
        invalid["assets/../../outside.css"] = Data("bad".utf8)
        for payload in try [manifest(files, version: "2.0"), manifest(invalid)] {
            await server.set(["manifest.json": payload])
            await store.refreshIfNeeded(force: true)
            #expect(await store.article(for: webURL)?.root == bundle)
        }
        #expect(await server.requests == ["manifest.json", "manifest.json"])
    }

    @Test("Corrupted downloaded content falls back to bundled help")
    func corruptCache() async throws {
        let (root, bundle, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = HelpTestServer()
        var newer = original
        newer["articles/tap-hold.html"] = Data("Good update".utf8)
        try await server.set(["manifest.json": manifest(newer, revision: String(repeating: "b", count: 64)), "tap-hold.html": newer["articles/tap-hold.html"]!])
        let first = makeStore(bundle, root, server)
        await first.refreshIfNeeded(force: true)
        let downloaded = try #require(await first.article(for: webURL))
        try Data("corrupt".utf8).write(to: downloaded.url)
        let restarted = makeStore(bundle, root, HelpTestServer())
        #expect(await restarted.article(for: webURL)?.root == bundle)
    }
}
