import SwiftUI

/// Slide-over view for configuring multi-tap (2x, 3x, 4x) actions.
struct MultiTapSlideOverView: View {
    @ObservedObject var viewModel: MapperViewModel
    let sourceKey: String

    private let tapCounts = [2, 3, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure what happens when you tap \(sourceKey) multiple times in quick succession.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

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
        HStack(spacing: 8) {
            Text("\(count)x Tap")
                .font(.subheadline.weight(.medium))

            Spacer()

            if isRecording {
                Text("Recording...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if action.isEmpty {
                Text("Not configured")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(KeyDisplayFormatter.format(action))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Button {
                onRecord()
            } label: {
                Image(systemName: isRecording ? "stop.fill" : "record.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("multitap-record-\(count)x")

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("multitap-clear-\(count)x")
        }
    }
}
