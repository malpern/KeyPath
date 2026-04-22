import CoreGraphics
import Foundation

struct TracingKey: Identifiable, Codable, Equatable {
    var id: UUID
    var keyCode: UInt16
    var label: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double?
    var rotationPivotX: Double?
    var rotationPivotY: Double?

    init(
        id: UUID = UUID(),
        keyCode: UInt16 = 0,
        label: String = "",
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        rotation: Double? = nil,
        rotationPivotX: Double? = nil,
        rotationPivotY: Double? = nil
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.rotationPivotX = rotationPivotX
        self.rotationPivotY = rotationPivotY
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
