@testable import KeyPathAppKit
import Testing

@Suite("FloatingLabelVisibility")
struct FloatingLabelVisibilityTests {
    private static let standardLabelToKeyCode: [String: UInt16] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3,
        "G": 5, "H": 4, "J": 38, "K": 40, "L": 37,
        "Q": 12, "W": 13, "S": 1, "R": 15, "T": 17
    ]

    private static func base(
        labelToKeyCode: [String: UInt16] = standardLabelToKeyCode,
        isLauncherMode: Bool = false,
        isLayerMode: Bool = false,
        vimHintsActive: Bool = false,
        remappedLabels: Set<String> = [],
        zoneSubtitleLabels: Set<String> = []
    ) -> FloatingLabelVisibility {
        FloatingLabelVisibility(
            labelToKeyCode: labelToKeyCode,
            isLauncherMode: isLauncherMode,
            isLayerMode: isLayerMode,
            vimHintsActive: vimHintsActive,
            remappedLabels: remappedLabels,
            zoneSubtitleLabels: zoneSubtitleLabels
        )
    }

    // MARK: - Base case

    @Test("normal letter visible on base layer")
    func normalLetterVisible() {
        let vis = Self.base()
        #expect(vis.isVisible("A"))
        #expect(vis.isVisible("Q"))
        #expect(vis.isVisible("F"))
    }

    @Test("lowercase input still matches uppercase keyCode map")
    func lowercaseInput() {
        let vis = Self.base()
        #expect(vis.isVisible("a"))
        #expect(vis.isVisible("h"))
    }

    // MARK: - Label not in keymap

    @Test("label not in keymap is hidden")
    func labelNotInKeymap() {
        let vis = Self.base()
        #expect(!vis.isVisible("Z"))
        #expect(!vis.isVisible("X"))
    }

    // MARK: - Special labels

    @Test("special labels are hidden")
    func specialLabelsHidden() {
        let vis = Self.base(labelToKeyCode: ["ESC": 53, "⌫": 51, "⇧": 56, "F1": 122])
        #expect(!vis.isVisible("ESC"))
        #expect(!vis.isVisible("⌫"))
        #expect(!vis.isVisible("⇧"))
        #expect(!vis.isVisible("F1"))
    }

    @Test("special labels hidden regardless of case")
    func specialLabelsCaseInsensitive() {
        let vis = Self.base(labelToKeyCode: ["HOME": 115, "PGUP": 116])
        #expect(!vis.isVisible("home"))
        #expect(!vis.isVisible("PGUP"))
    }

    // MARK: - Launcher mode

    @Test("all labels hidden in launcher mode")
    func launcherModeHidesAll() {
        let vis = Self.base(isLauncherMode: true)
        #expect(!vis.isVisible("A"))
        #expect(!vis.isVisible("H"))
        #expect(!vis.isVisible("Q"))
    }

    // MARK: - Layer mode

    @Test("all labels hidden in layer mode")
    func layerModeHidesAll() {
        let vis = Self.base(isLayerMode: true)
        #expect(!vis.isVisible("A"))
        #expect(!vis.isVisible("H"))
    }

    // MARK: - Remapped labels

    @Test("remapped labels are hidden")
    func remappedLabelsHidden() {
        let vis = Self.base(remappedLabels: ["A", "S"])
        #expect(!vis.isVisible("A"))
        #expect(!vis.isVisible("S"))
        #expect(vis.isVisible("D"))
    }

    @Test("transparent layer entries do not suppress base floating labels")
    func transparentLayerEntriesDoNotSuppressBaseFloatingLabels() {
        let info = LayerKeyInfo.transparent(fallbackLabel: "A")

        #expect(!OverlayKeyboardView.shouldHideFloatingLabel(
            for: info,
            baseLabel: "A",
            inputKeyName: "a"
        ))
    }

    @Test("identity mappings do not suppress base floating labels")
    func identityMappingsDoNotSuppressBaseFloatingLabels() {
        let info = LayerKeyInfo.mapped(displayLabel: "A", outputKey: "a", outputKeyCode: 0)

        #expect(!OverlayKeyboardView.shouldHideFloatingLabel(
            for: info,
            baseLabel: "A",
            inputKeyName: "a"
        ))
    }

    @Test("real remaps and actions suppress base floating labels")
    func realRemapsAndActionsSuppressBaseFloatingLabels() {
        let remap = LayerKeyInfo.mapped(displayLabel: "B", outputKey: "b", outputKeyCode: 11)
        let action = LayerKeyInfo.systemAction(action: "spotlight", description: "Spotlight")

        #expect(OverlayKeyboardView.shouldHideFloatingLabel(
            for: remap,
            baseLabel: "A",
            inputKeyName: "a"
        ))
        #expect(OverlayKeyboardView.shouldHideFloatingLabel(
            for: action,
            baseLabel: "A",
            inputKeyName: "a"
        ))
    }

    // MARK: - Zone subtitle labels

    @Test("labels with zone subtitles are hidden")
    func zoneSubtitleLabelsHidden() {
        let vis = Self.base(zoneSubtitleLabels: ["A", "S", "D", "F"])
        #expect(!vis.isVisible("A"))
        #expect(!vis.isVisible("F"))
        #expect(vis.isVisible("G"))
    }

    // MARK: - Vim hints (HJKL regression)

    @Test("HJKL hidden when vim hints active")
    func hjklHiddenDuringVimHints() {
        let vis = Self.base(vimHintsActive: true)
        #expect(!vis.isVisible("H"))
        #expect(!vis.isVisible("J"))
        #expect(!vis.isVisible("K"))
        #expect(!vis.isVisible("L"))
    }

    @Test("HJKL visible when vim hints inactive")
    func hjklVisibleWithoutVimHints() {
        let vis = Self.base(vimHintsActive: false)
        #expect(vis.isVisible("H"))
        #expect(vis.isVisible("J"))
        #expect(vis.isVisible("K"))
        #expect(vis.isVisible("L"))
    }

    @Test("non-HJKL visible even when vim hints active")
    func nonHjklVisibleDuringVimHints() {
        let vis = Self.base(vimHintsActive: true)
        #expect(vis.isVisible("A"))
        #expect(vis.isVisible("S"))
        #expect(vis.isVisible("D"))
        #expect(vis.isVisible("F"))
        #expect(vis.isVisible("Q"))
    }

    // MARK: - Condition independence

    @Test("each condition independently hides a label")
    func eachConditionIndependent() {
        #expect(!Self.base(isLauncherMode: true).isVisible("A"))
        #expect(!Self.base(isLayerMode: true).isVisible("A"))
        #expect(!Self.base(remappedLabels: ["A"]).isVisible("A"))
        #expect(!Self.base(zoneSubtitleLabels: ["A"]).isVisible("A"))
        #expect(!Self.base(vimHintsActive: true).isVisible("H"))
    }
}
