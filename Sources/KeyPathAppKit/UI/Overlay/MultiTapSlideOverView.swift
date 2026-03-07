import SwiftUI

/// Slide-over view for configuring multi-tap (2x, 3x, 4x) actions.
struct MultiTapSlideOverView: View {
    var viewModel: MapperViewModel
    let sourceKey: String

    private let tapCounts = [2, 3, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap \(sourceKey.uppercased()) multiple times to trigger different actions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(tapCounts, id: \.self) { count in
                MultiTapRow(
                    count: count,
                    action: viewModel.multiTapAction(for: count) ?? "",
                    isRecording: viewModel.isRecordingMultiTap(for: count),
                    onRecord: { viewModel.toggleMultiTapRecording(for: count) },
                    onClear: { viewModel.clearMultiTapAction(for: count) }
                )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct MultiTapRow: View {
    let count: Int
    let action: String
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Tap count badge
            Text("\(count)×")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(action.isEmpty ? .tertiary : .primary)
                .frame(width: 22)

            // Action display / record button
            Button(action: onRecord) {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("Press a key…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if action.isEmpty {
                        Text("Record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(KeyDisplayFormatter.format(action))
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.red.opacity(0.08) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isRecording ? Color.red.opacity(0.3) : Color.primary.opacity(0.1),
                            lineWidth: 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("multitap-record-\(count)x")

            // Clear button (only when configured)
            if !action.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("multitap-clear-\(count)x")
            }
        }
    }
}
