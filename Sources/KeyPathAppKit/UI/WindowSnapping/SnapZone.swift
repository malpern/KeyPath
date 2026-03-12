import SwiftUI

// MARK: - Snap Zone Model

enum SnapZone: String, CaseIterable {
    /// Corners
    case topLeft, topRight, bottomLeft, bottomRight
    /// Halves
    case left, right
    /// Full
    case maximize, center

    func key(for convention: WindowKeyConvention) -> String {
        switch convention {
        case .standard:
            switch self {
            case .topLeft: "U"
            case .topRight: "I"
            case .bottomLeft: "J"
            case .bottomRight: "K"
            case .left: "L"
            case .right: "R"
            case .maximize: "M"
            case .center: "C"
            }
        case .vim:
            switch self {
            case .topLeft: "Y"
            case .topRight: "U"
            case .bottomLeft: "B"
            case .bottomRight: "N"
            case .left: "H"
            case .right: "L"
            case .maximize: "M"
            case .center: "C"
            }
        }
    }

    var label: String {
        switch self {
        case .topLeft: "Top-Left"
        case .topRight: "Top-Right"
        case .bottomLeft: "Bottom-Left"
        case .bottomRight: "Bottom-Right"
        case .left: "Left"
        case .right: "Right"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    var color: Color {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            .purple
        case .left, .right:
            .blue
        case .maximize, .center:
            .green
        }
    }
}
