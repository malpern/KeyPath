@testable import KeyPathAppKit
import XCTest

/// Tests for PackInstaller's pure rendering logic (renderBindings) and
/// Pack model computed properties. These don't require RuleCollectionsManager.
@MainActor
final class PackInstallerRenderTests: XCTestCase {

    // MARK: - renderBindings: simple remap (no holdOutput)

    func testRenderBindings_SimpleRemap_ProducesKeystrokeAction() {
        let pack = Pack(
            id: "test.simple",
            version: "1.0.0",
            name: "Test Simple",
            tagline: "test",
            shortDescription: "test",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "caps", output: "esc", title: "Caps → Escape")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        XCTAssertEqual(rules.count, 1)
        let rule = rules[0]
        XCTAssertEqual(rule.input, "caps")
        XCTAssertEqual(rule.action, .keystroke(key: "esc"))
        XCTAssertNil(rule.behavior)
        XCTAssertEqual(rule.packSource, "test.simple")
        XCTAssertTrue(rule.isEnabled)
        XCTAssertEqual(rule.title, "Caps → Escape")
    }

    // MARK: - renderBindings: tap-hold (with holdOutput)

    func testRenderBindings_TapHold_ProducesDualRoleBehavior() {
        let pack = Pack(
            id: "test.taphold",
            version: "1.0.0",
            name: "Test TapHold",
            tagline: "test",
            shortDescription: "test",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "a", output: "a", holdOutput: "lctl")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: ["holdTimeout": 180])

