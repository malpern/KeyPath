import CoreGraphics
import CoreText
import Foundation
import Metal

struct KeyboardStageLegendAtlasDescriptor: Hashable, Sendable {
    enum Weight: Int, Hashable, Sendable {
        case regular
        case medium
    }

    var primary: String
    var secondary: String?
    var weight: Weight

    init(
        primary: String,
        secondary: String? = nil,
        weight: Weight = .regular
    ) {
        self.primary = primary
        self.secondary = secondary
        self.weight = weight
    }
}

struct KeyboardStageLegendAtlasEntry: Equatable, Sendable {
    /// `(minU, minV, maxU, maxV)` in Metal's top-left texture orientation.
    /// A shader can mix `xy` and `zw` with an upright, top-to-bottom local UV.
    var uvRect: SIMD4<Float>
}

struct KeyboardStageLegendAtlasSnapshot: @unchecked Sendable {
    let texture: any MTLTexture
    let entries: [KeyboardStageLegendAtlasDescriptor: KeyboardStageLegendAtlasEntry]
}

enum KeyboardStageLegendAtlasError: Error, Equatable {
    case capacityExceeded(Int)
    case bitmapContextUnavailable
    case textureCreationFailed
    case textureUploadFailed
}

struct KeyboardStageLegendAtlasSignature: Hashable, Sendable {
    let descriptors: [KeyboardStageLegendAtlasDescriptor]

    init(descriptors: some Sequence<KeyboardStageLegendAtlasDescriptor>) throws {
        let uniqueDescriptors = Set(descriptors)
        guard uniqueDescriptors.count <= KeyboardStageLegendAtlasLayout.capacity else {
            throw KeyboardStageLegendAtlasError.capacityExceeded(uniqueDescriptors.count)
        }
        self.descriptors = uniqueDescriptors.sorted(by: Self.areInStableOrder)
    }

    private static func areInStableOrder(
        _ lhs: KeyboardStageLegendAtlasDescriptor,
        _ rhs: KeyboardStageLegendAtlasDescriptor
    ) -> Bool {
        if lhs.primary != rhs.primary {
            return lhs.primary.utf8.lexicographicallyPrecedes(rhs.primary.utf8)
        }
        if lhs.secondary != rhs.secondary {
            switch (lhs.secondary, rhs.secondary) {
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case let (.some(lhsSecondary), .some(rhsSecondary)):
                return lhsSecondary.utf8.lexicographicallyPrecedes(rhsSecondary.utf8)
            case (nil, nil):
                break
            }
        }
        return lhs.weight.rawValue < rhs.weight.rawValue
    }
}

enum KeyboardStageLegendAtlasLayout {
    static let textureWidth = 2048
    static let textureHeight = 1024
    static let cellWidth = 256
    static let cellHeight = 128
    static let columnCount = textureWidth / cellWidth
    static let rowCount = textureHeight / cellHeight
    static let capacity = columnCount * rowCount

    static func entries(
        for signature: KeyboardStageLegendAtlasSignature
    ) -> [KeyboardStageLegendAtlasDescriptor: KeyboardStageLegendAtlasEntry] {
        Dictionary(uniqueKeysWithValues: signature.descriptors.enumerated().map { index, descriptor in
            let column = index % columnCount
            let row = index / columnCount
            let minU = Float(column * cellWidth) / Float(textureWidth)
            let minV = Float(row * cellHeight) / Float(textureHeight)
            let maxU = Float((column + 1) * cellWidth) / Float(textureWidth)
            let maxV = Float((row + 1) * cellHeight) / Float(textureHeight)
            return (
                descriptor,
                KeyboardStageLegendAtlasEntry(
                    uvRect: SIMD4(minU, minV, maxU, maxV)
                )
            )
        })
    }
}

final class KeyboardStageLegendAtlasCache: @unchecked Sendable {
    private struct DeviceKey: Hashable {
        let objectIdentifier: ObjectIdentifier
        let registryID: UInt64

        init(device: any MTLDevice) {
            objectIdentifier = ObjectIdentifier(device as AnyObject)
            registryID = device.registryID
        }
    }

    private struct CacheKey: Hashable {
        let device: DeviceKey
        let signature: KeyboardStageLegendAtlasSignature
    }

    private let lock = NSLock()
    private var snapshots: [CacheKey: KeyboardStageLegendAtlasSnapshot] = [:]

    func atlas(
        for descriptors: Set<KeyboardStageLegendAtlasDescriptor>,
        device: any MTLDevice
    ) throws -> KeyboardStageLegendAtlasSnapshot {
        try atlas(for: Array(descriptors), device: device)
    }

    func atlas(
        for descriptors: [KeyboardStageLegendAtlasDescriptor],
        device: any MTLDevice
    ) throws -> KeyboardStageLegendAtlasSnapshot {
        let signature = try KeyboardStageLegendAtlasSignature(descriptors: descriptors)
        let cacheKey = CacheKey(device: DeviceKey(device: device), signature: signature)
        lock.lock()
        defer { lock.unlock() }
        if let snapshot = snapshots[cacheKey] {
            return snapshot
        }

        let snapshot = try Self.makeAtlas(signature: signature, device: device)
        snapshots[cacheKey] = snapshot
        return snapshot
    }

