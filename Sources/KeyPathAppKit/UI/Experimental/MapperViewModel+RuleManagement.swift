import AppKit
import Foundation
import KeyPathCore
import KeyPathRulesCore

// MARK: - Rule Management (Save / Clear / Reset / App Pick)

extension MapperViewModel {
    func save(kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = inputSequence,
              let outputSeq = outputSequence,
              !inputSeq.isEmpty,
              !outputSeq.isEmpty
        else {
            statusMessage = "Capture both input and output first"
            statusIsError = true
            return
        }

        // Skip identity mappings (A→A) - no point in saving a rule that does nothing
        // Also skip if user hasn't changed anything from defaults
        // Exception: device-scoped mappings ARE identity for the default case but have overrides
        let inputKey = convertSequenceToKanataFormat(inputSeq).lowercased()
        let outputKey = convertSequenceToKanataFormat(outputSeq).lowercased()
        let hasAdvancedBehavior = advancedBehavior.hasAdvancedConfig
        let hasShiftedOutput = canUseShiftedOutput && currentShiftedOutputKanataString() != nil
        let hasDeviceCondition = selectedDeviceCondition != nil
        if inputKey == outputKey,
           selectedApp == nil,
           selectedSystemAction == nil,
           selectedURL == nil,
           !hasAdvancedBehavior,
           !hasShiftedOutput,
           !hasDeviceCondition
        {
            statusMessage = "Nothing to save - input and output are the same"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        // Check if this is an app-specific mapping
        if let appCondition = selectedAppCondition {
            let inputKanata = convertSequenceToKanataFormat(inputSeq)
            let outputKanata = convertSequenceToKanataFormat(outputSeq)

            let success = await saveAppSpecificMapping(
                inputKey: inputKanata,
                outputAction: outputKanata,
                appCondition: appCondition,
                kanataManager: kanataManager
            )

            if success {
                showTransientStatus("✓ Saved")
                SoundPlayer.shared.playSuccessSound()
                AppLogger.shared.log("✅ [MapperViewModel] Saved app-specific mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [only in \(appCondition.displayName)]")
            } else {
                statusMessage = "Failed to save app-specific rule"
                statusIsError = true
            }

            isSaving = false
            return
        }

        // Global mapping — save as CustomRule and let regenerateConfigFromCollections
        // build the full kanata config (handles forks, tap-hold, tap-dance, chords, macros, etc.)
        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let outputKanata = convertSequenceToKanataFormat(outputSeq)
        let shiftedOutputKanata = canUseShiftedOutput ? currentShiftedOutputKanataString() : nil

        // Convert currentLayer string to RuleCollectionLayer
        let targetLayer = layerFromString(currentLayer)

        // Use makeCustomRule to reuse existing rule ID for the same input key
        // This prevents duplicate keys in defsrc which causes Kanata validation errors
        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: outputKanata)
        customRule.notes = "Created via Mapper [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer
        customRule.shiftedOutput = shiftedOutputKanata

        // Add behavior based on configured actions
        // Priority: macro → chord → dualRole → tap-dance
        // (UI should prevent conflicting behaviors from being set simultaneously)
        if let macroBehavior, macroBehavior.isValid {
            customRule.behavior = .macro(macroBehavior)
            AppLogger.shared.log("💾 [MapperViewModel] Adding macro behavior")
        } else if advancedBehavior.hasValidCombo {
            var allKeys = [inputKanata]
            allKeys.append(contentsOf: advancedBehavior.comboKeys)
            let chord = ChordBehavior(
                keys: allKeys,
                output: KanataBehaviorRenderer.parseActionString(advancedBehavior.comboOutput),
                timeout: advancedBehavior.comboTimeout
            )
            customRule.behavior = .chord(chord)
            AppLogger.shared.log("💾 [MapperViewModel] Adding chord behavior: keys=\(allKeys), output='\(chord.outputString)'")
        } else if !holdAction.isEmpty {
            let dualRole = DualRoleBehavior(
                tapAction: KanataBehaviorRenderer.parseActionString(outputKanata),
                holdAction: KanataBehaviorRenderer.parseActionString(holdAction),
                tapTimeout: tapTimeout,
                holdTimeout: holdTimeout,
                activateHoldOnOtherKey: holdBehavior == .triggerEarly,
                quickTap: holdBehavior == .quickTap,
                customTapKeys: holdBehavior == .customKeys ? customTapKeysText.split(separator: " ").map(String.init) : []
            )
            customRule.behavior = .dualRole(dualRole)
            AppLogger.shared.log("💾 [MapperViewModel] Adding dualRole behavior: tap='\(outputKanata)', hold='\(holdAction)'")
        } else if !doubleTapAction.isEmpty || tapDanceSteps.contains(where: { !$0.action.isEmpty }) {
            var steps = [
                TapDanceStep(label: "Single tap", action: KanataBehaviorRenderer.parseActionString(outputKanata)),
                TapDanceStep(label: "Double tap", action: KanataBehaviorRenderer.parseActionString(doubleTapAction))
            ]
            for step in advancedBehavior.tapDanceSteps where !step.action.isEmpty {
                steps.append(TapDanceStep(label: step.label, action: KanataBehaviorRenderer.parseActionString(step.action)))
            }
            let tapDance = TapDanceBehavior(windowMs: tapTimeout, steps: steps)
            customRule.behavior = .tapOrTapDance(.tapDance(tapDance))
            AppLogger.shared.log("💾 [MapperViewModel] Adding tapDance behavior: \(steps.count) steps")
        }

        // Apply device condition: scoped output goes into deviceOverrides,
        // default output becomes identity (pass-through for other devices)
        if let deviceCondition = selectedDeviceCondition {
            let overrideAction = customRule.action
            customRule.deviceOverrides = [
                DeviceKeyOverride(
                    deviceHash: deviceCondition.deviceHash,
                    output: overrideAction,
                    behavior: customRule.behavior
                )
            ]
            customRule.action = .keystroke(key: inputKanata)
            customRule.behavior = nil
        }

        let customRuleSaved = await kanataManager.saveCustomRule(customRule, skipReload: false, autoResolveConflicts: true)
        AppLogger.shared.log("💾 [MapperViewModel] saveCustomRule returned: \(customRuleSaved)")

        if customRuleSaved {
            lastSavedRuleID = customRule.id
            showTransientStatus("✓ Saved")
            AppLogger.shared.log("✅ [MapperViewModel] Saved mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [layer: \(currentLayer)] (ruleID: \(customRule.id))")
        } else {
            statusMessage = "Rule save failed — config could not be applied"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false for input='\(inputKanata)', output='\(outputKanata)'")
        }

        isSaving = false
    }

