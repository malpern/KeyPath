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
            .modifier(
                GlassEffectModifier(
                    isEnabled: !reduceTransparency,
                    cornerRadius: 12,
                    fallbackFill: Color(NSColor.controlBackgroundColor)
                )
            )
    }

    @ViewBuilder
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
            .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
            .foregroundStyle(isInspectorOpen ? Color.accentColor : .secondary)
            .help(isInspectorOpen ? "Hide Inspector" : "Show Inspector")
        }
    }
}

// MARK: - Liquid Glass Effect (macOS 26+ only - no fallback)

private struct GlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        if isEnabled {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fallbackFill)
                )
        }
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(BorderedButtonStyle())
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(GlassButtonStyle())
        } else {
            content.buttonStyle(BorderedButtonStyle())
        }
    }
}
