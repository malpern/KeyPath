import CoreGraphics

/// Where the overlay goes when it appears on a display.
///
/// Each display remembers its own overlay frame. On a display the overlay has
/// never been placed on, the last frame is carried over at the same relative
/// position (same corner, same margins), scaled down only if it would not fit.
enum OverlayDisplayPlacement {
    static func frame(
        savedOnTarget: CGRect?,
        lastFrame: CGRect?,
        lastVisibleFrame: CGRect?,
        targetVisibleFrame: CGRect
    ) -> CGRect? {
        if let savedOnTarget, targetVisibleFrame.intersects(savedOnTarget) {
            return clamp(savedOnTarget, to: targetVisibleFrame)
        }
        guard let lastFrame else { return nil }
        guard let lastVisibleFrame, lastVisibleFrame.width > 0, lastVisibleFrame.height > 0 else {
            return clamp(lastFrame, to: targetVisibleFrame)
        }

        var size = lastFrame.size
        let fit = min(1, targetVisibleFrame.width / size.width, targetVisibleFrame.height / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)

        // Keep the frame's centre at the same fraction of the screen.
        let fx = (lastFrame.midX - lastVisibleFrame.minX) / lastVisibleFrame.width
        let fy = (lastFrame.midY - lastVisibleFrame.minY) / lastVisibleFrame.height
        let center = CGPoint(
            x: targetVisibleFrame.minX + fx * targetVisibleFrame.width,
            y: targetVisibleFrame.minY + fy * targetVisibleFrame.height
        )
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        return clamp(frame, to: targetVisibleFrame)
    }

    /// Moves (never resizes, unless larger than the screen) so the frame sits inside `bounds`.
    static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }
}
