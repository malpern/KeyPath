import SwiftUI

// MARK: - Things-Style Settings Design System

/// Clean, flat form layout matching Things app design
struct FormRow<Content: View>: View {
    let label: String
    let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .frame(width: 180, alignment: .trailing)
                .foregroundStyle(.primary)

            content()

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

/// Section with optional header and clean separator
struct FormSection<Content: View>: View {
    let header: String?
    let content: () -> Content

    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Divider()
                .padding(.top, 16)
        }
    }
}

/// Status indicator with colored dot and text
struct StatusRow: View {
    let label: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(status)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

/// Clean button row for settings actions
struct ActionButtonRow: View {
    let buttons: [ActionButton]

    struct ActionButton {
        let title: String
        let icon: String?
        let style: ActionStyle
        let action: () -> Void

        enum ActionStyle {
            case primary
            case secondary
            case destructive
        }

        init(
            title: String, icon: String? = nil, style: ActionStyle = .secondary,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.style = style
            self.action = action
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(buttons.indices, id: \.self) { index in
                let button = buttons[index]
                buttonView(for: button)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func buttonView(for button: ActionButton) -> some View {
        let baseButton = Button(action: button.action) {
            if let icon = button.icon {
                Label(button.title, systemImage: icon)
            } else {
                Text(button.title)
            }
        }

        switch button.style {
        case .primary:
            baseButton
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        case .secondary:
            baseButton
                .buttonStyle(.bordered)
                .controlSize(.regular)
        case .destructive:
            baseButton
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)
        }
    }
}

/// Info row with icon and description
struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

/// Simple list item for rules/logs
struct SimpleListItem: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let action: (() -> Void)?

    init(title: String, subtitle: String? = nil, icon: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Container Style

extension View {
    /// Apply consistent settings container background
    func settingsBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.windowBackgroundColor))
    }
}
