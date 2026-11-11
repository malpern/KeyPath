import AppKit
import SwiftUI

// MARK: - AppGlass Styles

enum AppGlassStyle {
    case chipBold
    case sheetBold
}

// MARK: - Background View

/// The app's glass surface: the system Liquid Glass material (macOS 26+), in the
/// given corner radius. It used to imitate glass with an `NSVisualEffectView`
/// and a hand-drawn gradient and border (project review 2026-11-09, P7).
struct AppGlassBackground: View {
    let style: AppGlassStyle
    var cornerRadius: CGFloat = 0

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .allowsHitTesting(false)
    }
}

// MARK: - Visual Effect Representable

/// A plain `NSVisualEffectView`, for window-level backgrounds that sit over the
/// desktop (`.behindWindow`) or need a specific AppKit material.
struct VisualEffectRepresentable: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    var emphasized = true

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Modifiers

extension View {
    func appGlassSheet(cornerRadius: CGFloat = 12) -> some View {
        background(AppGlassBackground(style: .sheetBold, cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
