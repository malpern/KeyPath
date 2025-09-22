import SwiftUI
import AppKit

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
        case .headerStrong, .sheetBold:
            return .contentBackground
        case .cardBold, .popoverBold, .chipBold:
            return .underWindowBackground
        }
    }

    private var overlayGradient: some View {
        // A bold, refractive-inspired overlay that we can dial back later
        let top = Color.white.opacity(0.08)
        let mid = Color.white.opacity(0.03)
        let bottom = Color.black.opacity(0.10)
        return LinearGradient(colors: [top, mid, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: style == .headerStrong ? 0.5 : 0.8)
            .allowsHitTesting(false)
    }
}

// MARK: - Visual Effect Representable

private struct VisualEffectRepresentable: NSViewRepresentable {
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
    func body(content: Content) -> some View {
        content
            .background(AppGlassBackground(style: .headerStrong))
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
    func appGlassHeader() -> some View { modifier(AppGlassHeader()) }
    func appGlassCard() -> some View { modifier(AppGlassCard()) }
}

