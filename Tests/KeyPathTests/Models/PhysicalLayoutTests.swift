@testable import KeyPathAppKit
import Testing

/// Tests for PhysicalLayout model and registry
struct PhysicalLayoutTests {
    // MARK: - Registry Tests

    @Test func allLayoutsAreRegistered() {
        #expect(PhysicalLayout.all.count >= 2, "Should have at least MacBook and Kinesis layouts")
    }

    @Test func findMacBookLayout() {
        let layout = PhysicalLayout.find(id: "macbook-us")
        #expect(layout != nil, "Should find MacBook US layout")
        #expect(layout?.name == "MacBook US")
    }

    @Test func findKinesisLayout() {
        let layout = PhysicalLayout.find(id: "kinesis-360")
        #expect(layout != nil, "Should find Kinesis Advantage 360 layout")
        #expect(layout?.name == "Kinesis Advantage 360")
    }

    @Test func findUnknownLayoutReturnsNil() {
        let layout = PhysicalLayout.find(id: "unknown-keyboard")
        #expect(layout == nil, "Unknown layout ID should return nil")
    }

    // MARK: - MacBook Layout Tests

    @Test func macBookLayoutHasKeys() {
        let layout = PhysicalLayout.macBookUS
        #expect(!layout.keys.isEmpty, "MacBook layout should have keys")
        // MacBook has function row, number row, 3 alpha rows, and modifier row
        #expect(layout.keys.count > 50, "MacBook should have over 50 keys")
    }

    @Test func macBookLayoutHasDimensions() {
        let layout = PhysicalLayout.macBookUS
        #expect(layout.totalWidth > 10, "MacBook layout should have reasonable width")
        #expect(layout.totalHeight > 4, "MacBook layout should have reasonable height")
    }

    // MARK: - Kinesis Layout Tests

    @Test func kinesisLayoutHasKeys() {
        let layout = PhysicalLayout.kinesisAdvantage360
        #expect(!layout.keys.isEmpty, "Kinesis layout should have keys")
        // Kinesis 360 has ~67 keys
        #expect(layout.keys.count > 60, "Kinesis should have over 60 keys")
    }

    @Test func kinesisLayoutHasSplitGap() {
        let layout = PhysicalLayout.kinesisAdvantage360
        // Total width should account for split gap (around 17-18 units for split keyboard)
        #expect(layout.totalWidth > 15, "Kinesis layout should have width accounting for split")
    }

    @Test func kinesisLayoutHasRotatedThumbKeys() {
        let layout = PhysicalLayout.kinesisAdvantage360
        let rotatedKeys = layout.keys.filter { $0.rotation != 0 }
        #expect(!rotatedKeys.isEmpty, "Kinesis should have rotated thumb cluster keys")
    }

    @Test func kinesisLayoutHasTallThumbKeys() {
        let layout = PhysicalLayout.kinesisAdvantage360
        let tallKeys = layout.keys.filter { $0.height > 1.5 }
        #expect(!tallKeys.isEmpty, "Kinesis should have tall thumb keys (height > 1.5)")
    }

    // MARK: - PhysicalKey Tests

    @Test func physicalKeyDefaults() {
        let key = PhysicalKey(keyCode: 0, label: "A", x: 0, y: 0)
        #expect(key.width == 1.0, "Default width should be 1.0")
        #expect(key.height == 1.0, "Default height should be 1.0")
        #expect(key.rotation == 0.0, "Default rotation should be 0.0")
    }

    @Test func physicalKeyCustomDimensions() {
        let key = PhysicalKey(keyCode: 56, label: "⇧", x: 0, y: 0, width: 2.35, height: 1.0, rotation: 15)
        #expect(key.width == 2.35)
        #expect(key.height == 1.0)
        #expect(key.rotation == 15)
    }

    // MARK: - Standard ANSI Layout Tests

    @Test func findAnsi60Layout() {
        let layout = PhysicalLayout.find(id: "ansi-60")
        #expect(layout != nil, "Should find 60% ANSI layout")
        #expect(layout?.name == "60% ANSI")
    }

    @Test func findAnsi65Layout() {
        let layout = PhysicalLayout.find(id: "ansi-65")
        #expect(layout != nil, "Should find 65% ANSI layout")
        #expect(layout?.name == "65% ANSI")
    }

    @Test func findAnsi75Layout() {
        let layout = PhysicalLayout.find(id: "ansi-75")
        #expect(layout != nil, "Should find 75% ANSI layout")
        #expect(layout?.name == "75% ANSI")
    }

    @Test func findAnsi80Layout() {
        let layout = PhysicalLayout.find(id: "ansi-80")
        #expect(layout != nil, "Should find 80% ANSI layout")
        #expect(layout?.name == "80% ANSI (TKL)")
    }

    @Test func findAnsi100Layout() {
        let layout = PhysicalLayout.find(id: "ansi-100")
        #expect(layout != nil, "Should find 100% ANSI layout")
        #expect(layout?.name == "100% ANSI (Full Size)")
    }

    @Test func ansi60LayoutHasKeys() {
        let layout = PhysicalLayout.ansi60Percent
        #expect(!layout.keys.isEmpty, "60% ANSI layout should have keys")
        #expect(layout.keys.count > 50, "60% should have over 50 keys")
    }

    @Test func ansi65LayoutHasArrowKeys() {
        let layout = PhysicalLayout.ansi65Percent
        let arrowKeys = layout.keys.filter { [123, 124, 125, 126].contains($0.keyCode) }
        #expect(!arrowKeys.isEmpty, "65% ANSI should have arrow keys")
        #expect(arrowKeys.count == 4, "Should have 4 arrow keys")
    }

