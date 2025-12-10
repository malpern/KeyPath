import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Notification for preset values

extension Notification.Name {
    /// Posted when Mapper should apply preset values (from overlay click)
    static let mapperPresetValues = Notification.Name("KeyPath.MapperPresetValues")
}

// MARK: - Mapper View

/// Experimental key mapping page with visual keycap-based input/output capture.
/// Accessible from File menu as "Mapper".
struct MapperView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @StateObject private var viewModel = MapperViewModel()

    /// Optional preset input from overlay click
    var presetInput: String?
    /// Optional preset output from overlay click
    var presetOutput: String?
    /// Optional preset layer from overlay click
    var presetLayer: String?

    /// Error alert state
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""

    /// Reset all confirmation dialog
    @State private var showingResetAllConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            // Compact toolbar with layer and clear
            HStack(spacing: 8) {
                // Layer indicator (compact)
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.currentLayer.lowercased() == "base" ? Color.secondary.opacity(0.4) : Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(viewModel.currentLayer.lowercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status message (centered area)
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(viewModel.statusIsError ? .red : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // System action picker menu
                Menu {
                    ForEach(SystemActionInfo.allActions) { action in
                        Button {
                            viewModel.selectSystemAction(action)
                        } label: {
                            Label(action.name, systemImage: action.sfSymbol)
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("System action")

                // App launcher picker button
                Button {
                    viewModel.pickAppForOutput()
                } label: {
                    Image(systemName: "app.badge")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Pick app to launch")
                .accessibilityLabel("Pick app")

                // Clear/reset button
                // Single click: reset current mapping
                // Double click: reset entire keyboard to defaults
                ResetButton(
                    isEnabled: viewModel.canSave || viewModel.inputLabel != "a" || viewModel.outputLabel != "a",
                    onSingleClick: { viewModel.clear() },
                    onDoubleClick: { showingResetAllConfirmation = true }
                )
            }
            .padding(.horizontal, 4)

            // Keycaps for input and output
            MapperKeycapPair(
                inputLabel: viewModel.inputLabel,
                inputKeyCode: viewModel.inputKeyCode,
                outputLabel: viewModel.outputLabel,
                isRecordingInput: viewModel.isRecordingInput,
                isRecordingOutput: viewModel.isRecordingOutput,
                outputAppInfo: viewModel.selectedApp,
                outputSystemActionInfo: viewModel.selectedSystemAction,
                onInputTap: { viewModel.toggleInputRecording() },
                onOutputTap: { viewModel.toggleOutputRecording() }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minWidth: 340, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: viewModel.canSave)
        .animation(.easeInOut(duration: 0.25), value: viewModel.statusMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.inputLabel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.outputLabel)
        .onAppear {
            viewModel.configure(kanataManager: kanataManager.underlyingManager)
            // Apply preset values if provided
            if let presetInput, let presetOutput {
                viewModel.applyPresets(input: presetInput, output: presetOutput, layer: presetLayer)
            } else {
                // No preset - use current layer from kanataManager
                viewModel.setLayer(kanataManager.currentLayerName)
            }
        }
        .onDisappear {
            viewModel.stopKeyCapture()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mapperPresetValues)) { notification in
            // Handle preset updates when window is already open
            if let input = notification.userInfo?["input"] as? String,
               let output = notification.userInfo?["output"] as? String
            {
                let layer = notification.userInfo?["layer"] as? String
                viewModel.applyPresets(input: input, output: output, layer: layer)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanataLayerChanged)) { notification in
            // Update layer when it changes (if not opened from overlay with specific layer)
            if let layerName = notification.userInfo?["layerName"] as? String,
               viewModel.originalInputKey == nil
            { // Only auto-update if not opened from overlay
                viewModel.setLayer(layerName)
            }
        }
        .onChange(of: kanataManager.lastError) { _, newError in
            if let error = newError {
                errorAlertMessage = error
                showingErrorAlert = true
                // Clear the error so it doesn't re-trigger
                kanataManager.lastError = nil
            }
        }
        .alert("Configuration Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage)
        }
        .alert("Reset Entire Layout?", isPresented: $showingResetAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Reset", role: .destructive) {
                Task {
                    await viewModel.resetAllToDefaults(kanataManager: kanataManager.underlyingManager)
                }
            }
        } message: {
            Text("This will remove all custom rules and restore the keyboard to its default mappings.")
        }
    }
}

// MARK: - Window Controller

@MainActor
class MapperWindowController {
    private var window: NSWindow?
    private weak var viewModel: KanataViewModel?
    /// Pending preset values to apply when view appears
    private var pendingPresetInput: String?
    private var pendingPresetOutput: String?
    private var pendingLayer: String?

    static let shared = MapperWindowController()

    /// Show the Mapper window, optionally with preset input/output values and layer from overlay click
    func showWindow(viewModel: KanataViewModel, presetInput: String? = nil, presetOutput: String? = nil, layer: String? = nil) {
        self.viewModel = viewModel
        pendingPresetInput = presetInput
        pendingPresetOutput = presetOutput
        pendingLayer = layer

        if let existingWindow = window, existingWindow.isVisible {
            // Window already visible - apply presets to existing view
            if let presetInput, let presetOutput {
                var userInfo: [String: Any] = ["input": presetInput, "output": presetOutput]
                if let layer {
                    userInfo["layer"] = layer
                }
                NotificationCenter.default.post(
                    name: .mapperPresetValues,
                    object: nil,
                    userInfo: userInfo
                )
            }
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MapperView(presetInput: presetInput, presetOutput: presetOutput, presetLayer: layer)
            .environmentObject(viewModel)

        // Window height calculation:
        // - Header: ~30pt
        // - Input keycap (max): 150pt + label 20pt = 170pt
        // - Arrow: ~25pt
        // - Output keycap (max): 150pt + label 20pt = 170pt
        // - Bottom bar: ~35pt
        // - Padding: ~30pt
        // Total: ~460pt for vertical layout with max-height keycaps
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mapper"
        window.minSize = NSSize(width: 340, height: 300)
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false

        // Persistent window position
        window.setFrameAutosaveName("MapperWindow")
        if !window.setFrameUsingName("MapperWindow") {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
    }
}

// MARK: - Preview

#Preview {
    MapperView()
        .environmentObject(KanataViewModel(manager: RuntimeCoordinator()))
        .frame(height: 500)
}
