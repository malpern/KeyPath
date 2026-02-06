import AppKit
import SwiftUI

/// A compact card showing an app's key overrides for the drawer's App Rules tab.
/// Designed for ~240px drawer width with hover-to-reveal action buttons.
/// Visual style matches CustomRulesView in Settings.
struct AppRuleCard: View {
    let keymap: AppKeymap
    let onEdit: (AppKeyOverride) -> Void
    let onDelete: (AppKeyOverride) -> Void
    let onAddRule: () -> Void
    /// Callback when hovering a rule row - passes inputKey for keyboard highlighting
    var onRuleHover: ((String?) -> Void)?

    @State private var hoveredOverrideId: UUID?
    @State private var isCardHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // App name header with icon and add button
            HStack(spacing: 6) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: keymap.mapping.bundleIdentifier) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                }

                Text(keymap.mapping.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                // Add rule button (secondary color, light grey)
                Button(action: onAddRule) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isCardHovered ? 1.0 : 0.5)
                .accessibilityIdentifier("add-rule-\(keymap.mapping.bundleIdentifier)")
                .accessibilityLabel("Add rule for \(keymap.mapping.displayName)")
            }

            // Rules list with chip-style keys
            VStack(spacing: 6) {
                ForEach(keymap.overrides) { override in
                    ruleRow(override: override)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isCardHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-rule-card-\(keymap.mapping.bundleIdentifier)")
        .accessibilityLabel("App rules for \(keymap.mapping.displayName)")
    }

    // MARK: - Subviews

    @ViewBuilder
    private func ruleRow(override: AppKeyOverride) -> some View {
        let isHovered = hoveredOverrideId == override.id

        HStack(spacing: 8) {
            // Input key chip
            KeyChip(text: override.inputKey)

            // Arrow (matching Settings style)
            Image(systemName: "arrow.right")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            // Output key chip
            KeyChip(text: override.outputAction)

            Spacer(minLength: 4)

            // Action buttons (visible with varying opacity based on hover)
            HStack(spacing: 4) {
                Button { onEdit(override) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(isHovered ? 1 : 0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("edit-rule-\(override.id)")
                .accessibilityLabel("Edit rule \(override.inputKey) to \(override.outputAction)")

                Button { onDelete(override) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(isHovered ? 1 : 0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("delete-rule-\(override.id)")
                .accessibilityLabel("Delete rule \(override.inputKey) to \(override.outputAction)")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(isHovered ? 0.4 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredOverrideId = hovering ? override.id : nil
            }
            // Notify parent for keyboard highlighting
            onRuleHover?(hovering ? override.inputKey : nil)
        }
        .onTapGesture {
            onEdit(override)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app-rule-row-\(override.id)")
    }

    // MARK: - Helpers

    private var cardBackground: some ShapeStyle {
        Color(NSColor.controlBackgroundColor).opacity(isCardHovered ? 1.0 : 0.8)
    }
}

// MARK: - Key Chip (matching Settings KeycapStyle)

/// Key chip matching the KeyCapChip style from Settings CustomRules
private struct KeyChip: View {
    let text: String

    /// Text color matching overlay keycaps (light blue-white)
    private static let textColor = Color(red: 0.88, green: 0.93, blue: 1.0)
    /// Background color matching overlay keycaps (dark gray)
    private static let backgroundColor = Color(white: 0.12)

    var body: some View {
        Text(text.capitalized.replacingOccurrences(of: "_", with: " "))
            .font(.body.monospaced().weight(.semibold))
            .foregroundStyle(Self.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Self.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Global Rules Card (Everywhere)

/// A card showing global rules that apply everywhere (not app-specific).
/// Visual style matches AppRuleCard for consistency.
/// Only shown when global rules exist.
struct GlobalRulesCard: View {
    let rules: [CustomRule]
    let onEdit: (CustomRule) -> Void
    let onDelete: (CustomRule) -> Void
    let onAddRule: () -> Void
    /// Callback when hovering a rule row - passes inputKey for keyboard highlighting
    var onRuleHover: ((String?) -> Void)?

    @State private var hoveredRuleId: UUID?
    @State private var isCardHovered = false

    var body: some View {
        // Rules list only - no header, just the rules
        VStack(spacing: 6) {
            ForEach(rules) { rule in
                globalRuleRow(rule: rule)
            }
        }
        .padding(12)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isCardHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("global-rules-card")
        .accessibilityLabel("Global rules")
    }

    // MARK: - Subviews

    @ViewBuilder
    private func globalRuleRow(rule: CustomRule) -> some View {
        let isHovered = hoveredRuleId == rule.id

        ZStack(alignment: .trailing) {
            // Rule mapping content
            HStack(spacing: 8) {
                // Input key chip
                GlobalKeyChip(text: rule.input)

                // Arrow (matching Settings style)
                Image(systemName: "arrow.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)

                // Output - show layer chip for layer switches, otherwise regular key chip
                if let layerName = LayerInfo.extractLayerName(from: rule.output) {
                    DrawerLayerChip(layerName: layerName)
                } else {
                    GlobalKeyChip(text: rule.output)
                }

                Spacer(minLength: 0)
            }

            // Action buttons overlay - only visible on hover
            if isHovered {
                HStack(spacing: 2) {
                    Button { onEdit(rule) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("edit-global-rule-\(rule.id)")
                    .accessibilityLabel("Edit rule \(rule.input) to \(rule.output)")

                    Button { onDelete(rule) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("delete-global-rule-\(rule.id)")
                    .accessibilityLabel("Delete rule \(rule.input) to \(rule.output)")
                }
                .padding(.trailing, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(isHovered ? 0.4 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredRuleId = hovering ? rule.id : nil
            }
            // Notify parent for keyboard highlighting
            onRuleHover?(hovering ? rule.input : nil)
        }
        .onTapGesture {
            onEdit(rule)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("global-rule-row-\(rule.id)")
    }

    // MARK: - Helpers

    private var cardBackground: some ShapeStyle {
        Color(NSColor.controlBackgroundColor).opacity(isCardHovered ? 1.0 : 0.8)
    }
}

/// Key chip for global rules - same style as KeyChip in AppRuleCard
private struct GlobalKeyChip: View {
    let text: String

    /// Text color matching overlay keycaps (light blue-white)
    private static let textColor = Color(red: 0.88, green: 0.93, blue: 1.0)
    /// Background color matching overlay keycaps (dark gray)
    private static let backgroundColor = Color(white: 0.12)

    var body: some View {
        Text(text.capitalized.replacingOccurrences(of: "_", with: " "))
            .font(.body.monospaced().weight(.semibold))
            .foregroundStyle(Self.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Self.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

/// Layer switch chip for the drawer - shows layer icon and "X Layer" name
private struct DrawerLayerChip: View {
    let layerName: String

    /// The SF Symbol icon for this layer
    private var layerIcon: String {
        LayerInfo.iconName(for: layerName)
    }

    /// Human-readable display name with "Layer" suffix
    private var displayName: String {
        "\(LayerInfo.displayName(for: layerName)) Layer"
    }

    var body: some View {
        HStack(spacing: 5) {
            // Layer icon
            Image(systemName: layerIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)

            // Layer name (e.g., "Nav Layer")
            Text(displayName)
                .font(.body.weight(.semibold))
                .foregroundColor(Color(red: 0.85, green: 0.92, blue: 1.0))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("App Rule Card - Populated") {
        AppRuleCard(
            keymap: PreviewFixtures.appKeymapsPopulated[0],
            onEdit: { _ in },
            onDelete: { _ in },
            onAddRule: {}
        )
        .padding()
        .frame(width: 260)
        .background(Color.black.opacity(0.8))
    }

    #Preview("App Rule Card - Minimal") {
        AppRuleCard(
            keymap: AppKeymap(
                mapping: AppKeyMapping(
                    bundleIdentifier: "com.apple.TextEdit",
                    displayName: "TextEdit",
                    virtualKeyName: "vk_textedit"
                ),
                overrides: [AppKeyOverride(inputKey: "f", outputAction: "home")]
            ),
            onEdit: { _ in },
            onDelete: { _ in },
            onAddRule: {}
        )
        .padding()
        .frame(width: 260)
        .background(Color.black.opacity(0.8))
    }

    #Preview("App Rule Card - Empty Overrides") {
        AppRuleCard(
            keymap: AppKeymap(
                mapping: AppKeyMapping(
                    bundleIdentifier: "com.apple.finder",
                    displayName: "Finder",
                    virtualKeyName: "vk_finder"
                ),
                overrides: []
            ),
            onEdit: { _ in },
            onDelete: { _ in },
            onAddRule: {}
        )
        .padding()
        .frame(width: 260)
        .background(Color.black.opacity(0.8))
    }
#endif
