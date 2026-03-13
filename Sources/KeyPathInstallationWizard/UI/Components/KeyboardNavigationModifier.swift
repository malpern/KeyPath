import SwiftUI

/// ViewModifier that adds keyboard navigation support with macOS version compatibility
public struct KeyboardNavigationModifier: ViewModifier {
    public let onLeftArrow: () -> Void
    public let onRightArrow: () -> Void
    public let onEscape: (() -> Void)?

    public init(
        onLeftArrow: @escaping () -> Void, onRightArrow: @escaping () -> Void,
        onEscape: (() -> Void)? = nil
    ) {
        self.onLeftArrow = onLeftArrow
        self.onRightArrow = onRightArrow
        self.onEscape = onEscape
    }

    public func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.leftArrow) {
                    onLeftArrow()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    onRightArrow()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onEscape?()
                    return .handled
                }
                .focusable(true)
        } else {
            // For macOS 13.0, keyboard navigation isn't available
            content
        }
    }
}
