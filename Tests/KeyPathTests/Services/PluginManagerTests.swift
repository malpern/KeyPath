import AppKit
@testable import KeyPathAppKit
import KeyPathPluginKit
@preconcurrency import XCTest

@MainActor
final class PluginManagerTests: KeyPathTestCase {
    private var root: URL!
    private var manager: PluginManager!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        manager = PluginManager()
        manager.testPluginsDirectory = root.appendingPathComponent("Installed")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        manager = nil
        try await super.tearDown()
    }

    private func archive() throws -> URL {
        let source = root.appendingPathComponent(UUID().uuidString)
        let bundle = source.appendingPathComponent("Fixture.bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("invalid bundle fixture".utf8).write(to: bundle.appendingPathComponent("fixture"))
        let zip = root.appendingPathComponent(UUID().uuidString + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", bundle.path, zip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    func testInvalidBundleDoesNotReportInstalled() async throws {
        let zip = try archive()
        manager.testDownload = { _ in zip }
        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)
        XCTAssertFalse(result)
        XCTAssertNotNil(manager.installError)
        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertTrue(manager.availablePlugins.contains { $0.id == "com.keypath.insights" })
        XCTAssertFalse(manager.isInstalling)
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Installed/Fixture.bundle").path))
    }

    func testNonPluginPrincipalDoesNotReportInstalled() async throws {
        let zip = try archive()
        manager.testDownload = { _ in zip }
        manager.testPluginInstance = { _ in NSObject() }
        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)
        XCTAssertFalse(result)
        XCTAssertNotNil(manager.installError)
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testValidPluginActivatesOnce() async throws {
        let zip = try archive()
        let plugin = FixturePlugin()
        manager.testDownload = { _ in zip }
        manager.testPluginInstance = { _ in plugin }
        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)
        XCTAssertTrue(result)
        XCTAssertNil(manager.installError)
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(plugin.activationCount, 1)
        manager.loadPlugin(from: root.appendingPathComponent("Installed/Fixture.bundle"))
        XCTAssertEqual(plugin.activationCount, 1)
        XCTAssertFalse(manager.availablePlugins.contains { $0.id == "com.keypath.insights" })
    }

    func testCancelledDownloadDoesNotReportSuccessOrError() async {
        manager.testDownload = { _ in throw CancellationError() }
        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)
        XCTAssertFalse(result)
        XCTAssertNil(manager.installError)
        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertFalse(manager.isInstalling)
    }

    func testFailedReplacementRestoresPreviousUnloadedBundle() async throws {
        let previous = root.appendingPathComponent("Installed/Fixture.bundle")
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        let original = Data("previous plugin bytes".utf8)
        try original.write(to: previous.appendingPathComponent("previous"))
        let zip = try archive()
        manager.testDownload = { _ in zip }
        manager.testPluginInstance = { _ in NSObject() }

        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)

        XCTAssertFalse(result)
        XCTAssertNotNil(manager.installError)
        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertEqual(try Data(contentsOf: previous.appendingPathComponent("previous")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.appendingPathComponent("fixture").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: previous.deletingLastPathComponent().path), ["Fixture.bundle"])
    }

    func testSuccessfulReplacementRemovesBackup() async throws {
        let previous = root.appendingPathComponent("Installed/Fixture.bundle")
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: previous.appendingPathComponent("previous"))
        let zip = try archive()
        let plugin = FixturePlugin()
        manager.testDownload = { _ in zip }
        manager.testPluginInstance = { _ in plugin }

        let result = await manager.installPlugin(from: URL(string: "https://example.invalid/plugin.zip")!)

        XCTAssertTrue(result)
        XCTAssertEqual(plugin.activationCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.appendingPathComponent("previous").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.appendingPathComponent("fixture").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: previous.deletingLastPathComponent().path), ["Fixture.bundle"])
    }

    private final class FixturePlugin: NSObject, KeyPathPlugin {
        static var identifier: String {
            "com.keypath.insights"
        }

        static var displayName: String {
            "Test Insights"
        }

        var activationCount = 0
        func makeSettingsViewController() -> NSViewController {
            MainActor.assumeIsolated { NSViewController() }
        }

        func activate() {
            activationCount += 1
        }
    }
}
