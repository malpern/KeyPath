@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class CLIRuleAddIntegrationTests: XCTestCase {
    private let facade = RulesFacade()

    override func setUp() async throws {
        try await super.setUp()
        try await CustomRulesStore.shared.saveRules([])
    }

    override func tearDown() async throws {
        try await CustomRulesStore.shared.saveRules([])
        try await super.tearDown()
    }

    // MARK: - KeyAction JSON decoding (all 13 variants)

    func testDecodeKeystrokeAction() throws {
        let json = #"{"keystroke":{"key":"esc"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .keystroke(key: "esc"))
    }

    func testDecodeHyperAction() throws {
        let json = #"{"hyper":{}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .hyper)
    }

    func testDecodeMehAction() throws {
        let json = #"{"meh":{}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .meh)
    }

    func testDecodeLaunchAppAction() throws {
        let json = #"{"launchApp":{"name":"Safari","bundleId":"com.apple.Safari"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .launchApp(name: "Safari", bundleId: "com.apple.Safari"))
    }

    func testDecodeOpenURLAction() throws {
        let json = #"{"openURL":{"_0":"https://example.com"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .openURL("https://example.com"))
    }

    func testDecodeOpenFolderAction() throws {
        let json = #"{"openFolder":{"path":"~/Documents","name":"Docs"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .openFolder(path: "~/Documents", name: "Docs"))
    }

    func testDecodeRunScriptAction() throws {
        let json = #"{"runScript":{"path":"~/.scripts/foo.sh","name":"Foo"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .runScript(path: "~/.scripts/foo.sh", name: "Foo"))
    }

    func testDecodeSystemActionAction() throws {
        let json = #"{"systemAction":{"id":"volume-up"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .systemAction(id: "volume-up"))
    }

    func testDecodeNotifyAction() throws {
        let json = #"{"notify":{"title":"Done","body":"Build succeeded","sound":true}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .notify(title: "Done", body: "Build succeeded", sound: true))
    }

    func testDecodeWindowActionAction() throws {
        let json = #"{"windowAction":{"position":"left-half"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .windowAction(position: "left-half"))
    }

    func testDecodeFakeKeyAction() throws {
        let json = #"{"fakeKey":{"name":"vk1","action":"tap"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .fakeKey(name: "vk1", action: .tap))
    }

    func testDecodeActivateLayerAction() throws {
        let json = #"{"activateLayer":{"name":"nav"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .activateLayer(name: "nav"))
    }

    func testDecodeRawKanataAction() throws {
        let json = #"{"rawKanata":{"_0":"(multi lctl c)"}}"#
        let action = try decode(KeyAction.self, from: json)
        XCTAssertEqual(action, .rawKanata("(multi lctl c)"))
    }

    // MARK: - MappingBehavior JSON decoding

    func testDecodeDualRoleBehavior() throws {
        let json = #"{"dualRole":{"tapAction":{"keystroke":{"key":"a"}},"holdAction":{"keystroke":{"key":"lctl"}},"tapTimeout":200,"holdTimeout":200,"activateHoldOnOtherKey":true}}"#
        let behavior = try decode(MappingBehavior.self, from: json)
        if case let .dualRole(d) = behavior {
            XCTAssertEqual(d.tapAction, .keystroke(key: "a"))
            XCTAssertEqual(d.holdAction, .keystroke(key: "lctl"))
            XCTAssertEqual(d.tapTimeout, 200)
            XCTAssertTrue(d.activateHoldOnOtherKey)
        } else {
            XCTFail("Expected dualRole")
        }
    }

    func testDecodeMacroBehavior() throws {
        let json = #"{"macro":{"text":"hello world","outputs":[],"source":"text"}}"#
        let behavior = try decode(MappingBehavior.self, from: json)
        if case let .macro(m) = behavior {
            XCTAssertEqual(m.text, "hello world")
            XCTAssertEqual(m.source, .text)
        } else {
            XCTFail("Expected macro")
        }
    }

    func testDecodeChordBehavior() throws {
        let json = #"{"chord":{"keys":["j","k"],"output":{"keystroke":{"key":"esc"}},"timeout":200}}"#
        let behavior = try decode(MappingBehavior.self, from: json)
        if case let .chord(c) = behavior {
            XCTAssertEqual(c.keys, ["j", "k"])
            XCTAssertEqual(c.output, .keystroke(key: "esc"))
            XCTAssertEqual(c.timeout, 200)
        } else {
            XCTFail("Expected chord")
        }
    }

    func testDecodeTapDanceBehavior() throws {
        let json = #"{"tapOrTapDance":{"tapDance":{"_0":{"windowMs":200,"steps":[{"label":"Single","action":{"keystroke":{"key":"esc"}}},{"label":"Double","action":{"keystroke":{"key":"caps"}}}]}}}}"#
        let behavior = try decode(MappingBehavior.self, from: json)
        if case let .tapOrTapDance(.tapDance(td)) = behavior {
            XCTAssertEqual(td.windowMs, 200)
            XCTAssertEqual(td.steps.count, 2)
            XCTAssertEqual(td.steps[0].action, .keystroke(key: "esc"))
        } else {
            XCTFail("Expected tapDance, got \(behavior)")
        }
    }

    // MARK: - Invalid JSON

    func testDecodeInvalidActionJSONThrows() {
        let json = #"{"bogus": "nope"}"#
        XCTAssertThrowsError(try decode(KeyAction.self, from: json))
    }

    func testDecodeInvalidBehaviorJSONThrows() {
        let json = #"{"notReal": {}}"#
        XCTAssertThrowsError(try decode(MappingBehavior.self, from: json))
    }

    func testDecodeMalformedJSONThrows() {
        let json = "not json at all"
        XCTAssertThrowsError(try decode(KeyAction.self, from: json))
    }

    // MARK: - End-to-end add with action JSON via facade

    func testAddRuleWithHyperAction() async throws {
        let result = try await facade.addRule(input: "caps", action: .hyper)
        guard case let .created(detail) = result else {
            XCTFail("Expected .created")
            return
        }
        XCTAssertEqual(detail.action, .hyper)

        let shown = await facade.showRule(input: "caps")
        XCTAssertEqual(shown?.action, .hyper)
    }

    func testAddRuleWithLaunchAppAction() async throws {
        let result = try await facade.addRule(
            input: "f1",
            action: .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created")
            return
        }
        XCTAssertEqual(detail.action, .launchApp(name: "Safari", bundleId: "com.apple.Safari"))
    }

    func testAddRuleWithMacroBehavior() async throws {
        let behavior = MappingBehavior.macro(MacroBehavior(text: "hello", source: .text))
        let result = try await facade.addRule(
            input: "f2",
            action: .keystroke(key: "f2"),
            behavior: behavior
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created")
            return
        }
        if case let .macro(m) = detail.behavior {
            XCTAssertEqual(m.text, "hello")
        } else {
            XCTFail("Expected macro behavior")
        }
    }

    func testAddRuleWithChordBehavior() async throws {
        let behavior = MappingBehavior.chord(ChordBehavior(
            keys: ["j", "k"],
            output: .keystroke(key: "esc"),
            timeout: 150
        ))
        let result = try await facade.addRule(
            input: "j",
            action: .keystroke(key: "j"),
            behavior: behavior
        )
        guard case let .created(detail) = result else {
            XCTFail("Expected .created")
            return
        }
        if case let .chord(c) = detail.behavior {
            XCTAssertEqual(c.keys, ["j", "k"])
            XCTAssertEqual(c.timeout, 150)
        } else {
            XCTFail("Expected chord behavior")
        }
    }

    // MARK: - CLIRuleDetail serialization round-trip

    func testRuleDetailEncodesAndDecodes() async throws {
        _ = try await facade.addRule(
            input: "caps",
            action: .hyper,
            shiftedOutput: "~",
            title: "Hyper Key",
            notes: "Makes caps into hyper",
            targetLayer: "base"
        )
        let detail = await facade.showRule(input: "caps")!

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(detail)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CLIRuleDetail.self, from: data)

        XCTAssertEqual(decoded.input, "caps")
        XCTAssertEqual(decoded.action, .hyper)
        XCTAssertEqual(decoded.shiftedOutput, "~")
        XCTAssertEqual(decoded.title, "Hyper Key")
        XCTAssertEqual(decoded.targetLayer, "base")
    }

    // MARK: - RuleAddResult serialization

    func testRuleAddResultCreatedEncodesCorrectly() throws {
        let detail = CLIRuleDetail(
            input: "caps", action: .hyper, behavior: nil,
            shiftedOutput: nil, title: nil, notes: nil,
            targetLayer: "base", deviceOverrides: nil,
            isEnabled: true, createdAt: Date()
        )
        let result = RuleAddResult.created(detail)
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"status\":\"created\""))
    }

    func testRuleAddResultSkippedEncodesCorrectly() throws {
        let result = RuleAddResult.skipped
        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"status\":\"skipped\""))
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(type, from: data)
    }
}
