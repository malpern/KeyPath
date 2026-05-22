@testable import KeyPathAppKit
@preconcurrency import XCTest

final class TimelineGrouperTests: XCTestCase {
    private func makeKeyInput(key: String, action: KanataKeyAction = .press, layer: String? = "base") -> KeystrokeTimelineEvent {
        KeystrokeTimelineEvent(
            id: UUID(),
            timestamp: Date(),
            kind: .keyInput(KeyInputPayload(key: key, action: action, layer: layer, kanataTimestamp: nil))
        )
    }

    private func makeLayerChange(layer: String) -> KeystrokeTimelineEvent {
        KeystrokeTimelineEvent(
            id: UUID(),
            timestamp: Date(),
            kind: .layerChanged(LayerChangePayload(layerName: layer))
        )
    }

    private func makeHoldActivated(key: String, action: String) -> KeystrokeTimelineEvent {
        KeystrokeTimelineEvent(
            id: UUID(),
            timestamp: Date(),
            kind: .holdActivated(TapHoldPayload(key: key, outputAction: action, reason: "timeout", kanataTimestamp: 0))
        )
    }

    // MARK: - Text Run Grouping

    func testConsecutivePrintableKeysGroupIntoTextRun() {
        let events = ["h", "e", "l", "l", "o"].map { makeKeyInput(key: $0) }
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 1)
        if case let .textRun(run) = segments.first {
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), "hello")
        } else {
            XCTFail("Expected text run")
        }
    }

    func testModifierKeysExcludedFromTextRun() {
        let events = [
            makeKeyInput(key: "a"),
            makeKeyInput(key: "lsft"),
            makeKeyInput(key: "b"),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 1)
        if case let .textRun(run) = segments.first {
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), "ab")
        } else {
            XCTFail("Expected text run")
        }
    }

    func testReleaseEventsSkipped() {
        let events = [
            makeKeyInput(key: "a", action: .press),
            makeKeyInput(key: "a", action: .release),
            makeKeyInput(key: "b", action: .press),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 1)
        if case let .textRun(run) = segments.first {
            XCTAssertEqual(run.characters.count, 2)
        } else {
            XCTFail("Expected text run")
        }
    }

    func testNonPrintableKeyBreaksTextRun() {
        let events = [
            makeKeyInput(key: "a"),
            makeKeyInput(key: "esc"),
            makeKeyInput(key: "b"),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 3)
        if case .textRun = segments[0], case .eventCard = segments[1], case .textRun = segments[2] {
            // correct
        } else {
            XCTFail("Expected textRun, eventCard, textRun")
        }
    }

    // MARK: - Layer Dividers

    func testLayerChangeCreatesLayerDivider() {
        let events = [
            makeKeyInput(key: "a"),
            makeLayerChange(layer: "nav"),
            makeKeyInput(key: "b"),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "nav")
        XCTAssertEqual(segments.count, 3)
        if case let .layerDivider(divider) = segments[1] {
            XCTAssertEqual(divider.layerName, "nav")
        } else {
            XCTFail("Expected layer divider")
        }
    }

    // MARK: - Event Cards

    func testTapHoldCreatesEventCard() {
        let events = [
            makeKeyInput(key: "a"),
            makeHoldActivated(key: "caps", action: "lctl"),
            makeKeyInput(key: "b"),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 3)
        if case let .eventCard(card) = segments[1],
           case let .tapHold(data) = card.cardKind
        {
            XCTAssertEqual(data.key, "caps")
            XCTAssertTrue(data.isHold)
        } else {
            XCTFail("Expected tap-hold event card")
        }
    }

    func testEmptyInputProducesNoSegments() {
        let segments = TimelineGrouper.group([], currentLayer: "base")
        XCTAssertTrue(segments.isEmpty)
    }

    func testSpecialCharacterMapping() {
        let events = [
            makeKeyInput(key: "spc"),
            makeKeyInput(key: "comm"),
            makeKeyInput(key: "dot"),
        ]
        let segments = TimelineGrouper.group(events, currentLayer: "base")
        XCTAssertEqual(segments.count, 1)
        if case let .textRun(run) = segments.first {
            XCTAssertEqual(run.characters.map(\.displayChar).joined(), " ,.")
        } else {
            XCTFail("Expected text run")
        }
    }
}
