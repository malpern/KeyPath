import AppKit
import SwiftUI

/// Main simulator view combining keyboard input, event queue, and results display.
struct SimulatorView: View {
    @StateObject private var viewModel = SimulatorViewModel()
    @FocusState private var isKeyboardFocused: Bool
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId

    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    var body: some View {
        if !FeatureFlags.simulatorAndVirtualKeysEnabled {
            disabledView
        } else {
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
                Task {
                    await viewModel.loadAvailableApps()
                }
            }
            .onDisappear {
                viewModel.stopKeyMonitoring()
            }
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
                        .foregroundColor(.secondary)
                }

                Spacer()

                // App context picker
                appContextPicker

                // Delay stepper
                delayControl
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // Keyboard
            SimulatorKeyboardView(
                layout: activeLayout,
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

    private var appContextPicker: some View {
        HStack(spacing: 4) {
            Text("Simulate as:")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.selectedAppBundleId) {
                Text("Any App").tag(nil as String?)
                ForEach(viewModel.availableApps, id: \.bundleId) { app in
                    Text(app.displayName).tag(app.bundleId as String?)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityIdentifier("simulator-app-picker")
            .accessibilityLabel("Select app context for simulation")
        }
    }

    private var delayControl: some View {
        HStack(spacing: 4) {
            Text("Delay:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("", value: $viewModel.defaultDelayMs, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .accessibilityIdentifier("simulator-delay-input")
                .accessibilityLabel("Delay between events in milliseconds")

            Text("ms")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var disabledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.slash")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Simulator Disabled")
                .font(.title3.weight(.semibold))
            Text("Enable the simulator feature flag to use the virtual keyboard simulator.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    SimulatorView()
}

#Preview("Simulator - Narrow") {
    SimulatorView()
        .frame(width: 900, height: 560)
}
