import AppKit
import KeyPathCore
import SwiftUI

extension OverlayMapperSection {
    var bodyView: some View {
        let base = VStack(spacing: 8) {
            if shouldShowHealthGate {
                healthGateContent
            } else {
                mapperContent
            }
        }

        let withAppear = base.onAppear {
            refreshInstalledPacks()
            guard !shouldShowHealthGate, let kanataViewModel else { return }
            viewModel.configure(kanataManager: kanataViewModel.underlyingManager)
            viewModel.setLayer(kanataViewModel.currentLayerName)
            let defaultKeyCode: UInt16 = 0
            let layerInfo = layerKeyMap[defaultKeyCode]
            let inputLabel = "a"
            let outputLabel = layerInfo?.displayLabel ?? "a"
            viewModel.setInputFromKeyClick(
                keyCode: defaultKeyCode,
                inputLabel: inputLabel,
                outputLabel: outputLabel,
                appIdentifier: layerInfo?.appLaunchIdentifier,
                systemActionIdentifier: layerInfo?.systemActionIdentifier,
                urlIdentifier: layerInfo?.urlIdentifier
            )
            viewModel.loadBehaviorFromExistingRule(kanataManager: kanataViewModel.underlyingManager)
            onKeySelected?(viewModel.inputKeyCode)
            updateConfiguredBehaviorSlots()
        }

        let withPackChanges = withAppear.onReceive(
            NotificationCenter.default.publisher(for: .installedPacksChanged)
        ) { _ in
            refreshInstalledPacks()
        }

        let withDisappear = withPackChanges.onDisappear {
            viewModel.stopKeyCapture()
        }

        let withExit = withDisappear.onExitCommand {
            if isAnyRecordingActive {
                cancelAllRecording()
            }
        }

        let withInputChange = withExit.onChange(of: viewModel.inputKeyCode) { _, newKeyCode in
            onKeySelected?(newKeyCode)
            selectedBehaviorSlot = .tap
            selectedTapOutputMode = .default
            selectedTapCount = 1
            updateConfiguredBehaviorSlots()
        }

        let withLayerChange = withInputChange.onReceive(
            NotificationCenter.default.publisher(for: .kanataLayerChanged)
        ) { notification in
            if let layerName = notification.userInfo?["layerName"] as? String {
                viewModel.setLayer(layerName)
            }
        }

        let withDrawerSelection = withLayerChange.onReceive(
            NotificationCenter.default.publisher(for: .mapperDrawerKeySelected)
        ) { notification in
            handleDrawerKeySelection(notification)
        }

        let withOpenAppConditionPicker = withDrawerSelection.onReceive(
            NotificationCenter.default.publisher(for: .openMapperAppConditionPicker)
        ) { _ in
            guard !shouldShowHealthGate else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isAppConditionPickerOpen = true
            }
        }

        let withSetAppCondition = withOpenAppConditionPicker.onReceive(
            NotificationCenter.default.publisher(for: .mapperSetAppCondition)
        ) { notification in
            handleSetAppCondition(notification)
        }

        let withAutoSave = withSetAppCondition.onChange(of: viewModel.isRecordingOutput) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard !shouldShowHealthGate else { return }

            let hasOutputAction = viewModel.selectedApp != nil ||
                viewModel.selectedSystemAction != nil ||
                viewModel.selectedURL != nil
            let hasKeyRemapping = viewModel.inputLabel.lowercased() != viewModel.outputLabel.lowercased()

