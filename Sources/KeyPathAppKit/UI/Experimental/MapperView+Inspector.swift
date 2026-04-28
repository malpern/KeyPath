import AppKit
import SwiftUI

// MARK: - Mapper Inspector Panel

/// Inspector panel with Liquid Glass styling for the Mapper window.
/// Contains output type selection (key, app, system action, URL).
struct MapperInspectorPanel: View {
    @Bindable var viewModel: MapperViewModel
    @Environment(KanataViewModel.self) private var kanataManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Pack suggestions for the current input key. Only visible
                // when ≥ 1 Starter Kit pack targets the selected input —
                // turns the inspector into a discovery surface for new users
                // who don't know the Gallery exists.
                if !packSuggestions.isEmpty {
                    packSuggestionsSection
                    Divider()
                        .padding(.vertical, 4)
                }

                // App Condition Section (precondition - rule only applies when app is active)
                appConditionSection

                Divider()
                    .padding(.vertical, 4)

                // Output Type Options
                outputTypeSection

                Divider()
                    .padding(.vertical, 4)

                // Advanced Behavior Toggle (own section, before system actions)
                advancedBehaviorSection

                Divider()
                    .padding(.vertical, 4)

                // System Actions Section
                systemActionsSection
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
        .overlay(
            LeftRoundedRectangle(radius: 10)
                .stroke(Color(white: isDark ? 0.3 : 0.75), lineWidth: 1)
        )
        .clipShape(LeftRoundedRectangle(radius: 10))
    }

    // MARK: - Pack Suggestions

    /// Pack selected by the user to open in Pack Detail (sheet presentation).
    @State private var packForDetail: Pack?

    /// Packs from the Starter Kit whose bindings target the currently
    /// selected input key. Empty ⇒ the section doesn't render.
    private var packSuggestions: [Pack] {
        guard let kanataKey = currentInputKanataToken else { return [] }
        return PackRegistry.packsTargeting(kanataKey: kanataKey)
    }

    /// The input key's kanata-style identifier (e.g. "caps", "d", "rmet")
    /// — pulled from the first key of the captured input sequence.
    private var currentInputKanataToken: String? {
        viewModel.inputSequence?.keys.first?.baseKey.lowercased()
    }

    @ViewBuilder
    private var packSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(packSuggestions) { pack in
                packSuggestionRow(pack)
            }
        }
        .sheet(item: $packForDetail) { pack in
            PackDetailView(pack: pack)
                .environment(kanataManagerForGallery())
        }
    }

    /// A single pack suggestion as a compact clickable row. Shows the pack's
    /// hero icon, name, and tagline, plus an install state indicator.
    private func packSuggestionRow(_ pack: Pack) -> some View {
        Button(action: { packForDetail = pack }) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.min")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                Text(pack.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pack.tagline)
        .accessibilityIdentifier("pack-suggestion-row-\(pack.id)")
    }

    /// Compact hero icon — same vocabulary as the pack card / Pack Detail
    /// header but shrunk down for an inspector-width row.
    private func packRowIcon(_ pack: Pack) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 34, height: 34)
            if let secondary = pack.iconSecondarySymbol {
                HStack(spacing: 1) {
                    Image(systemName: pack.iconSymbol)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: secondary)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            } else {
                Image(systemName: pack.iconSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private func kanataManagerForGallery() -> KanataViewModel {
        kanataManager
    }

    /// Display-friendly label for the current input (⇪, D, ⌘, etc.).
    private var inputDisplayLabel: String {
        guard let token = currentInputKanataToken else { return "this key" }
        switch token {
        case "caps": return "⇪ Caps Lock"
        case "lmet", "rmet": return "⌘ Command"
        case "lalt", "ralt": return "⌥ Option"
        case "lctl", "rctl": return "⌃ Control"
        case "lsft", "rsft": return "⇧ Shift"
        case "spc": return "Space"
        case "ret": return "Return"
        case "esc": return "Escape"
        case "tab": return "Tab"
        case "bspc": return "Delete"
        default: return token.count == 1 ? token.uppercased() : token
        }
    }

    // MARK: - App Condition Section

    @State private var showingAppPickerSheet = false

    private var appConditionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active App")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            InspectorButton(
                icon: "app.dashed",
                title: "Any App",
                isSelected: viewModel.selectedAppCondition == nil
            ) {
                viewModel.clearAppCondition()
            }
            .accessibilityIdentifier("mapper-app-condition-any")

            onlyInRow

            Text("Rule only applies when this app is frontmost")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .sheet(isPresented: $showingAppPickerSheet) {
            AppConditionPickerSheet(
                onSelect: { condition in
                    viewModel.selectedAppCondition = condition
                },
                onBrowse: {
                    viewModel.pickAppCondition()
                }
            )
        }
    }

    @ViewBuilder
    private var onlyInRow: some View {
        if let condition = viewModel.selectedAppCondition {
            // Selected state: custom row with app icon + name + clear button
            HStack(spacing: 12) {
                Image(nsImage: condition.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Only in...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(condition.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Button {
                    viewModel.clearAppCondition()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear app condition")
                .accessibilityIdentifier("mapper-clear-app-condition")
                .accessibilityLabel("Clear app condition")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture {
                showingAppPickerSheet = true
            }
            .accessibilityIdentifier("mapper-app-condition-only-in-selected")
        } else {
            InspectorButton(
                icon: "app.badge",
                title: "Only in...",
                isSelected: false
            ) {
                showingAppPickerSheet = true
            }
            .accessibilityIdentifier("mapper-app-condition-only-in")
        }
    }

    // MARK: - Output Type Section

    private var outputTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Key output (default)
            InspectorButton(
                icon: "keyboard",
                title: "Send Keystroke",
                isSelected: viewModel.selectedApp == nil && viewModel.selectedSystemAction == nil && viewModel.selectedURL == nil
            ) {
                // Clear special outputs, allow normal key recording
                viewModel.selectedApp = nil
                viewModel.selectedSystemAction = nil
                viewModel.selectedURL = nil
            }

            // App launcher
            InspectorButton(
                icon: "app.badge",
                title: "Launch App",
                isSelected: viewModel.selectedApp != nil
            ) {
                viewModel.pickAppForOutput()
            }

            // URL
            InspectorButton(
                icon: "link",
                title: "Open Link",
                isSelected: viewModel.selectedURL != nil
            ) {
                viewModel.showURLInputDialog()
            }
        }
    }

    // MARK: - System Actions Section

    private var systemActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(SystemActionInfo.allActions) { action in
                    SystemActionButton(
                        action: action,
                        isSelected: viewModel.selectedSystemAction?.id == action.id
                    ) {
                        viewModel.selectSystemAction(action)
                    }
                }
            }
        }
    }

    // MARK: - Advanced Behavior Section

    private var advancedBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label on its own line
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .font(.body)
                    .foregroundStyle(viewModel.showAdvanced ? Color.accentColor : .secondary)
                Text("Hold, Double Tap, etc.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Toggle on its own line
            Toggle("Different actions for tap vs hold", isOn: $viewModel.showAdvanced).accessibilityIdentifier(
                "mapper-advanced-behavior-toggle"
            )
            .toggleStyle(.switch)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Different actions for tap vs hold")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            LeftRoundedRectangle(radius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        } else {
            ZStack {
                VisualEffectRepresentable(material: .menu, blending: .withinWindow)
                LeftRoundedRectangle(radius: 10)
                    .fill(Color.white.opacity(isDark ? 0.06 : 0.10))
                LeftRoundedRectangle(radius: 10)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                    .blendMode(.overlay)
            }
            .clipShape(LeftRoundedRectangle(radius: 10))
        }
    }
}

// MARK: - Inspector Button

/// Button style for inspector panel options.
struct InspectorButton: View {
    let icon: String
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, subtitle == nil ? 8 : 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("mapper-inspector-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(title)
    }
}

// MARK: - System Action Button

/// Compact button for system actions in the grid.
struct SystemActionButton: View {
    let action: SystemActionInfo
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: action.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(action.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("mapper-system-action-\(action.id)")
        .accessibilityLabel(action.name)
    }
}
