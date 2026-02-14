import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Inset Back Plane

/// A container that creates an inset "back plane" effect for expanded content.
/// Uses an inner shadow and subtle gradient to create depth.
struct InsetBackPlane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.15),
                                        Color.clear,
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }
}
