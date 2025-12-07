import AppKit
import SwiftUI

// MARK: - AppGlass Styles

enum AppGlassStyle {
    case headerStrong
    case cardBold
    case chipBold
    case popoverBold
    case sheetBold
}

// MARK: - Background View

struct AppGlassBackground: View {
    let style: AppGlassStyle
    var cornerRadius: CGFloat = 0

    var body: some View {
        ZStack {
            VisualEffectRepresentable(material: material, blending: .behindWindow)
                .overlay(overlayGradient)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(borderOverlay)
        .compositingGroup()
    }

    private var material: NSVisualEffectView.Material {
        switch style {
        case .headerStrong:
            .menu
        case .cardBold, .chipBold:
            .menu
        case .popoverBold:
            .popover
        case .sheetBold:
            .hudWindow
        }
    }

    private var overlayGradient: some View {
        // A bold, refractive-inspired overlay that we can dial back later
        let top = Color.white.opacity(0.08)
        let mid = Color.white.opacity(0.03)
        let bottom = Color.black.opacity(0.10)
        return LinearGradient(
            colors: [top, mid, bottom], startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: style == .headerStrong ? 0.5 : 0.8)
            .allowsHitTesting(false)
    }
}

// MARK: - Visual Effect Representable

struct VisualEffectRepresentable: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Modifiers

struct AppGlassHeader: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(AppGlassBackground(style: .headerStrong, cornerRadius: radius))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct AppGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppGlassBackground(style: .cardBold, cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func appGlassHeader() -> some View { modifier(AppGlassHeader(radius: 12)) }
    func appGlassCard() -> some View { modifier(AppGlassCard()) }
    func appGlassPopover(cornerRadius: CGFloat = 10) -> some View {
        background(AppGlassBackground(style: .popoverBold, cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func appGlassSheet(cornerRadius: CGFloat = 12) -> some View {
        background(AppGlassBackground(style: .sheetBold, cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Solid Surface Card (for high-contrast content)

struct AppSurfaceCard: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
            )
    }
}

extension View {
    func appSurfaceCard(radius: CGFloat = 12) -> some View {
        modifier(AppSurfaceCard(radius: radius))
    }
}

// MARK: - Field Glass (tinted for text legibility)

struct AppFieldGlass: ViewModifier {
    var radius: CGFloat = 8
    var opacity: Double = 0.18 // tint strength for readability
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(opacity))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

extension View {
    func appFieldGlass(radius: CGFloat = 8, opacity: Double = 0.18) -> some View {
        modifier(AppFieldGlass(radius: radius, opacity: opacity))
    }
}

// MARK: - Button Glass (tinted)

struct AppButtonGlass: ViewModifier {
    var tint: Color = .accentColor
    var radius: CGFloat = 8
    var active: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 0)
            .background(
                ZStack {
                    VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                    // Tint layer
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(active ? 0.22 : 0.10))
                    // Highlight edge
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        .blendMode(.overlay)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func appButtonGlass(tint: Color = .accentColor, radius: CGFloat = 8, active: Bool = true)
        -> some View {
        modifier(AppButtonGlass(tint: tint, radius: radius, active: active))
    }
}

// MARK: - Solid Glass Button

struct AppSolidGlassButton: ViewModifier {
    var tint: Color = .accentColor
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func appSolidGlassButton(tint: Color = .accentColor, radius: CGFloat = 8) -> some View {
        modifier(AppSolidGlassButton(tint: tint, radius: radius))
    }
}
