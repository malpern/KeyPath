import Foundation
import Testing

@testable import KeyPathAppKit

@Suite("PhysicalLayout Drawer Key Injection")
struct PhysicalLayoutDrawerInjectionTests {
    // MARK: - Helper

    private func makeKey(
        keyCode: UInt16 = PhysicalKey.unmappedKeyCode,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0
    ) -> PhysicalKey {
        PhysicalKey(keyCode: keyCode, label: label, x: x, y: y, width: width)
    }

    private func makeLayout(id: String = "custom-test", keys: [PhysicalKey]) -> PhysicalLayout {
        let maxX = keys.map { $0.x + $0.width }.max() ?? 0
        let maxY = keys.map { $0.y + $0.height }.max() ?? 0
        return PhysicalLayout(id: id, name: "Test", keys: keys, totalWidth: maxX, totalHeight: maxY)
    }

    // MARK: - isLayerKeyLabel

    @Test func isLayerKeyLabel_recognizesValidLabels() {
        #expect(PhysicalLayout.isLayerKeyLabel("L0"))
        #expect(PhysicalLayout.isLayerKeyLabel("L1"))
        #expect(PhysicalLayout.isLayerKeyLabel("L9"))
        #expect(PhysicalLayout.isLayerKeyLabel("T0"))
        #expect(PhysicalLayout.isLayerKeyLabel("T2"))
        #expect(PhysicalLayout.isLayerKeyLabel("D0"))
        #expect(PhysicalLayout.isLayerKeyLabel("D3"))
        #expect(PhysicalLayout.isLayerKeyLabel("L12")) // two-digit layer number
    }

    @Test func isLayerKeyLabel_rejectsNonLayerLabels() {
        #expect(!PhysicalLayout.isLayerKeyLabel("🔒"))
        #expect(!PhysicalLayout.isLayerKeyLabel("RGB"))
        #expect(!PhysicalLayout.isLayerKeyLabel("BL"))
        #expect(!PhysicalLayout.isLayerKeyLabel("⟲"))
        #expect(!PhysicalLayout.isLayerKeyLabel("a"))
        #expect(!PhysicalLayout.isLayerKeyLabel("Fn"))
        #expect(!PhysicalLayout.isLayerKeyLabel("Lower"))
        #expect(!PhysicalLayout.isLayerKeyLabel(""))
        #expect(!PhysicalLayout.isLayerKeyLabel("L")) // no number
    }

    // MARK: - Drawer Key Injection

    @Test func picksRightmostLayerKey() {
        let layout = makeLayout(keys: [
            makeKey(label: "L0", x: 0, y: 5),
            makeKey(label: "L1", x: 12, y: 5),
            makeKey(keyCode: 49, label: "", x: 3, y: 5, width: 6), // spacebar
        ])

        let result = layout.withDrawerKeyInjected()

        #expect(result.hasDrawerButtons)
        // L1 at x=12 should become the drawer key
        let drawerKey = result.keys.first { $0.label == "🔒" }
        #expect(drawerKey != nil)
        #expect(drawerKey?.x == 12)
        // L0 should remain unchanged
        let layerKey = result.keys.first { $0.label == "L0" }
        #expect(layerKey != nil)
    }

    @Test func tieBreaksWithBottomMost() {
        let layout = makeLayout(keys: [
            makeKey(label: "L0", x: 12, y: 2),
            makeKey(label: "L1", x: 12, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        let drawerKey = result.keys.first { $0.label == "🔒" }
        #expect(drawerKey != nil)
        #expect(drawerKey?.y == 5) // bottom-most wins
        // Other layer key preserved
        let remaining = result.keys.first { $0.label == "L0" }
        #expect(remaining != nil)
    }

    @Test func skipsNonLayerLabels() {
        let layout = makeLayout(keys: [
            makeKey(label: "RGB", x: 12, y: 5),
            makeKey(label: "BL", x: 11, y: 5),
            makeKey(label: "⟲", x: 10, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        #expect(!result.hasDrawerButtons)
        // All keys unchanged
        #expect(result.keys.contains { $0.label == "RGB" })
        #expect(result.keys.contains { $0.label == "BL" })
    }

    @Test func preservesExistingDrawerKey() {
        let layout = makeLayout(keys: [
            makeKey(label: "🔒", x: 14, y: 0),
            makeKey(label: "L1", x: 12, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        // Should not change anything — already has drawer
        let drawerKeys = result.keys.filter { $0.label == "🔒" }
        #expect(drawerKeys.count == 1)
        #expect(drawerKeys.first?.x == 14) // original position
        // L1 still present
        #expect(result.keys.contains { $0.label == "L1" })
    }

    @Test func noCandidatesReturnsUnchanged() {
        let layout = makeLayout(keys: [
            makeKey(keyCode: 49, label: "", x: 3, y: 5, width: 6),
            makeKey(keyCode: 55, label: "⌘", x: 0, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        #expect(!result.hasDrawerButtons)
        #expect(result.keys.count == layout.keys.count)
    }

    @Test func onlyAppliesToCustomLayouts() {
        let layout = makeLayout(id: "ansi-80", keys: [
            makeKey(label: "L0", x: 12, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        // Non-custom layout should be unchanged
        #expect(!result.hasDrawerButtons)
        #expect(result.keys.first?.label == "L0")
    }

    @Test func singleLayerKeyBecomesDrawer() {
        let layout = makeLayout(keys: [
            makeKey(keyCode: 55, label: "⌘", x: 0, y: 5),
            makeKey(label: "L0", x: 12, y: 5),
            makeKey(keyCode: 62, label: "⌃", x: 13, y: 5),
        ])

        let result = layout.withDrawerKeyInjected()

        #expect(result.hasDrawerButtons)
        let drawerKey = result.keys.first { $0.label == "🔒" }
        #expect(drawerKey?.x == 12)
        // No L0 remaining
        #expect(!result.keys.contains { $0.label == "L0" })
    }

    @Test func preservesKeyProperties() {
        let original = makeKey(label: "T2", x: 12.5, y: 5.5, width: 1.25)
        let layout = makeLayout(keys: [original])

        let result = layout.withDrawerKeyInjected()

        let drawerKey = result.keys.first { $0.label == "🔒" }
        #expect(drawerKey?.x == 12.5)
        #expect(drawerKey?.y == 5.5)
        #expect(drawerKey?.width == 1.25)
        #expect(drawerKey?.keyCode == PhysicalKey.unmappedKeyCode)
    }
}
