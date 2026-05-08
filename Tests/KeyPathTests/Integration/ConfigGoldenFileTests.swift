@testable import KeyPathAppKit
import KeyPathCore
import XCTest

/// Golden file tests for config generation.
///
/// These assert the exact .kbd output for specific rule collection configurations.
/// When the config generator changes, the test diff shows exactly what changed —
/// making it easy to spot unintended regressions in kanata syntax.
///
/// To update golden files after an intentional change:
///   Set UPDATE_GOLDEN=1 environment variable and run these tests.
final class ConfigGoldenFileTests: XCTestCase {
    private let goldenDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("GoldenConfigs")

    private var shouldUpdate: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Golden file tests are sensitive to shared global state from other tests
        // (RuleCollectionCatalog defaults can be mutated by earlier test suites).
        // Run them in isolation: swift test --filter ConfigGoldenFileTests
        if ProcessInfo.processInfo.environment["KEYPATH_SNAPSHOTS"] == "1" {
            throw XCTSkip("Golden file tests are isolated — run separately to avoid shared state interference")
        }
        if shouldUpdate {
            try FileManager.default.createDirectory(at: goldenDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Assertions

    private func normalizeConfig(_ config: String) -> String {
        let uuidPattern = try! NSRegularExpression(
            pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        )
        let range = NSRange(config.startIndex..., in: config)
        return uuidPattern.stringByReplacingMatches(in: config, range: range, withTemplate: "<UUID>")
    }

    private func assertGoldenConfig(
        _ config: String,
        named name: String,
        sortLines: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let goldenFile = goldenDir.appendingPathComponent("\(name).kbd")

        var normalized = normalizeConfig(config)
        if sortLines {
            normalized = normalized.components(separatedBy: "\n").sorted().joined(separator: "\n")
        }

        if shouldUpdate {
            try? normalized.write(to: goldenFile, atomically: true, encoding: .utf8)
            XCTFail("Golden file updated: \(name).kbd (UPDATE_GOLDEN=1 is on)", file: file, line: line)
            return
        }

        guard let expected = try? String(contentsOf: goldenFile, encoding: .utf8) else {
            try? FileManager.default.createDirectory(at: goldenDir, withIntermediateDirectories: true)
            try? normalized.write(to: goldenFile, atomically: true, encoding: .utf8)
            XCTFail(
                "Golden file created: \(name).kbd — re-run test to verify",
                file: file,
                line: line
            )
            return
        }

        if normalized != expected {
            let actualFile = goldenDir.appendingPathComponent("\(name).actual.kbd")
            try? normalized.write(to: actualFile, atomically: true, encoding: .utf8)
            XCTFail(
                "Config output changed for '\(name)'. Diff: diff \(goldenFile.path) \(actualFile.path)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Golden Tests

    @MainActor
    func testDefaultConfig_Golden() {
        let collections = RuleCollectionCatalog().defaultCollections()
        let config = KanataConfiguration.generateFromCollections(collections)

        XCTAssertFalse(config.isEmpty, "Default config should not be empty")
        assertGoldenConfig(config, named: "default")
    }

    @MainActor
    func testCapsLockEscapeHyper_Golden() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.capsLockRemap }) {
            collections[idx].isEnabled = true
        }
        let config = KanataConfiguration.generateFromCollections(collections)
        assertGoldenConfig(config, named: "caps-escape-hyper")
    }

    @MainActor
    func testHomeRowMods_Golden() {
        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.homeRowMods }) {
            collections[idx].isEnabled = true
        }
        let config = KanataConfiguration.generateFromCollections(collections)
        assertGoldenConfig(config, named: "home-row-mods")
    }

    @MainActor
    func testSimpleCustomRule_Golden() {
        let rule = CustomRule(input: "a", output: "b")
        let ruleCollections = [rule].compactMap { $0.asRuleCollection() }
        var collections = RuleCollectionCatalog().defaultCollections()
        collections.append(contentsOf: ruleCollections)
        let config = KanataConfiguration.generateFromCollections(collections)
        assertGoldenConfig(config, named: "simple-remap-a-to-b")
    }

    @MainActor
    func testCustomRuleWithShiftedOutput_Golden() {
        let rule = CustomRule(input: "1", output: "2", shiftedOutput: "at")
        let ruleCollections = [rule].compactMap { $0.asRuleCollection() }
        var collections = RuleCollectionCatalog().defaultCollections()
        collections.append(contentsOf: ruleCollections)
        let config = KanataConfiguration.generateFromCollections(collections)
        assertGoldenConfig(config, named: "remap-with-shifted-output")
    }

    @MainActor
    func testVimNavigation_Golden() {
        guard let pack = PackRegistry.pack(id: "com.keypath.pack.vim-navigation"),
              let collectionID = pack.associatedCollectionID
        else {
            return XCTFail("Vim navigation pack not found")
        }

        var collections = RuleCollectionCatalog().defaultCollections()
        if let idx = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[idx].isEnabled = true
        }
        let config = KanataConfiguration.generateFromCollections(collections)
        assertGoldenConfig(config, named: "vim-navigation")
    }
}
