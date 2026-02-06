import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// MARK: - Single Key Picker Content

struct SingleKeyPickerContent: View {
    let collection: RuleCollection
    let onSelectOutput: (String) -> Void

    @State private var selectedOutput: String
    @State private var showingCustomPopover = false
    @State private var customKeyInput = ""

    private var config: SingleKeyPickerConfig? {
        collection.configuration.singleKeyPickerConfig
    }

    init(collection: RuleCollection, onSelectOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectOutput = onSelectOutput
        let cfg = collection.configuration.singleKeyPickerConfig
        _selectedOutput = State(initialValue: cfg?.selectedOutput ?? cfg?.presetOptions.first?.output ?? "")
    }

    private var selectedPreset: SingleKeyPreset? {
        config?.presetOptions.first { $0.output == selectedOutput }
    }

    private var isCustomSelection: Bool {
        guard let cfg = config else { return false }
        return !cfg.presetOptions.contains { $0.output == selectedOutput }
            && !selectedOutput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Segmented picker
            HStack(spacing: 0) {
                ForEach(config?.presetOptions ?? []) { preset in
                    PickerSegment(
                        label: preset.label,
                        isSelected: selectedOutput == preset.output,
                        isFirst: preset.id == config?.presetOptions.first?.id,
                        isLast: preset.id == config?.presetOptions.last?.id && !isCustomSelection
                    ) {
                        selectedOutput = preset.output
                        onSelectOutput(preset.output)
                    }
                }

                // Custom segment with popover
                PickerSegment(
                    label: "Custom",
                    isSelected: isCustomSelection,
                    isFirst: false,
                    isLast: true
                ) {
                    customKeyInput = isCustomSelection ? selectedOutput : ""
                    showingCustomPopover = true
                }
                .popover(isPresented: $showingCustomPopover, arrowEdge: .bottom) {
                    CustomKeyPopover(
                        keyInput: $customKeyInput,
                        onConfirm: {
                            let normalized = CustomRuleValidator.normalizeKey(customKeyInput)
                            if CustomRuleValidator.isValidKey(normalized) {
                                selectedOutput = normalized
                                onSelectOutput(normalized)
                            }
                            showingCustomPopover = false
                        },
                        onCancel: {
                            showingCustomPopover = false
                        }
                    )
                }
            }
            .padding(.horizontal, 4)

            // Description that updates based on selection
            if let preset = selectedPreset {
                Text(preset.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                    .id(preset.output)
            } else if isCustomSelection {
                HStack {
                    Text("Custom key: \(selectedOutput)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit") {
                        customKeyInput = selectedOutput
                        showingCustomPopover = true
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    .accessibilityIdentifier("rules-summary-custom-key-edit-button")
                    .accessibilityLabel("Edit custom key")
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedOutput)
    }
}

// MARK: - Layer Preset Picker Content

struct LayerPresetPickerContent: View {
    let collection: RuleCollection
    let onSelectPreset: (String) -> Void

    @State private var selectedPresetId: String
    @State private var hasInteracted = false // Track if user has clicked a preset
    @Namespace private var symbolAnimation

    private var config: LayerPresetPickerConfig? {
        collection.configuration.layerPresetPickerConfig
    }

    init(collection: RuleCollection, onSelectPreset: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectPreset = onSelectPreset
        let cfg = collection.configuration.layerPresetPickerConfig
        _selectedPresetId = State(initialValue: cfg?.selectedPresetId ?? cfg?.presets.first?.id ?? "")
    }

    private var selectedPreset: LayerPreset? {
        config?.presets.first { $0.id == selectedPresetId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mini-preview cards for each preset
            HStack(spacing: 12) {
                ForEach(config?.presets ?? []) { preset in
                    MiniPresetCard(
                        preset: preset,
                        isSelected: selectedPresetId == preset.id
                    ) {
                        hasInteracted = true // Mark that user clicked
                        selectedPresetId = preset.id
                        onSelectPreset(preset.id)
                    }
                }
            }

            // Full keyboard grid for selected preset
            if let preset = selectedPreset {
                VStack(alignment: .leading, spacing: 8) {
                    Text(preset.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    AnimatedKeyboardTransformGrid(
                        mappings: preset.mappings,
                        namespace: symbolAnimation,
                        enableAnimation: hasInteracted
                    )
                }
            }
        }
        .padding(.vertical, 8)
        // Only animate after user has interacted - prevents animation on view appear/re-render
        .animation(hasInteracted ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: selectedPresetId)
    }
}

// MARK: - Mini Preset Card

struct MiniPresetCard: View {
    let preset: LayerPreset
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    /// Define keyboard rows for mini preview (home row focus)
    private static let previewRows: [[String]] = [
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]
    ]

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Label
                HStack {
                    if let icon = preset.icon {
                        Image(systemName: icon)
                            .font(.caption)
                    }
                    Text(preset.label)
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(isSelected ? .primary : .secondary)

                // Mini keyboard preview (home row only)
                HStack(spacing: 2) {
                    ForEach(Self.previewRows[0], id: \.self) { key in
                        let output = preset.mappings.first { $0.input.lowercased() == key }?.description ?? key
                        MiniKeycap(label: output)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.4 : 0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-preset-button-\(preset.id)")
        .accessibilityLabel("Select preset \(preset.label)")
        .onHover { isHovered = $0 }
    }
}

// MARK: - Mini Keycap (for preset previews)

struct MiniKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Tap-Hold Picker Content

struct TapHoldPickerContent: View {
    let collection: RuleCollection
    let onSelectTapOutput: (String) -> Void
    let onSelectHoldOutput: (String) -> Void

    @State private var selectedTap: String
    @State private var selectedHold: String
    @State private var showingCustomTapPopover = false
    @State private var showingCustomHoldPopover = false
    @State private var customTapInput = ""
    @State private var customHoldInput = ""

    private var config: TapHoldPickerConfig? {
        collection.configuration.tapHoldPickerConfig
    }

    init(collection: RuleCollection, onSelectTapOutput: @escaping (String) -> Void, onSelectHoldOutput: @escaping (String) -> Void) {
        self.collection = collection
        self.onSelectTapOutput = onSelectTapOutput
        self.onSelectHoldOutput = onSelectHoldOutput
        let cfg = collection.configuration.tapHoldPickerConfig
        let tapOptions = cfg?.tapOptions ?? []
        let holdOptions = cfg?.holdOptions ?? []
        _selectedTap = State(initialValue: cfg?.selectedTapOutput ?? tapOptions.first?.output ?? "hyper")
        _selectedHold = State(initialValue: cfg?.selectedHoldOutput ?? holdOptions.first?.output ?? "hyper")
    }

    private var tapOptions: [SingleKeyPreset] {
        config?.tapOptions ?? []
    }

    private var holdOptions: [SingleKeyPreset] {
        config?.holdOptions ?? []
    }

    private var selectedTapPreset: SingleKeyPreset? {
        tapOptions.first { $0.output == selectedTap }
    }

    private var selectedHoldPreset: SingleKeyPreset? {
        holdOptions.first { $0.output == selectedHold }
    }

    private var isCustomTapSelection: Bool {
        !tapOptions.contains { $0.output == selectedTap } && !selectedTap.isEmpty
    }

    private var isCustomHoldSelection: Bool {
        !holdOptions.contains { $0.output == selectedHold } && !selectedHold.isEmpty
    }

    /// Get display label for a custom tap selection (handles system actions)
    private var customTapDisplayLabel: String {
        displayLabelFor(selectedTap)
    }

    /// Get display label for a custom hold selection (handles system actions)
    private var customHoldDisplayLabel: String {
        displayLabelFor(selectedHold)
    }

    /// Get display label for a custom value (system action or key)
    private func displayLabelFor(_ value: String) -> String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.name
        }
        return value
    }

    /// Get SF Symbol for a custom value if it's a system action
    private func sfSymbolFor(_ value: String) -> String? {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: value),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.sfSymbol
        }
        return nil
    }

    /// Check if caps lock is "lost" (not available via tap or hold)
    private var capsLockLost: Bool {
        selectedTap != "caps" && selectedHold != "caps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // TAP section
            VStack(alignment: .leading, spacing: 8) {
                Text("TAP")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 0) {
                    ForEach(tapOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedTap == preset.output,
                            isFirst: preset.id == tapOptions.first?.id,
                            isLast: preset.id == tapOptions.last?.id && !isCustomTapSelection
                        ) {
                            selectedTap = preset.output
                            onSelectTapOutput(preset.output)
                        }
                    }

                    // Show custom selection as a segment when one is selected
                    if isCustomTapSelection {
                        CustomValueSegment(
                            label: customTapDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedTap),
                            isSelected: true,
                            isLast: false
                        ) {
                            // Already selected, do nothing
                        }
                    }

                    PickerSegment(
                        label: isCustomTapSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: true
                    ) {
                        customTapInput = isCustomTapSelection ? selectedTap : ""
                        showingCustomTapPopover = true
                    }
                    .popover(isPresented: $showingCustomTapPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customTapInput,
                            onConfirm: {
                                // For system action outputs, use the value directly
                                if CustomRuleValidator.isSystemActionOutput(customTapInput) {
                                    selectedTap = customTapInput
                                    onSelectTapOutput(customTapInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customTapInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedTap = normalized
                                        onSelectTapOutput(normalized)
                                    }
                                }
                                showingCustomTapPopover = false
                            },
                            onCancel: {
                                showingCustomTapPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedTapPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // HOLD section
            VStack(alignment: .leading, spacing: 8) {
                Text("HOLD")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 0) {
                    ForEach(holdOptions) { preset in
                        PickerSegment(
                            label: preset.label,
                            isSelected: selectedHold == preset.output,
                            isFirst: preset.id == holdOptions.first?.id,
                            isLast: preset.id == holdOptions.last?.id && !isCustomHoldSelection
                        ) {
                            selectedHold = preset.output
                            onSelectHoldOutput(preset.output)
                        }
                    }

                    // Show custom selection as a segment when one is selected
                    if isCustomHoldSelection {
                        CustomValueSegment(
                            label: customHoldDisplayLabel,
                            sfSymbol: sfSymbolFor(selectedHold),
                            isSelected: true,
                            isLast: false
                        ) {
                            // Already selected, do nothing
                        }
                    }

                    PickerSegment(
                        label: isCustomHoldSelection ? "Edit" : "Custom",
                        isSelected: false,
                        isFirst: false,
                        isLast: true
                    ) {
                        customHoldInput = isCustomHoldSelection ? selectedHold : ""
                        showingCustomHoldPopover = true
                    }
                    .popover(isPresented: $showingCustomHoldPopover, arrowEdge: .bottom) {
                        CustomKeyPopover(
                            keyInput: $customHoldInput,
                            onConfirm: {
                                // For system action outputs, use the value directly
                                if CustomRuleValidator.isSystemActionOutput(customHoldInput) {
                                    selectedHold = customHoldInput
                                    onSelectHoldOutput(customHoldInput)
                                } else {
                                    let normalized = CustomRuleValidator.normalizeKey(customHoldInput)
                                    if CustomRuleValidator.isValidKey(normalized) {
                                        selectedHold = normalized
                                        onSelectHoldOutput(normalized)
                                    }
                                }
                                showingCustomHoldPopover = false
                            },
                            onCancel: {
                                showingCustomHoldPopover = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)

                if let preset = selectedHoldPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }

            // Suggestion: Lost Caps Lock
            if capsLockLost {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("Lost Caps Lock? Enable \"Backup Caps Lock\" to get it back via Both Shifts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.1))
                )
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.15), value: selectedTap)
        .animation(.easeInOut(duration: 0.15), value: selectedHold)
    }
}

// MARK: - Custom Key Popover

struct CustomKeyPopover: View {
    @Binding var keyInput: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showingSuggestions = true
    @FocusState private var isInputFocused: Bool

    private var structuredSuggestions: [CustomRuleValidator.Suggestion] {
        Array(CustomRuleValidator.structuredSuggestions(for: keyInput).prefix(12))
    }

    private var isValidKey: Bool {
        // For system action outputs, they're already in the correct format
        if CustomRuleValidator.isSystemActionOutput(keyInput) {
            return true
        }
        let normalized = CustomRuleValidator.normalizeKey(keyInput)
        return CustomRuleValidator.isValidKey(normalized)
    }

    /// Display label for the current input (shows friendly name for system actions)
    private var displayLabel: String {
        if let actionId = CustomRuleValidator.extractSystemActionId(from: keyInput),
           let action = CustomRuleValidator.systemAction(for: actionId) {
            return action.name
        }
        return keyInput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Custom Key or Action")
                .font(.headline)

            // Key input with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                TextField("Key name or action (e.g., tab, Mission Control)", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        if isValidKey {
                            onConfirm()
                        }
                    }
                    .onChange(of: keyInput) { _, _ in
                        showingSuggestions = true
                    }

                // Autocomplete suggestions with icons for system actions
                if showingSuggestions, !structuredSuggestions.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(structuredSuggestions.enumerated()), id: \.offset) { _, suggestion in
                                Button {
                                    keyInput = suggestion.value
                                    showingSuggestions = false
                                } label: {
                                    HStack(spacing: 6) {
                                        if let symbol = suggestion.sfSymbol {
                                            Image(systemName: symbol)
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                                .frame(width: 16)
                                        }
                                        Text(suggestion.displayLabel)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.08))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                // Show friendly name when system action is selected
                if CustomRuleValidator.isSystemActionOutput(keyInput) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Action: \(displayLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                // Validation feedback for invalid input
                else if !keyInput.isEmpty, !isValidKey {
                    Text("Unknown key name")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("rules-summary-custom-key-cancel-button")
                .accessibilityLabel("Cancel")

                Spacer()

                Button("OK") {
                    onConfirm()
                }
                .keyboardShortcut(.return)
                .disabled(!isValidKey)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rules-summary-custom-key-ok-button")
                .accessibilityLabel("OK")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            isInputFocused = true
        }
    }
}

struct PickerSegment: View {
    let label: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 70)
                .background(
                    RoundedRectangle(cornerRadius: isFirst ? 6 : (isLast ? 6 : 0))
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                        .clipShape(SegmentShape(isFirst: isFirst, isLast: isLast))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-segment-button-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

struct SegmentShape: Shape {
    let isFirst: Bool
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 6
        var path = Path()

        if isFirst, isLast {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        } else if isFirst {
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
        } else if isLast {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.addRect(rect)
        }

        return path
    }
}

// MARK: - Custom Value Segment

/// A segment that displays a custom value (with optional icon for system actions)
struct CustomValueSegment: View {
    let label: String
    let sfSymbol: String?
    let isSelected: Bool
    let isLast: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 60)
            .background(
                RoundedRectangle(cornerRadius: isLast ? 6 : 0)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                    .clipShape(SegmentShape(isFirst: false, isLast: isLast))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules-summary-custom-segment-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}
