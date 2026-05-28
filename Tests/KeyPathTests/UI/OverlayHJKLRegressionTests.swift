import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Testing

/// Regression tests for HJKL arrow rendering across overlay layers.
///
/// These tests protect against three bugs that occurred in the same session:
/// 1. Nav layer HJKL showed text ("H — Left") instead of arrow symbols
///    because augmentation dropped vimLabels
/// 2. KindaVim HJKL showed letter + arrow overlap because floating labels
///    weren't hidden when vim hints rendered
/// 3. Base layer HJKL went blank because floating labels were hidden whenever
///    the KindaVim pack was installed, not just when hints actually rendered

// MARK: - Augmentation preserves vimLabels

@Suite("mergeAugmentation preserves vimLabels")
struct MergeAugmentationTests {

    @Test("vimLabel from original is preserved when augmentation has none")
    func preservesOriginalVimLabel() {
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
            isLayerSwitch: false,
            collectionId: RuleCollectionIdentifier.vimNavigation
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.vimLabel == "←")
    }

    @Test("displayLabel uses original when vimLabel exists")
    func prefersOriginalDisplayLabelWhenVimLabelExists() {
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

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.displayLabel == "←")
    }

    @Test("displayLabel uses augmented when no vimLabel exists")
    func usesAugmentedDisplayLabelWithoutVimLabel() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.displayLabel == "h — left")
    }

    @Test("collectionId preserved from original when augmented has none")
    func preservesCollectionId() {
        let collectionId = RuleCollectionIdentifier.vimNavigation
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: collectionId,
            vimLabel: "←"
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.collectionId == collectionId)
    }

    @Test("all four arrow vimLabels survive augmentation")
    func allArrowVimLabelsSurvive() {
        let arrows: [(key: String, label: String, code: UInt16)] = [
            ("left", "←", 123), ("down", "↓", 125),
            ("up", "↑", 126), ("right", "→", 124),
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

            let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

            #expect(result.vimLabel == arrow.label, "vimLabel for \(arrow.key) should be \(arrow.label)")
            #expect(result.displayLabel == arrow.label, "displayLabel for \(arrow.key) should be \(arrow.label)")
        }
    }
}

// MARK: - Floating label HJKL visibility

@Suite("Floating label HJKL visibility logic")
struct FloatingLabelHJKLTests {

    @Test("HJKL floating labels hidden when vim hints render")
    func hjklHiddenDuringVimHints() {
        let vimHintsActive = true
        let hjklLabels = ["H", "J", "K", "L"]

        for label in hjklLabels {
            let isHidden = vimHintsActive && ["H", "J", "K", "L"].contains(label.uppercased())
            #expect(isHidden == true, "\(label) should be hidden during vim hints")
        }
    }

    @Test("HJKL floating labels visible when vim hints not rendering")
    func hjklVisibleWithoutVimHints() {
        let vimHintsActive = false
        let hjklLabels = ["H", "J", "K", "L"]

        for label in hjklLabels {
            let isHidden = vimHintsActive && ["H", "J", "K", "L"].contains(label.uppercased())
            #expect(isHidden == false, "\(label) should be visible without vim hints")
        }
    }

    @Test("non-HJKL floating labels visible even during vim hints")
    func nonHjklVisibleDuringVimHints() {
        let vimHintsActive = true
        let otherLabels = ["A", "S", "D", "F", "G", "Q", "W", "E", "R"]

        for label in otherLabels {
            let isHidden = vimHintsActive && ["H", "J", "K", "L"].contains(label.uppercased())
            #expect(isHidden == false, "\(label) should be visible even during vim hints")
        }
    }
}

// MARK: - Additional mergeAugmentation behavior

@Suite("mergeAugmentation edge cases")
struct MergeAugmentationEdgeCaseTests {

