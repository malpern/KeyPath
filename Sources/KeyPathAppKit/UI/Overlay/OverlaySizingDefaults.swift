import CoreGraphics

enum OverlaySizingDefaults {
    static let baseHeight: CGFloat = 220
    static let startupScale: CGFloat = 1.3
    static let resetScale: CGFloat = 1.3
    static let startupBottomMargin: CGFloat = 40
    static let defaultOriginMargin: CGFloat = 20

    static func startupSize(aspectRatio: CGFloat, inspectorWidth: CGFloat) -> CGSize {
        OverlayWindowSizing.size(
            baseHeight: baseHeight,
            scale: startupScale,
            aspectRatio: aspectRatio,
            inspectorVisible: false,
            inspectorWidth: inspectorWidth
        )
    }

    static func resetCenteredFrame(
        visibleFrame: CGRect?,
        aspectRatio: CGFloat,
        inspectorWidth: CGFloat
    ) -> CGRect {
        OverlayWindowSizing.centeredFrame(
            visibleFrame: visibleFrame,
            baseHeight: baseHeight,
            scale: resetScale,
            aspectRatio: aspectRatio,
            inspectorVisible: false,
            inspectorWidth: inspectorWidth
        )
    }
}
