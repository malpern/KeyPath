import SwiftUI

extension OverlayMapperSection {
    enum TapOutputMode: String, CaseIterable {
        case `default`
        case shifted
    }

    var activeTapOutputLabel: String {
        switch selectedTapOutputMode {
        case .default:
            viewModel.outputLabel
        case .shifted:
            viewModel.shiftedOutputLabel ?? "Set ⇧ output"
        }
    }

    var activeTapIsRecording: Bool {
        switch selectedTapOutputMode {
        case .default:
            viewModel.isRecordingOutput
        case .shifted:
            viewModel.isRecordingShiftedOutput
        }
    }

    var shiftOutputEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailSectionHeader("Action")
            tapOutputModeRow(
                title: "Default",
                subtitle: defaultActionSummary,
                mode: .default,
                accessibilityIdentifier: "overlay-mapper-shift-mode-default"
            )

            detailSectionHeader("Variants")

            if viewModel.hasShiftedOutputConfigured || viewModel.canUseShiftedOutput {
                tapOutputModeRow(
                    title: "Shift Variant",
                    subtitle: shiftVariantSummary,
                    mode: .shifted,
                    accessibilityIdentifier: "overlay-mapper-shift-mode-shifted",
                    trailingAction: viewModel.hasShiftedOutputConfigured
                        ? AnyView(
                            Button("Remove") {
                                removeShiftVariant()
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("overlay-mapper-shift-remove")
                        )
                        : nil
                )

                if selectedTapOutputMode == .shifted {
                    Text(shiftOutputHelperText)
                        .font(.caption2)
                        .foregroundStyle(viewModel.canUseShiftedOutput ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("overlay-mapper-shift-helper")
                }
            } else {
                unavailableDetailRow(
                    title: "Shift Variant",
                    message: shiftOutputHelperText
                )
            }

            detailSectionHeader("Additional Actions")
            multiTapActionRow
        }
        .padding(.top, 6)
    }

    private var shiftOutputHelperText: String {
        if let reason = viewModel.shiftedOutputBlockingReason {
            return reason
        }
        if let shifted = viewModel.shiftedOutputLabel, !shifted.isEmpty {
            return "Shift + \(viewModel.inputLabel) sends \(shifted). Tap the output keycap to change it."
        }
        return "Tap the output keycap to capture the output when Shift is held."
    }

    private var defaultActionSummary: String {
        if let selectedApp = viewModel.selectedApp {
            return "Launches \(selectedApp.name)"
        }
        if let selectedSystemAction = viewModel.selectedSystemAction {
            return selectedSystemAction.name
        }
        if viewModel.selectedURL != nil {
            return "Opens URL"
        }
        if selectedLayerOutput != nil {
            return "Goes to a layer"
        }
        return "Types \(viewModel.outputLabel)"
    }

    private var shiftVariantSummary: String {
        if let shifted = viewModel.shiftedOutputLabel, !shifted.isEmpty {
            return "Shift-\(viewModel.inputLabel.uppercased()) types \(shifted)"
        }
        return "Add a separate action when Shift is held."
    }

    private var multiTapSummary: String {
        let configuredCounts = [2, 3, 4].filter { viewModel.multiTapAction(for: $0) != nil }
        if configuredCounts.isEmpty {
            return "Add actions for double- or triple-tap."
        }
        let summary = configuredCounts.map { "\($0)x" }.joined(separator: ", ")
        return "Configured for \(summary) taps."
    }

    private func removeShiftVariant() {
        viewModel.clearShiftedOutput()
        selectedTapOutputMode = .default

        if viewModel.isIdentityKeystrokeMapping {
            viewModel.revertToKeystroke()
        } else if let manager = kanataViewModel?.underlyingManager {
            Task { await viewModel.save(kanataManager: manager) }
        }
    }

    private func detailSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityHidden(true)
    }

    private func tapOutputModeRow(
        title: String,
        subtitle: String,
        mode: TapOutputMode,
        accessibilityIdentifier: String,
        trailingAction: AnyView? = nil
    ) -> some View {
        let isSelected = selectedTapOutputMode == mode
        return Button {
            selectedTapOutputMode = mode
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if let trailingAction {
                    trailingAction
                }

                Image(systemName: isSelected ? "record.circle.fill" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func unavailableDetailRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityIdentifier("overlay-mapper-shift-unavailable")
    }

    private var multiTapActionRow: some View {
        Button {
            showMultiTapSlideOver = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multi-Tap Actions")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(multiTapSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-mapper-multitap-link")
    }
}
