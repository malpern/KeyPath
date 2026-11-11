import AppKit
@testable import KeyPathAppKit
import KeyPathInsights
import KeyPathPluginKit
@preconcurrency import XCTest

@MainActor
final class PluginManagerTests: KeyPathTestCase {
    private var manager: PluginManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = PluginManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    func testPluginActivatesOnceAndDuplicatesAreIgnored() {
        let plugin = FixturePlugin()
        XCTAssertTrue(manager.register(plugin))
        XCTAssertFalse(manager.register(FixturePlugin()), "same identifier: ignored")
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(plugin.activationCount, 1)
    }

    func testBuiltInRegistrationAddsInsightsOnceAndClearsLegacyPlugins() throws {
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: legacy) }
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Insights.bundle"),
                                                withIntermediateDirectories: true)

        manager.registerBuiltInPlugins(legacyPluginsDirectory: legacy)
        manager.registerBuiltInPlugins(legacyPluginsDirectory: legacy)

        XCTAssertEqual(manager.plugins.map { type(of: $0).identifier }, [InsightsPlugin.identifier])
        XCTAssertEqual(InsightsPlugin.identifier, "com.keypath.insights")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testLegacyDownloadedPluginsAreRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = root.appendingPathComponent("KeyPath/Plugins", isDirectory: true)
        let activityLog = root.appendingPathComponent("KeyPath/ActivityLog", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("Insights.bundle"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activityLog, withIntermediateDirectories: true)

        PluginManager.removeLegacyDownloadedPlugins(directory: legacy)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activityLog.path), "activity data is not touched")
        PluginManager.removeLegacyDownloadedPlugins(directory: legacy) // absent: no-op
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
