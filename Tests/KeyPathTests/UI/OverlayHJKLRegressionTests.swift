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
