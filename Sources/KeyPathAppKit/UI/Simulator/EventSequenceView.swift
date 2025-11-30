import SwiftUI

/// Horizontal strip showing queued key events and action buttons.
struct EventSequenceView: View {
    let taps: [SimulatorKeyTap]
    let onClear: () -> Void
    let onRun: () -> Void
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Event chips (scrollable)
            eventChipsSection

            Spacer(minLength: 8)

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var eventChipsSection: some View {
        if taps.isEmpty {
            Text("Click keys to queue events")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(taps.enumerated()), id: \.element.id) { index, tap in
                        EventChip(tap: tap, index: index + 1)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Clear button
            Button(action: onClear) {
                Label("Clear", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(taps.isEmpty)
            .help("Clear all queued events")

            // Run button
            Button(action: onRun) {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Label("Run", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(taps.isEmpty || isRunning)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Run simulation (⌘↩)")
        }
    }
}

/// A chip displaying a single queued key event.
/// Shows different styling for tap (↓↑) vs hold (⏱).
struct EventChip: View {
    let tap: SimulatorKeyTap
    let index: Int

    private var icon: String {
        tap.isHold ? "⏱" : "↓↑"
    }

    private var backgroundColor: Color {
        tap.isHold ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.12)
    }

    private var accentColor: Color {
        tap.isHold ? .orange : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            // Index badge
            Text("\(index)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            // Key press/release indicator (tap) or timer icon (hold)
            Text(icon)
                .font(.system(size: 10))
                .foregroundColor(accentColor)

            // Key label
            Text(tap.displayLabel)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .cornerRadius(6)
    }
}

// MARK: - Preview

#Preview("Empty") {
    EventSequenceView(
        taps: [],
        onClear: {},
        onRun: {},
        isRunning: false
    )
}

#Preview("With Taps and Holds") {
    EventSequenceView(
        taps: [
            SimulatorKeyTap(kanataKey: "j", displayLabel: "J", delayAfterMs: 200, isHold: false),
            SimulatorKeyTap(kanataKey: "caps", displayLabel: "Caps", delayAfterMs: 400, isHold: true),
            SimulatorKeyTap(kanataKey: "l", displayLabel: "L", delayAfterMs: 200, isHold: false)
        ],
        onClear: {},
        onRun: {},
        isRunning: false
    )
}

#Preview("Running") {
    EventSequenceView(
        taps: [
            SimulatorKeyTap(kanataKey: "a", displayLabel: "A", delayAfterMs: 200)
        ],
        onClear: {},
        onRun: {},
        isRunning: true
    )
}
