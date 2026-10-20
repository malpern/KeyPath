@testable import KeyPathAppKit
import KeyPathRulesCore
import SwiftUI
import XCTest

@MainActor
final class ShortcutListAlignmentTests: XCTestCase {
    func testMissionControlReadsByNameAndMatchesTheOverlayColor() throws {
        let missionControl = try XCTUnwrap(RuleCollectionCatalog().defaultCollections().first { $0.id == RuleCollectionIdentifier.missionControl })
        let keyMap: [UInt16: LayerKeyInfo] = [
            46: .mapped(displayLabel: "↑⌃", outputKey: "up", outputKeyCode: nil, collectionId: missionControl.id), // m
            43: .mapped(displayLabel: "←⌃", outputKey: "left", outputKeyCode: nil, collectionId: missionControl.id) // ,
        ]
        let vm = ContextHUDViewModel()
        vm.update(layerName: "nav", keyMap: keyMap, collections: [missionControl], style: .defaultList)

        let entries = vm.groups.flatMap(\.entries)
        XCTAssertEqual(Set(entries.map(\.action)), ["Mission Control", "Previous Desktop"])
        let overlayColor = KeycapSymbols.collectionColor(for: missionControl.id)
        XCTAssertTrue(vm.groups.allSatisfy { $0.color == overlayColor }, "same color as the overlay")
    }

    func testMissionControlKeycapLabelsFitOneKey() {
        for label in LayerKeyMapper.missionControlKeycapLabels.values {
            XCTAssertLessThanOrEqual(label.count, 7, label)
        }
    }
}
