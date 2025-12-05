import AppKit
import SwiftUI

/// Main simulator view combining keyboard input, event queue, and results display.
struct SimulatorView: View {
    @StateObject private var viewModel = SimulatorViewModel()
    @FocusState private var isKeyboardFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard section (top) - fills available space
            keyboardSection

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
        .focusable()
        .focused($isKeyboardFocused)
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            if let key = SimulatorViewModel.physicalKeyFromCharacter(keyPress.key.character) {
                viewModel.tapKey(key)
                return .handled
            }
            return .ignored
        }
        .onAppear {
            isKeyboardFocused = true
            viewModel.startKeyMonitoring()
        }
        .onDisappear {
            viewModel.stopKeyMonitoring()
        }
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtual Keyboard")
                        .font(.headline)
                    Text("Click to tap • Long-press to hold • Type to add keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Delay stepper
                delayControl
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Keyboard
            SimulatorKeyboardView(
                layout: .macBookUS,
                pressedKeyCodes: viewModel.pressedKeyCodes,
                onKeyTap: { key in
                    viewModel.tapKey(key)
                },
                onKeyHold: { key in
                    viewModel.holdKey(key)
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var delayControl: some View {
        HStack(spacing: 4) {
            Text("Delay:")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("", value: $viewModel.defaultDelayMs, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)

            Text("ms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SimulatorView()
}