    private static func makeAtlas(
        signature: KeyboardStageLegendAtlasSignature,
        device: any MTLDevice
    ) throws -> KeyboardStageLegendAtlasSnapshot {
        let entries = KeyboardStageLegendAtlasLayout.entries(for: signature)
        let pixels = try KeyboardStageLegendAtlasRasterizer.rasterize(
            descriptors: signature.descriptors
        )

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: KeyboardStageLegendAtlasLayout.textureWidth,
            height: KeyboardStageLegendAtlasLayout.textureHeight,
            mipmapped: false
        )
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw KeyboardStageLegendAtlasError.textureCreationFailed
        }
        texture.label = "KeyPath keyboard legend atlas"

        try upload(pixels: pixels, to: texture, device: device)
        return KeyboardStageLegendAtlasSnapshot(texture: texture, entries: entries)
    }

    private static func upload(
        pixels: [UInt8],
        to texture: any MTLTexture,
        device: any MTLDevice
    ) throws {
        let expectedByteCount = KeyboardStageLegendAtlasLayout.textureWidth
            * KeyboardStageLegendAtlasLayout.textureHeight
        guard pixels.count == expectedByteCount else {
            throw KeyboardStageLegendAtlasError.textureUploadFailed
        }

        let buffer: (any MTLBuffer)? = pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: pixels.count,
                options: .storageModeShared
            )
        }
        guard let buffer,
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeBlitCommandEncoder()
        else {
            throw KeyboardStageLegendAtlasError.textureUploadFailed
        }

        encoder.label = "Upload KeyPath keyboard legend atlas"
        encoder.copy(
            from: buffer,
            sourceOffset: 0,
            sourceBytesPerRow: KeyboardStageLegendAtlasLayout.textureWidth,
            sourceBytesPerImage: pixels.count,
            sourceSize: MTLSize(
                width: KeyboardStageLegendAtlasLayout.textureWidth,
                height: KeyboardStageLegendAtlasLayout.textureHeight,
                depth: 1
            ),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw KeyboardStageLegendAtlasError.textureUploadFailed
        }
    }
}

enum KeyboardStageLegendAtlasRasterizer {
    private static let primaryFontSize = CGFloat(KeyboardStageLegendAtlasLayout.cellHeight) * 0.33
    private static let secondaryFontSize = CGFloat(KeyboardStageLegendAtlasLayout.cellHeight) * 0.16
    private static let color = CGColor(gray: 1, alpha: 1)

    static func rasterize(
        descriptors: [KeyboardStageLegendAtlasDescriptor]
    ) throws -> [UInt8] {
        let width = KeyboardStageLegendAtlasLayout.textureWidth
        let height = KeyboardStageLegendAtlasLayout.textureHeight
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let didRender = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)
            context.setFillColor(color)
            context.setTextDrawingMode(.fill)
            context.textMatrix = .identity

            for (index, descriptor) in descriptors.enumerated() {
                draw(descriptor, at: index, in: context)
            }
            context.flush()
            return true
        }
        guard didRender else {
            throw KeyboardStageLegendAtlasError.bitmapContextUnavailable
        }

        // CGBitmapContext stores the upper user-space rows first for this
        // grayscale layout, which already matches Metal's v=0 top-row sampling.
        // Reflecting the bytes here would move deterministic atlas slots to the
        // opposite end of the texture and leave the requested UVs blank.
        return pixels
    }

    private static func draw(
        _ descriptor: KeyboardStageLegendAtlasDescriptor,
        at index: Int,
        in context: CGContext
    ) {
        let column = index % KeyboardStageLegendAtlasLayout.columnCount
        let topOriginRow = index / KeyboardStageLegendAtlasLayout.columnCount
        let bottomOriginRow = KeyboardStageLegendAtlasLayout.rowCount - topOriginRow - 1
        let cell = CGRect(
            x: column * KeyboardStageLegendAtlasLayout.cellWidth,
            y: bottomOriginRow * KeyboardStageLegendAtlasLayout.cellHeight,
            width: KeyboardStageLegendAtlasLayout.cellWidth,
            height: KeyboardStageLegendAtlasLayout.cellHeight
        )

        if let secondary = descriptor.secondary, !secondary.isEmpty {
            drawLine(
                descriptor.primary,
                font: font(size: primaryFontSize, weight: descriptor.weight),
                center: CGPoint(x: cell.midX, y: cell.minY + cell.height * 0.62),
                in: context
            )
            drawLine(
                secondary,
                font: font(size: secondaryFontSize, weight: descriptor.weight),
                center: CGPoint(x: cell.midX, y: cell.minY + cell.height * 0.27),
                in: context
            )
        } else {
            drawLine(
                descriptor.primary,
                font: font(size: primaryFontSize, weight: descriptor.weight),
                center: CGPoint(x: cell.midX, y: cell.midY),
                in: context
            )
        }
    }

    private static func drawLine(
        _ string: String,
        font: CTFont,
        center: CGPoint,
        in context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: center.x - bounds.midX,
            y: center.y - bounds.midY
        )
        CTLineDraw(line, context)
    }

    private static func font(
        size: CGFloat,
        weight: KeyboardStageLegendAtlasDescriptor.Weight
    ) -> CTFont {
        let baseFont = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        guard weight == .medium else { return baseFont }

        let traits: [CFString: Any] = [
            kCTFontWeightTrait: 0.23
        ]
        let attributes: [CFString: Any] = [
            kCTFontTraitsAttribute: traits
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(baseFont),
            attributes as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
