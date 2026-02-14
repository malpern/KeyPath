import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct VimArrowKeysView: View {
    var body: some View {
        VStack(spacing: 8) {
            // Arrow key cluster
            HStack(spacing: 20) {
                // Left side labels
                VStack(alignment: .trailing, spacing: 4) {
                    Text("← H")
                        .font(.caption.monospaced().weight(.medium))
                    Text("Move left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Center cluster (J K)
                VStack(spacing: 4) {
                    VimArrowKey(key: "K", direction: .up)
                    HStack(spacing: 4) {
                        VimArrowKey(key: "H", direction: .left)
                        VimArrowKey(key: "J", direction: .down)
                        VimArrowKey(key: "L", direction: .right)
                    }
                }

                // Right side labels
                VStack(alignment: .leading, spacing: 4) {
                    Text("L →")
                        .font(.caption.monospaced().weight(.medium))
                    Text("Move right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct VimArrowKey: View {
    let key: String
    let direction: ArrowDirection

    @State private var isHovered = false
    @State private var pulseOffset: CGSize = .zero
    @State private var pulseOpacity: Double = 0

    enum ArrowDirection {
        case up, down, left, right

        var arrow: String {
            switch self {
            case .up: "↑"
            case .down: "↓"
            case .left: "←"
            case .right: "→"
            }
        }

        var offset: CGSize {
            switch self {
            case .up: CGSize(width: 0, height: -12)
            case .down: CGSize(width: 0, height: 12)
            case .left: CGSize(width: -12, height: 0)
            case .right: CGSize(width: 12, height: 0)
            }
        }
    }

    var body: some View {
        ZStack {
            // Pulse arrow (animated)
            Text(direction.arrow)
                .font(.body.weight(.bold))
                .foregroundColor(.blue)
                .offset(pulseOffset)
                .opacity(pulseOpacity)

            // Key label
            Text(key)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundColor(isHovered ? .blue : .primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovered ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                triggerPulse()
            }
        }
    }

    private func triggerPulse() {
        // Reset
        pulseOffset = .zero
        pulseOpacity = 0.8

        // Animate outward
        withAnimation(.easeOut(duration: 0.4)) {
            pulseOffset = direction.offset
            pulseOpacity = 0
        }
    }
}
