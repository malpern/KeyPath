import AppKit
@testable import KeyPathAppKit
import KeyPathPluginKit
@preconcurrency import XCTest

@MainActor
final class PluginManagerTests: KeyPathTestCase {
    private var manager: PluginManager!
    private let bundleURL = URL(fileURLWithPath: "/nonexistent/Fixture.bundle")

    override func setUp() async throws {
        try await super.setUp()
        manager = PluginManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    func testUnloadableBundleIsNotLoaded() {
        manager.testPluginInstance = { _ in throw CocoaError(.fileReadCorruptFile) }
        XCTAssertFalse(manager.loadPlugin(from: bundleURL))
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testNonPluginPrincipalIsNotLoaded() {
        manager.testPluginInstance = { _ in NSObject() }
        XCTAssertFalse(manager.loadPlugin(from: bundleURL))
        XCTAssertTrue(manager.plugins.isEmpty)
    }

    func testValidPluginActivatesOnce() {
        let plugin = FixturePlugin()
        manager.testPluginInstance = { _ in plugin }
        XCTAssertTrue(manager.loadPlugin(from: bundleURL))
        XCTAssertTrue(manager.loadPlugin(from: bundleURL), "a second load of the same bundle is a no-op")
        XCTAssertEqual(manager.plugins.count, 1)
        XCTAssertEqual(plugin.activationCount, 1)
    }

    func testPluginsDirectoryIsOnlyTheAppBundle() throws {
        // The manager no longer has a user plugins directory or a download path.
        let source = try String(
            contentsOf: LintScanner.path("Sources/KeyPathAppKit/Services/PluginManager.swift"), encoding: .utf8
        )
        XCTAssertFalse(source.contains("Application Support"))
        XCTAssertFalse(source.contains("URLSession"))
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
