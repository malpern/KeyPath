@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// The generator asks Kanata, through the bridge, whether a token is a key.
/// A key it knows is emitted as that key, so admission can refuse it with a
/// reason; only a word Kanata does not know is typed as a macro.
@MainActor
final class GeneratorKeyNameTests: KeyPathTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        BackendCapabilityProfile.testOverride = SessionBridgeTestFixture.profile
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        BackendCapabilityProfile.testOverride = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try await super.tearDown()
    }

    func testKanataKeysAreEmittedAsKeysAndWordsAreTyped() {
        XCTAssertEqual(KanataKeyConverter.convertToKanataSequence("f21"), "f21")
        XCTAssertEqual(KanataKeyConverter.convertToKanataSequence("calc"), "calc")
        XCTAssertEqual(KanataKeyConverter.convertToKanataSequence("esc"), "esc")
        XCTAssertEqual(KanataKeyConverter.convertToKanataSequence("hello"), "(macro h e l l o)")
        XCTAssertEqual(KanataKeyConverter.convertToKanataSequence("notakey"), "(macro n o t a k e y)")
    }

    func testTheProfileTellsKeysFromWordsAndSaysWhenItCannot() {
        let profile = SessionBridgeTestFixture.profile
        XCTAssertEqual(profile.knowsKey("f21"), true)
        XCTAssertEqual(profile.knowsKey("volu"), true)
        XCTAssertEqual(profile.knowsKey("hello"), false)
        XCTAssertNil(BackendCapabilityProfile(backend: .session) { _ in nil }.knowsKey("f21"), "no bridge, no answer")
    }

    /// `f21` used to become `(macro f 2 1)` and type three characters. Now it
    /// is a key the session cannot send, refused before anything is written.
    func testAKeyTheSessionCannotSendIsRefusedNotTyped() async throws {
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = []
        let rule = CustomRule(title: "Twenty-one", input: "f9", action: .keystroke(key: "f21"))
        XCTAssertEqual(manager.reviewAdmission(forProposed: rule).refusal,
                       "Twenty-one sends f21, which the current backend can't send.")
        do {
            try await service.saveConfiguration(ruleCollections: [], customRules: [rule])
            XCTFail("an output the session cannot send must not be saved")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("driverless session"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.configurationPath)
            && ((try? String(contentsOfFile: service.configurationPath, encoding: .utf8))?.contains("(macro f 2 1)") ?? false))
    }
}
