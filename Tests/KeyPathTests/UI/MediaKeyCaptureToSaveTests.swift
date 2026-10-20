import AppKit
@testable import KeyPathAppKit
@testable import KeyPathCore
import KeyPathRulesCore
@preconcurrency import XCTest

/// A media key captured from a system-defined event becomes a rule the session
/// can post: the path from NSEvent through the Mapper to the generated config,
/// end to end, against the real bridge.
@MainActor
final class MediaKeyCaptureToSaveTests: KeyPathTestCase {
    private var directory: URL!
    private var coordinator: RuntimeCoordinator!
    private var service: ConfigurationService!

    override func setUp() async throws {
        try await super.setUp()
        try SessionBridgeTestFixture.requireAvailable()
        BackendCapabilityProfile.testOverride = SessionBridgeTestFixture.profile
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = RuleCollectionStore.testStore(at: directory.appendingPathComponent("RuleCollections.json"))
        let rules = CustomRulesStore.testStore(at: directory.appendingPathComponent("CustomRules.json"))
        service = ConfigurationService.sessionTestService(configDirectory: directory.path, ruleCollectionStore: collections, customRulesStore: rules)
        let manager = RuleCollectionsManager(ruleCollectionStore: collections, customRulesStore: rules, configurationService: service)
        manager.ruleCollections = []
        manager.customRules = []
        try await service.saveRuleState(ruleCollections: [], customRules: [], collectionStore: collections, customStore: rules)
        coordinator = RuntimeCoordinator(injectedConfigurationService: service, injectedRuleCollectionsManager: manager)
    }

    override func tearDown() async throws {
        BackendCapabilityProfile.testOverride = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        coordinator = nil; service = nil; directory = nil
        try await super.tearDown()
    }

    /// `NSEvent.otherEvent(.systemDefined, subtype 8)` as the hardware sends it.
    private func mediaEvent(nxKeyType: Int, down: Bool) throws -> NSEvent {
        try XCTUnwrap(NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: (nxKeyType << 16) | ((down ? 0xA : 0xB) << 8), data2: -1
        ))
    }

    func testCaptureNamesTheMediaKeyAndIgnoresKeyUp() throws {
        let mute = try XCTUnwrap(KeyboardCapture.mediaKeyPress(from: mediaEvent(nxKeyType: 7, down: true)))
        XCTAssertEqual(mute.baseKey, "mute")
        XCTAssertEqual(mute.keyCode, 1007)
        XCTAssertNil(try KeyboardCapture.mediaKeyPress(from: mediaEvent(nxKeyType: 7, down: false)))
        XCTAssertEqual(try XCTUnwrap(KeyboardCapture.mediaKeyPress(from: mediaEvent(nxKeyType: 0, down: true))).baseKey, "volumeup")
    }

    func testCapturedMediaKeyBecomesAPostableRule() async throws {
        for (nxKeyType, kanata) in [(7, "mute"), (0, "volu"), (2, "brup"), (16, "pp")] {
            let press = try XCTUnwrap(KeyboardCapture.mediaKeyPress(from: mediaEvent(nxKeyType: nxKeyType, down: true)))
            let vm = MapperViewModel()
            vm.configure(kanataManager: coordinator)
            vm.inputSequence = KeySequence(keys: [KeyPress(baseKey: "grave", modifiers: [], keyCode: 50)], captureMode: .single)
            vm.outputSequence = KeySequence(keys: [press], captureMode: .single)
            await vm.save(kanataManager: coordinator)
            XCTAssertFalse(vm.statusIsError, "\(kanata): \(vm.statusMessage ?? "")")
            XCTAssertEqual(vm.statusMessage?.hasPrefix("✓ Saved"), true, vm.statusMessage ?? "nil")
            let rule = try XCTUnwrap(coordinator.ruleCollectionsManager.customRules.first { $0.input == "grv" || $0.input == "grave" })
            XCTAssertEqual(rule.action, .keystroke(key: kanata))
            let config = try String(contentsOfFile: service.configurationPath, encoding: .utf8)
            XCTAssertTrue(config.contains(kanata), "\(kanata) missing from the generated config")
            XCTAssertFalse(config.contains("(macro"), "a media key must never be typed as letters")
        }
    }
}
