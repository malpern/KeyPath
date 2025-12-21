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

    var body: some View {
        toolbarContent
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassedEffect(in: .rect(cornerRadius: 12), interactive: true)
    }

    @ViewBuilder
    private var toolbarContent: some View {
        HStack(spacing: 8) {
            // Layer indicator (compact)
            HStack(spacing: 4) {
                Circle()
                    .fill(currentLayer.lowercased() == "base" ? Color.secondary.opacity(0.4) : Color.accentColor)
                    .frame(width: 6, height: 6)
                Text(currentLayer.lowercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status message (centered area)
            if let message = statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(statusIsError ? .red : .secondary)
                    .lineLimit(1)
            }

            Spacer()

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
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("System action")

            // App launcher picker button
            Button {
                onAppPicker()
            } label: {
                Image(systemName: "app.badge")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Pick app to launch")

            // URL mapping button
            Button {
                onURLPicker()
            } label: {
                Image(systemName: "link")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Map to web URL")

            // Clear/reset button
            ResetButton(
                isEnabled: canSave || inputLabel != "a" || outputLabel != "a",
                onSingleClick: onReset,
                onDoubleClick: onResetAll
            )
        }
    }
}

// MARK: - Reset Button with Double-Click Support

/// A button that handles single click (reset current) and double click (reset all).
private struct ResetButton: View {
    let isEnabled: Bool
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    @State private var clickCount = 0
    @State private var clickTimer: Timer?

    private let doubleClickDelay: TimeInterval = 0.3

    var body: some View {
        Label("Reset", systemImage: "arrow.counterclockwise")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(buttonBackground)
            .opacity(isEnabled ? 1.0 : 0.3)
            .contentShape(Rectangle())
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

    @ViewBuilder
    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Liquid Glass Effect with Backward Compatibility

extension View {
    /// Apply Liquid Glass effect on macOS 26+ with graceful fallback to AppGlass on older systems.
    @ViewBuilder
    func glassedEffect(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            // macOS 26+: Use native Liquid Glass effect
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            // Older macOS: Fallback to AppGlass material
            self.background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.08),
                                .white.opacity(0.03),
                                .black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .blendMode(.overlay)
                    )
                    .overlay(
                        shape
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            )
            .clipShape(shape)
        }
    }
}
