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
}
