@testable import KeyPathAppKit
import XCTest

final class CLIParityTests: XCTestCase {
    func testAllKeyActionCasesHaveCLISchemaName() {
        let actions: [KeyAction] = [
            .keystroke(key: "a"), .hyper, .meh,
            .launchApp(name: "App", bundleId: nil),
            .openURL("https://example.com"),
            .openFolder(path: "/tmp", name: nil),
            .runScript(path: "/tmp/s.sh", name: nil),
            .systemAction(id: "volume-up"),
            .notify(title: "hi", body: nil, sound: false),
            .windowAction(position: "left-half"),
            .fakeKey(name: "vk1", action: .tap),
            .activateLayer(name: "nav"),
            .rawKanata("XX"),
        ]
        for action in actions {
            XCTAssertFalse(action.cliSchemaName.isEmpty, "Empty schema name for \(action)")
        }
    }

    func testAllMappingBehaviorCasesHaveCLISchemaName() {
        let behaviors: [MappingBehavior] = [
            .dualRole(DualRoleBehavior(tapAction: .keystroke(key: "a"), holdAction: .keystroke(key: "lctl"))),
            .tapOrTapDance(.tap),
            .macro(MacroBehavior()),
            .chord(ChordBehavior(keys: ["j", "k"], output: .keystroke(key: "esc"))),
        ]
        for behavior in behaviors {
            XCTAssertFalse(behavior.cliSchemaName.isEmpty, "Empty schema name for \(behavior)")
        }
    }

    func testSchemaNamesDontCollide() {
        let actionNames = KeyAction.allSchemaDescriptions.map(\.name)
        XCTAssertEqual(actionNames.count, Set(actionNames).count, "KeyAction schema names have collision: \(actionNames)")

        let behaviorNames = MappingBehavior.allSchemaDescriptions.map(\.name)
        XCTAssertEqual(behaviorNames.count, Set(behaviorNames).count, "MappingBehavior schema names have collision: \(behaviorNames)")
    }

    func testActionSchemaCount() {
        XCTAssertEqual(KeyAction.allSchemaDescriptions.count, 13, "Expected 13 KeyAction schemas (one per case)")
    }

    func testBehaviorSchemaCount() {
        XCTAssertEqual(MappingBehavior.allSchemaDescriptions.count, 4, "Expected 4 MappingBehavior schemas (one per case)")
    }

    func testAllSchemasHaveDescriptions() {
        for entry in KeyAction.allSchemaDescriptions {
            XCTAssertFalse(entry.description.isEmpty, "Empty description for action schema '\(entry.name)'")
        }
        for entry in MappingBehavior.allSchemaDescriptions {
            XCTAssertFalse(entry.description.isEmpty, "Empty description for behavior schema '\(entry.name)'")
        }
    }
}
