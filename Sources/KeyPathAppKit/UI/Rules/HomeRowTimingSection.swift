import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Reusable timing section for Home Row Mods — flat, macOS-native layout.
///
/// Layout:
/// - Header: "Timing" + raw values toggle + reset to defaults
/// - Typing Feel: slider OR raw text fields (mutually exclusive)
/// - Quick tap checkbox + inline slider when checked
/// - Per-finger sensitivity checkbox + sliders when checked
struct HomeRowTimingSection: View {
    @Binding var config: HomeRowModsConfig
    let onConfigChanged: (HomeRowModsConfig) -> Void

    @State private var sliderDebounceTask: Task<Void, Never>?
    @State private var showPerFinger: Bool = false

    private var feelSliderPosition: Double? {
        TypingFeelMapping.sliderPosition(tapWindow: config.timing.tapWindow, holdDelay: config.timing.holdDelay)
    }

    private var effectiveSliderPosition: Double {
        feelSliderPosition ?? 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header

            HStack(spacing: 8) {
                Text("Timing")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if config.showExpertTiming {
                            // Turning OFF raw mode — snap values to nearest curve position
                            let snapped = TypingFeelMapping.snapToCurve(
                                tapWindow: config.timing.tapWindow,
                                holdDelay: config.timing.holdDelay
                            )
                            config.timing.tapWindow = snapped.tapWindow
                            config.timing.holdDelay = snapped.holdDelay
                            config.showExpertTiming = false
                        } else {
                            config.showExpertTiming = true
                        }
                    }
                    updateConfig()
                } label: {
                    Label("Raw values", systemImage: "number")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    config.showExpertTiming
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .foregroundStyle(config.showExpertTiming ? Color.accentColor : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            config.showExpertTiming ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                            lineWidth: 0.5
                        )
                )
                .accessibilityIdentifier("home-row-mods-raw-values-toggle")
                .accessibilityLabel("Raw values mode")
                .accessibilityAddTraits(config.showExpertTiming ? .isSelected : [])

                if hasNonDefaultTiming {
                    Button {
                        config.timing = .default
                        config.showExpertTiming = false
                        showPerFinger = false
                        updateConfig()
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-row-mods-timing-reset-defaults")
                }
            }

            // MARK: - Typing Feel (slider or raw fields)

