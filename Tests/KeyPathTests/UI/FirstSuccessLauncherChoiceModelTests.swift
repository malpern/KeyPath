import AppKit
@testable import KeyPathAppKit
import KeyPathRulesCore
import XCTest

@MainActor
final class FirstSuccessLauncherChoiceModelTests: XCTestCase {
    func testChoiceRequiresBothAnAppAndAKey() {
        let model = FirstSuccessLauncherChoiceModel()

        XCTAssertFalse(model.canApply)
        XCTAssertNil(model.mapping)
        XCTAssertEqual(
            localized(model.validationMessage),
            "Choose an app and a letter."
        )

        model.selectedApp = safari

        XCTAssertFalse(model.canApply)
        XCTAssertEqual(
            localized(model.validationMessage),
            "Choose one letter for the shortcut."
        )
    }

    func testCanonicalKeyNormalizesCaseAndWhitespace() {
        let model = FirstSuccessLauncherChoiceModel(selectedApp: safari)

        model.setCanonicalKey(" Q ")
        XCTAssertEqual(model.canonicalKey, "q")
        XCTAssertEqual(model.displayedKey, "Q")
        XCTAssertTrue(model.canApply)
    }

    func testNewShortcutGraphemeReplacesTheDisplayedKey() {
        XCTAssertEqual(
            FirstSuccessLauncherChoiceModel.replacementDisplayGrapheme(
                from: "QW",
                replacing: "Q"
            ),
            "W"
        )
        XCTAssertEqual(
            FirstSuccessLauncherChoiceModel.replacementDisplayGrapheme(
                from: "WQ",
                replacing: "Q"
            ),
            "W"
        )
        XCTAssertEqual(
            FirstSuccessLauncherChoiceModel.replacementDisplayGrapheme(
                from: "Q🚀",
                replacing: "Q"
            ),
            "🚀"
        )
    }

    func testOnlyOnePhysicalLetterCanApply() {
        let model = FirstSuccessLauncherChoiceModel(selectedApp: safari)

        for invalidKey in ["qq", "1", ";", "semicolon", "é"] {
            model.setCanonicalKey(invalidKey)

            XCTAssertFalse(model.canApply)
            XCTAssertNil(model.mapping)
            XCTAssertEqual(localized(model.validationMessage), "Use a single letter.")
        }
    }

    func testOccupiedCanonicalKeyCannotApply() {
        let model = FirstSuccessLauncherChoiceModel(
            selectedApp: safari,
            canonicalKey: "Q",
            occupiedCanonicalKeys: [" q ", "Z", ";", "1"]
        )

        XCTAssertEqual(model.occupiedCanonicalKeys, ["1", "q", "semicolon", "z"])
        XCTAssertFalse(model.canApply)
        XCTAssertNil(model.mapping)
        XCTAssertEqual(
            localized(model.validationMessage),
            "That letter already has a shortcut. Choose another."
        )
    }

    func testOccupiedCanonicalKeysCanBeReplacedAndStayNormalized() {
        let model = FirstSuccessLauncherChoiceModel(
            selectedApp: safari,
            canonicalKey: "m"
        )
        XCTAssertTrue(model.canApply)

        model.setOccupiedCanonicalKeys([" M ", "x", "4"])

        XCTAssertEqual(model.occupiedCanonicalKeys, ["4", "m", "x"])
        XCTAssertFalse(model.canApply)
        XCTAssertNil(model.mapping)
    }

    func testLogicalLetterCanMapToCanonicalPunctuationOnAnAlternateKeymap() throws {
        let model = FirstSuccessLauncherChoiceModel(selectedApp: safari)

        model.setCanonicalKey("slash", displayedAs: "Z")

        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.displayedKey, "Z")
        XCTAssertEqual(try XCTUnwrap(model.mapping).key, "slash")

        model.setCanonicalKey("slash", displayedAs: "/")
        XCTAssertFalse(model.canApply)
        XCTAssertNil(model.mapping)
    }

    func testMappingUsesCanonicalKeyAndSelectedApplication() throws {
        let model = FirstSuccessLauncherChoiceModel(
            selectedApp: safari,
            canonicalKey: "Q"
        )

        let firstMapping = try XCTUnwrap(model.mapping)
        let secondMapping = try XCTUnwrap(model.mapping)

        XCTAssertTrue(model.canApply)
        XCTAssertNil(model.validationMessage)
        XCTAssertEqual(firstMapping.id, secondMapping.id)
        XCTAssertEqual(firstMapping.key, "q")
        XCTAssertEqual(
            firstMapping.action,
            .launchApp(name: "Safari", bundleId: "com.apple.Safari")
        )
        XCTAssertTrue(firstMapping.isEnabled)
    }

    func testMappingAllowsApplicationWithoutBundleIdentifier() throws {
        let app = AppLaunchInfo(
            name: "Local Tool",
            bundleIdentifier: nil,
            icon: NSImage()
        )
        let model = FirstSuccessLauncherChoiceModel(
            selectedApp: app,
            canonicalKey: "t"
        )

        let mapping = try XCTUnwrap(model.mapping)

        XCTAssertEqual(
            mapping.action,
            .launchApp(name: "Local Tool", bundleId: nil)
        )
    }

    private var safari: AppLaunchInfo {
        AppLaunchInfo(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            icon: NSImage()
        )
    }

    private func localized(_ resource: LocalizedStringResource?) -> String? {
        resource.map { String(localized: $0) }
    }
}
