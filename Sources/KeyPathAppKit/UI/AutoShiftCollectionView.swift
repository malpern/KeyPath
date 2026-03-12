import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Auto Shift Symbols Collection View

/// Interactive grid of symbol key chips with timeout and fast-typing controls.
///
/// Styled to match `HomeRowKeyChip` — each chip shows the tap output (normal symbol)
/// prominently and the hold output (shifted symbol) below with a "hold" indicator,
/// making the dual-role behavior immediately obvious.
struct AutoShiftCollectionView: View {
    let config: AutoShiftSymbolsConfig
    let onConfigChanged: (AutoShiftSymbolsConfig) -> Void

    // MARK: - Internal State

    @State private var enabledKeys: Set<String>
    @State private var timeoutMs: Int
    @State private var protectFastTyping: Bool
    @State private var hoveredKey: String?
    @State private var flashedKey: String?
    @State private var eventMonitor: Any?

    // MARK: - Constants

    private static let keyCodeToKanataKey: [UInt16: String] = [
        50: "grv", // `
        27: "min", // -
        24: "eql", // =
        33: "lbrc", // [
        30: "rbrc", // ]
        42: "bsls", // \
        41: "scln", // ;
        39: "apos", // '
        43: "comm", // ,
        47: "dot", // .
        44: "slsh", // /
    ]

    /// Top row: keys that appear on the number/bracket row of a keyboard
    private static let topRowKeys = ["grv", "min", "eql", "lbrc", "rbrc", "bsls"]
    /// Bottom row: keys that appear on the punctuation row
    private static let bottomRowKeys = ["scln", "apos", "comm", "dot", "slsh"]

    // MARK: - Init

