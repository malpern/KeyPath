import SwiftUI

/// Shared settings primitives. Native controls retain platform keyboard/focus behavior.
/// Specialty editors (rules, keyboard diagrams, history tables) keep their own content.
enum SettingsDesign {
    static let pageInset: CGFloat = 20
    static let sectionGap: CGFloat = 24
    static let sectionContentGap: CGFloat = 12
    static let rowGap: CGFloat = 12
    static let labelGap: CGFloat = 2
    static let cardInset: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let optionRadius: CGFloat = 8
    static let optionWidth: CGFloat = 240
    static let compactOptionWidth: CGFloat = 190
    static let optionGap: CGFloat = 10
}

struct SettingsSectionHeader: View {
    let title: String
    var icon: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(color).font(.body)
            }
            Text(title).font(.headline).foregroundStyle(.secondary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionContentGap) {
            SettingsSectionHeader(title: title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(SettingsDesign.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsDesign.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.cornerRadius)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var help: String?
    var subtitleColor: Color = .secondary
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        HStack(alignment: .center, spacing: SettingsDesign.rowGap) {
            VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
                HStack(spacing: 4) {
                    Text(title).font(.body.weight(.medium))
                    if let help { InfoTip(help) }
                }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(title)
        }
    }
}

extension View {
    func settingsBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    func settingsAction() -> some View {
        buttonStyle(.bordered).controlSize(.regular)
    }

    func settingsPrimaryAction() -> some View {
        buttonStyle(.borderedProminent).controlSize(.regular)
    }
}

/// A compact macOS-style row: recognizable label on the left, native control on the right.
struct SettingsControlRow<Control: View>: View {
    let title: String
    let icon: String
    var help: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: SettingsDesign.rowGap) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            Text(title).font(.body.weight(.medium))
            if let help { InfoTip(help) }
            Spacer(minLength: SettingsDesign.rowGap)
            control
        }
    }
}

/// Appearance choices show the actual label treatment rather than describing it.
struct SettingsKeyPreviewChoice: View {
    let title: String
    let keys: [String]
    var dimmed = false
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SettingsDesign.optionGap) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.self) { key in
                        Text(key).font(.system(size: 12, weight: .medium))
                            .frame(minWidth: 44, minHeight: 32)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.primary.opacity(0.18), lineWidth: 1))
                    }
                }
                .opacity(dimmed ? 0.35 : 1)
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(title).font(.body)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(SettingsDesign.cardInset)
            .background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: SettingsDesign.optionRadius))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.optionRadius)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