    func reset() {
        inputLabel = "A"
        outputLabel = "A"
        clearShiftedOutput()
        inputKeyCode = 0 // Default to A key
        // Reset to default A key sequences so save works without capturing input first
        inputSequence = Self.defaultAKeySequence
        outputSequence = Self.defaultAKeySequence
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        selectedAppCondition = nil
        selectedDeviceCondition = nil
        statusMessage = nil
        // Reset all advanced behavior settings
        advancedBehavior.reset()
    }

    /// Reset for a new mapping but preserve selectedAppCondition
    /// Used when adding a new rule to a specific app
    func resetForNewMapping() {
        inputLabel = "A"
        outputLabel = "A"
        clearShiftedOutput()
        inputKeyCode = 0 // Default to A key
        inputSequence = Self.defaultAKeySequence
        outputSequence = Self.defaultAKeySequence
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        // Keep selectedAppCondition - don't reset it
        statusMessage = nil
    }

    /// Clear all values, delete the saved rule, and reset to original key context (or default)
    func clear() {
        stopRecording()
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil

        // Delete the saved rule if we have one, otherwise try to resolve by input
        if let manager = kanataManager {
            if let ruleID = lastSavedRuleID {
                Task {
                    await manager.removeCustomRule(withID: ruleID)
                    // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
                    AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule \(ruleID)")
                }
                lastSavedRuleID = nil
            } else if let inputKanata = currentInputKanataString() {
                // Use makeCustomRule to reuse existing rule ID for this input (if any)
                let probeRule = manager.makeCustomRule(input: inputKanata, output: "xx")
                Task {
                    await manager.removeCustomRule(withID: probeRule.id)
                    AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule by input \(inputKanata) (id: \(probeRule.id))")
                }
            }
        }

        // Reset to original key context if opened from overlay, otherwise default
        if let origInput = originalInputKey, let origOutput = originalOutputKey {
            // Re-apply the original presets
            inputLabel = formatKeyForDisplay(origInput)
            inputSequence = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )

            if let appIdentifier = originalAppIdentifier,
               let appInfo = appLaunchInfo(for: appIdentifier)
            {
                selectedApp = appInfo
                outputLabel = appInfo.name
                outputSequence = nil
            } else if let url = originalURL {
                selectedURL = url
                outputLabel = extractDomain(from: url)
                outputSequence = nil
            } else if let systemActionId = originalSystemActionIdentifier,
                      let systemAction = SystemActionInfo.find(byOutput: systemActionId)
            {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
            } else if let systemAction = SystemActionInfo.find(byOutput: origOutput) {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
            } else {
                outputLabel = formatKeyForDisplay(origOutput)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: origOutput, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
            }
            applyShiftedOutputPreset(originalShiftedOutputKey)

            statusMessage = nil
            AppLogger.shared.log("🧹 [MapperViewModel] Reset to original key: \(origInput) → \(origOutput)")
        } else {
            // No context - reset to default
            reset()
            AppLogger.shared.log("🧹 [MapperViewModel] Cleared mapping (no key context)")
        }
    }

    /// Revert to keystroke mode - clears any actions and resets output to match input
    /// Used when switching from system action/app/URL back to plain keystroke
    func revertToKeystroke() {
        stopRecording()

        // Clear all actions
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        selectedFolder = nil
        selectedScript = nil
        clearShiftedOutput()

        // Reset output to match input (identity mapping: A→A)
        outputLabel = inputLabel
        outputSequence = inputSequence

        // Delete the saved rule if we have one
        if let manager = kanataManager {
            if let ruleID = lastSavedRuleID {
                AppLogger.shared.log("🧹 [MapperViewModel] revertToKeystroke: deleting by lastSavedRuleID=\(ruleID)")
                Task {
                    await manager.removeCustomRule(withID: ruleID)
                    NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                    AppLogger.shared.log("🧹 [MapperViewModel] Reverted to keystroke, deleted rule \(ruleID)")
                }
                lastSavedRuleID = nil
            } else if let inputKanata = currentInputKanataString() {
                AppLogger.shared.log("🧹 [MapperViewModel] revertToKeystroke: no lastSavedRuleID, probing by input='\(inputKanata)'")
                let probeRule = manager.makeCustomRule(input: inputKanata, output: "xx")
                AppLogger.shared.log("🧹 [MapperViewModel] revertToKeystroke: probeRule.id=\(probeRule.id)")
                Task {
                    await manager.removeCustomRule(withID: probeRule.id)
                    NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                    AppLogger.shared.log("🧹 [MapperViewModel] Reverted to keystroke, deleted rule by input \(inputKanata)")
                }
            } else {
                AppLogger.shared.log("⚠️ [MapperViewModel] revertToKeystroke: no lastSavedRuleID and currentInputKanataString() is nil")
            }
        } else {
            AppLogger.shared.log("⚠️ [MapperViewModel] revertToKeystroke: kanataManager is nil — cannot delete rule")
        }

        statusMessage = "✓ Reverted to keystroke"
    }

    /// Reset entire keyboard by clearing all custom rules (preserves rule collections)
    func resetAllToDefaults(kanataManager: RuntimeCoordinator) async {
        stopRecording()

        // Clear all custom rules but preserve rule collections
        await kanataManager.clearAllCustomRules()

        // Reset local state
        reset()
        lastSavedRuleID = nil
        originalInputKey = nil
        originalOutputKey = nil
        originalShiftedOutputKey = nil
        originalLayer = nil
        currentLayer = "base"

        // Post notification to update keyboard
        NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

        statusMessage = "✓ Custom rules cleared"
        statusIsError = false
        AppLogger.shared.log("🔄 [MapperViewModel] Cleared all custom rules (collections preserved)")
    }

    /// Open file picker to select an app for launch action
    func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to launch"
        panel.prompt = "Select"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self?.handleSelectedApp(at: url)
            }
        }
    }

    func appLaunchInfo(for identifier: String) -> AppLaunchInfo? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
            return buildAppLaunchInfo(from: url)
        }

        // Fallback: treat identifier as an app name and look in common locations.
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(identifier).app"),
            URL(fileURLWithPath: "/System/Applications/\(identifier).app")
        ]

        for url in candidates where Foundation.FileManager().fileExists(atPath: url.path) {
            return buildAppLaunchInfo(from: url)
        }

        return nil
    }

    func buildAppLaunchInfo(from url: URL) -> AppLaunchInfo {
        let appName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64) // Reasonable size for display

        return AppLaunchInfo(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            icon: icon
        )
    }

    /// Process the selected app and update output
    func handleSelectedApp(at url: URL) {
        let appInfo = buildAppLaunchInfo(from: url)

        selectedApp = appInfo
        selectedSystemAction = nil // Clear any system action selection
        selectedURL = nil
        clearShiftedOutput()
        outputLabel = appInfo.name
        outputSequence = nil // Clear any key sequence output

        AppLogger.shared.log("📱 [MapperViewModel] Selected app: \(appInfo.name) (\(appInfo.bundleIdentifier ?? "no bundle ID"))")
        AppLogger.shared.log("📱 [MapperViewModel] kanataOutput will be: \(appInfo.kanataOutput)")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("📱 [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveAppLaunchMapping(kanataManager: manager)
            }
        } else {
            AppLogger.shared.log("📱 [MapperViewModel] Waiting for input to be recorded (inputSequence=\(inputSequence?.displayString ?? "nil"), manager=\(kanataManager != nil ? "set" : "nil"))")
        }
    }
}
