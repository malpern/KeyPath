import AppKit
import KeyPathRulesCore
import SwiftUI

// MARK: - Function Keys View

/// A visual view for the macOS Function Keys rule collection.
/// Shows F1-F12 and explains unavailable media remapping.
struct FunctionKeysView: View {
    let mappings: [KeyMapping]
    /// The current function key mode from the collection
    let currentMode: FunctionKeyMode?
    /// Callback when display mode changes
    var onModeChange: ((FunctionKeyMode) -> Void)?

    /// The saved mode, including unsupported media configurations that need changing.
    @State private var preferMediaKeys: Bool = false

    init(mappings: [KeyMapping], currentMode: FunctionKeyMode? = nil, onModeChange: ((FunctionKeyMode) -> Void)? = nil) {
        self.mappings = mappings
        self.currentMode = currentMode
        self.onModeChange = onModeChange
        // Initialize preferMediaKeys based on currentMode
        _preferMediaKeys = State(initialValue: currentMode?.preferMediaKeys ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Function key row
            FunctionKeyRow(showMediaKeys: preferMediaKeys)

            // Toggle control
            DisplayModeToggle(showMediaKeys: $preferMediaKeys)

            Text(SystemActionInfo.driverlessMediaUnavailableReason + " Your keyboard’s normal media controls remain managed by macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .onChange(of: preferMediaKeys) { _, newValue in
            let mode = FunctionKeyMode(preferMediaKeys: newValue)
            guard mode.isSupportedInDriverlessSession else { return }
            onModeChange?(mode)
        }
    }
}

// MARK: - Function Key Row

private struct FunctionKeyRow: View {
    let showMediaKeys: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FunctionKeyInfo.allKeys, id: \.keyCode) { keyInfo in
                FunctionKeyCard(
                    keyInfo: keyInfo,
                    showMediaKey: showMediaKeys
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
        VStack(spacing: 4) {
            // Icon/label area
            ZStack {
                if displayedShowMedia {
                    // Media key icon
                    Image(systemName: keyInfo.mediaIcon)
                        .font(.body.weight(.medium))
                        .foregroundColor(keyInfo.iconColor)
                } else {
                    // Function key label
                    Text(keyInfo.fKeyLabel)
                        .font(.footnote.monospaced().weight(.semibold))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(displayedShowMedia ? keyInfo.iconColor.opacity(0.12) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(displayedShowMedia ? keyInfo.iconColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )

            // Small label underneath
            Text(displayedShowMedia ? keyInfo.shortLabel : keyInfo.fKeyLabel)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            displayedShowMedia = showMediaKey
            randomDelay = Double.random(in: 0 ... 0.12)
            durationMultiplier = Double.random(in: 0.8 ... 1.3)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SettingsOptionCard(
                    icon: "sun.max",
                    title: "Media Keys",
                    subtitle: "Unsupported in driverless mode",
                    isSelected: showMediaKeys
                ) {
                    guard FunctionKeyMode.media.isSupportedInDriverlessSession else { return }
                    showMediaKeys = true
                }
                .disabled(!FunctionKeyMode.media.isSupportedInDriverlessSession)
                .accessibilityIdentifier("function-key-mode-media")

                SettingsOptionCard(
                    icon: "function",
                    title: "Function Keys",
                    subtitle: "F1–F12 for apps",
                    isSelected: !showMediaKeys
                ) {
                    showMediaKeys = false
                }
                .accessibilityIdentifier("function-key-mode-function")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Icon Segmented Control

/// A segmented control that displays SF Symbol icons with labels
private struct IconSegmentedControl<T: Hashable>: NSViewRepresentable {
    @Binding var selection: T
    let segments: [(value: T, icon: String, label: String)]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = segments.count
        control.segmentStyle = .texturedRounded
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        for (index, segment) in segments.enumerated() {
            // Create image from SF Symbol
            if let image = NSImage(systemSymbolName: segment.icon, accessibilityDescription: segment.label) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                let configuredImage = image.withSymbolConfiguration(config)
                control.setImage(configuredImage, forSegment: index)
            }
            control.setLabel(segment.label, forSegment: index)
            control.setWidth(0, forSegment: index) // Auto-size
        }

        // Select initial segment
        if let index = segments.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = index
        }

        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context _: Context) {
        if let index = segments.firstIndex(where: { $0.value == selection }) {
            if nsView.selectedSegment != index {
                nsView.selectedSegment = index
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: IconSegmentedControl

        init(_ parent: IconSegmentedControl) {
            self.parent = parent
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            if index >= 0, index < parent.segments.count {
                parent.selection = parent.segments[index].value
            }
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
        .frame(width: 500)
        .padding()
}

#Preview("Function Keys - F Row Mode") {
    FunctionKeysView(
        mappings: [],
        currentMode: .function,
        onModeChange: { _ in }
    )
    .frame(width: 500)
    .padding()
}
