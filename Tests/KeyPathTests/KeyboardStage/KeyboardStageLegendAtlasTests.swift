import Foundation
@testable import KeyPathAppKit
import Metal
import XCTest

final class KeyboardStageLegendAtlasTests: XCTestCase {
    func testSignatureDeduplicatesAndIgnoresRequestOrder() throws {
        let caps = descriptor("caps lock", weight: .medium)
        let command = descriptor("⌘", secondary: "command")
        let escape = descriptor("esc")

        let forward = try KeyboardStageLegendAtlasSignature(
            descriptors: [caps, command, escape, caps]
        )
        let reverse = try KeyboardStageLegendAtlasSignature(
            descriptors: [escape, command, caps]
        )

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.descriptors.count, 3)
        XCTAssertEqual(Set(forward.descriptors), [caps, command, escape])
    }

    func testSignatureSortIncludesSecondaryTextAndWeight() throws {
        let regular = descriptor("A")
        let medium = descriptor("A", weight: .medium)
        let secondary = descriptor("A", secondary: "alternate")

        let signature = try KeyboardStageLegendAtlasSignature(
            descriptors: [secondary, medium, regular]
        )

        XCTAssertEqual(signature.descriptors, [regular, medium, secondary])
    }

    func testCapacityCountsUniqueDescriptors() throws {
        let atCapacity = (0 ..< KeyboardStageLegendAtlasLayout.capacity).map {
            descriptor(String(format: "legend-%02d", $0))
        }
        XCTAssertNoThrow(
            try KeyboardStageLegendAtlasSignature(descriptors: atCapacity + atCapacity)
        )

        let overCapacity = atCapacity + [descriptor("legend-over-capacity")]
        XCTAssertThrowsError(
            try KeyboardStageLegendAtlasSignature(descriptors: overCapacity)
        ) { error in
            XCTAssertEqual(
                error as? KeyboardStageLegendAtlasError,
                .capacityExceeded(KeyboardStageLegendAtlasLayout.capacity + 1)
            )
        }
    }

    func testSlotsAndUVsAreDeterministicAcrossRows() throws {
        let descriptors = (0 ..< 9).map {
            descriptor(String(format: "legend-%02d", $0))
        }
        let signature = try KeyboardStageLegendAtlasSignature(descriptors: descriptors.reversed())
        let entries = KeyboardStageLegendAtlasLayout.entries(for: signature)

        XCTAssertEqual(entries.count, descriptors.count)
        for (index, descriptor) in descriptors.enumerated() {
            let column = index % KeyboardStageLegendAtlasLayout.columnCount
            let row = index / KeyboardStageLegendAtlasLayout.columnCount
            let expected = SIMD4<Float>(
                Float(column) / Float(KeyboardStageLegendAtlasLayout.columnCount),
                Float(row) / Float(KeyboardStageLegendAtlasLayout.rowCount),
                Float(column + 1) / Float(KeyboardStageLegendAtlasLayout.columnCount),
                Float(row + 1) / Float(KeyboardStageLegendAtlasLayout.rowCount)
            )
            XCTAssertEqual(entries[descriptor]?.uvRect, expected)
        }
    }

    func testEmptySignatureProducesNoEntries() throws {
        let signature = try KeyboardStageLegendAtlasSignature(
            descriptors: [KeyboardStageLegendAtlasDescriptor]()
        )

        XCTAssertTrue(signature.descriptors.isEmpty)
        XCTAssertTrue(KeyboardStageLegendAtlasLayout.entries(for: signature).isEmpty)
    }

    func testCoreTextRasterizerProducesCoverageInDeterministicCells() throws {
        let descriptors = [
            descriptor("caps lock", weight: .medium),
            descriptor("⌘", secondary: "command")
        ]
        let signature = try KeyboardStageLegendAtlasSignature(descriptors: descriptors.reversed())
        let pixels = try KeyboardStageLegendAtlasRasterizer.rasterize(
            descriptors: signature.descriptors
        )

        XCTAssertEqual(
            pixels.count,
            KeyboardStageLegendAtlasLayout.textureWidth
                * KeyboardStageLegendAtlasLayout.textureHeight
        )
        for index in signature.descriptors.indices {
            XCTAssertTrue(cellContainsCoverage(index: index, pixels: pixels))
        }
        XCTAssertFalse(cellContainsCoverage(index: 2, pixels: pixels))
    }

    func testCacheReusesTextureForEquivalentRequests() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this test host.")
        }
        let cache = KeyboardStageLegendAtlasCache()
        let caps = descriptor("caps lock", weight: .medium)
        let command = descriptor("⌘", secondary: "command")

        let first = try cache.atlas(for: [caps, command, caps], device: device)
        let second = try cache.atlas(for: Set([command, caps]), device: device)

        XCTAssertTrue((first.texture as AnyObject) === (second.texture as AnyObject))
        XCTAssertEqual(first.entries, second.entries)
        XCTAssertEqual(first.texture.pixelFormat, .r8Unorm)
        XCTAssertEqual(first.texture.width, KeyboardStageLegendAtlasLayout.textureWidth)
        XCTAssertEqual(first.texture.height, KeyboardStageLegendAtlasLayout.textureHeight)
    }

    private func descriptor(
        _ primary: String,
        secondary: String? = nil,
        weight: KeyboardStageLegendAtlasDescriptor.Weight = .regular
    ) -> KeyboardStageLegendAtlasDescriptor {
        KeyboardStageLegendAtlasDescriptor(
            primary: primary,
            secondary: secondary,
            weight: weight
        )
    }

    private func cellContainsCoverage(index: Int, pixels: [UInt8]) -> Bool {
        let column = index % KeyboardStageLegendAtlasLayout.columnCount
        let row = index / KeyboardStageLegendAtlasLayout.columnCount
        let xRange = column * KeyboardStageLegendAtlasLayout.cellWidth
            ..< (column + 1) * KeyboardStageLegendAtlasLayout.cellWidth
        let yRange = row * KeyboardStageLegendAtlasLayout.cellHeight
            ..< (row + 1) * KeyboardStageLegendAtlasLayout.cellHeight
        for y in yRange {
            let rowOffset = y * KeyboardStageLegendAtlasLayout.textureWidth
            if xRange.contains(where: { pixels[rowOffset + $0] > 0 }) {
                return true
            }
        }
        return false
    }
}