        XCTAssertEqual(rules.count, 1)
        let rule = rules[0]
        XCTAssertEqual(rule.input, "a")
        XCTAssertNotNil(rule.behavior)
        if case let .dualRole(dr) = rule.behavior {
            XCTAssertEqual(dr.tapTimeout, 180)
            XCTAssertEqual(dr.holdTimeout, 180)
            XCTAssertTrue(dr.activateHoldOnOtherKey)
        } else {
            XCTFail("Expected dualRole behavior")
        }
    }

    func testRenderBindings_TapHold_DefaultTimeout200() {
        let pack = Pack(
            id: "test.taphold",
            version: "1.0.0",
            name: "Test",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "f", output: "f", holdOutput: "lmet")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        if case let .dualRole(dr) = rules.first?.behavior {
            XCTAssertEqual(dr.tapTimeout, 200)
            XCTAssertEqual(dr.holdTimeout, 200)
        } else {
            XCTFail("Expected dualRole behavior with default 200ms timeout")
        }
    }

    // MARK: - renderBindings: multiple bindings

    func testRenderBindings_MultipleBindings_ProducesMatchingRules() {
        let pack = Pack(
            id: "test.multi",
            version: "1.0.0",
            name: "Test Multi",
            tagline: "test",
            shortDescription: "test",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "a", output: "a", holdOutput: "lctl", title: "A mod"),
                PackBindingTemplate(input: "s", output: "s", holdOutput: "lalt", title: "S mod"),
                PackBindingTemplate(input: "caps", output: "esc", title: "Caps remap")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        XCTAssertEqual(rules.count, 3)
        XCTAssertEqual(rules[0].input, "a")
        XCTAssertEqual(rules[1].input, "s")
        XCTAssertEqual(rules[2].input, "caps")

        XCTAssertNotNil(rules[0].behavior)
        XCTAssertNotNil(rules[1].behavior)
        XCTAssertNil(rules[2].behavior)
    }

    // MARK: - renderBindings: pack source tagging

    func testRenderBindings_AllRulesTaggedWithPackID() {
        let pack = Pack(
            id: "com.keypath.pack.custom-test",
            version: "1.0.0",
            name: "Custom",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "x", output: "y"),
                PackBindingTemplate(input: "z", output: "w")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        for rule in rules {
            XCTAssertEqual(rule.packSource, "com.keypath.pack.custom-test")
        }
    }

    // MARK: - renderBindings: title fallback

    func testRenderBindings_NoTitle_UsesPackNameWithInput() {
        let pack = Pack(
            id: "test.notitle",
            version: "1.0.0",
            name: "My Pack",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "q", output: "w")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        XCTAssertEqual(rules.first?.title, "My Pack · Q")
    }

    // MARK: - renderBindings: notes pass-through

    func testRenderBindings_NotesPassedThrough() {
        let pack = Pack(
            id: "test.notes",
            version: "1.0.0",
            name: "Notes Pack",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "a", output: "b", notes: "This is a note")
            ]
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])

        XCTAssertEqual(rules.first?.notes, "This is a note")
    }

    // MARK: - renderBindings: empty bindings

    func testRenderBindings_EmptyBindings_ProducesNoRules() {
        let pack = Pack(
            id: "test.empty",
            version: "1.0.0",
            name: "Empty Pack",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: []
        )

        let rules = PackInstaller.shared.renderBindings(for: pack, quickSettings: [:])
        XCTAssertTrue(rules.isEmpty)
    }

    // MARK: - Pack model properties

    func testAffectedKeys_DeduplicatesInputs() {
        let pack = Pack(
            id: "test.dedup",
            version: "1.0.0",
            name: "Dedup",
            tagline: "t",
            shortDescription: "t",
            longDescription: "",
            category: "Test",
            iconSymbol: "star",
            bindings: [
                PackBindingTemplate(input: "a", output: "b"),
                PackBindingTemplate(input: "a", output: "c"),
                PackBindingTemplate(input: "d", output: "e")
            ]
        )

        XCTAssertEqual(Set(pack.affectedKeys), Set(["a", "d"]))
    }

    func testManagedCollectionIDs_VisualOnly_ReturnsEmpty() {
        let pack = PackRegistry.kindaVim
        XCTAssertTrue(pack.managedCollectionIDs.isEmpty)
    }

    func testManagedCollectionIDs_CollectionBacked_ReturnsSingleID() {
        let pack = PackRegistry.capsLockToEscape
        XCTAssertEqual(pack.managedCollectionIDs, [RuleCollectionIdentifier.capsLockRemap])
    }

    func testManagedCollectionIDs_VallackSystem_ReturnsThreeCollections() {
        let pack = PackRegistry.vallackSystem
        XCTAssertEqual(pack.managedCollectionIDs.count, 3)
        XCTAssertTrue(pack.managedCollectionIDs.contains(RuleCollectionIdentifier.vallackNavigation))
        XCTAssertTrue(pack.managedCollectionIDs.contains(RuleCollectionIdentifier.homeRowMods))
        XCTAssertTrue(pack.managedCollectionIDs.contains(RuleCollectionIdentifier.homeRowLayerToggles))
    }

    func testPreferredDetailWidth_WidePacksReturn760() {
        let widePacks = ["com.keypath.pack.vim-navigation", "com.keypath.pack.window-snapping"]
        for packID in widePacks {
            let pack = PackRegistry.pack(id: packID)!
            XCTAssertEqual(pack.preferredDetailWidth, 760, "Expected 760 for \(packID)")
        }
    }

    func testPreferredDetailWidth_HomeRowMods860() {
        XCTAssertEqual(PackRegistry.homeRowMods.preferredDetailWidth, 860)
    }

    func testPreferredDetailWidth_Launcher960() {
        XCTAssertEqual(PackRegistry.launcher.preferredDetailWidth, 960)
    }

    // MARK: - PackQuickSetting

    func testPackQuickSetting_DefaultSliderValue() {
        let setting = PackQuickSetting(
            id: "holdTimeout",
            label: "Hold timing",
            kind: .slider(defaultValue: 180, min: 120, max: 300, step: 20, unitSuffix: " ms")
        )
        XCTAssertEqual(setting.defaultSliderValue, 180)
    }

    // MARK: - PackBindingTemplate

    func testPackBindingTemplate_Equality() {
        let a = PackBindingTemplate(input: "a", output: "b", holdOutput: "lctl")
        let b = PackBindingTemplate(input: "a", output: "b", holdOutput: "lctl")
        let c = PackBindingTemplate(input: "a", output: "b", holdOutput: "lalt")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - InstallError descriptions

    func testInstallError_Descriptions() {
        let noManager = PackInstaller.InstallError.noRuleCollectionsManager
        XCTAssertNotNil(noManager.errorDescription)
        XCTAssertTrue(noManager.errorDescription!.contains("not available"))

        let saveFailed = PackInstaller.InstallError.saveFailed("disk full")
        XCTAssertTrue(saveFailed.errorDescription!.contains("disk full"))

        let mutex = PackInstaller.InstallError.mutuallyExclusive(
            conflicts: [(id: "a", name: "Pack A"), (id: "b", name: "Pack B")]
        )
        XCTAssertTrue(mutex.errorDescription!.contains("Pack A"))
        XCTAssertTrue(mutex.errorDescription!.contains("Pack B"))

        let depMissing = PackInstaller.InstallError.dependencyMissing(
            name: "KindaVim",
            websiteURL: URL(string: "https://kindavim.app")!
        )
        XCTAssertTrue(depMissing.errorDescription!.contains("KindaVim"))
    }
}
