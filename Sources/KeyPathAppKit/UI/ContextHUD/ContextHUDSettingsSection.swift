import SwiftUI

/// Visual settings section for the Context HUD
struct ContextHUDSettingsSection: View {
    @State private var displayMode = PreferencesService.shared.contextHUDDisplayMode
    @State private var triggerMode = PreferencesService.shared.contextHUDTriggerMode
    @State private var timeout = PreferencesService.shared.contextHUDTimeout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context HUD")
                .font(.headline)
                .foregroundColor(.secondary)

            // Display Mode - visual cards
            VStack(alignment: .leading, spacing: 6) {
                Text("Display")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    displayModeCard(
                        mode: .overlayOnly,
                        icon: "keyboard",
                        title: "Overlay",
                        subtitle: "Full keyboard"
                    )
                    displayModeCard(
                        mode: .hudOnly,
                        icon: "list.bullet.rectangle",
                        title: "HUD",
                        subtitle: "Compact list"
                    )
                    displayModeCard(
                        mode: .both,
                        icon: "rectangle.on.rectangle",
                        title: "Both",
                        subtitle: "Overlay + HUD"
                    )
                }
            }

            // Trigger Mode - visual cards
            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    triggerModeCard(
                        mode: .holdToShow,
                        icon: "hand.tap",
                        title: "Hold",
                        subtitle: "Show while held"
                    )
                    triggerModeCard(
                        mode: .tapToToggle,
                        icon: "hand.point.up",
                        title: "Tap",
                        subtitle: "Toggle on/off"
                    )
                }
            }

            // Timeout slider
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("Auto-dismiss")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(timeout, specifier: "%.1f")s")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 36)
                }

                Slider(value: $timeout, in: 1 ... 10, step: 0.5)
                    .frame(maxWidth: 260)
                    .onChange(of: timeout) { _, newValue in
                        PreferencesService.shared.contextHUDTimeout = newValue
                    }
                    .accessibilityIdentifier("settings-context-hud-timeout")
                    .accessibilityLabel("Context HUD Timeout")
            }
        }
    }

    // MARK: - Display Mode Card

    private func displayModeCard(
        mode: ContextHUDDisplayMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = displayMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                displayMode = mode
                PreferencesService.shared.contextHUDDisplayMode = mode
            }
        } label: {
            VStack(spacing: 6) {
                // Icon area with mini illustration
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                        .frame(height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-context-hud-display-\(mode.rawValue)")
        .accessibilityLabel("\(title) display mode")
    }

    // MARK: - Trigger Mode Card

    private func triggerModeCard(
        mode: ContextHUDTriggerMode,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = triggerMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                triggerMode = mode
                PreferencesService.shared.contextHUDTriggerMode = mode
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-context-hud-trigger-\(mode.rawValue)")
        .accessibilityLabel("\(title) trigger mode")
    }
}