            guard hasOutputAction || hasKeyRemapping else { return }
            autosaveCurrentMapping()
        }

        let withShiftAutoSave = withAutoSave.onChange(of: viewModel.isRecordingShiftedOutput) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard !shouldShowHealthGate else { return }
            guard viewModel.hasShiftedOutputConfigured else { return }
            autosaveCurrentMapping()
        }

        let withDoubleTapAutoSave = withShiftAutoSave.onChange(of: viewModel.isRecordingDoubleTap) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard !shouldShowHealthGate else { return }
            guard !viewModel.doubleTapAction.isEmpty else { return }
            autosaveCurrentMapping()
        }

        let withHoldAutoSave = withDoubleTapAutoSave.onChange(of: viewModel.isRecordingHold) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            guard !shouldShowHealthGate else { return }
            guard !viewModel.holdAction.isEmpty else { return }
            autosaveCurrentMapping()
        }

        let withOutputChange = withHoldAutoSave.onChange(of: viewModel.outputLabel) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withShiftedOutputChange = withOutputChange.onChange(of: viewModel.shiftedOutputLabel) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withHoldChange = withShiftedOutputChange.onChange(of: viewModel.holdAction) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withDoubleTapChange = withHoldChange.onChange(of: viewModel.doubleTapAction) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withTapDanceChange = withDoubleTapChange.onChange(of: viewModel.tapDanceSteps.map(\.action)) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withAppChange = withTapDanceChange.onChange(of: viewModel.selectedApp?.name) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withSystemChange = withAppChange.onChange(of: viewModel.selectedSystemAction?.id) { _, _ in
            updateConfiguredBehaviorSlots()
        }

        let withShiftAvailability = withSystemChange.onChange(of: viewModel.canUseShiftedOutput) { _, canUse in
            if !canUse {
                if selectedTapOutputMode == .shifted {
                    selectedTapOutputMode = .default
                }
                if selectedBehaviorSlot == .shift {
                    selectedBehaviorSlot = .tap
                }
            }
        }

        let withSlotChange = withShiftAvailability.onChange(of: selectedBehaviorSlot) { _, newSlot in
            selectedTapOutputMode = newSlot == .shift ? .shifted : .default
            if newSlot != .tap { selectedTapCount = 1 }
            playBehaviorAnimation(for: newSlot)
        }

        let withTapModeChange = withSlotChange.onChange(of: selectedTapOutputMode) { _, newMode in
            if newMode == .shifted, viewModel.isRecordingOutput {
                viewModel.stopRecording()
            } else if newMode == .default, viewModel.isRecordingShiftedOutput {
                viewModel.stopRecording()
            }
        }

        let withTapCountChange = withTapModeChange.onChange(of: selectedTapCount) { _, newCount in
            if newCount > 1 {
                playBehaviorAnimation(for: .tap)
            }
        }

        let withResetDialog = withTapCountChange.confirmationDialog(
            "Clear Mapping",
            isPresented: $showingResetDialog,
            titleVisibility: .visible
        ) {
            if selectedBehaviorSlot != .tap, currentSlotIsConfigured {
                Button("Clear \(selectedBehaviorSlot.label) Only") {
                    clearCurrentSlot()
                }
                .accessibilityIdentifier("overlay-mapper-reset-slot-button")
            }

            Button("Clear All for \"\(viewModel.inputLabel.uppercased())\"") {
                clearAllBehaviorsForCurrentKey()
            }
            .accessibilityIdentifier("overlay-mapper-reset-key-button")

            Button("Clear All Custom Mappings", role: .destructive) {
                performResetAll()
            }
            .accessibilityIdentifier("overlay-mapper-reset-all-button")

            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-mapper-reset-cancel-button")
        } message: {
            if selectedBehaviorSlot != .tap, currentSlotIsConfigured {
                Text("What would you like to clear?")
            } else {
                Text("Choose what to clear for \"\(viewModel.inputLabel.uppercased())\"")
            }
        }

        let selectedKeyInfo: LayerKeyInfo? = viewModel.inputKeyCode.flatMap { layerKeyMap[$0] }
        let withLayerMapRefresh = withResetDialog.onChange(of: selectedKeyInfo) { _, newInfo in
            refreshFromLayerMap(newInfo)
        }

        let withURLSheet = withLayerMapRefresh.sheet(isPresented: $viewModel.showingURLDialog) {
            URLInputDialog(
                urlText: $viewModel.urlInputText,
                onSubmit: { viewModel.submitURL() },
                onCancel: { viewModel.showingURLDialog = false }
            )
        }

        return withURLSheet.sheet(isPresented: $showingAppPickerSheet) {
            let vm = viewModel
            AppConditionPickerSheet(
                onSelect: { condition in
                    vm.selectedAppCondition = condition
                },
                onBrowse: {
                    pickAppForCondition()
                }
            )
        }
    }

    private func refreshInstalledPacks() {
        Task {
            let records = await InstalledPackTracker.shared.allInstalled()
            installedPackIDs = Set(records.map(\.packID))
        }
    }

    private func autosaveCurrentMapping() {
        guard let manager = kanataViewModel?.underlyingManager else { return }
        Task {
            await viewModel.save(kanataManager: manager)
            updateConfiguredBehaviorSlots()
        }
    }

    private func handleDrawerKeySelection(_ notification: Notification) {
        guard !shouldShowHealthGate else { return }
        guard let keyCode = notification.userInfo?["keyCode"] as? UInt16,
              let inputKey = notification.userInfo?["inputKey"] as? String,
              let outputKey = notification.userInfo?["outputKey"] as? String
        else { return }

        let appId = notification.userInfo?["appIdentifier"] as? String
        let systemId = notification.userInfo?["systemActionIdentifier"] as? String
        let urlId = notification.userInfo?["urlIdentifier"] as? String
        let shiftedOutputKey = notification.userInfo?["shiftedOutputKey"] as? String
        let displayLabel = notification.userInfo?["displayLabel"] as? String

        viewModel.setInputFromKeyClick(
            keyCode: keyCode,
            inputLabel: inputKey,
            outputLabel: outputKey,
            appIdentifier: appId,
            systemActionIdentifier: systemId,
            urlIdentifier: urlId,
            shiftedOutputKey: shiftedOutputKey
        )

        if let displayLabel, displayLabel != outputKey {
            viewModel.outputLabel = viewModel.formatKeyForDisplay(displayLabel)
        }
        selectedTapOutputMode = shiftedOutputKey == nil ? .default : .shifted

        if let manager = kanataViewModel?.underlyingManager {
            viewModel.loadBehaviorFromExistingRule(kanataManager: manager)
        }

        if let bundleId = notification.userInfo?["appBundleId"] as? String,
           let displayName = notification.userInfo?["appDisplayName"] as? String
        {
            viewModel.selectedAppCondition = AppConditionInfo(
                bundleIdentifier: bundleId,
                displayName: displayName,
                icon: appIcon(bundleIdentifier: bundleId)
            )
        }
    }

    private func handleSetAppCondition(_ notification: Notification) {
        guard !shouldShowHealthGate else { return }
        guard let bundleId = notification.userInfo?["bundleId"] as? String,
              let displayName = notification.userInfo?["displayName"] as? String
        else { return }

        viewModel.selectedAppCondition = AppConditionInfo(
            bundleIdentifier: bundleId,
            displayName: displayName,
            icon: appIcon(bundleIdentifier: bundleId)
        )
        viewModel.resetForNewMapping()
    }

    private func appIcon(bundleIdentifier: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 24, height: 24)
            return icon
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }

    private func refreshFromLayerMap(_ newInfo: LayerKeyInfo?) {
        guard let keyCode = viewModel.inputKeyCode, let newInfo else { return }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        let outputKey = newInfo.outputKey ?? newInfo.displayLabel
        guard !outputKey.isEmpty else { return }
        viewModel.setInputFromKeyClick(
            keyCode: keyCode,
            inputLabel: inputKey,
            outputLabel: outputKey,
            appIdentifier: newInfo.appLaunchIdentifier,
            systemActionIdentifier: newInfo.systemActionIdentifier,
            urlIdentifier: newInfo.urlIdentifier
        )
        if !newInfo.displayLabel.isEmpty, newInfo.displayLabel != outputKey {
            viewModel.outputLabel = viewModel.formatKeyForDisplay(newInfo.displayLabel)
        }
        if let manager = kanataViewModel?.underlyingManager {
            viewModel.loadBehaviorFromExistingRule(kanataManager: manager)
        }
    }
}
