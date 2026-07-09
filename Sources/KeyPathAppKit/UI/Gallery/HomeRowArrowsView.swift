import KeyPathRulesCore
import SwiftUI

struct HomeRowArrowsView: View {
    let config: LayerPresetPickerConfig
    let onSelectPreset: (String) -> Void

    @State private var selectedPresetId: String

    init(config: LayerPresetPickerConfig, onSelectPreset: @escaping (String) -> Void) {
        self.config = config
        self.onSelectPreset = onSelectPreset
        _selectedPresetId = State(initialValue: config.selectedPresetId ?? "inverted-t")
    }

    private var isVim: Bool {
        selectedPresetId == "vim"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            presetCards
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPresetId)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 20) {
            keycapCluster

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

    @ViewBuilder
    private var keycapCluster: some View {
        if isVim {
            HStack(spacing: 3) {
                keycap("←", label: "H")
                keycap("↓", label: "J")
                keycap("↑", label: "K")
                keycap("→", label: "L")
            }
        } else {
            VStack(spacing: 3) {
                keycap("↑", label: "I")
                HStack(spacing: 3) {
                    keycap("←", label: "J")
                    keycap("↓", label: "K")
                    keycap("→", label: "L")
                }
            }
        }
    }

    private var heroHeadline: String {
        if isVim {
            "Hold F for Vim-style\nHJKL arrow keys."
        } else {
            "Hold F for arrow keys\nright under your fingers."
        }
    }

    private var heroSubhead: String {
        if isVim {
            "Classic Vim navigation.\nTap F normally to type."
        } else {
            "Matches your arrow key layout.\nTap F normally to type."
        }
    }

    private func keycap(_ arrow: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(arrow)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
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
            SettingsOptionCard(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                title: "Inverted-T",
                subtitle: "Arrow key layout",
                isSelected: !isVim
            ) {
                selectedPresetId = "inverted-t"
                onSelectPreset("inverted-t")
            }
            SettingsOptionCard(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Vim-Style",
                subtitle: "HJKL layout",
                isSelected: isVim
            ) {
                selectedPresetId = "vim"
                onSelectPreset("vim")
            }
        }
    }
}
