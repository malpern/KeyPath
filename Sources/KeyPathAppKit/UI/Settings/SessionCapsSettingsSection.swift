import Foundation
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

struct SessionCapsSettingsSection: View {
    @Environment(KanataViewModel.self) private var runtime
    @State private var device: SessionCapsMappingPolicy.DeviceIdentity?
    @State private var boot = ""
    @State private var reservesF18 = false
    @State private var automaticDisabled = UserDefaults.standard.bool(forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
            HStack(spacing: SettingsDesign.rowGap) {
                Image(systemName: "capslock").foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
                    HStack(spacing: 4) {
                        Text("Caps Lock remapping").font(.body.weight(.medium))
                        InfoTip("KeyPath uses F18 behind the scenes, so avoid using F18 for anything else.")
                    }
                    Text(statusText).font(.caption).foregroundStyle(statusIsWarning ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !automaticDisabled, device == nil, !busy {
                    Button("Check Again") { Task { await reviewKeyboard() } }
                        .settingsAction()
                        .accessibilityIdentifier("settings-caps-check-again")
                }
                Toggle("Caps Lock remapping", isOn: Binding(
                    get: { !automaticDisabled },
                    set: { enabled in Task { await setEnabled(enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(busy)
                .accessibilityIdentifier("settings-caps-toggle")
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await reviewKeyboard() }
    }

    private var rulesUseCaps: Bool {
        Self.rulesUseCapsLock(collections: runtime.ruleCollections, customRules: runtime.customRules)
    }

    private var statusText: String {
        if automaticDisabled {
            return rulesUseCaps ? "Off \u{00B7} Rules that use Caps Lock won\u{2019}t run" : "Off"
        }
        guard let device else { return "Connect one compatible keyboard" }
        return "On \u{00B7} " + (device.appleBuiltIn == true ? "Built-in keyboard" : "Your keyboard")
    }

    private var statusIsWarning: Bool {
        (automaticDisabled && rulesUseCaps) || (!automaticDisabled && device == nil && !busy)
    }

    static func rulesUseCapsLock(collections: [RuleCollection], customRules: [CustomRule]) -> Bool {
        let names: Set = ["caps", "capslock", "caps_lock"]
        let inCollections = collections.contains { collection in
            guard collection.isEnabled else { return false }
            if case let .tapHoldPicker(config) = collection.configuration, names.contains(config.inputKey.lowercased()) {
                return true
            }
            return collection.mappings.contains { names.contains($0.input.lowercased()) }
        }
        return inCollections || customRules.contains { $0.isEnabled && names.contains($0.input.lowercased()) }
    }

    /// On: allow automatic setup, saving this keyboard now when one is connected.
    /// Off: clear the saved keyboard and stop automatic setup (the former Disable).
    @MainActor
    private func setEnabled(_ enabled: Bool) async {
        message = nil
        if enabled, device == nil {
            UserDefaults.standard.set(false, forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
            automaticDisabled = false
            return
        }
        reservesF18 = enabled
        await applySelection(enabled: enabled)
        automaticDisabled = UserDefaults.standard.bool(forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
    }

    @MainActor
    private func reviewKeyboard() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let found = try await Task.detached {
                try (SessionCapsHIDUtilTransport.backend().enumerate(), SessionCapsRuntimeSupport.bootSessionUUID())
            }.value
            boot = found.1
            device = found.0.count == 1 ? found.0.first : nil
            let saved = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey)
                .flatMap { try? SessionCapsSelection.decode($0, currentBoot: boot) }
            reservesF18 = saved?.device == device
            message = nil
        } catch {
            device = nil
            message = "This keyboard could not be verified for Caps Lock setup. Profiles without Caps Lock rules can still run."
        }
    }

    @MainActor
    private func applySelection(enabled: Bool) async {
        guard !busy else { return }
        let selection: SessionCapsSelection?
        if enabled {
            guard let device, reservesF18 else { return }
            selection = SessionCapsSelection(device: device, bootSessionUUID: boot, reservesF18: true)
        } else { selection = nil }
        busy = true
        defer { busy = false }
        guard await runtime.setCapsSelection(selection, automaticSetupDisabled: !enabled) else {
            message = "Caps Lock setup could not be changed safely. Existing settings were kept. If the keyboard was disconnected, restart your Mac and try again."
            return
        }
        message = nil
    }
}
