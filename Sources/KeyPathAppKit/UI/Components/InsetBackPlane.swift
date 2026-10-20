import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Inset Back Plane

/// A container that creates an inset "back plane" effect for expanded content.
/// Uses the shared Settings grouped-box treatment.
struct InsetBackPlane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Same grouped box as Settings, rather than a recessed plane.
            .background(SettingsDesign.groupFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsDesign.groupStroke, lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}
