import SwiftUI

/// Main simulator view combining keyboard input, event queue, and results display.
struct SimulatorView: View {
    @StateObject private var viewModel = SimulatorViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard section (top)
            keyboardSection
                .frame(maxHeight: 280)

            Divider()

            // Event queue strip
            EventSequenceView(
                taps: viewModel.queuedTaps,
                onClear: { viewModel.clearAll() },
                onRun: {
                    Task {
                        await viewModel.runSimulation()
                    }
                },
                isRunning: viewModel.isRunning
            )

            Divider()

            // Results section (bottom, scrollable)
            SimulationResultsView(
                result: viewModel.result,
                error: viewModel.error
            )
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Virtual Keyboard")
                    .font(.headline)

                Spacer()

                // Delay stepper
                delayControl
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Keyboard
            SimulatorKeyboardView(
                layout: .macBookUS,
                onKeyTap: { key in
                    viewModel.tapKey(key)
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(white: 0.98))
    }

    private var delayControl: some View {
        HStack(spacing: 4) {
            Text("Delay:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("", value: $viewModel.defaultDelayMs, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)

            Text("ms")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SimulatorView()
}
