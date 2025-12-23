import SwiftUI

// MARK: - Function Keys View

/// A visual view for the macOS Function Keys rule collection.
/// Shows F1-F12 as flip cards that reveal either function keys or media icons.
struct FunctionKeysView: View {
    let mappings: [KeyMapping]

    /// Display mode: true = show media keys (default Mac behavior), false = show F-keys
    @State private var showMediaKeys: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Function key row
            FunctionKeyRow(showMediaKeys: showMediaKeys)

            // Toggle control
            DisplayModeToggle(showMediaKeys: $showMediaKeys)

            // Educational tip
            HStack(spacing: 6) {
                Image(systemName: "fn")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.6))
                    )
                Text("Hold fn to temporarily flip to function keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Function Key Row

private struct FunctionKeyRow: View {
    let showMediaKeys: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FunctionKeyInfo.allKeys, id: \.keyCode) { keyInfo in
                FunctionKeyCard(
                    keyInfo: keyInfo,
                    showMediaKey: showMediaKeys
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Function Key Card (Flip Card)

private struct FunctionKeyCard: View {
    let keyInfo: FunctionKeyInfo
    let showMediaKey: Bool

    /// Current displayed content
    @State private var displayedShowMedia: Bool = true
    @State private var flipAngle: Double = 0

    /// Randomized timing for organic feel
    @State private var randomDelay: Double = 0
    @State private var durationMultiplier: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            // Icon/label area
            ZStack {
                if displayedShowMedia {
                    // Media key icon
                    Image(systemName: keyInfo.mediaIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(keyInfo.iconColor)
                } else {
                    // Function key label
                    Text(keyInfo.fKeyLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(displayedShowMedia ? keyInfo.iconColor.opacity(0.12) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(displayedShowMedia ? keyInfo.iconColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )

            // Small label underneath
            Text(displayedShowMedia ? keyInfo.shortLabel : keyInfo.fKeyLabel)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            displayedShowMedia = showMediaKey
            randomDelay = Double.random(in: 0...0.15)
            durationMultiplier = Double.random(in: 0.8...1.3)
        }
        .onChange(of: showMediaKey) { oldValue, newValue in
            guard oldValue != newValue else { return }

            if reduceMotion {
                displayedShowMedia = newValue
            } else {
                // Direction: showing media flips right, showing F-keys flips left
                let targetAngle: Double = newValue ? 90 : -90
                let baseDuration = 0.15 * durationMultiplier

                DispatchQueue.main.asyncAfter(deadline: .now() + randomDelay) {
                    withAnimation(.easeIn(duration: baseDuration)) {
                        flipAngle = targetAngle
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + baseDuration) {
                        displayedShowMedia = newValue
                        withAnimation(.easeOut(duration: baseDuration)) {
                            flipAngle = 0
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Display Mode Toggle

private struct DisplayModeToggle: View {
    @Binding var showMediaKeys: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Display Mode", selection: $showMediaKeys) {
                Text("Media Keys").tag(true)
                Text("Function Keys").tag(false)
            }
            .pickerStyle(.segmented)

            Text(showMediaKeys
                ? "Shows brightness, volume, and media controls (default Mac behavior)"
                : "Shows F1-F12 for apps that use function keys")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Function Key Info Model

private struct FunctionKeyInfo {
    let keyCode: String
    let fKeyLabel: String
    let mediaIcon: String
    let shortLabel: String
    let iconColor: Color

    static let allKeys: [FunctionKeyInfo] = [
        FunctionKeyInfo(keyCode: "f1", fKeyLabel: "F1", mediaIcon: "sun.min", shortLabel: "Dim", iconColor: .yellow),
        FunctionKeyInfo(keyCode: "f2", fKeyLabel: "F2", mediaIcon: "sun.max", shortLabel: "Bright", iconColor: .yellow),
        FunctionKeyInfo(keyCode: "f3", fKeyLabel: "F3", mediaIcon: "rectangle.3.group", shortLabel: "Mission", iconColor: .blue),
        FunctionKeyInfo(keyCode: "f4", fKeyLabel: "F4", mediaIcon: "magnifyingglass", shortLabel: "Search", iconColor: .blue),
        FunctionKeyInfo(keyCode: "f5", fKeyLabel: "F5", mediaIcon: "mic", shortLabel: "Dictate", iconColor: .green),
        FunctionKeyInfo(keyCode: "f6", fKeyLabel: "F6", mediaIcon: "moon", shortLabel: "DND", iconColor: .purple),
        FunctionKeyInfo(keyCode: "f7", fKeyLabel: "F7", mediaIcon: "backward.fill", shortLabel: "Prev", iconColor: .pink),
        FunctionKeyInfo(keyCode: "f8", fKeyLabel: "F8", mediaIcon: "playpause.fill", shortLabel: "Play", iconColor: .pink),
        FunctionKeyInfo(keyCode: "f9", fKeyLabel: "F9", mediaIcon: "forward.fill", shortLabel: "Next", iconColor: .pink),
        FunctionKeyInfo(keyCode: "f10", fKeyLabel: "F10", mediaIcon: "speaker.slash", shortLabel: "Mute", iconColor: .gray),
        FunctionKeyInfo(keyCode: "f11", fKeyLabel: "F11", mediaIcon: "speaker.wave.1", shortLabel: "Vol-", iconColor: .gray),
        FunctionKeyInfo(keyCode: "f12", fKeyLabel: "F12", mediaIcon: "speaker.wave.3", shortLabel: "Vol+", iconColor: .gray)
    ]
}

// MARK: - Preview

#Preview {
    FunctionKeysView(mappings: [])
        .frame(width: 450)
        .padding()
}
