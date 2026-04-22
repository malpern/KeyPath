import Foundation

struct LayoutTracerPhysicalKeyDTO: Codable {
    let keyCode: UInt16
    let label: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double?
    let rotationPivotX: Double?
    let rotationPivotY: Double?
}

struct LayoutTracerPhysicalLayoutDTO: Codable {
    let id: String
    let name: String
    let keys: [LayoutTracerPhysicalKeyDTO]
    let totalWidth: Double?
    let totalHeight: Double?
}

enum LayoutTracerExporter {
    static func export(
        id: String,
        name: String,
        keys: [TracingKey],
        totalWidth: Double?,
        totalHeight: Double?
    ) throws -> Data {
        let normalizedKeys = keys.enumerated().map { index, key in
            LayoutTracerPhysicalKeyDTO(
                keyCode: key.keyCode,
                label: key.label.isEmpty ? "K\(index + 1)" : key.label,
                x: key.x,
                y: key.y,
                width: key.width,
                height: key.height,
                rotation: key.rotation,
                rotationPivotX: key.rotationPivotX,
                rotationPivotY: key.rotationPivotY
            )
        }
        .sorted {
            if $0.y == $1.y {
                return $0.x < $1.x
            }
            return $0.y < $1.y
        }

        let document = LayoutTracerPhysicalLayoutDTO(
            id: id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "custom-layout" : id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Layout" : name,
            keys: normalizedKeys,
            totalWidth: totalWidth,
            totalHeight: totalHeight
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}
