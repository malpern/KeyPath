import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

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
            .font(.caption2.monospaced().weight(.medium))
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
