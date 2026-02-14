import SwiftUI

// MARK: - Window Snapping View

/// A visual, interactive view for the Window Snapping rule collection.
/// Displays a monitor canvas with snap zones and floating action cards.
struct WindowSnappingView: View {
    let mappings: [KeyMapping]
    let convention: WindowKeyConvention
    let onConventionChange: (WindowKeyConvention) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Convention picker (leader key style)
            ConventionPicker(
                convention: convention,
                onConventionChange: onConventionChange
            )

            // Permission status indicator
            PermissionStatusBanner()

            // Monitor canvas with snap zones
            MonitorCanvas(convention: convention)

            // Floating action cards row
            ActionCardsRow(convention: convention)

            // Tip
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Activate via Leader → w, then press the action key")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    WindowSnappingView(
        mappings: [],
        convention: .standard,
        onConventionChange: { _ in }
    )
    .frame(width: 400)
    .padding()
}

#Preview("Window Snapping - Vim") {
    WindowSnappingView(
        mappings: [],
        convention: .vim,
        onConventionChange: { _ in }
    )
    .frame(width: 400)
    .padding()
}
