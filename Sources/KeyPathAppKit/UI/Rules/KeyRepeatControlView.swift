import KeyPathRulesCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct KeyRepeatControlView: View {
    let config: KeyRepeatControlConfig
    let onConfigChanged: (KeyRepeatControlConfig) -> Void

    @State private var globalDelayMs: Int
    @State private var globalIntervalMs: Int
    @State private var arrowEnabled: Bool
    @State private var arrowDelayMs: Int
    @State private var arrowIntervalMs: Int
    @State private var deleteEnabled: Bool
    @State private var deleteDelayMs: Int
    @State private var deleteIntervalMs: Int
    @State private var fwdDeleteEnabled: Bool
    @State private var fwdDeleteDelayMs: Int
    @State private var fwdDeleteIntervalMs: Int
    @State private var customOverrides: [KeyRepeatOverride]
    @State private var showingAddCustom = false
    @State private var newKeyText = ""
    @State private var selectedPreset: KeyRepeatControlConfig.Preset?
    @State private var testText = "Hold an arrow key or delete here to feel the speed. Then try holding a letter to compare."
    @State private var showingSettings = false

    private static let arrowKeys: Set<String> = ["left", "right", "up", "down"]
    private static let builtInKeys: Set<String> = ["left", "right", "up", "down", "bspc", "del"]

    init(config: KeyRepeatControlConfig, onConfigChanged: @escaping (KeyRepeatControlConfig) -> Void) {
        self.config = config
        self.onConfigChanged = onConfigChanged
        _globalDelayMs = State(initialValue: config.globalDelayMs)
        _globalIntervalMs = State(initialValue: config.globalIntervalMs)
        let arrows = config.perKeyOverrides.filter { Self.arrowKeys.contains($0.key) }
        _arrowEnabled = State(initialValue: !arrows.isEmpty)
        _arrowDelayMs = State(initialValue: arrows.first?.delayMs ?? 150)
        _arrowIntervalMs = State(initialValue: arrows.first?.intervalMs ?? 20)
        let bspc = config.perKeyOverrides.first { $0.key == "bspc" }
        _deleteEnabled = State(initialValue: bspc != nil)
        _deleteDelayMs = State(initialValue: bspc?.delayMs ?? 210)
        _deleteIntervalMs = State(initialValue: bspc?.intervalMs ?? 20)
        let del = config.perKeyOverrides.first { $0.key == "del" }
        _fwdDeleteEnabled = State(initialValue: del != nil)
        _fwdDeleteDelayMs = State(initialValue: del?.delayMs ?? 210)
        _fwdDeleteIntervalMs = State(initialValue: del?.intervalMs ?? 20)
        let custom = config.perKeyOverrides.filter { !Self.builtInKeys.contains($0.key) }
        _customOverrides = State(initialValue: custom)
        _selectedPreset = State(initialValue: Self.matchPreset(config))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            presetCards

            HStack {
                Spacer()
                Button("Settings...") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("key-repeat-settings-button")
            }

            testArea
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPreset)
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 20) {
            VStack(spacing: 3) {
                heroKeycap("↑")
                HStack(spacing: 3) {
                    heroKeycap("←")
                    heroKeycap("↓")
                    heroKeycap("→")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(heroHeadline)
                    .font(.body.weight(.medium))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())

                Text(heroSubhead)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var heroHeadline: String {
        switch selectedPreset {
        case .balanced, .none:
            "Arrow keys and delete\nrepeat 3× faster."
        case .fastNavigation:
            "Arrow keys and delete\nrepeat 4× faster."
        case .careful:
            "Arrow keys and delete\nrepeat 2× faster."
        }
    }

    private var heroSubhead: String {
        switch selectedPreset {
        case .balanced, .none:
            "Regular keys stay steady.\nNo ghost characters under load."
        case .fastNavigation:
            "Everything is faster.\nBuilt for rapid code navigation."
        case .careful:
            "Longer delays prevent accidents.\nGreat for new keyboard layouts."
        }
    }

    private func heroKeycap(_ label: String) -> some View {
        Text(label)
            .font(.title2.weight(.medium))
            .frame(width: 42, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
                    .shadow(color: Color.accentColor.opacity(0.1), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(Color.accentColor)
    }

    // MARK: - Preset Cards

    private var presetCards: some View {
        HStack(spacing: 8) {
            ForEach(KeyRepeatControlConfig.Preset.allCases) { preset in
                SettingsOptionCard(
                    icon: presetIcon(preset),
                    title: preset.label,
                    subtitle: preset.description,
                    isSelected: selectedPreset == preset
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { applyPreset(preset) }
                }
            }
        }
    }

    private func presetIcon(_ preset: KeyRepeatControlConfig.Preset) -> String {
        switch preset {
        case .balanced: "dial.medium"
        case .fastNavigation: "hare"
        case .careful: "tortoise"
        }
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fast Navigation Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { showingSettings = false }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("key-repeat-settings-done-button")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(
                        "Repeat start delay is how long you hold a key before it begins repeating. Repeat speed is how quickly it continues.",
                        bundle: #bundle
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    allKeysSection
                    arrowSection
                    HStack(alignment: .top, spacing: 12) {
                        deleteSection
                        fwdDeleteSection
                    }
                    if !customOverrides.isEmpty {
                        customKeysSection
                    }
                    addCustomButton
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .settingsBackground()
        .onChange(of: globalDelayMs) { _, _ in syncFromCustomize() }
        .onChange(of: globalIntervalMs) { _, _ in syncFromCustomize() }
        .onChange(of: arrowEnabled) { _, _ in syncFromCustomize() }
        .onChange(of: arrowDelayMs) { _, _ in syncFromCustomize() }
        .onChange(of: arrowIntervalMs) { _, _ in syncFromCustomize() }
        .onChange(of: deleteEnabled) { _, _ in syncFromCustomize() }
        .onChange(of: deleteDelayMs) { _, _ in syncFromCustomize() }
        .onChange(of: deleteIntervalMs) { _, _ in syncFromCustomize() }
        .onChange(of: fwdDeleteEnabled) { _, _ in syncFromCustomize() }
        .onChange(of: fwdDeleteDelayMs) { _, _ in syncFromCustomize() }
        .onChange(of: fwdDeleteIntervalMs) { _, _ in syncFromCustomize() }
        .onChange(of: customOverrides) { _, _ in syncFromCustomize() }
    }

    // MARK: - Settings Sections

    private var allKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All keys")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                KeyRepeatTimingSummary(
                    delayMs: globalDelayMs,
                    intervalMs: globalIntervalMs,
                    speedScale: KeyRepeatControlConfig.globalSpeedScale
                )
            }
            RepeatStartDelaySliderRow(
                delayMs: $globalDelayMs,
                range: 50 ... 2000,
                step: 10,
                accessibilityID: "key-repeat-slider-global-delay"
            )
            RepeatSpeedSliderRow(
                intervalMs: $globalIntervalMs,
                scale: KeyRepeatControlConfig.globalSpeedScale,
                accessibilityID: "key-repeat-slider-global-speed"
            )
        }
    }

    private var arrowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Arrow keys", isOn: $arrowEnabled)
                    .font(.subheadline.weight(.semibold))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("key-repeat-arrow-toggle")
                Spacer()
                if arrowEnabled {
                    KeyRepeatTimingSummary(
                        delayMs: arrowDelayMs,
                        intervalMs: arrowIntervalMs,
                        speedScale: KeyRepeatControlConfig.overrideSpeedScale
                    )
                }
            }
            if arrowEnabled {
                RepeatStartDelaySliderRow(
                    delayMs: $arrowDelayMs,
                    range: 50 ... 1000,
                    step: 10,
                    accessibilityID: "key-repeat-slider-arrow-delay"
                )
                RepeatSpeedSliderRow(
                    intervalMs: $arrowIntervalMs,
                    scale: KeyRepeatControlConfig.overrideSpeedScale,
                    accessibilityID: "key-repeat-slider-arrow-speed"
                )
            }
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Delete ⌫", isOn: $deleteEnabled)
                .font(.subheadline.weight(.semibold))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("key-repeat-delete-toggle")
            if deleteEnabled {
                RepeatStartDelaySliderRow(
                    delayMs: $deleteDelayMs,
                    range: 50 ... 1000,
                    step: 10,
                    accessibilityID: "key-repeat-slider-delete-delay"
                )
                RepeatSpeedSliderRow(
                    intervalMs: $deleteIntervalMs,
                    scale: KeyRepeatControlConfig.overrideSpeedScale,
                    accessibilityID: "key-repeat-slider-delete-speed"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fwdDeleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Fwd Delete ⌦", isOn: $fwdDeleteEnabled)
                .font(.subheadline.weight(.semibold))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("key-repeat-fwd-delete-toggle")
            if fwdDeleteEnabled {
                RepeatStartDelaySliderRow(
                    delayMs: $fwdDeleteDelayMs,
                    range: 50 ... 1000,
                    step: 10,
                    accessibilityID: "key-repeat-slider-fwd-delete-delay"
                )
                RepeatSpeedSliderRow(
                    intervalMs: $fwdDeleteIntervalMs,
                    scale: KeyRepeatControlConfig.overrideSpeedScale,
                    accessibilityID: "key-repeat-slider-fwd-delete-speed"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Custom Keys

    private var customKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(customOverrides.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.key)
                        .font(.subheadline.weight(.semibold).monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.1)))
                        .foregroundStyle(Color.accentColor)

                    VStack(spacing: 4) {
                        RepeatStartDelaySliderRow(
                            delayMs: Binding(
                                get: {
                                    customOverrides.indices.contains(index)
                                        ? customOverrides[index].delayMs
                                        : entry.delayMs
                                },
                                set: {
                                    if customOverrides.indices.contains(index) {
                                        customOverrides[index].delayMs = $0
                                    }
                                }
                            ),
                            range: 50 ... 2000,
                            step: 10,
                            accessibilityID: "key-repeat-slider-custom-\(entry.key)-delay"
                        )
                        RepeatSpeedSliderRow(
                            intervalMs: Binding(
                                get: {
                                    customOverrides.indices.contains(index)
                                        ? customOverrides[index].intervalMs
                                        : entry.intervalMs
                                },
                                set: {
                                    if customOverrides.indices.contains(index) {
                                        customOverrides[index].intervalMs = $0
                                    }
                                }
                            ),
                            scale: KeyRepeatControlConfig.globalSpeedScale,
                            accessibilityID: "key-repeat-slider-custom-\(entry.key)-speed"
                        )
                    }

                    Button { customOverrides.remove(at: index) } label: {
                        Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("key-repeat-remove-custom-\(entry.key)")
                        .accessibilityLabel("Remove custom repeat for \(entry.key)")
                }
            }
        }
    }

    private var addCustomButton: some View {
        Group {
            if showingAddCustom {
                HStack(spacing: 8) {
                    TextField("Key name (e.g. a, spc)", text: $newKeyText)
                        .textFieldStyle(.roundedBorder).font(.subheadline).frame(maxWidth: 160)
                        .onSubmit { commitCustomKey() }
                        .accessibilityIdentifier("key-repeat-custom-key-field")
                    Button("Add") { commitCustomKey() }
                        .disabled(newKeyText.trimmingCharacters(in: .whitespaces).isEmpty).controlSize(.small)
                        .accessibilityIdentifier("key-repeat-add-custom-button")
                    Button("Cancel") { showingAddCustom = false; newKeyText = "" }.controlSize(.small)
                        .accessibilityIdentifier("key-repeat-cancel-custom-button")
                }
            } else {
                Button { showingAddCustom = true } label: {
                    Label("Add custom key", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("key-repeat-add-custom-key-button")
            }
        }
    }

    private func commitCustomKey() {
        let key = newKeyText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, !Self.builtInKeys.contains(key),
              !customOverrides.contains(where: { $0.key == key }) else { return }
        customOverrides.append(KeyRepeatOverride(key: key, delayMs: globalDelayMs, intervalMs: globalIntervalMs))
        newKeyText = ""; showingAddCustom = false
    }

    // MARK: - Test Area

    private var testArea: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Test area")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tertiary)

            TextEditor(text: $testText)
                .font(.callout)
                .frame(height: 56)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                .accessibilityIdentifier("key-repeat-test-area")
        }
    }

    // MARK: - State

    private func applyPreset(_ preset: KeyRepeatControlConfig.Preset) {
        let p = preset.config
        selectedPreset = preset
        globalDelayMs = p.globalDelayMs; globalIntervalMs = p.globalIntervalMs
        let arrows = p.perKeyOverrides.filter { Self.arrowKeys.contains($0.key) }
        arrowEnabled = !arrows.isEmpty
        if let a = arrows.first { arrowDelayMs = a.delayMs; arrowIntervalMs = a.intervalMs }
        let bspc = p.perKeyOverrides.first { $0.key == "bspc" }
        deleteEnabled = bspc != nil
        if let b = bspc { deleteDelayMs = b.delayMs; deleteIntervalMs = b.intervalMs }
        let del = p.perKeyOverrides.first { $0.key == "del" }
        fwdDeleteEnabled = del != nil
        if let d = del { fwdDeleteDelayMs = d.delayMs; fwdDeleteIntervalMs = d.intervalMs }
        customOverrides = p.perKeyOverrides.filter { !Self.builtInKeys.contains($0.key) }
        emitConfig()
    }

    private func syncFromCustomize() {
        selectedPreset = Self.matchPreset(buildConfig())
        emitConfig()
    }

    private func emitConfig() {
        onConfigChanged(buildConfig())
    }

    private func buildConfig() -> KeyRepeatControlConfig {
        var overrides: [KeyRepeatOverride] = []
        if arrowEnabled {
            for k in ["left", "right", "up", "down"] {
                overrides.append(KeyRepeatOverride(key: k, delayMs: arrowDelayMs, intervalMs: arrowIntervalMs))
            }
        }
        if deleteEnabled { overrides.append(KeyRepeatOverride(key: "bspc", delayMs: deleteDelayMs, intervalMs: deleteIntervalMs)) }
        if fwdDeleteEnabled { overrides.append(KeyRepeatOverride(key: "del", delayMs: fwdDeleteDelayMs, intervalMs: fwdDeleteIntervalMs)) }
        overrides.append(contentsOf: customOverrides)
        return KeyRepeatControlConfig(isEnabled: config.isEnabled, globalDelayMs: globalDelayMs,
                                      globalIntervalMs: globalIntervalMs, perKeyOverrides: overrides)
    }

    private static func matchPreset(_ config: KeyRepeatControlConfig) -> KeyRepeatControlConfig.Preset? {
        KeyRepeatControlConfig.Preset.allCases.first { $0.config == config }
    }
}

