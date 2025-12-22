import CoreGraphics

enum OverlayLayoutMetrics {
    static let headerHeight: CGFloat = 15
    static let headerBottomSpacing: CGFloat = 4
    static let keyboardPadding: CGFloat = 6
    static let keyboardTrailingPadding: CGFloat = keyboardPadding
    static let outerHorizontalPadding: CGFloat = 4
    static let inspectorSeamWidth: CGFloat = 0

    static var verticalChrome: CGFloat {
        headerHeight + headerBottomSpacing + keyboardPadding
    }

    static func horizontalChrome(
        inspectorVisible: Bool,
        inspectorWidth: CGFloat
    ) -> CGFloat {
        let inspectorChrome = inspectorVisible ? inspectorWidth + inspectorSeamWidth : 0
        return keyboardPadding
            + keyboardTrailingPadding
            + outerHorizontalPadding * 2
            + inspectorChrome
    }
}
