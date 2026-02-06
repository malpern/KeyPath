import SwiftUI

extension OverlayKeycapView {
    // MARK: - Window Action Detection

    /// Detect window action type from output label for color-coding
    func windowActionColor(from label: String) -> Color? {
        guard currentLayerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        // Corners - purple
        if lower.contains("top") && lower.contains("left") { return .purple }
        if lower.contains("top") && lower.contains("right") { return .purple }
        if lower.contains("bottom") && lower.contains("left") { return .purple }
        if lower.contains("bottom") && lower.contains("right") { return .purple }

        // Halves - blue
        if lower.contains("left") && lower.contains("half") { return .blue }
        if lower.contains("right") && lower.contains("half") { return .blue }

        // Maximize/Center - green
        if lower.contains("maximize") || lower.contains("fullscreen") { return .green }
        if lower.contains("center") { return .green }

        // Displays - orange
        if lower.contains("display") || lower.contains("monitor") { return .orange }

        // Spaces - cyan
        if lower.contains("space") { return .cyan }

        // Undo - gray
        if lower.contains("undo") { return .gray }

        return nil
    }

    /// Get SF Symbol for window action
    func windowActionSymbol(from label: String) -> String? {
        guard currentLayerName.lowercased().contains("window") else { return nil }

        let lower = label.lowercased()

        // Directional arrows for halves
        if lower.contains("left") && lower.contains("half") { return "arrow.left" }
        if lower.contains("right") && lower.contains("half") { return "arrow.right" }

        // Diagonal arrows for corners
        if lower.contains("top") && lower.contains("left") { return "arrow.up.left" }
        if lower.contains("top") && lower.contains("right") { return "arrow.up.right" }
        if lower.contains("bottom") && lower.contains("left") { return "arrow.down.left" }
        if lower.contains("bottom") && lower.contains("right") { return "arrow.down.right" }

        // Maximize/restore
        if lower.contains("maximize") || lower.contains("fullscreen") {
            return "arrow.up.left.and.arrow.down.right"
        }
        if lower.contains("center") { return "circle.grid.cross" }

        // Displays
        if lower.contains("display") || lower.contains("monitor") { return "display" }

        // Spaces
        if lower.contains("next"), lower.contains("space") { return "arrow.right.square" }
        if lower.contains("previous"), lower.contains("space") { return "arrow.left.square" }

        return nil
    }
}
