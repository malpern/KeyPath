import AppKit
import SwiftUI

struct OverlayGlassButtonStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background(
                Group {
                    if reduceTransparency {
                        Color.clear
                    } else {
                        ZStack {
                            VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                .blendMode(.overlay)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OverlayGlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if isEnabled {
                        if reduceTransparencyFallback {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(fallbackFill)
                        } else {
                            AppGlassBackground(style: .chipBold, cornerRadius: cornerRadius)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fallbackFill)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var reduceTransparencyFallback: Bool {
        // `OverlayGlassEffectModifier` is used for subtle pill backgrounds.
        // When transparency is reduced, keep it solid/tinted instead of blur.
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
