import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// View modifier that applies overlay-style keycap appearance
struct KeycapStyle: ViewModifier {
    /// Text color matching overlay keycaps (light blue-white)
    static let textColor = Color(red: 0.88, green: 0.93, blue: 1.0)

    /// Background color matching overlay keycaps (dark gray)
    static let backgroundColor = Color(white: 0.12)

    /// Corner radius matching overlay keycaps
    static let cornerRadius: CGFloat = 6

    var ghost: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Self.backgroundColor.opacity(ghost ? 0.4 : 1))
                    .shadow(color: .black.opacity(ghost ? 0.1 : 0.4), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(Color.white.opacity(ghost ? 0.06 : 0.15), lineWidth: 0.5)
            )
    }
}
