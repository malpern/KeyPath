import AppKit
import SwiftUI

// MARK: - Mapper Inspector Panel

/// Inspector panel with Liquid Glass styling for the Mapper window.
/// Contains output type selection (key, app, system action, URL).
struct MapperInspectorPanel: View {
    @ObservedObject var viewModel: MapperViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

    // MARK: - App Condition Section

    @State private var showingAppConditionMenu = false

    private var appConditionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Only When App Active")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Current selection or "Any App" button
            if let condition = viewModel.selectedAppCondition {
                // Show selected app with clear button
                HStack(spacing: 10) {
                    Image(nsImage: condition.icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text(condition.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel.clearAppCondition()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear app condition")
                    .accessibilityIdentifier("mapper-clear-app-condition")
                    .accessibilityLabel("Clear app condition")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            } else {
                // Show "Any App" picker button
                Menu {
                    // Any App option (default)
                    Button {
                        viewModel.clearAppCondition()
                    } label: {
                        Label("Any App", systemImage: "app.dashed")
                    }

                    Divider()

                    // Running apps
                    let runningApps = viewModel.getRunningApps()
                    if !runningApps.isEmpty {
                        ForEach(runningApps) { app in
                            Button {
                                viewModel.selectedAppCondition = app
                            } label: {
                                Label {
                                    Text(app.displayName)
                                } icon: {
                                    Image(nsImage: app.icon)
                                }
                            }
                        }

                        Divider()
                    }

                    // Browse for any app
                    Button {
                        viewModel.pickAppCondition()
                    } label: {
                        Label("Browse...", systemImage: "folder")
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)

                        Text("Any App")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("mapper-app-condition-picker")
                .accessibilityLabel("Select app condition")
            }

            Text("Rule only applies when this app is frontmost")
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                    .font(.system(size: 14))
                    .foregroundStyle(viewModel.showAdvanced ? Color.accentColor : .secondary)
                Text("Hold, Double Tap, etc.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Toggle on its own line
            Toggle("Different actions for tap vs hold", isOn: $viewModel.showAdvanced)
                .toggleStyle(.switch)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mapper-advanced-behavior-toggle")
                .accessibilityLabel("Different actions for tap vs hold")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            LeftRoundedRectangle(radius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        } else if #available(macOS 26.0, *) {
            LeftRoundedRectangle(radius: 10)
                .fill(.clear)
                .glassEffect(.regular, in: LeftRoundedRectangle(radius: 10))
        } else {
            LeftRoundedRectangle(radius: 10)
                .fill(Color(white: isDark ? 0.12 : 0.92))
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
                    .font(.system(size: 16))
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
                    .font(.system(size: 18))
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
