import SwiftUI

// MARK: - Mapper Toolbar

/// Adaptive toolbar for MapperView that uses Liquid Glass on macOS 26+ with backward compatibility.
/// Simplified version - most functions moved to inspector sidebar.
struct MapperToolbar: View {
    let currentLayer: String
    let statusMessage: String?
    let statusIsError: Bool
    let isInspectorOpen: Bool
    let onToggleInspector: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        toolbarContent
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(toolbarBackground)
    }

    private var toolbarContent: some View {
        HStack {
            // Layer indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(currentLayer.lowercased() == "base" ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 8, height: 8)
                Text(currentLayer.lowercased())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status message (centered area)
            if let message = statusMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(statusIsError ? .red : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Inspector toggle button
            Button {
                onToggleInspector()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(toolbarButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(isInspectorOpen ? Color.accentColor : .secondary)
            .help(isInspectorOpen ? "Hide Inspector" : "Show Inspector")
        }
    }

    private var toolbarBackground: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            } else {
                AppGlassBackground(style: .headerStrong, cornerRadius: 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolbarButtonBackground: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(isInspectorOpen ? 0.18 : 0.10))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        .blendMode(.overlay)
                }
            }
        }
    }
}

// MARK: - Notes

//
// We intentionally avoid SwiftUI "Liquid Glass" APIs here.
// GitHub CI currently builds with Xcode 16.4 (macOS 15 SDK), which does not include those symbols.
