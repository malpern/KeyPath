@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

/// Turning Caps Lock remapping off warns only when enabled rules actually use Caps Lock.
final class SessionCapsSettingsSectionTests: XCTestCase {
    private func collection(input: String, enabled: Bool = true) -> RuleCollection {
        RuleCollection(
            name: "Test", summary: "", category: .productivity,
            mappings: [KeyMapping(input: input, action: .keystroke(key: "esc"))], isEnabled: enabled
        )
    }

    func testEnabledCollectionMappingCapsCounts() {
        XCTAssertTrue(SessionCapsSettingsSection.rulesUseCapsLock(collections: [collection(input: "caps")], customRules: []))
        XCTAssertTrue(SessionCapsSettingsSection.rulesUseCapsLock(collections: [collection(input: "CapsLock")], customRules: []))
    }

    func testDisabledOrUnrelatedRulesDoNotCount() {
        XCTAssertFalse(SessionCapsSettingsSection.rulesUseCapsLock(
            collections: [collection(input: "caps", enabled: false), collection(input: "a")], customRules: []
        ))
    }

    func testEnabledCustomRuleOnCapsCounts() {
        let rule = CustomRule(input: "caps", action: .keystroke(key: "esc"))
        XCTAssertTrue(SessionCapsSettingsSection.rulesUseCapsLock(collections: [], customRules: [rule]))
    }
}
