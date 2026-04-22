import Foundation

struct TracingGuide: Identifiable, Codable, Equatable {
    enum Axis: String, Codable {
        case horizontal
        case vertical
    }

    var id: UUID
    var axis: Axis
    var position: Double

    init(id: UUID = UUID(), axis: Axis, position: Double) {
        self.id = id
        self.axis = axis
        self.position = position
    }
}
