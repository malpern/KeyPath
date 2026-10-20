import Foundation
@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// Phase 4e: one renderer for "this configuration cannot run", attributed to
/// the rule the engine blames; `keypath doctor` lists every verdict.
@MainActor
final class SessionConfigurationRefusalTests: KeyPathTestCase {
    private var directory: URL!
    private var manager: RuleCollectionsManager!
    private let allowAll = BackendCapabilityProfile(backend: .session) { _ in true }
    private let noMedia = BackendCapabilityProfile(backend: .session) { !BackendCapabilityProfile.fallbackConsumerKeys.contains($0) }

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        let service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = []
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        manager = nil; directory = nil
        try await super.tearDown()
    }

    // MARK: - Renderer

    func testValidHasNoMessage() {
        XCTAssertNil(SessionConfigurationRefusal.message(.valid))
        XCTAssertNil(SessionConfigurationRefusal.message(.valid, attribution: ["anything"]))
    }

    func testInvalidWithoutAttributionKeepsTheValidatorReason() {
        let message = SessionConfigurationRefusal.message(.invalid(reason: "unsupported output key volu"))
        XCTAssertEqual(message, "This configuration cannot run in the driverless session: unsupported output key volu. "
            + "Edit the configuration and retry; existing rules were preserved.")
    }

    func testInvalidWithAttributionNamesTheRuleFirst() {
        let message = SessionConfigurationRefusal.message(
            .invalid(reason: "unsupported output key volu"),
            attribution: ["Louder sends Volume Up, which the current backend can't send."]
        )
        XCTAssertEqual(message, "This configuration cannot run in the driverless session. "
            + "Louder sends Volume Up, which the current backend can't send. "
            + "Turn that rule off or change it, then retry; existing rules were preserved. "
            + "(Validator: unsupported output key volu.)")
    }

    func testUnavailableIsNotARefusal() {
        let message = SessionConfigurationRefusal.message(.unavailable(reason: "bridge library missing"), attribution: ["ignored"]) ?? ""
        XCTAssertTrue(message.hasPrefix("Driverless configuration validation is unavailable: bridge library missing."), message)
        XCTAssertFalse(message.contains("cannot run"))
        XCTAssertFalse(message.contains("ignored"))
    }

    // MARK: - Attribution from the engine

    func testBlockingSentencesNameTheRule() {
        manager.customRules = [CustomRule(title: "Louder", input: "f12", action: .keystroke(key: "volu")),
                               CustomRule(title: "Fine", input: "f11", action: .keystroke(key: "a"))]
        XCTAssertEqual(manager.blockingAdmissionSentences(profile: noMedia),
                       ["Louder sends Volume Up, which the current backend can't send."])
        XCTAssertEqual(manager.blockingAdmissionSentences(profile: allowAll), [])
    }

    func testDisabledRulesAreNotBlamed() {
        var off = CustomRule(title: "Louder", input: "f12", action: .keystroke(key: "volu"))
        off.isEnabled = false
        manager.customRules = [off]
        XCTAssertEqual(manager.blockingAdmissionSentences(profile: noMedia), [])
    }

    // MARK: - Doctor

    func testFindingsCarryEveryVerdictInTheAppsWords() {
        manager.admissionEnvironment = .init(capsIntermediate: "f18")
        manager.customRules = [
            CustomRule(title: "Mine", input: "f18", action: .keystroke(key: "a")),
            CustomRule(title: "Louder", input: "f12", action: .keystroke(key: "volu")),
            CustomRule(title: "A", input: "f13", action: .keystroke(key: "b")),
            CustomRule(title: "B", input: "f13", action: .keystroke(key: "c"))
        ]
        let findings = manager.admissionFindings(profile: noMedia)
        XCTAssertEqual(findings.map(\.severity), ["blocking", "needsChoice", "automatic"])
        XCTAssertEqual(findings[0].subject, "Louder")
        XCTAssertEqual(findings[0].explanation, "Louder sends Volume Up, which the current backend can't send.")
        XCTAssertEqual(findings[0].fixes, ["Turn off Louder"])
        XCTAssertEqual(findings[1].title, "Key conflict on f13")
        XCTAssertEqual(Set(findings[1].fixes), ["Turn off A", "Turn off B"])
        XCTAssertEqual(findings[2].title, "Caps Lock will use F19")
        XCTAssertEqual(findings[2].fixes, [])
        XCTAssertEqual(manager.admissionFindings(profile: allowAll).map(\.severity), ["needsChoice", "automatic"])
    }

    func testFindingsRoundTripThroughTheControlChannel() throws {
        let finding = RuntimeControl.AdmissionFinding(severity: "blocking", subject: "Louder", title: "Louder can't run here",
                                                      explanation: "Louder sends Volume Up, which the current backend can't send.",
                                                      fixes: ["Turn off Louder"])
        var response = RuntimeControl.Response(ok: true, operation: .doctor, state: .failed, workerPID: nil, failure: "x",
                                               lastError: nil, layer: nil, appPID: 1, appVersion: "1")
        response.admission = [finding]
        let data = try JSONEncoder().encode(response)
        XCTAssertEqual(try JSONDecoder().decode(RuntimeControl.Response.self, from: data), response)
        // An app that predates the field answers without it.
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "admission")
        let decoded = try JSONDecoder().decode(RuntimeControl.Response.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.admission)
    }
}
