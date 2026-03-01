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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                tapOutputModeButton(title: "Default", mode: .default)
                tapOutputModeButton(title: "With Shift ⇧", mode: .shifted)

                Spacer(minLength: 0)

                if selectedTapOutputMode == .shifted, viewModel.hasShiftedOutputConfigured {
                    Button("Remove") {
                        viewModel.clearShiftedOutput()
                        if viewModel.isIdentityKeystrokeMapping {
                            viewModel.revertToKeystroke()
                        } else if let manager = kanataViewModel?.underlyingManager {
                            Task { await viewModel.save(kanataManager: manager) }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("overlay-mapper-shift-remove")
                }
            }

            if selectedTapOutputMode == .shifted {
                Text(shiftOutputHelperText)
                    .font(.caption2)
                    .foregroundStyle(viewModel.canUseShiftedOutput ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .accessibilityIdentifier("overlay-mapper-shift-helper")
            }
        }
        .padding(.horizontal, 2)
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

    @ViewBuilder
    private func tapOutputModeButton(title: String, mode: TapOutputMode) -> some View {
        let isSelected = selectedTapOutputMode == mode
        Button {
            selectedTapOutputMode = mode
        } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.15), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode == .default ? "overlay-mapper-shift-mode-default" : "overlay-mapper-shift-mode-shifted")
    }
}
