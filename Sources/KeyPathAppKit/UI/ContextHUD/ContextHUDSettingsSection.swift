import SwiftUI

/// Visual settings section for the Shortcut List
struct ContextHUDSettingsSection: View {
    @State private var displayMode = PreferencesService.shared.contextHUDDisplayMode
    @State private var triggerMode = PreferencesService.shared.contextHUDTriggerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcut List")
                .font(.headline)
                .foregroundColor(.secondary)

            // Display Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Display")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    displayModeCard(
                        mode: .overlayOnly,
                        icon: "keyboard",
                        title: "Overlay",
                        subtitle: "Full keyboard"
                    )
                    displayModeCard(
                        mode: .hudOnly,
                        icon: "list.bullet.rectangle",
                        title: "List",
                        subtitle: "Compact view"
                    )
                    displayModeCard(
                        mode: .both,
                        icon: "rectangle.on.rectangle",
                        title: "Both",
                        subtitle: "Overlay + List"
                    )
                }
            }

            // Trigger Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
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
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }

                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 84)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-context-hud-trigger-\(mode.rawValue)")
        .accessibilityLabel("\(title) trigger mode")
    }
}