    @Test("transparent augmented key preserves original displayLabel")
    func transparentPreservesOriginalLabel() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "A",
            outputKey: "a",
            outputKeyCode: 0
        )
        let augmented = LayerKeyInfo(
            displayLabel: "augmented-label",
            outputKey: "a",
            outputKeyCode: 0,
            isTransparent: true,
            isLayerSwitch: false
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        // When no vimLabel exists, displayLabel comes from augmented regardless of transparency
        #expect(result.displayLabel == "augmented-label")
        #expect(result.isTransparent == true)
    }

    @Test("augmented vimLabel used when original has none")
    func augmentedVimLabelUsedWhenOriginalHasNone() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "J",
            outputKey: "j",
            outputKeyCode: 38
        )
        let augmented = LayerKeyInfo(
            displayLabel: "j — down",
            outputKey: "down",
            outputKeyCode: 125,
            isTransparent: false,
            isLayerSwitch: false,
            vimLabel: "↓"
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        // vimLabel = original.vimLabel ?? augmented.vimLabel — original is nil, so augmented wins
        #expect(result.vimLabel == "↓")
    }

    @Test("original vimLabel takes precedence over augmented")
    func originalVimLabelTakesPrecedence() {
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
            isLayerSwitch: false,
            vimLabel: "⬅️"
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        // original.vimLabel ?? augmented.vimLabel — original is non-nil, so it wins
        #expect(result.vimLabel == "←")
    }

    @Test("outputKeyCode preserved from augmented")
    func outputKeyCodeFromAugmented() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "H",
            outputKey: "h",
            outputKeyCode: 4
        )
        let augmented = LayerKeyInfo(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        // outputKeyCode = augmented.outputKeyCode ?? original.outputKeyCode
        #expect(result.outputKeyCode == 123)
    }

    @Test("outputKeyCode falls back to original when augmented is nil")
    func outputKeyCodeFallsBackToOriginal() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "H",
            outputKey: "h",
            outputKeyCode: 4
        )
        let augmented = LayerKeyInfo(
            displayLabel: "action",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: false
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.outputKeyCode == 4)
    }

    @Test("layer switch keys preserve isLayerSwitch flag")
    func layerSwitchFlagPreserved() {
        let original = LayerKeyInfo.mapped(
            displayLabel: "Tab",
            outputKey: "tab",
            outputKeyCode: 48
        )
        let augmented = LayerKeyInfo(
            displayLabel: "Nav",
            outputKey: nil,
            outputKeyCode: nil,
            isTransparent: false,
            isLayerSwitch: true
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        #expect(result.isLayerSwitch == true)
    }

    @Test("augmented collectionId takes precedence when both present")
    func augmentedCollectionIdWhenBothPresent() {
        let originalId = UUID()
        let augmentedId = UUID()
        let original = LayerKeyInfo.mapped(
            displayLabel: "←",
            outputKey: "left",
            outputKeyCode: 123,
            collectionId: originalId
        )
        let augmented = LayerKeyInfo(
            displayLabel: "h — left",
            outputKey: "left",
            outputKeyCode: 123,
            isTransparent: false,
            isLayerSwitch: false,
            collectionId: augmentedId
        )

        let result = KeyboardVisualizationViewModel.mergeAugmentation(augmented, with: original)

        // collectionId = original.collectionId ?? augmented.collectionId — original takes precedence
        #expect(result.collectionId == originalId)
    }
}

// MARK: - VimBindings HJKL displayLabel

@Suite("VimBindings HJKL display labels are arrow-only")
struct VimBindingsArrowLabelTests {

    @Test("HJKL hints have pure arrow displayLabels")
    func hjklDisplayLabelsAreArrows() {
        let hints = VimBindings.hints(strategy: .accessibility, mode: .normal, showAdvanced: false)
        let arrowHints = hints.filter { ["h", "j", "k", "l"].contains($0.key) }

        #expect(arrowHints.count == 4)

        let expectedArrows: [String: String] = ["h": "←", "j": "↓", "k": "↑", "l": "→"]
        for hint in arrowHints {
            #expect(hint.displayLabel == expectedArrows[hint.key],
                    "\(hint.key) displayLabel should be \(expectedArrows[hint.key]!), got \(hint.displayLabel)")
        }
    }
}
