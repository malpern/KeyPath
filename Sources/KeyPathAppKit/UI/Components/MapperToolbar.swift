import SwiftUI

// MARK: - Mapper Toolbar

/// Adaptive toolbar for MapperView that uses Liquid Glass on macOS 26+ with backward compatibility.
struct MapperToolbar: View {
    let currentLayer: String
    let statusMessage: String?
    let statusIsError: Bool
    let canSave: Bool
    let inputLabel: String
    let outputLabel: String

    let onSystemActionPicked: (SystemActionInfo) -> Void
    let onAppPicker: () -> Void
    let onURLPicker: () -> Void
    let onReset: () -> Void
    let onResetAll: () -> Void

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

            // Toolbar buttons group - use default spacing and sizing
            HStack {
                // System action picker menu
                Menu {
                    ForEach(SystemActionInfo.allActions) { action in
                        Button {
                            onSystemActionPicked(action)
                        } label: {
                            Label(action.name, systemImage: action.sfSymbol)
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .help("System action")

                // App launcher picker button
                Button {
                    onAppPicker()
                } label: {
                    Image(systemName: "app.badge")
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .help("Pick app to launch")

                // URL mapping button
                Button {
                    onURLPicker()
                } label: {
                    Image(systemName: "link")
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .help("Map to web URL")

                // Clear/reset button
                ResetButton(
                    isEnabled: canSave || inputLabel != "a" || outputLabel != "a",
                    reduceTransparency: reduceTransparency,
                    onSingleClick: onReset,
                    onDoubleClick: onResetAll
                )
            }
        }
    }
}

// MARK: - Reset Button with Double-Click Support

/// A button that handles single click (reset current) and double click (reset all).
private struct ResetButton: View {
    let isEnabled: Bool
    let reduceTransparency: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?

    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Button {
            // Handle via onTapGesture below for double-click support
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
        .disabled(!isEnabled)
        .onTapGesture {
                guard isEnabled else { return }
                clickCount += 1

                if clickCount == 1 {
                    // Start timer to wait for potential second click
                    clickTimer = Timer.scheduledTimer(withTimeInterval: doubleClickDelay, repeats: false) { _ in
                        Task { @MainActor in
                            if clickCount == 1 {
                                onSingleClick()
                            }
                            clickCount = 0
                        }
                    }
                } else if clickCount >= 2 {
                    // Double click detected
                    clickTimer?.invalidate()
                    clickTimer = nil
                    clickCount = 0
                    onDoubleClick()
                }
            }
            .help("Click: Reset mapping. Double-click: Reset all to defaults")
    }
}

// MARK: - Liquid Glass Effect (macOS 26+ only - no fallback)

// Fallback code removed to verify Liquid Glass is being applied directly

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
