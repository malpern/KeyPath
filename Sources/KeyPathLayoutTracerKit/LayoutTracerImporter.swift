import Foundation

struct ImportedTracingLayout {
    let id: String
    let name: String
    let keys: [TracingKey]
    let totalWidth: Double?
    let totalHeight: Double?
    let recommendedCoordinateScale: Double
    let usesExplicitBounds: Bool
}

enum LayoutTracerImporter {
    static func load(from data: Data) throws -> ImportedTracingLayout {
        let decoder = JSONDecoder()
        let layout = try decoder.decode(LayoutTracerPhysicalLayoutDTO.self, from: data)
        let derivedMaxX = layout.keys.map { $0.x + $0.width }.max() ?? 0
        let recommendedCoordinateScale: Double
        if layout.totalWidth == nil, derivedMaxX < 100 {
            recommendedCoordinateScale = 64
        } else {
            recommendedCoordinateScale = 1
        }
        return ImportedTracingLayout(
            id: layout.id,
            name: layout.name,
            keys: layout.keys.map {
                TracingKey(
                    keyCode: $0.keyCode,
                    label: $0.label,
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height,
                    rotation: $0.rotation,
                    rotationPivotX: $0.rotationPivotX,
                    rotationPivotY: $0.rotationPivotY
                )
            },
            totalWidth: layout.totalWidth,
            totalHeight: layout.totalHeight,
            recommendedCoordinateScale: recommendedCoordinateScale,
            usesExplicitBounds: layout.totalWidth != nil || layout.totalHeight != nil
        )
    }
}
