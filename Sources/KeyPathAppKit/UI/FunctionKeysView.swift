import AppKit
import SwiftUI

// MARK: - Function Keys View

/// A visual view for the macOS Function Keys rule collection.
/// Shows F1-F12 as flip cards that reveal either function keys or media icons.
struct FunctionKeysView: View {
    let mappings: [KeyMapping]
    /// Callback when display mode changes (true = media keys, false = function keys)
    var onModeChange: ((Bool) -> Void)?

    /// User's preferred display mode: true = show media keys (default Mac behavior)
    @State private var preferMediaKeys: Bool = true

    /// Whether fn key is currently held (temporarily flips display)
    @State private var isFnHeld: Bool = false

    /// Event monitor for fn key
    @State private var flagsMonitor: Any?

    /// Effective display state (combines preference with fn key override)
    private var showMediaKeys: Bool {
        // If user prefers media keys and fn is held, show F-keys (flip)
        // If user prefers F-keys and fn is held, show media keys (flip)
        preferMediaKeys != isFnHeld
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Function key row
            FunctionKeyRow(showMediaKeys: showMediaKeys)

            // Toggle control
            DisplayModeToggle(showMediaKeys: $preferMediaKeys)

            // Educational tip
            HStack(spacing: 8) {
                FnKeyBadge()
                Text("Hold fn to temporarily flip to \(preferMediaKeys ? "function keys" : "media keys")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .onAppear {
            startMonitoringFnKey()
        }
        .onDisappear {
            stopMonitoringFnKey()
        }
        .onChange(of: preferMediaKeys) { _, newValue in
            onModeChange?(newValue)
        }
    }

    // MARK: - Fn Key Monitoring

    private func startMonitoringFnKey() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed != isFnHeld {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFnHeld = fnPressed
                }
            }
            return event
        }
    }

    private func stopMonitoringFnKey() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }
}

// MARK: - Fn Key Badge

private struct FnKeyBadge: View {
    var body: some View {
        Text("fn")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 20, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.7))
            )
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
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(keyInfo.iconColor)
                } else {
                    // Function key label
                    Text(keyInfo.fKeyLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            displayedShowMedia = showMediaKey
            randomDelay = Double.random(in: 0...0.12)
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
        VStack(alignment: .leading, spacing: 10) {
            // Custom segmented control with icons
            IconSegmentedControl(
                selection: $showMediaKeys,
                segments: [
                    (true, "sun.max", "Media Keys"),
                    (false, "function", "Function Keys")
                ]
            )
            .padding(.horizontal, 4)

            // Description
            Text(showMediaKeys
                ? "Shows brightness, volume, and media controls (default Mac behavior)"
                : "Shows F1-F12 for apps that use function keys")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
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

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
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
            if index >= 0 && index < parent.segments.count {
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
