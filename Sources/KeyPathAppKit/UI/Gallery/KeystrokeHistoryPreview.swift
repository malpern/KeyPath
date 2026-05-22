import SwiftUI

struct KeystrokeHistoryPreview: View {
    private let isDark: Bool

    init(isDark: Bool = true) {
        self.isDark = isDark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewToolbar
            Divider().opacity(0.3)
            previewTimeline
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark
                    ? Color.black.opacity(0.3)
                    : Color(NSColor.controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Toolbar

    private var previewToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)

            Text("12 events")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Timeline

    private var previewTimeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            sampleTextRun("Hello world")

            sampleTapHoldCard(key: "f", output: "⌘", isHold: true)

            sampleLayerDivider("nav")

            sampleNonPrintableRun([("←", 3), ("↓", 1)])

            sampleHrmCard(key: "d", latency: 142, threshold: 180)

            sampleLayerDivider("base")

            sampleTextRun("fixed!")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Sample Segments

    private func sampleTextRun(_ text: String) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(isDark ? .white : .primary)
                    .padding(.horizontal, 0.5)
            }
        }
        .padding(.vertical, 2)
    }

    private func sampleTapHoldCard(key: String, output: String, isHold: Bool) -> some View {
        HStack(spacing: 4) {
            Text(isHold ? "HOLD" : "TAP")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isHold ? Color.orange : Color.blue)
                )

            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)

            Text(output)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill((isHold ? Color.orange : Color.blue).opacity(isDark ? 0.1 : 0.06))
        )
    }

    private func sampleHrmCard(key: String, latency: Int, threshold: Int) -> some View {
        HStack(spacing: 4) {
            Text("TAP")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue)
                )

            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isDark ? .white : .primary)

            Text("other-key-up")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06))
                )

            let ratio = Double(latency) / Double(threshold)
            let color: Color = ratio < 0.5 ? .green : (ratio < 0.8 ? .yellow : .red)
            Text("\(latency)ms")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.blue.opacity(isDark ? 0.1 : 0.06))
        )
    }

    private func sampleLayerDivider(_ name: String) -> some View {
        HStack(spacing: 6) {
            dividerLine
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            dividerLine
        }
        .padding(.vertical, 4)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(height: 0.5)
    }

    private func sampleNonPrintableRun(_ keys: [(String, Int)]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 1) {
                    Text(entry.0)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if entry.1 > 1 {
                        Text("\u{00D7}\(entry.1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isDark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.04))
        )
    }
}