    @Test func ansi75LayoutHasFunctionKeys() {
        let layout = PhysicalLayout.ansi75Percent
        let functionKeys = layout.keys.filter { (96...111).contains($0.keyCode) || [99, 118, 120, 122].contains($0.keyCode) }
        #expect(!functionKeys.isEmpty, "75% ANSI should have function keys")
    }

    @Test func ansi80LayoutHasFunctionKeys() {
        let layout = PhysicalLayout.ansi80Percent
        let functionKeys = layout.keys.filter { (96...111).contains($0.keyCode) || [99, 118, 120, 122].contains($0.keyCode) }
        #expect(!functionKeys.isEmpty, "80% ANSI should have function keys")
    }

    // MARK: - New Keyboard Layout Tests

    @Test func findAnsi40Layout() {
        let layout = PhysicalLayout.find(id: "ansi-40")
        #expect(layout != nil, "Should find 40% ANSI layout")
        #expect(layout?.name == "40% ANSI")
    }

    @Test func findHhkbLayout() {
        let layout = PhysicalLayout.find(id: "hhkb")
        #expect(layout != nil, "Should find HHKB layout")
        #expect(layout?.name == "HHKB (Happy Hacking Keyboard)")
    }

    @Test func findCorneLayout() {
        let layout = PhysicalLayout.find(id: "corne")
        #expect(layout != nil, "Should find Corne layout")
        #expect(layout?.name == "Corne (crkbd)")
    }

    @Test func findSofleLayout() {
        let layout = PhysicalLayout.find(id: "sofle")
        #expect(layout != nil, "Should find Sofle layout")
        #expect(layout?.name == "Sofle")
    }

    @Test func findFerrisSweepLayout() {
        let layout = PhysicalLayout.find(id: "ferris-sweep")
        #expect(layout != nil, "Should find Ferris Sweep layout")
        #expect(layout?.name == "Ferris Sweep")
    }

    @Test func findCornixLayout() {
        let layout = PhysicalLayout.find(id: "cornix")
        #expect(layout != nil, "Should find Cornix layout")
        #expect(layout?.name == "Cornix")
    }

    @Test func ansi40LayoutHasKeys() {
        let layout = PhysicalLayout.ansi40Percent
        #expect(!layout.keys.isEmpty, "40% ANSI layout should have keys")
        #expect(layout.keys.count > 40, "40% should have over 40 keys")
    }

    @Test func hhkbLayoutHasKeys() {
        let layout = PhysicalLayout.hhkb
        #expect(!layout.keys.isEmpty, "HHKB layout should have keys")
        #expect(layout.keys.count > 50, "HHKB should have over 50 keys")
    }

    @Test func corneLayoutHasKeys() {
        let layout = PhysicalLayout.corne
        #expect(!layout.keys.isEmpty, "Corne layout should have keys")
        // Corne has 42 keys total (3x6+3 per half)
        #expect(layout.keys.count >= 30, "Corne should have at least 30 keys")
    }

    @Test func corneLayoutHasSplitGap() {
        let layout = PhysicalLayout.corne
        // Split keyboards have a gap in the middle (around x=6-8)
        let leftKeys = layout.keys.filter { $0.x < 6 }
        let rightKeys = layout.keys.filter { $0.x > 8 }
        #expect(!leftKeys.isEmpty, "Corne should have left half keys")
        #expect(!rightKeys.isEmpty, "Corne should have right half keys")
    }

    @Test func sofleLayoutHasKeys() {
        let layout = PhysicalLayout.sofle
        #expect(!layout.keys.isEmpty, "Sofle layout should have keys")
        // Sofle has 58 keys total (6x4+5 per half)
        #expect(layout.keys.count >= 40, "Sofle should have at least 40 keys")
    }

    @Test func sofleLayoutHasSplitGap() {
        let layout = PhysicalLayout.sofle
        let leftKeys = layout.keys.filter { $0.x < 6 }
        let rightKeys = layout.keys.filter { $0.x > 8 }
        #expect(!leftKeys.isEmpty, "Sofle should have left half keys")
        #expect(!rightKeys.isEmpty, "Sofle should have right half keys")
    }

    @Test func ferrisSweepLayoutHasKeys() {
        let layout = PhysicalLayout.ferrisSweep
        #expect(!layout.keys.isEmpty, "Ferris Sweep layout should have keys")
        // Ferris Sweep has 34 keys total (5x3+2 per half)
        #expect(layout.keys.count >= 20, "Ferris Sweep should have at least 20 keys")
    }

    @Test func ferrisSweepLayoutHasSplitGap() {
        let layout = PhysicalLayout.ferrisSweep
        let leftKeys = layout.keys.filter { $0.x < 5 }
        let rightKeys = layout.keys.filter { $0.x > 6 }
        #expect(!leftKeys.isEmpty, "Ferris Sweep should have left half keys")
        #expect(!rightKeys.isEmpty, "Ferris Sweep should have right half keys")
    }

    @Test func cornixLayoutHasKeys() {
        let layout = PhysicalLayout.cornix
        #expect(!layout.keys.isEmpty, "Cornix layout should have keys")
        #expect(layout.keys.count >= 30, "Cornix should have at least 30 keys")
    }

    @Test func cornixLayoutHasSplitGap() {
        let layout = PhysicalLayout.cornix
        let leftKeys = layout.keys.filter { $0.x < 6 }
        let rightKeys = layout.keys.filter { $0.x > 8 }
        #expect(!leftKeys.isEmpty, "Cornix should have left half keys")
        #expect(!rightKeys.isEmpty, "Cornix should have right half keys")
    }
}
