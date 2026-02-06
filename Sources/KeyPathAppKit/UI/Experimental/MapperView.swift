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
    /// Optional input keyCode from overlay click (for proper keycap rendering)
    var presetInputKeyCode: UInt16?
    /// Optional app identifier from overlay click
    var presetAppIdentifier: String?
    /// Optional system action identifier from overlay click
    var presetSystemActionIdentifier: String?
    /// Optional URL identifier from overlay click
    var presetURLIdentifier: String?

    /// Error alert state
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""

    /// Reset all confirmation dialog
    @State private var showingResetAllConfirmation = false

    /// Inspector panel visibility
    @State private var isInspectorOpen = false

    /// New layer creation sheet
    @State private var showingNewLayerSheet = false
    @State private var newLayerName = ""

    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            VStack(spacing: 8) {
                // Keycaps for input and output
                MapperKeycapPair(
                    inputLabel: viewModel.inputLabel,
                    inputKeyCode: viewModel.inputKeyCode,
                    outputLabel: viewModel.outputLabel,
                    isRecordingInput: viewModel.isRecordingInput,
                    isRecordingOutput: viewModel.isRecordingOutput,
                    outputAppInfo: viewModel.selectedApp,
                    outputSystemActionInfo: viewModel.selectedSystemAction,
                    outputURLFavicon: viewModel.selectedURLFavicon,
                    onInputTap: { viewModel.toggleInputRecording() },
                    onOutputTap: { viewModel.toggleOutputRecording() }
                )
                .frame(height: 160)

                // Advanced behavior content (shown when toggle in sidebar is ON)
                if viewModel.showAdvanced {
                    AdvancedBehaviorContent(viewModel: viewModel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Bottom bar: layer indicator (left)
                HStack {
                    LayerSwitcherButton(
                        currentLayer: viewModel.currentLayer,
                        onSelectLayer: { layer in
                            viewModel.setLayer(layer)
                        },
                        onCreateLayer: {
                            showingNewLayerSheet = true
                        }
                    )
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 300, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    ResetMappingButton(
                        onSingleClick: { viewModel.clear() },
                        onDoubleClick: { showingResetAllConfirmation = true }
                    )
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isInspectorOpen.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isInspectorOpen ? "Hide Inspector" : "Show Inspector")
                    .accessibilityIdentifier("mapper-toggle-inspector-button")
                    .accessibilityLabel(isInspectorOpen ? "Hide Inspector" : "Show Inspector")
                }
            }

            // Inspector panel (slides in from right)
            if isInspectorOpen {
                MapperInspectorPanel(viewModel: viewModel)
                    .frame(width: 240)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: isInspectorOpen ? 540 : 300, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: isInspectorOpen)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showAdvanced)
        .animation(.easeInOut(duration: 0.25), value: viewModel.canSave)
        .animation(.easeInOut(duration: 0.25), value: viewModel.statusMessage)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.inputLabel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.outputLabel)
        .onAppear {
            viewModel.configure(kanataManager: kanataManager.underlyingManager)
            // Apply preset values if provided
            if let presetInput, let presetOutput {
                viewModel.applyPresets(
                    input: presetInput,
                    output: presetOutput,
                    layer: presetLayer,
                    inputKeyCode: presetInputKeyCode,
                    appIdentifier: presetAppIdentifier,
                    systemActionIdentifier: presetSystemActionIdentifier,
                    urlIdentifier: presetURLIdentifier
                )
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
               let output = notification.userInfo?["output"] as? String {
                let layer = notification.userInfo?["layer"] as? String
                let inputKeyCode = notification.userInfo?["inputKeyCode"] as? UInt16
                let appIdentifier = notification.userInfo?["appIdentifier"] as? String
                let systemActionIdentifier = notification.userInfo?["systemActionIdentifier"] as? String
                let urlIdentifier = notification.userInfo?["urlIdentifier"] as? String
                viewModel.applyPresets(
                    input: input,
                    output: output,
                    layer: layer,
                    inputKeyCode: inputKeyCode,
                    appIdentifier: appIdentifier,
                    systemActionIdentifier: systemActionIdentifier,
                    urlIdentifier: urlIdentifier
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kanataLayerChanged)) { notification in
            // Update layer when it changes (if not opened from overlay with specific layer)
            if let layerName = notification.userInfo?["layerName"] as? String,
               viewModel.originalInputKey == nil { // Only auto-update if not opened from overlay
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
        .sheet(isPresented: $viewModel.showingURLDialog) {
            URLInputDialog(
                urlText: $viewModel.urlInputText,
                onSubmit: { viewModel.submitURL() },
                onCancel: { viewModel.showingURLDialog = false }
            )
        }
        .sheet(isPresented: $viewModel.showConflictDialog) {
            MapperConflictDialog(
                onKeepHold: { viewModel.resolveConflictKeepHold() },
                onKeepTapDance: { viewModel.resolveConflictKeepTapDance() },
                onCancel: {
                    viewModel.showConflictDialog = false
                    viewModel.pendingConflictType = nil
                    viewModel.pendingConflictField = ""
                }
            )
        }
        .sheet(isPresented: $showingNewLayerSheet) {
            NewLayerSheet(
                layerName: $newLayerName,
                existingLayers: viewModel.getAvailableLayers(),
                onSubmit: { name in
                    viewModel.createLayer(name)
                    newLayerName = ""
                    showingNewLayerSheet = false
                },
                onCancel: {
                    newLayerName = ""
                    showingNewLayerSheet = false
                }
            )
        }
    }
}
