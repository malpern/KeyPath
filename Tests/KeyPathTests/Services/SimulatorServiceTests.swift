@testable import KeyPathAppKit
@preconcurrency import XCTest

final class SimulatorServiceTests: XCTestCase {
    // MARK: - JSON Parsing Tests

    func testParseSimulationResult() throws {
        let json = """
        {
            "events": [
                {"type": "input", "t": 0, "action": "press", "key": "j"},
                {"type": "output", "t": 0, "action": "press", "key": "j"},
                {"type": "input", "t": 200, "action": "release", "key": "j"},
                {"type": "output", "t": 200, "action": "release", "key": "j"}
            ],
            "finalLayer": "base",
            "duration_ms": 200
        }
        """

        let result = try JSONDecoder().decode(SimulationResult.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(result.events.count, 4)
        XCTAssertEqual(result.finalLayer, "base")
        XCTAssertEqual(result.durationMs, 200)
    }

    func testParseInputEvent() throws {
        let json = """
        {"type": "input", "t": 100, "action": "press", "key": "a"}
        """

        let event = try JSONDecoder().decode(SimEvent.self, from: XCTUnwrap(json.data(using: .utf8)))

        if case let .input(t, action, key) = event {
            XCTAssertEqual(t, 100)
            XCTAssertEqual(action, .press)
            XCTAssertEqual(key, "a")
        } else {
            XCTFail("Expected input event")
        }
    }

    func testParseOutputEvent() throws {
        let json = """
        {"type": "output", "t": 50, "action": "release", "key": "lsft"}
        """

        let event = try JSONDecoder().decode(SimEvent.self, from: XCTUnwrap(json.data(using: .utf8)))

        if case let .output(t, action, key) = event {
            XCTAssertEqual(t, 50)
            XCTAssertEqual(action, .release)
            XCTAssertEqual(key, "lsft")
        } else {
            XCTFail("Expected output event")
        }
    }

    func testParseLayerEvent() throws {
        let json = """
        {"type": "layer", "t": 1500, "from": "base", "to": "nav"}
        """

        let event = try JSONDecoder().decode(SimEvent.self, from: XCTUnwrap(json.data(using: .utf8)))

        if case let .layer(t, from, to) = event {
            XCTAssertEqual(t, 1500)
            XCTAssertEqual(from, "base")
            XCTAssertEqual(to, "nav")
        } else {
            XCTFail("Expected layer event")
        }
    }

    func testParseUnicodeEvent() throws {
        let json = """
        {"type": "unicode", "t": 300, "char": "😀"}
        """

        let event = try JSONDecoder().decode(SimEvent.self, from: XCTUnwrap(json.data(using: .utf8)))

        if case let .unicode(t, char) = event {
            XCTAssertEqual(t, 300)
            XCTAssertEqual(char, "😀")
        } else {
            XCTFail("Expected unicode event")
        }
    }

    func testParseMouseEvent() throws {
        let json = """
        {"type": "mouse", "t": 400, "action": "click", "data": "left"}
        """

        let event = try JSONDecoder().decode(SimEvent.self, from: XCTUnwrap(json.data(using: .utf8)))

        if case let .mouse(t, action, data) = event {
            XCTAssertEqual(t, 400)
            XCTAssertEqual(action, .click)
            XCTAssertEqual(data, "left")
        } else {
            XCTFail("Expected mouse event")
        }
    }

    func testNullFinalLayer() throws {
        let json = """
        {
            "events": [],
            "finalLayer": null,
            "duration_ms": 0
        }
        """

        let result = try JSONDecoder().decode(SimulationResult.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertNil(result.finalLayer)
    }

    // MARK: - Sim Content Generation

    func testGenerateSimContent() async {
        let service = SimulatorService()
        let taps = [
            SimulatorKeyTap(kanataKey: "a", displayLabel: "A", delayAfterMs: 200),
            SimulatorKeyTap(kanataKey: "s", displayLabel: "S", delayAfterMs: 50)
        ]

        let content = await service.generateSimContent(from: taps)

        XCTAssertEqual(content, "d:a t:200 u:a d:s t:50 u:s")
    }

    func testGenerateSimContentEmpty() async {
        let service = SimulatorService()
        let content = await service.generateSimContent(from: [])

        XCTAssertEqual(content, "")
    }

    // MARK: - ViewModel Key Mapping

    func testKeyCodeToKanataName() {
        // Test common keys
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(0), "a")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(1), "s")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(2), "d")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(3), "f")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(49), "spc")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(36), "ret")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(48), "tab")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(56), "lsft")
        XCTAssertEqual(SimulatorViewModel.keyCodeToKanataName(55), "lmet")
    }

    func testDisplayLabelForKanataKey() {
        XCTAssertEqual(SimulatorViewModel.displayLabelForKanataKey("spc"), "Space")
        XCTAssertEqual(SimulatorViewModel.displayLabelForKanataKey("ret"), "Return")
        XCTAssertEqual(SimulatorViewModel.displayLabelForKanataKey("lsft"), "Shift")
        XCTAssertEqual(SimulatorViewModel.displayLabelForKanataKey("a"), "A")
    }
}
