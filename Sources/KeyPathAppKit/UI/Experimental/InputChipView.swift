import AppKit
import SwiftUI

// MARK: - Input Chip View

struct InputChipView: View {
    let input: CapturedInput
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var appearAnimation = false

    var body: some View {
        HStack(spacing: 6) {
            chipContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipBackground)
        .overlay(chipBorder)
        .clipShape(RoundedRectangle(cornerRadius: chipCornerRadius))
        .shadow(color: .black.opacity(0.1), radius: appearAnimation ? 4 : 0, y: appearAnimation ? 2 : 0)
        .scaleEffect(appearAnimation ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appearAnimation = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("input-capture-delete-button")
                .accessibilityLabel("Delete")
            }
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        switch input {
        case let .key(keyInput):
            keyChipContent(keyInput)
        case let .app(appInput):
            appChipContent(appInput)
        case let .url(urlInput):
            urlChipContent(urlInput)
        }
    }

    private func keyChipContent(_ keyInput: CapturedInput.KeyInput) -> some View {
        HStack(spacing: 4) {
            // Modifier icons
            if keyInput.modifiers.contains(.command) {
                modifierBadge("⌘")
            }
            if keyInput.modifiers.contains(.shift) {
                modifierBadge("⇧")
            }
            if keyInput.modifiers.contains(.option) {
                modifierBadge("⌥")
            }
            if keyInput.modifiers.contains(.control) {
                modifierBadge("⌃")
            }

            // Key name
            Text(keyInput.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    private func modifierBadge(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 4))
    }

    private func appChipContent(_ appInput: CapturedInput.AppInput) -> some View {
        HStack(spacing: 8) {
            if let icon = appInput.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
            }

            Text(appInput.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func urlChipContent(_ urlInput: CapturedInput.URLInput) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)

            Text(urlInput.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private var chipBackground: some View {
        Group {
            switch input {
            case .key:
                LinearGradient(
                    colors: [
                        Color(NSColor.controlBackgroundColor),
                        Color(NSColor.controlBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .app:
                Color.accentColor.opacity(0.1)
            case .url:
                Color.orange.opacity(0.1)
            }
        }
    }

    private var chipBorder: some View {
        RoundedRectangle(cornerRadius: chipCornerRadius)
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch input {
        case .key:
            Color.white.opacity(isHovered ? 0.3 : 0.15)
        case .app:
            Color.accentColor.opacity(isHovered ? 0.5 : 0.3)
        case .url:
            Color.orange.opacity(isHovered ? 0.5 : 0.3)
        }
    }

    private var chipCornerRadius: CGFloat {
        switch input {
        case .key: 8
        case .app, .url: 10
        }
    }
}
