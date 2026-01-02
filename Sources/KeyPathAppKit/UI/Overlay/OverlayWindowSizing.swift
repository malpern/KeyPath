import CoreGraphics

enum OverlayWindowSizing {
    static func size(
        baseHeight: CGFloat,
        scale: CGFloat,
        aspectRatio: CGFloat,
        inspectorVisible: Bool,
        inspectorWidth: CGFloat
    ) -> CGSize {
        let targetHeight = baseHeight * scale
        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: inspectorVisible,
            inspectorWidth: inspectorWidth
        )
        let keyboardHeight = max(0, targetHeight - verticalChrome)
        let keyboardWidth = keyboardHeight * max(aspectRatio, 0.1)
        let width = keyboardWidth + horizontalChrome
        return CGSize(width: width, height: targetHeight)
    }

    static func centeredFrame(
        visibleFrame: CGRect?,
        baseHeight: CGFloat,
        scale: CGFloat,
        aspectRatio: CGFloat,
        inspectorVisible: Bool,
        inspectorWidth: CGFloat
    ) -> CGRect {
        let size = size(
            baseHeight: baseHeight,
            scale: scale,
            aspectRatio: aspectRatio,
            inspectorVisible: inspectorVisible,
            inspectorWidth: inspectorWidth
        )
        guard let visibleFrame else {
            return CGRect(origin: .zero, size: size)
        }

        let origin = CGPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2)
        )
        return CGRect(origin: origin, size: size)
    }
}
