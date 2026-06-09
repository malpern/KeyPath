@testable import KeyPathAppKit
import KeyPathCore
import Testing

@Suite("LayerMappingBuilder")
struct LayerMappingBuilderTests {
    // MARK: - mergeAugmentation

    @Test("vimLabel preserved from original through merge")
    func mergePreservesVimLabel() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            vimLabel: "←"
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

        #expect(result.vimLabel == "←")
        #expect(result.displayLabel == "←")
    }

    @Test("collectionId preserved from original through merge")
    func mergePreservesCollectionId() {
        let id = RuleCollectionIdentifier.vimNavigation
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: id,
            vimLabel: "←"
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

        #expect(result.collectionId == id)
    }

    // MARK: - buildRemapOutputMap

    @Test("remapped keys appear in output map")
    func remapOutputMapIncludesRemaps() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "B", outputKey: "b", outputKeyCode: 11)
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result[0] == 11)
    }

    @Test("identity mappings excluded from output map")
    func remapOutputMapExcludesIdentity() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "A", outputKey: "a", outputKeyCode: 0)
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result.isEmpty)
    }

    @Test("transparent keys excluded from output map")
    func remapOutputMapExcludesTransparent() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "B",
                outputKey: "b",
                outputKeyCode: 11,
                isTransparent: true,
                isLayerSwitch: false
            )
        ]

        let result = LayerMappingBuilder.buildRemapOutputMap(from: mapping)

        #expect(result.isEmpty)
    }

    // MARK: - extractPushMsgInfo

    @Test("extracts app launch from push-msg")
    func extractAppLaunch() {
        let output = #"(push-msg "launch:Safari")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.appLaunchIdentifier == "Safari")
    }

    @Test("extracts system action from push-msg")
    func extractSystemAction() {
        let output = #"(push-msg "system:spotlight")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.systemActionIdentifier == "spotlight")
    }

    @Test("extracts URL from push-msg")
    func extractURL() {
        let output = #"(push-msg "open:github.com")"#
        let result = LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil)

        #expect(result?.urlIdentifier != nil)
    }

    @Test("returns nil for non-push-msg output")
    func nonPushMsgReturnsNil() {
        let result = LayerMappingBuilder.extractPushMsgInfo(from: "a", description: nil)

        #expect(result == nil)
    }

    // MARK: - Static push-msg regex compilation guards

    //
    // The four push-msg regexes in LayerMappingBuilder are compiled with `try!`
    // as `private static let` properties (issue #854). These tests exercise each
    // regex once so any malformed pattern crashes the test suite at access time
    // — not at app launch — until/unless a centralized safe-regex factory lands.

    @Test("extractAppLaunchIdentifier exercises pushMsgLaunchRegex")
    func extractAppLaunchIdentifierMatches() {
        let output = #"(push-msg "launch:Safari")"#

        #expect(LayerMappingBuilder.extractAppLaunchIdentifier(from: output) == "Safari")
        #expect(LayerMappingBuilder.extractAppLaunchIdentifier(from: "noop") == nil)
    }

    @Test("extractUrlIdentifier exercises pushMsgOpenRegex")
    func extractURLIdentifierMatches() {
        let output = #"(push-msg "open:github.com")"#

        #expect(LayerMappingBuilder.extractUrlIdentifier(from: output) != nil)
        #expect(LayerMappingBuilder.extractUrlIdentifier(from: "noop") == nil)
    }

    @Test("extractSystemActionIdentifier exercises pushMsgSystemRegex")
    func extractSystemActionIdentifierMatches() {
        let output = #"(push-msg "system:spotlight")"#

        #expect(LayerMappingBuilder.extractSystemActionIdentifier(from: output) == "spotlight")
        #expect(LayerMappingBuilder.extractSystemActionIdentifier(from: "noop") == nil)
    }

    @Test("extractPushMsgInfo exercises pushMsgTypeValueRegex")
    func extractPushMsgInfoMatches() {
        let output = #"(push-msg "launch:Safari")"#

        #expect(LayerMappingBuilder.extractPushMsgInfo(from: output, description: nil) != nil)
        #expect(LayerMappingBuilder.extractPushMsgInfo(from: "noop", description: nil) == nil)
    }

    // MARK: - Pipeline invariant: vimLabels survive augmentation

    @Test("all four HJKL vimLabels survive mergeAugmentation")
    func allArrowVimLabelsSurviveMerge() {
        let arrows: [(key: String, label: String, code: UInt16)] = [
            ("left", "←", 123), ("down", "↓", 125),
            ("up", "↑", 126), ("right", "→", 124)
        ]

        for arrow in arrows {
            let original = LayerKeyInfo.mapped(
                displayLabel: arrow.label,
                outputKey: arrow.key,
                outputKeyCode: arrow.code,
                vimLabel: arrow.label
            )
            let augmented = LayerKeyInfo(
                displayLabel: "\(arrow.key) — \(arrow.key)",
                outputKey: arrow.key,
                outputKeyCode: arrow.code,
                isTransparent: false,
                isLayerSwitch: false
            )

            let result = LayerMappingBuilder.mergeAugmentation(augmented, with: original)

            #expect(result.vimLabel == arrow.label, "vimLabel for \(arrow.key) should survive")
            #expect(result.displayLabel == arrow.label, "displayLabel for \(arrow.key) should use original")
        }
    }

    // MARK: - systemActionDisplayLabel

    @Test("known system actions get friendly names")
    func systemActionLabels() {
        #expect(LayerMappingBuilder.systemActionDisplayLabel("spotlight") == "Spotlight")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("dnd") == "Do Not Disturb")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("mission-control") == "Mission Control")
        #expect(LayerMappingBuilder.systemActionDisplayLabel("notification-center") == "Notification Center")
    }

    @Test("unknown system actions get capitalized")
    func unknownSystemActionCapitalized() {
        #expect(LayerMappingBuilder.systemActionDisplayLabel("custom-thing") == "Custom-Thing")
    }

    // MARK: - mediaKeyDisplayLabel

    @Test("media keys get display labels")
    func mediaKeyLabels() {
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("brup") == "Brightness Up")
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("volu") == "Volume Up")
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("pp") == "Play/Pause")
    }

    @Test("non-media keys return nil")
    func nonMediaKeyReturnsNil() {
        #expect(LayerMappingBuilder.mediaKeyDisplayLabel("a") == nil)
    }

    // MARK: - Home Row Mods augmentation

    @Test("home row mods augment base layer with hold modifier labels")
    func homeRowModsAugmentBaseLayerWithHoldModifierLabels() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "A",
                outputKey: "a",
                outputKeyCode: 0,
                isTransparent: true,
                isLayerSwitch: false
            ),
            1: LayerKeyInfo(
                displayLabel: "S",
                outputKey: "s",
                outputKeyCode: 1,
                isTransparent: true,
                isLayerSwitch: false
            ),
            41: LayerKeyInfo(
                displayLabel: ";",
                outputKey: "semicolon",
                outputKeyCode: 41,
                isTransparent: true,
                isLayerSwitch: false
            ),
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a", "s", ";"],
            modifierAssignments: ["a": "lsft", "s": "lctl", ";": "rsft"]
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "base"
        )

        #expect(result[0]?.displayLabel == "⇧")
        #expect(result[1]?.displayLabel == "⌃")
        // Semicolon verifies the dual-registration path for config aliases like ";" vs overlay names.
        #expect(result[41]?.displayLabel == "⇧")
        #expect(result[0]?.collectionId == RuleCollectionIdentifier.homeRowMods)
        #expect(result[0]?.isTransparent == false)
    }

    @Test("home row mods augmentation ignores non-base layer")
    func homeRowModsAugmentationIgnoresNonBaseLayer() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: .mapped(displayLabel: "←", outputKey: "left", outputKeyCode: 123)
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a"],
            modifierAssignments: ["a": "lsft"]
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "nav"
        )

        #expect(result[0]?.displayLabel == "←")
    }

    @Test("home row mods layer hold mode injects assigned layer labels")
    func homeRowModsLayerHoldModeInjectsAssignedLayerLabels() {
        let mapping: [UInt16: LayerKeyInfo] = [
            0: LayerKeyInfo(
                displayLabel: "A",
                outputKey: "a",
                outputKeyCode: 0,
                isTransparent: true,
                isLayerSwitch: false
            ),
            41: LayerKeyInfo(
                displayLabel: ";",
                outputKey: "semicolon",
                outputKeyCode: 41,
                isTransparent: true,
                isLayerSwitch: false
            ),
        ]
        let config = HomeRowModsConfig(
            enabledKeys: ["a", ";"],
            modifierAssignments: ["a": "lsft"],
            layerAssignments: ["a": "nav", ";": "fun"],
            holdMode: .layers
        )
        let collection = RuleCollection(
            id: RuleCollectionIdentifier.homeRowMods,
            name: "Home Row Mods",
            summary: "",
            category: .productivity,
            mappings: [],
            isEnabled: true,
            isSystemDefault: true,
            configuration: .homeRowMods(config)
        )

        let result = LayerMappingBuilder.augmentWithPushMsgActions(
            mapping: mapping,
            customRules: [],
            ruleCollections: [collection],
            currentLayerName: "base"
        )

        #expect(result[0]?.displayLabel == "Nav")
        #expect(result[41]?.displayLabel == "Fun")
        #expect(result[0]?.collectionId == RuleCollectionIdentifier.homeRowMods)
        #expect(result[0]?.isTransparent == false)
    }
}
