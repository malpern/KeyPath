import CoreGraphics
import Foundation

enum OverlayInspectorMath {
    static func easedProgress(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        // Control points for easeInEaseOut: (0.42, 0) and (0.58, 1)
        return cubicBezierY(t: clamped, p1y: 0.0, p2y: 1.0, p1x: 0.42, p2x: 0.58)
    }

    static func revealValue(
        start: CGFloat,
        target: CGFloat,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> CGFloat {
        guard duration > 0 else { return target }
        let progress = min(1.0, max(0.0, elapsed / duration))
        let eased = easedProgress(CGFloat(progress))
        return start + (target - start) * eased
    }

    static func clampedReveal(
        expandedWidth: CGFloat,
        collapsedWidth: CGFloat,
        inspectorWidth: CGFloat
    ) -> CGFloat {
        guard inspectorWidth > 0 else { return 0 }
        let reveal = (expandedWidth - collapsedWidth) / inspectorWidth
        return max(0, min(1, reveal))
    }

    private static func cubicBezierY(
        t inputX: CGFloat,
        p1y: CGFloat,
        p2y: CGFloat,
        p1x: CGFloat,
        p2x: CGFloat
    ) -> CGFloat {
        var tGuess = inputX
        for _ in 0 ..< 8 {
            let x = bezierValue(t: tGuess, p1: p1x, p2: p2x)
            let dx = bezierDerivative(t: tGuess, p1: p1x, p2: p2x)
            if abs(dx) < 0.00001 { break }
            tGuess -= (x - inputX) / dx
            tGuess = max(0, min(1, tGuess))
        }

        return bezierValue(t: tGuess, p1: p1y, p2: p2y)
    }

    private static func bezierValue(t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * t * p1
            + 3 * oneMinusT * t * t * p2
            + t * t * t
    }

    private static func bezierDerivative(t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * p1
            + 6 * oneMinusT * t * (p2 - p1)
            + 3 * t * t * (1 - p2)
    }
}