private struct KeyRepeatTimingSummary: View {
    let delayMs: Int
    let intervalMs: Int
    let speedScale: KeyRepeatSpeedScale

    private var repeatsPerSecond: Double {
        speedScale.repeatsPerSecond(forIntervalMs: intervalMs)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(
                "\(repeatsPerSecond, format: repeatSpeedFormat(repeatsPerSecond)) repeats/sec",
                bundle: #bundle,
                comment: "Primary summary of a keyboard key's automatic repeat speed."
            )
            .font(.caption.monospaced().weight(.medium))

            Text(
                "\(delayMs) ms start · \(intervalMs) ms interval",
                bundle: #bundle,
                comment: "Secondary technical summary: repeat start delay followed by the interval between repeats."
            )
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
    }
}

private struct RepeatStartDelaySliderRow: View {
    @Binding var delayMs: Int
    let range: ClosedRange<Int>
    let step: Int
    let accessibilityID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    "Repeat start delay",
                    bundle: #bundle,
                    comment: "Label for how long a key must be held before automatic repetition begins."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Text(
                    "\(delayMs) ms",
                    bundle: #bundle,
                    comment: "Current keyboard repeat start delay in milliseconds."
                )
                .font(.caption.monospaced().weight(.medium))
            }

            Slider(
                value: $delayMs.snappedDouble(step: step),
                in: Double(range.lowerBound) ... Double(range.upperBound)
            )
            .controlSize(.small)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(Text("Repeat start delay", bundle: #bundle))
            .accessibilityValue(Text("\(delayMs) milliseconds", bundle: #bundle))

            HStack {
                Text("Starts sooner", bundle: #bundle)
                Spacer()
                Text("Starts later", bundle: #bundle)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct RepeatSpeedSliderRow: View {
    @Binding var intervalMs: Int
    let scale: KeyRepeatSpeedScale
    let accessibilityID: String

    private var repeatsPerSecond: Double {
        scale.repeatsPerSecond(forIntervalMs: intervalMs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    "Repeat speed",
                    bundle: #bundle,
                    comment: "Label for how quickly a held key repeats after its start delay."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(
                        "\(repeatsPerSecond, format: repeatSpeedFormat(repeatsPerSecond)) repeats/sec",
                        bundle: #bundle,
                        comment: "Primary value for a keyboard key's automatic repeat speed."
                    )
                    .font(.caption.monospaced().weight(.medium))
                    Text(
                        "\(intervalMs) ms interval",
                        bundle: #bundle,
                        comment: "Secondary technical value for the interval between keyboard repeats."
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                }
            }

            Slider(
                value: $intervalMs.repeatsPerSecond(scale: scale),
                in: scale.repeatsPerSecondRange
            )
            .controlSize(.small)
            .accessibilityIdentifier(accessibilityID)
            .accessibilityLabel(Text("Repeat speed", bundle: #bundle))
            .accessibilityValue(
                Text(
                    "\(repeatsPerSecond, format: repeatSpeedFormat(repeatsPerSecond)) repeats per second",
                    bundle: #bundle,
                    comment: "Accessibility value for a keyboard key's automatic repeat speed."
                )
            )
            .accessibilityHint(
                Text(
                    "The equivalent interval is \(intervalMs) milliseconds. Moving right repeats faster.",
                    bundle: #bundle
                )
            )

            HStack {
                Text("Slower", bundle: #bundle)
                Spacer()
                Text("Faster", bundle: #bundle)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

private extension Binding where Value == Int {
    func snappedDouble(step: Int) -> Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Int(($0 / Double(step)).rounded()) * step }
        )
    }

    func repeatsPerSecond(scale: KeyRepeatSpeedScale) -> Binding<Double> {
        Binding<Double>(
            get: { scale.repeatsPerSecond(forIntervalMs: wrappedValue) },
            set: { wrappedValue = scale.intervalMs(forRepeatsPerSecond: $0) }
        )
    }
}

private func repeatSpeedFormat(_ repeatsPerSecond: Double) -> FloatingPointFormatStyle<Double> {
    .number.precision(.fractionLength(repeatsPerSecond < 10 ? 1 : 0))
}