    init(config: AutoShiftSymbolsConfig, onConfigChanged: @escaping (AutoShiftSymbolsConfig) -> Void) {
        self.config = config
        self.onConfigChanged = onConfigChanged
        _enabledKeys = State(initialValue: config.enabledKeys)
        _timeoutMs = State(initialValue: config.timeoutMs)
        _protectFastTyping = State(initialValue: config.protectFastTyping)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            experimentalBadge
            keyboardSection
            timeoutSection
            fastTypingToggle
        }
        .onAppear { installEventMonitor() }
        .onDisappear { removeEventMonitor() }
        .onChange(of: enabledKeys) { _, _ in emitConfig() }
        .onChange(of: timeoutMs) { _, _ in emitConfig() }
        .onChange(of: protectFastTyping) { _, _ in emitConfig() }
    }

    // MARK: - Experimental Badge

    private var experimentalBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "flask.fill")
                .font(.caption2)
                .foregroundColor(.orange)
            Text("Experimental")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityLabel("Experimental feature")
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(spacing: 10) {
            // Helper text — matches HRM style
            Text("Tap for symbol, hold for shifted")
                .font(.caption)
                .foregroundColor(.secondary)

            // Responsive sizing like HRM's ViewThatFits
            ViewThatFits(in: .horizontal) {
                keyRows(chipSize: 64)
                keyRows(chipSize: 56)
                keyRows(chipSize: 48)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    private func keyRows(chipSize: CGFloat) -> some View {
        let spacing = max(4, chipSize * 0.1)
        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(Self.topRowKeys, id: \.self) { key in
                    autoShiftChip(for: key, size: chipSize)
                }
            }
            HStack(spacing: spacing) {
                ForEach(Self.bottomRowKeys, id: \.self) { key in
                    autoShiftChip(for: key, size: chipSize)
                }
            }
        }
    }

    // MARK: - Key Chip (HomeRowKeyChip-style)

    private func autoShiftChip(for key: String, size: CGFloat) -> some View {
        let labels = AutoShiftSymbolsConfig.shiftedLabels[key]
        let isEnabled = enabledKeys.contains(key)
        let isHovered = hoveredKey == key
        let isFlashed = flashedKey == key

        let letterSize = max(15, size * 0.3)
        let shiftedSize = max(12, size * 0.22)

        return Button {
            toggleKey(key)
        } label: {
            VStack(spacing: 4) {
                // Tap output — prominent, like the letter in HRM
                Text(labels?.normal ?? key)
                    .font(.system(size: letterSize, weight: .semibold, design: .monospaced))
                    .foregroundColor(chipTextColor(isEnabled: isEnabled, isFlashed: isFlashed))

                // Hold output — styled as a "shift target" chip
                if isEnabled {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: max(8, size * 0.13), weight: .semibold))
                        Text(labels?.shifted ?? "")
                            .font(.system(size: shiftedSize, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(holdChipForeground(isFlashed: isFlashed))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(holdChipBackground(isFlashed: isFlashed))
                    )
                    .overlay(
                        Capsule()
                            .stroke(holdChipBorder(isFlashed: isFlashed), lineWidth: 0.6)
                    )
                } else {
                    Text("—")
                        .font(.system(size: max(11, size * 0.2)))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipBackground(isEnabled: isEnabled, isHovered: isHovered, isFlashed: isFlashed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(chipBorder(isEnabled: isEnabled, isHovered: isHovered, isFlashed: isFlashed),
                            lineWidth: isFlashed ? 2 : 1)
            )
            .scaleEffect(isFlashed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isFlashed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredKey = hovering ? key : nil
            }
            #if os(macOS)
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            #endif
        }
        .accessibilityIdentifier("autoshift-key-\(key)")
        .accessibilityLabel("Tap \(labels?.normal ?? key), hold for \(labels?.shifted ?? ""), \(isEnabled ? "enabled" : "disabled")")
        .accessibilityAddTraits(isEnabled ? .isSelected : [])
    }

    // MARK: - Chip Colors (matches HomeRowKeyChip)

    private func chipTextColor(isEnabled: Bool, isFlashed: Bool) -> Color {
        if isFlashed {
            .white
        } else if isEnabled {
            .primary
        } else {
            .secondary.opacity(0.5)
        }
    }

    private func chipBackground(isEnabled: Bool, isHovered: Bool, isFlashed: Bool) -> Color {
        if isFlashed {
            .accentColor
        } else if isHovered {
            Color(NSColor.controlAccentColor).opacity(0.2)
        } else if isEnabled {
            Color(NSColor.controlBackgroundColor)
        } else {
            Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    private func chipBorder(isEnabled: Bool, isHovered: Bool, isFlashed: Bool) -> Color {
        if isFlashed {
            .accentColor
        } else if isHovered {
            Color(NSColor.controlAccentColor).opacity(0.5)
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    // MARK: - Hold Chip Colors (like HomeRowLayerTargetChip)

    private func holdChipForeground(isFlashed: Bool) -> Color {
        isFlashed ? .white.opacity(0.9) : .accentColor
    }

    private func holdChipBackground(isFlashed: Bool) -> Color {
        isFlashed ? Color.white.opacity(0.15) : Color.accentColor.opacity(0.14)
    }

    private func holdChipBorder(isFlashed: Bool) -> Color {
        isFlashed ? Color.white.opacity(0.3) : Color.accentColor.opacity(0.28)
    }

    // MARK: - Timeout Section

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Timeout")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(timeoutMs) ms")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(timeoutMs) },
                    set: { timeoutMs = Int($0) }
                ),
                in: 100 ... 400,
                step: 10
            )
            .accessibilityIdentifier("autoshift-timeout-slider")
            .accessibilityLabel("Auto shift timeout")
            .accessibilityValue("\(timeoutMs) milliseconds")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Fast Typing Toggle

    private var fastTypingToggle: some View {
        Toggle(isOn: $protectFastTyping) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Protect fast typing")
                    .font(.subheadline.weight(.medium))
                Text("Ignore holds when another key was pressed recently")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("autoshift-protect-fast-typing")
        .accessibilityLabel("Protect fast typing")
    }

    // MARK: - Actions

    private func toggleKey(_ key: String) {
        if enabledKeys.contains(key) {
            enabledKeys.remove(key)
        } else {
            enabledKeys.insert(key)
        }
    }

    private func emitConfig() {
        var updated = config
        updated.enabledKeys = enabledKeys
        updated.timeoutMs = timeoutMs
        updated.protectFastTyping = protectFastTyping
        onConfigChanged(updated)
    }

    // MARK: - Key Event Monitor

    private func installEventMonitor() {
        #if os(macOS)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if let kanataKey = Self.keyCodeToKanataKey[event.keyCode] {
                    flashKey(kanataKey)
                }
                return event
            }
        #endif
    }

    private func removeEventMonitor() {
        #if os(macOS)
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        #endif
    }

    private func flashKey(_ key: String) {
        withAnimation(.easeOut(duration: 0.1)) {
            flashedKey = key
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.15)) {
                if flashedKey == key {
                    flashedKey = nil
                }
            }
        }
    }
}
