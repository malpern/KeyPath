@testable import KeyPathAppKit
import Testing

@Suite("OverlayKeyboardView.escLeftInset")
struct OverlayKeyboardLayoutTests {
    @Test("returns keyGap at scale 1 for macBookUS")
    func escLeftInsetAtScaleOne() {
        let inset = OverlayKeyboardView.escLeftInset(
            for: .macBookUS,
            scale: 1,
            keyUnitSize: 32,
            keyGap: 2
        )
        #expect(abs(inset - 2) < 0.001)
    }

    @Test("scales proportionally at scale 2")
    func escLeftInsetAtScaleTwo() {
        let inset = OverlayKeyboardView.escLeftInset(
            for: .macBookUS,
            scale: 2,
            keyUnitSize: 32,
            keyGap: 2
        )
        #expect(abs(inset - 4) < 0.001)
    }

    @Test("scales proportionally at scale 0.5")
    func escLeftInsetAtHalfScale() {
        let inset = OverlayKeyboardView.escLeftInset(
            for: .macBookUS,
            scale: 0.5,
            keyUnitSize: 32,
            keyGap: 2
        )
        #expect(abs(inset - 1) < 0.001)
    }

    @Test("returns keyGap * scale when layout has no ESC key")
    func escLeftInsetNoEscKey() {
        let emptyLayout = PhysicalLayout(
            id: "test-empty",
            name: "Empty",
            keys: [],
            totalWidth: 10,
            totalHeight: 4
        )
        let inset = OverlayKeyboardView.escLeftInset(
            for: emptyLayout,
            scale: 1,
            keyUnitSize: 32,
            keyGap: 2
        )
        #expect(abs(inset - 2) < 0.001)
    }

    @Test("returns non-negative even with unusual parameters")
    func escLeftInsetNonNegative() {
        let inset = OverlayKeyboardView.escLeftInset(
            for: .macBookUS,
            scale: 1,
            keyUnitSize: 1,
            keyGap: 0
        )
        #expect(inset >= 0)
    }

    @Test("works with different built-in layouts")
    func escLeftInsetDifferentLayouts() {
        let layouts: [PhysicalLayout] = [.macBookUS, .macBookISO, .macBookJIS]
        for layout in layouts {
            let inset = OverlayKeyboardView.escLeftInset(
                for: layout,
                scale: 1,
                keyUnitSize: 32,
                keyGap: 2
            )
            #expect(inset >= 0, "escLeftInset should be non-negative for \(layout.name)")
        }
    }
}
