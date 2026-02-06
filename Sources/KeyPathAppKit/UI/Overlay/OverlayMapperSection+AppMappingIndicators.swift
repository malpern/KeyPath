import AppKit
import KeyPathCore
import SwiftUI

extension OverlayMapperSection {
    // MARK: - App-Specific Mapping Indicators

    /// Shows small app icons for apps that have mappings for the currently selected key
    /// Uses a fixed height to prevent layout shifting
    var appMappingIndicators: some View {
        // Fixed height container to prevent layout shifts
        ZStack(alignment: .topLeading) {
            // Invisible spacer to reserve height (one row of 16px icons + padding)
            Color.clear.frame(height: 20)

            if !viewModel.appsWithCurrentKeyMapping.isEmpty,
               let keyCode = viewModel.inputKeyCode
            {
                let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
                FlowLayout(spacing: 4) {
                    ForEach(viewModel.appsWithCurrentKeyMapping) { appKeymap in
                        appMappingIcon(for: appKeymap, inputKey: inputKey)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Individual app icon button for the mapping indicators
    func appMappingIcon(for appKeymap: AppKeymap, inputKey: String) -> some View {
        let bundleId = appKeymap.mapping.bundleIdentifier
        let displayName = appKeymap.mapping.displayName
        let mapping = appKeymap.overrides.first { $0.inputKey.lowercased() == inputKey.lowercased() }
        let output = mapping?.outputAction ?? "?"
        let tooltip = "\(displayName): \(inputKey) → \(output)"

        return Button {
            selectAppFromIndicator(appKeymap)
        } label: {
            if let icon = AppIconResolver.icon(forBundleIdentifier: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityIdentifier("app-mapping-indicator-\(bundleId)")
    }

    /// Handle tap on an app mapping indicator - switches to that app's context
    func selectAppFromIndicator(_ appKeymap: AppKeymap) {
        let bundleId = appKeymap.mapping.bundleIdentifier
        let displayName = appKeymap.mapping.displayName

        // Get icon using existing resolver
        let icon = AppIconResolver.icon(forBundleIdentifier: bundleId)
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: displayName)!

        // Create AppConditionInfo and set on view model
        viewModel.selectedAppCondition = AppConditionInfo(
            bundleIdentifier: bundleId,
            displayName: displayName,
            icon: icon
        )

        // Find the override for this input key and update output display
        if let keyCode = viewModel.inputKeyCode {
            let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
            if let override = appKeymap.overrides.first(where: { $0.inputKey.lowercased() == inputKey.lowercased() }) {
                viewModel.outputLabel = KeyDisplayFormatter.format(override.outputAction)
            }
        }
    }

    var everywhereOption: some View {
        Button {
            viewModel.selectedAppCondition = nil
            isAppConditionPickerOpen = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.selectedAppCondition == nil ? "checkmark" : "globe")
                    .font(.title2)
                    .frame(width: 28)
                    .opacity(viewModel.selectedAppCondition == nil ? 1 : 0.6)
                Text("Everywhere")
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
    }

    var onlyInHeader: some View {
        HStack {
            Text("Only in...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    var runningAppsList: some View {
        if cachedRunningApps.isEmpty {
            HStack {
                Spacer()
                Text("No apps running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
        } else {
            ForEach(cachedRunningApps, id: \.processIdentifier) { app in
                runningAppButton(for: app)
            }
        }
    }

    func runningAppButton(for app: NSRunningApplication) -> some View {
        Button {
            selectRunningApp(app)
        } label: {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app")
                        .font(.title3)
                        .frame(width: 24, height: 24)
                }
                Text(app.localizedName ?? "Unknown")
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                if viewModel.selectedAppCondition?.bundleIdentifier == app.bundleIdentifier {
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
        .accessibilityIdentifier("overlay-mapper-running-app-\(app.bundleIdentifier ?? "pid-\(app.processIdentifier)")")
        .accessibilityLabel(app.localizedName ?? "Unknown app")
    }

    func selectRunningApp(_ app: NSRunningApplication) {
        if let bundleId = app.bundleIdentifier,
           let name = app.localizedName
        {
            let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
            viewModel.selectedAppCondition = AppConditionInfo(
                bundleIdentifier: bundleId,
                displayName: name,
                icon: icon
            )
        }
        isAppConditionPickerOpen = false
    }

    var chooseAppOption: some View {
        Button {
            isAppConditionPickerOpen = false
            pickAppForCondition()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.title3)
                    .frame(width: 28)
                Text("Choose App...")
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .focusable(false)
    }

    /// Clear all behavior slots for the current key (tap, hold, combo)
    func clearAllBehaviorsForCurrentKey() {
        // Clear tap (remove any app/system/URL mapping)
        viewModel.revertToKeystroke()

        // Clear all advanced behaviors (hold, multi-tap, timing, etc.)
        viewModel.advancedBehavior.reset()

        // Update UI state
        updateConfiguredBehaviorSlots()
        onKeySelected?(nil)
        SoundPlayer.shared.playSuccessSound()
    }

    /// Perform the actual reset of entire keyboard to defaults, including app-specific rules
    func performResetAll() {
        guard let manager = kanataViewModel?.underlyingManager else { return }
        Task {
            // Reset custom key mappings on all layers
            await viewModel.resetAllToDefaults(kanataManager: manager)

            // Also delete ALL app-specific rules
            do {
                let keymaps = await AppKeymapStore.shared.loadKeymaps()
                for keymap in keymaps {
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                }

                // Regenerate config and restart Kanata if we deleted any app rules
                if !keymaps.isEmpty {
                    try await AppConfigGenerator.regenerateFromStore()
                    await AppContextService.shared.reloadMappings()
                    _ = await manager.restartKanata(reason: "All app rules reset")
                }
            } catch {
                AppLogger.shared.log("⚠️ [OverlayMapper] Failed to clear app rules: \(error)")
            }

            // Update UI state on main thread
            await MainActor.run {
                updateConfiguredBehaviorSlots()
            }

            // Play success sound after reset completes
            SoundPlayer.shared.playSuccessSound()
        }
        onKeySelected?(nil)
        // Also update immediately for responsiveness
        updateConfiguredBehaviorSlots()
    }

    /// Open file picker for app condition
    func pickAppForCondition() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app for this rule to apply only when it's active"

        if panel.runModal() == .OK, let url = panel.url {
            let displayName = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let bundleId = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            viewModel.selectedAppCondition = AppConditionInfo(bundleIdentifier: bundleId, displayName: displayName, icon: icon)
        }
    }

    /// Toggle recording for the currently selected behavior slot
    func toggleRecordingForCurrentSlot() {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.toggleOutputRecording()
        case .hold:
            viewModel.toggleHoldRecording()
        case .combo:
            viewModel.toggleComboOutputRecording()
        }
    }

    /// Clear the action for the currently selected behavior slot
    func clearCurrentSlot() {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.revertToKeystroke()
        case .hold:
            viewModel.advancedBehavior.holdAction = ""
        case .combo:
            viewModel.advancedBehavior.comboKeys = []
            viewModel.advancedBehavior.comboOutput = ""
        }
        updateConfiguredBehaviorSlots()
        SoundPlayer.shared.playSuccessSound()
    }

    /// Update which behavior slots have actions configured
    func updateConfiguredBehaviorSlots() {
        var slots: Set<BehaviorSlot> = []

        // Check tap slot
        let tapHasAction = viewModel.selectedApp != nil ||
            viewModel.selectedSystemAction != nil ||
            viewModel.selectedURL != nil ||
            viewModel.outputLabel.lowercased() != viewModel.inputLabel.lowercased() ||
            hasMultiTapConfigured
        if tapHasAction {
            slots.insert(.tap)
        }

        // Check hold slot
        if !viewModel.holdAction.isEmpty {
            slots.insert(.hold)
        }

        // Check combo slot
        if viewModel.advancedBehavior.hasValidCombo {
            slots.insert(.combo)
        }

        configuredBehaviorSlots = slots
    }

    /// Play animation on the output keycap to demonstrate the selected behavior
    /// Choreography: For non-tap slots, label fades in first, then keycap bounces
    func playBehaviorAnimation(for slot: BehaviorSlot) {
        // Cancel any existing animation
        behaviorAnimationTask?.cancel()

        // Reset label state when switching slots
        showBehaviorLabel = false
        outputKeycapBounce = false

        behaviorAnimationTask = Task { @MainActor in
            switch slot {
            case .tap:
                // Single press animation - no label needed
                withAnimation(.easeIn(duration: 0.1)) {
                    outputKeycapScale = 0.88
                }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    outputKeycapScale = 1.0
                }

            case .hold:
                // Choreography: label first, then keycap animation
                withAnimation(.easeOut(duration: 0.12)) {
                    showBehaviorLabel = true
                }
                try? await Task.sleep(for: .milliseconds(80))
                // Bounce the keycap
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    outputKeycapBounce = true
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapBounce = false
                }
                // Then press-hold animation
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeIn(duration: 0.15)) {
                    outputKeycapScale = 0.85
                }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    outputKeycapScale = 1.0
                }

            case .combo:
                // Choreography: label first, then keycap animation
                withAnimation(.easeOut(duration: 0.12)) {
                    showBehaviorLabel = true
                }
                try? await Task.sleep(for: .milliseconds(80))
                // Bounce the keycap
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    outputKeycapBounce = true
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapBounce = false
                }
                // Combo animation: two quick simultaneous presses
                try? await Task.sleep(for: .milliseconds(100))
                // Simulate pressing multiple keys together
                withAnimation(.easeIn(duration: 0.1)) {
                    outputKeycapScale = 0.85
                }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    outputKeycapScale = 1.05
                }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    outputKeycapScale = 1.0
                }
            }
        }
    }

    // Output type dropdown - select what happens when the key is triggered
}
