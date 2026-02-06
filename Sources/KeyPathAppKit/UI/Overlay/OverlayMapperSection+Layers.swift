import AppKit
import KeyPathCore
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Layers Expanded Content

    /// Content shown when Go to Layer section is expanded
    var layersExpandedContent: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Available Layers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // List of available layers
            ForEach(viewModel.availableLayers, id: \.self) { layer in
                layerRow(layer)
            }

            // "Create New Layer..." option
            Button {
                newLayerName = ""
                showingNewLayerDialog = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .frame(width: 20)
                    Text("Create New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerItemButtonStyle())
            .focusable(false)
        }
    }

    /// Button for a layer in the list
    private func layerRow(_ layer: String) -> some View {
        let isSelected = selectedLayerOutput == layer
        let isSystemLayer = viewModel.isSystemLayer(layer)
        let layerIdentifier = layer
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        return Button {
            selectLayerOutput(layer)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSystemLayer ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .font(.body)
                    .foregroundStyle(isSystemLayer ? .blue : .primary)
                    .frame(width: 20)
                Text(layer.capitalized)
                    .font(.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
        .accessibilityIdentifier("overlay-layer-\(layerIdentifier)")
    }

    /// Select a layer as the output action
    func selectLayerOutput(_ layer: String) {
        selectedLayerOutput = layer
        viewModel.selectedApp = nil
        viewModel.selectedSystemAction = nil
        viewModel.selectedURL = nil
        viewModel.outputLabel = "→ \(layer.capitalized)"
        isSystemActionPickerOpen = false

        // Save the layer switch mapping
        if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
            Task {
                await saveLayerSwitchMapping(layer: layer, kanataManager: manager)
            }
        }
    }

    /// Save a mapping that switches to a layer
    func saveLayerSwitchMapping(layer: String, kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = viewModel.inputKeyCode else { return }

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(inputSeq)
        let outputKanata = "(layer-switch \(layer))"

        var customRule = kanataManager.makeCustomRule(input: inputKey, output: outputKanata)
        customRule.notes = "Switch to \(layer) layer"

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        if success {
            viewModel.statusMessage = "✓ Saved"
            SoundPlayer.shared.playSuccessSound()
            AppLogger.shared.log("✅ [OverlayMapper] Saved layer switch: \(inputKey) → layer:\(layer)")
        } else {
            viewModel.statusMessage = "Failed to save"
            viewModel.statusIsError = true
        }
    }

    /// Dialog for creating a new layer
    var newLayerDialogContent: some View {
        VStack(spacing: 16) {
            Text("Create New Layer")
                .font(.headline)

            TextField("Layer name", text: $newLayerName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityIdentifier("overlay-layer-dialog-name")

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingNewLayerDialog = false
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("overlay-layer-dialog-cancel")

                Button("Create") {
                    if !newLayerName.isEmpty {
                        viewModel.createLayer(newLayerName)
                        showingNewLayerDialog = false
                        // Select the new layer
                        Task {
                            await viewModel.refreshAvailableLayers()
                            selectLayerOutput(newLayerName.lowercased())
                        }
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newLayerName.isEmpty)
                .accessibilityIdentifier("overlay-layer-dialog-create")
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    /// Open file picker to choose an app for the output action
    func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app to launch when this key is pressed"

        if panel.runModal() == .OK, let url = panel.url {
            let displayName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            viewModel.selectedApp = AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
            isSystemActionPickerOpen = false
        }
    }

    @ViewBuilder
    func systemActionGroupView(_ group: SystemActionGroup) -> some View {
        // Section header
        HStack {
            Text(group.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)

        // 3-column grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(group.actions) { action in
                systemActionButton(action)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    func systemActionButton(_ action: SystemActionInfo) -> some View {
        let isSelected = viewModel.selectedSystemAction?.id == action.id
        Button {
            // Use the proper method which handles auto-save
            viewModel.selectSystemAction(action)
            isSystemActionPickerOpen = false
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: action.sfSymbol)
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                Text(action.name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityIdentifier("system-action-\(action.id)")
    }

    var shouldShowHealthGate: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return false
    }

    var healthGateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text(healthGateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(healthGateMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onHealthTap) {
                Text(healthGateButtonTitle)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("overlay-mapper-fix-issues")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(isDark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var healthGateTitle: String {
        switch healthIndicatorState {
        case .checking:
            "System Not Ready"
        case let .unhealthy(issueCount):
            issueCount == 1 ? "1 Issue Found" : "\(issueCount) Issues Found"
        case .healthy, .dismissed:
            "System Ready"
        }
    }

    private var healthGateMessage: String {
        switch healthIndicatorState {
        case .checking:
            "Checking system health before enabling the mapper."
        case let .unhealthy(issueCount):
            issueCount == 1
                ? "Fix the issue to enable quick remapping in the drawer."
                : "Fix the issues to enable quick remapping in the drawer."
        case .healthy, .dismissed:
            "System health is good."
        }
    }

    private var healthGateButtonTitle: String {
        switch healthIndicatorState {
        case .checking:
            "Open Setup"
        case .unhealthy:
            "Fix Issues"
        case .healthy, .dismissed:
            "Open Setup"
        }
    }
}
