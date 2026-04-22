import CoreGraphics
import Foundation

enum LayoutTracerSnapEngine {
    private static let threshold = 8.0

    static func snapMove(moving: TracingKey, others: [TracingKey], guides: [TracingGuide] = []) -> TracingKey {
        var moved = moving
        moved.x = snap(
            value: moved.x,
            candidates: others.flatMap { [$0.x, $0.x + $0.width] } +
                guides.filter { $0.axis == .vertical }.map(\.position)
        ) ?? moved.x
        moved.y = snap(
            value: moved.y,
            candidates: others.flatMap { [$0.y, $0.y + $0.height] } +
                guides.filter { $0.axis == .horizontal }.map(\.position)
        ) ?? moved.y
        return moved
    }

    static func snapResize(resizing: TracingKey, others: [TracingKey], guides: [TracingGuide] = []) -> TracingKey {
        var resized = resizing
        let snappedMaxX = snap(
            value: resized.x + resized.width,
            candidates: others.flatMap { [$0.x, $0.x + $0.width] } +
                guides.filter { $0.axis == .vertical }.map(\.position)
        )
        let snappedMaxY = snap(
            value: resized.y + resized.height,
            candidates: others.flatMap { [$0.y, $0.y + $0.height] } +
                guides.filter { $0.axis == .horizontal }.map(\.position)
        )

        if let snappedMaxX {
            resized.width = max(20, snappedMaxX - resized.x)
        }
        if let snappedMaxY {
            resized.height = max(20, snappedMaxY - resized.y)
        }
        return resized
    }

    private static func snap(value: Double, candidates: [Double]) -> Double? {
        let closest = candidates.min { abs($0 - value) < abs($1 - value) }
        guard let closest, abs(closest - value) <= threshold else { return nil }
        return closest
    }
}
