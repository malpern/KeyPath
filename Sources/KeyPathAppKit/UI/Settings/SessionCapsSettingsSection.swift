import AppKit
import Foundation
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

struct SessionCapsSettingsSection: View {
    @Environment(KanataViewModel.self) private var runtime
    @State private var keyboards: [SessionCapsHIDUtilTransport.Keyboard] = []
    /// Connected keyboards that cannot be a Caps target; never offered.
    @State private var withheld = 0
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
                if !automaticDisabled, device == nil || showsPicker, !busy {
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
            if !automaticDisabled, showsPicker {
                Picker("Keyboard", selection: Binding(
                    get: { device?.registryEntryID },
                    set: { id in
                        guard let chosen = keyboards.first(where: { $0.id == id }) else { return }
                        Task { await choose(chosen.device) }
                    }
                )) {
                    if device == nil { Text("Choose a keyboard").tag(UInt64?.none) }
                    ForEach(keyboards) { keyboard in
                        Text(keyboard.name).tag(UInt64?.some(keyboard.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(busy)
                .padding(.leading, 20 + SettingsDesign.rowGap)
                .accessibilityIdentifier("settings-caps-keyboard-picker")
                .accessibilityHint("Caps Lock rules apply to the keyboard you choose")
            }
            if !automaticDisabled, withheld > 0 {
                Text(withheld == 1 ? "One connected keyboard can\u{2019}t be used for Caps Lock rules."
                    : "\(withheld) connected keyboards can\u{2019}t be used for Caps Lock rules.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await reviewKeyboard() }
        // Keyboards come and go while Settings is open; refresh on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await reviewKeyboard() }
        }
    }

    /// With a withheld keyboard present, even one eligible keyboard is an
    /// explicit choice, matching automatic setup.
    private var showsPicker: Bool {
        Self.showsPicker(keyboards: keyboards.count, withheld: withheld)
    }

    static func showsPicker(keyboards: Int, withheld: Int) -> Bool {
        keyboards > 1 || (withheld > 0 && keyboards > 0)
    }

    private var rulesUseCaps: Bool {
        Self.rulesUseCapsLock(collections: runtime.ruleCollections, customRules: runtime.customRules)
    }

    private var statusText: String {
        if automaticDisabled {
            return rulesUseCaps ? "Off \u{00B7} Rules that use Caps Lock won\u{2019}t run" : "Off"
        }
        guard let device else {
            if showsPicker { return "Choose which keyboard Caps Lock rules apply to" }
            return withheld > 0 ? "No connected keyboard can be used" : "Connect a compatible keyboard"
        }
        let name = keyboards.first(where: { $0.device == device })?.name
            ?? (device.appleBuiltIn == true ? "Built-in keyboard" : "Your keyboard")
        return "On \u{00B7} " + name
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
    private func reviewKeyboard(keepMessage: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let found = try await Task.detached {
                try (SessionCapsHIDUtilTransport.keyboards(), SessionCapsRuntimeSupport.bootSessionUUID())
            }.value
            boot = found.1
            keyboards = found.0.keyboards
            withheld = found.0.withheld
            let saved = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey)
                .flatMap { try? SessionCapsSelection.decode($0, currentBoot: boot) }
            device = Self.effectiveDevice(saved: saved?.device, connected: keyboards.map(\.device), withheld: withheld)
            reservesF18 = saved?.device == device
            if !keepMessage { message = nil }
        } catch {
            keyboards = []
            withheld = 0
            device = nil
            message = "This keyboard could not be verified for Caps Lock setup. Profiles without Caps Lock rules can still run."
        }
    }

    /// A saved choice wins while that instance is connected; otherwise one
    /// keyboard is used automatically and several need an explicit choice.
    static func effectiveDevice(saved: SessionCapsMappingPolicy.DeviceIdentity?,
                                connected: [SessionCapsMappingPolicy.DeviceIdentity],
                                withheld: Int = 0) -> SessionCapsMappingPolicy.DeviceIdentity?
    {
        if let saved, (try? SessionCapsMappingPolicy.requireUnique(saved, among: connected)) != nil { return saved }
        return connected.count == 1 && withheld == 0 ? connected.first : nil
    }

    @MainActor
    private func choose(_ chosen: SessionCapsMappingPolicy.DeviceIdentity) async {
        guard !busy, chosen != device || !reservesF18 else { return }
        let previous = (device, reservesF18)
        device = chosen
        reservesF18 = true
        message = nil
        await applySelection(enabled: true)
        if message != nil {
            (device, reservesF18) = previous
            message = "That keyboard could not be set up for Caps Lock. It may have been unplugged; check the list and try again. Existing settings were kept."
            await reviewKeyboard(keepMessage: true)
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