            VStack(alignment: .leading, spacing: 4) {
                Text("Typing Feel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if config.showExpertTiming {
                    // Raw text fields replace the slider
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tap window")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: Binding(
                                    get: { config.timing.tapWindow },
                                    set: { newValue in
                                        config.timing.tapWindow = newValue
                                        updateConfig()
                                    }
                                ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .accessibilityIdentifier("home-row-mods-tap-window-field")
                                Text("ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hold delay")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: Binding(
                                    get: { config.timing.holdDelay },
                                    set: { newValue in
                                        config.timing.holdDelay = newValue
                                        updateConfig()
                                    }
                                ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .accessibilityIdentifier("home-row-mods-hold-delay-field")
                                Text("ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Text("Values are set manually. Disable Raw Values to use the slider.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    // Feel slider
                    HStack(spacing: 8) {
                        Text("More Letters")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { effectiveSliderPosition },
                                set: { newPosition in
                                    let values = TypingFeelMapping.timingValues(forSliderPosition: newPosition)
                                    config.timing.tapWindow = values.tapWindow
                                    config.timing.holdDelay = values.holdDelay
                                    debouncedUpdateConfig()
                                }
                            ),
                            in: 0 ... 1,
                            step: 0.05
                        )
                        .accessibilityIdentifier("home-row-mods-feel-slider")
                        .accessibilityLabel("Typing feel")

                        Text("More Modifiers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)
                    }

                    Text("\(TypingFeelMapping.helperText(forSliderPosition: effectiveSliderPosition)) (tap: \(config.timing.tapWindow)ms, hold: \(config.timing.holdDelay)ms)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 88)
                }
            }

            // MARK: - Quick Tap

            Toggle("Favor tap when another key is pressed", isOn: Binding(
                get: { config.timing.quickTapEnabled },
                set: { newValue in
                    config.timing.quickTapEnabled = newValue
                    updateConfig()
                }
            ))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("home-row-mods-quick-tap-toggle")
            .accessibilityLabel("Favor tap when another key is pressed")

            if config.timing.quickTapEnabled {
                HStack(spacing: 8) {
                    Text("Strict")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)

                    Slider(value: Binding(
                        get: { Double(config.timing.quickTapTermMs) },
                        set: { newValue in
                            config.timing.quickTapTermMs = Int(newValue)
                            debouncedUpdateConfig()
                        }
                    ), in: 0 ... 80, step: 5)
                        .accessibilityIdentifier("home-row-mods-quick-tap-term-slider")
                        .accessibilityLabel("Quick tap extra time")

                    Text("Forgiving")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                }

                Text(quickTapHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 88)
            }

            // MARK: - Per-Finger Sensitivity

            Toggle("Adjust per-finger sensitivity", isOn: $showPerFinger)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("home-row-mods-per-finger-toggle")
                .accessibilityLabel("Adjust per-finger sensitivity")

            if showPerFinger {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add extra delay for slower fingers to prevent accidental holds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(TypingFeelMapping.FingerGroup.allCases, id: \.self) { finger in
                        fingerSliderRow(finger: finger)
                    }

                    if config.showExpertTiming, hasAnyPerKeyOffsets {
                        Divider()
                            .padding(.vertical, 2)
                        perKeyOffsetFields
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: config.timing.quickTapEnabled)
        .animation(.easeInOut(duration: 0.2), value: showPerFinger)
        .animation(.easeInOut(duration: 0.15), value: config.showExpertTiming)
        .onAppear {
            showPerFinger = hasAnyPerKeyOffsets
        }
    }

    // MARK: - Finger Slider Row

    private static let fingerEmoji: [TypingFeelMapping.FingerGroup: String] = [
        .pinky: "\u{1F91E}", // crossed fingers (smallest finger gesture)
        .ring: "\u{1F48D}", // ring
        .middle: "\u{1F595}", // middle finger
        .index: "\u{261D}\u{FE0F}", // index pointing up
    ]

    private func fingerSliderRow(finger: TypingFeelMapping.FingerGroup) -> some View {
        let sensitivity = TypingFeelMapping.fingerSensitivity(for: finger, in: config.timing)
        let isCustom = sensitivity == nil
        let displayValue = sensitivity ?? 0
        let emoji = Self.fingerEmoji[finger] ?? ""

        return HStack(spacing: 8) {
            Text("\(emoji) \(finger.displayName)")
                .font(.caption)
                .frame(width: 80, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { Double(displayValue) },
                    set: { newValue in
                        TypingFeelMapping.applyFingerSensitivity(Int(newValue), for: finger, to: &config.timing)
                        debouncedUpdateConfig()
                    }
                ),
                in: 0 ... 80,
                step: 5
            )
            .accessibilityIdentifier("home-row-mods-finger-\(finger.rawValue)-slider")
            .accessibilityLabel("\(finger.displayName) finger sensitivity")

            if isCustom {
                Text("Mixed")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text(displayValue > 0 ? "+\(displayValue)ms" : "0ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }

    // MARK: - Per-Key Offset Fields (Expert, shown inside per-finger section)

    private var perKeyOffsetFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-key tap offsets (ms)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("0", value: Binding(
                                get: { config.timing.tapOffsets[key] ?? 0 },
                                set: { newValue in
                                    if newValue == 0 {
                                        config.timing.tapOffsets.removeValue(forKey: key)
                                    } else {
                                        config.timing.tapOffsets[key] = newValue
                                    }
                                    updateConfig()
                                }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                    Spacer()
                }
            }

            Divider()

            Text("Per-key hold offsets (ms)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(chunks(of: HomeRowModsConfig.allKeys, size: 4), id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("0", value: Binding(
                                get: { config.timing.holdOffsets[key] ?? 0 },
                                set: { newValue in
                                    if newValue == 0 {
                                        config.timing.holdOffsets.removeValue(forKey: key)
                                    } else {
                                        config.timing.holdOffsets[key] = newValue
                                    }
                                    updateConfig()
                                }
                            ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private var quickTapHelperText: String {
        if config.timing.quickTapTermMs == 0 {
            return "No extra time added. Uses base tap window only."
        }
        return "Adds \(config.timing.quickTapTermMs)ms to the tap window during key rolls."
    }

    private var hasNonDefaultTiming: Bool {
        config.timing != .default || config.showExpertTiming
    }

    private var hasAnyPerKeyOffsets: Bool {
        !config.timing.tapOffsets.isEmpty || !config.timing.holdOffsets.isEmpty
    }

    private func updateConfig() {
        onConfigChanged(config)
    }

    private func debouncedUpdateConfig() {
        sliderDebounceTask?.cancel()
        sliderDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            updateConfig()
        }
    }
}

// MARK: - Private Helpers

private func chunks<T>(of array: [T], size: Int) -> [[T]] {
    stride(from: 0, to: array.count, by: size).map { start in
        Array(array[start ..< min(start + size, array.count)])
    }
}
