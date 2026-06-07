@testable import KeyPathAppKit
import Testing

@Suite("TapHoldLabelPrecedence")
struct TapHoldLabelPrecedenceTests {
    @Test("matches logical base label case-insensitively")
    func matchesLogicalBaseLabelCaseInsensitively() {
        #expect(TapHoldLabelPrecedence.idleLabelAddsNoNewVisualInformation("a", baseLabel: "A", keyLabel: "Q"))
    }

    @Test("matches physical key label when logical label differs")
    func matchesPhysicalKeyLabelWhenLogicalLabelDiffers() {
        #expect(TapHoldLabelPrecedence.idleLabelAddsNoNewVisualInformation(";", baseLabel: "Ö", keyLabel: ";"))
    }

    @Test("matches symbol labels")
    func matchesSymbolLabels() {
        #expect(TapHoldLabelPrecedence.idleLabelAddsNoNewVisualInformation("⇪", baseLabel: "⇪", keyLabel: "caps"))
    }

    @Test("does not match alternate tap labels")
    func doesNotMatchAlternateTapLabels() {
        #expect(!TapHoldLabelPrecedence.idleLabelAddsNoNewVisualInformation("⎋", baseLabel: "⇪", keyLabel: "⇪"))
    }
}
