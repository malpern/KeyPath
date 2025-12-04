import Testing
@testable import KeyPathAppKit

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
}
