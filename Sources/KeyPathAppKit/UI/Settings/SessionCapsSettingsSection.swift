import AppKit
import Combine
import Foundation
import KeyPathCore
import KeyPathRulesCore
import SwiftUI

/// Keyboard picks are never dropped. One made while Settings is busy waits
/// for that work, then applies; a later pick replaces an earlier waiting one.
struct SessionCapsChoiceQueue<Device: Equatable> {
    private(set) var pending: Device?

    /// The device to apply now, or nil when it was queued.
    mutating func submit(_ device: Device, busy: Bool) -> Device? {
        if busy {
            pending = device
            return nil
        }
        pending = nil
        return device
    }

    /// The waiting pick, once.
    mutating func takeAfterRefresh() -> Device? {
        defer { pending = nil }
        return pending
    }
}

struct SessionCapsSettingsSection: View {
    @Environment(KanataViewModel.self) private var runtime
    @State private var keyboards: [SessionCapsHIDUtilTransport.Keyboard] = []
    /// Connected keyboards that cannot be a Caps target; never offered.
    @State private var withheld = 0
    @State private var device: SessionCapsMappingPolicy.DeviceIdentity?
    @State private var boot = ""
    /// The saved selection's consent for `device`; nil until one is saved.
    @State private var saved: SessionCapsSelection?
    /// Another app's Caps mapping on the chosen keyboard, if any.
    @State private var conflict: SessionCapsConflict?
    @State private var fleetUncovered: [String] = []
    @State private var excludedIDs = SessionCapsRuntimeSupport.excludedKeyboardIDs()
    @State private var automaticDisabled = UserDefaults.standard.bool(forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
    @State private var selectedOnly = SessionCapsRuntimeSupport.selectedKeyboardOnly()
    @State private var showAdvanced = false
    @State private var choosingOneKeyboard = false
    @State private var busy = false
    @State private var message: String?
    /// The saved keyboard when it is no longer connected as that instance.
    @State private var disconnected: String?
    /// A pick made while the list was refreshing; applied after, never dropped.
    @State private var choices = SessionCapsChoiceQueue<SessionCapsMappingPolicy.DeviceIdentity>()
    /// A refresh asked for while one ran (an unplug and replug close together).
    @State private var refreshAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
            HStack(spacing: SettingsDesign.rowGap) {
                Image(systemName: "capslock").foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
                    HStack(spacing: 4) {
                        Text("Caps Lock rules").font(.body.weight(.medium))
                        InfoTip(reservedKeyTip)
                    }
                    Text(statusText).font(.caption).foregroundStyle(statusIsWarning ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !automaticDisabled, keyboards.isEmpty || withheld > 0 || conflict != nil || !fleetUncovered.isEmpty, !busy {
                    Button("Check Again") { Task { await reviewKeyboard() } }
                        .settingsAction()
                        .accessibilityIdentifier("settings-caps-check-again")
                }
            }
            DisclosureGroup("Caps Lock options", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: SettingsDesign.labelGap) {
                    if selectedOnly {
                        Button("Use Caps Lock rules on all keyboards") {
                            Task { await setSelectedOnly(false) }
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("settings-caps-use-all-keyboards")
                    } else if choosingOneKeyboard {
                        Button("Cancel choosing a keyboard") {
                            choosingOneKeyboard = false
                            message = nil
                        }
                        .accessibilityIdentifier("settings-caps-cancel-keyboard-choice")
                    } else {
                        ForEach(keyboards) { keyboard in
                            let id = SessionCapsRuntimeSupport.preferenceID(keyboard.device)
                            Toggle("Use on \(keyboard.name)", isOn: Binding(
                                get: { !excludedIDs.contains(id) },
                                set: { enabled in Task { await setKeyboardEnabled(id, enabled: enabled) } }
                            ))
                            .disabled(busy || automaticDisabled)
                            .accessibilityIdentifier("settings-caps-keyboard-\(keyboard.id)")
                        }
                        Button("Use on one keyboard only") {
                            Task { await setSelectedOnly(true) }
                        }
                        .disabled(busy || keyboards.isEmpty)
                        .accessibilityIdentifier("settings-caps-use-one-keyboard")
                    }

                    if selectedOnly || choosingOneKeyboard {
                        Picker("Keyboard", selection: Binding(
                            get: { choosingOneKeyboard ? nil : (choices.pending?.registryEntryID ?? device?.registryEntryID) },
                            set: { id in
                                guard let chosen = keyboards.first(where: { $0.id == id }) else { return }
                                Task { await choose(chosen.device) }
                            }
                        )) {
                            if device == nil || choosingOneKeyboard { Text("Choose a keyboard").tag(UInt64?.none) }
                            ForEach(keyboards) { keyboard in
                                Text(keyboard.name).tag(UInt64?.some(keyboard.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(busy)
                        .accessibilityIdentifier("settings-caps-keyboard-picker")
                        .accessibilityHint("Caps Lock rules apply to the keyboard you choose")
                    }

                    Toggle("Enable Caps Lock rules", isOn: Binding(
                        get: { !automaticDisabled },
                        set: { enabled in Task { await setEnabled(enabled) } }
                    ))
                    .disabled(busy)
                    .accessibilityIdentifier("settings-caps-toggle")
                }
                .padding(.leading, 20 + SettingsDesign.rowGap)
            }
            .accessibilityIdentifier("settings-caps-advanced")
            if !automaticDisabled, withheld > 0 {
                Text(withheld == 1 ? "One connected keyboard can\u{2019}t be used for Caps Lock rules."
                    : "\(withheld) connected keyboards can\u{2019}t be used for Caps Lock rules.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !automaticDisabled, let conflict {
                Text(conflict.message).font(.caption).foregroundStyle(.orange)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-caps-conflict")
            }
            if !automaticDisabled, !selectedOnly {
                ForEach(fleetUncovered, id: \.self) { detail in
                    Text(detail).font(.caption).foregroundStyle(.orange)
                        .padding(.leading, 20 + SettingsDesign.rowGap)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .padding(.leading, 20 + SettingsDesign.rowGap)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await reviewKeyboard()
            if rulesUseCaps, !automaticDisabled {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled, !busy { await reviewKeyboard() }
            }
        }
        // Keyboards come and go while Settings is open; refresh on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await reviewKeyboard() }
        }
        // ...and while it stays open: an unplugged keyboard must not keep
        // reading "On". hidutil can trail the HID notification slightly.
        .onReceive(NotificationCenter.default.publisher(for: .hidKeyboardConnected).merge(
            with: NotificationCenter.default.publisher(for: .hidKeyboardDisconnected)
        )) { _ in
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await reviewKeyboard()
                // The worker's next inventory check may follow the HID event.
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled, !busy { await reviewKeyboard() }
            }
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

    private var reservedKey: String {
        let stored = UInt32(exactly: UserDefaults.standard.integer(forKey: SessionCapsRuntimeSupport.allIntermediateKey))
        let usage = selectedOnly ? saved?.intermediateUsage : stored.flatMap { SessionCapsIntermediate.isCandidate($0) ? $0 : nil }
        return SessionCapsIntermediate.label(usage ?? SessionCapsIntermediate.defaultUsage)
    }

    private var reservedKeyTip: String {
        "KeyPath uses \(reservedKey) behind the scenes, so avoid using \(reservedKey) for anything else. "
            + "If one of your rules, another app, or a keyboard shortcut uses \(reservedKey), KeyPath switches to another key from F13 to F20."
    }

    private var rulesUseCaps: Bool {
        Self.rulesUseCapsLock(collections: runtime.ruleCollections, customRules: runtime.customRules)
    }

    private var statusText: String {
        if automaticDisabled {
            return rulesUseCaps ? "Off \u{00B7} Rules that use Caps Lock won\u{2019}t run" : "Off"
        }
        if !rulesUseCaps { return "Applies automatically when you add a Caps Lock rule" }
        if !selectedOnly {
            if keyboards.isEmpty {
                return "Caps Lock rules will apply when a compatible keyboard connects"
            }
            let participating = keyboards.count { !excludedIDs.contains(SessionCapsRuntimeSupport.preferenceID($0.device)) }
            let covered = max(0, participating - fleetUncovered.count)
            if participating == 0 {
                return "Caps Lock rules are off on every connected keyboard"
            }
            return fleetUncovered.isEmpty
                ? "On \u{00B7} \(participating == keyboards.count ? "all compatible keyboards" : "\(participating) selected keyboards") \u{00B7} Uses \(reservedKey) behind the scenes"
                : "Caps Lock active on \(covered) of \(participating) selected keyboards"
        }
        guard let device else {
            if let disconnected {
                return Self.disconnectedStatus(name: disconnected, listed: keyboards.map(\.name), showsPicker: showsPicker)
            }
            if showsPicker { return "Choose which keyboard Caps Lock rules apply to" }
            return withheld > 0 ? "No connected keyboard can be used" : "Connect a compatible keyboard"
        }
        let name = keyboards.first(where: { $0.device == device })?.name
            ?? (device.appleBuiltIn == true ? "Built-in keyboard" : "Your keyboard")
        return "On \u{00B7} " + name + (saved == nil ? "" : " \u{00B7} Uses \(reservedKey) behind the scenes")
    }

    private var statusIsWarning: Bool {
        guard rulesUseCaps else { return false }
        if automaticDisabled { return true }
        if busy { return false }
        if keyboards.isEmpty { return true }
        return selectedOnly ? (device == nil || conflict != nil) : !fleetUncovered.isEmpty
    }

    /// The saved keyboard is gone as that instance. Back at the same port it is
    /// re-bound automatically and never reaches here; listed under the same
    /// name means another port (or a twin), which needs choosing again.
    static func disconnectedStatus(name: String, listed: [String], showsPicker: Bool) -> String {
        if listed.contains(name) {
            return "\(name) is connected to a different port \u{00B7} Choose it again to turn Caps Lock rules back on"
        }
        return "\(name) is disconnected \u{00B7} Caps Lock rules are paused"
            + (showsPicker ? "; choose a keyboard" : "")
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
        if !selectedOnly {
            busy = true
            let changed = await runtime.setCapsSelection(nil, automaticSetupDisabled: !enabled,
                                                         selectedKeyboardOnly: false)
            busy = false
            if changed {
                automaticDisabled = !enabled
            } else {
                message = "Caps Lock setup could not be changed safely. Existing settings were kept."
            }
            await applyDeferredWork()
            return
        }
        if enabled, device == nil {
            UserDefaults.standard.set(false, forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
            automaticDisabled = false
            return
        }
        await applySelection(enabled: enabled)
        automaticDisabled = UserDefaults.standard.bool(forKey: SessionCapsRuntimeSupport.automaticSetupDisabledKey)
        await applyDeferredWork()
    }

    @MainActor
    private func setSelectedOnly(_ only: Bool) async {
        guard !busy, only != selectedOnly || choosingOneKeyboard else { return }
        if only {
            choosingOneKeyboard = true
            showAdvanced = true
            message = "Choose the keyboard whose Caps Lock key should use these rules."
            return
        }
        busy = true
        let changed = await runtime.setCapsSelection(nil, automaticSetupDisabled: false,
                                                     selectedKeyboardOnly: false)
        busy = false
        if changed {
            selectedOnly = false
            choosingOneKeyboard = false
            saved = nil
            message = nil
        } else {
            message = "Caps Lock setup could not be changed safely. Existing settings were kept."
        }
        await applyDeferredWork()
    }

    @MainActor
    private func setKeyboardEnabled(_ id: String, enabled: Bool) async {
        guard !busy else { return }
        var next = excludedIDs
        if enabled { next.remove(id) } else { next.insert(id) }
        busy = true
        let changed = await runtime.setCapsExcludedKeyboardIDs(next)
        busy = false
        if changed {
            excludedIDs = next
            message = nil
            await refreshKeyboards(keepMessage: false)
        } else {
            message = "This keyboard preference could not be changed safely. Existing settings were kept."
        }
        await applyDeferredWork()
    }

    @MainActor
    private func reviewKeyboard(keepMessage: Bool = false) async {
        if busy { refreshAgain = true }
        await refreshKeyboards(keepMessage: keepMessage)
        await applyDeferredWork()
    }

    /// A keyboard picked while Settings was busy (the click that opens the
    /// menu can also activate the app and start a refresh) is applied now.
    @MainActor
    private func applyDeferredWork() async {
        // Work deferred while busy: a refresh first, so a queued pick is
        // checked against the current list, then the pick itself.
        while refreshAgain, !busy {
            refreshAgain = false
            await refreshKeyboards(keepMessage: message != nil)
        }
        guard !busy, let next = choices.takeAfterRefresh() else { return }
        await choose(next)
    }

    @MainActor
    private func refreshKeyboards(keepMessage: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let needsCaps = rulesUseCaps
            let storedData = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey)
            let displaced = SessionCapsSelectionStore.displaced?.data
            let found = try await Task.detached {
                let boot = try SessionCapsRuntimeSupport.bootSessionUUID()
                let stored = storedData.flatMap { try? SessionCapsSelection.decode($0, currentBoot: boot) }
                // Gone means the instance no longer exists, not merely that it
                // is unusable (a second identical keyboard withholds it).
                let gone = try stored.map { try !SessionCapsHIDUtilTransport.registryEntryExists($0.device.registryEntryID) } ?? false
                let list = try SessionCapsHIDUtilTransport.keyboards()
                // Replugged at the same port: the session re-binds it, so show it as chosen.
                let devices = list.keyboards.map(\.device)
                let rebound = SessionCapsRuntimeSupport.reboundSelection(selectionData: displaced, devices: devices, boot: boot)
                    ?? (gone ? stored?.rebound(among: devices, currentBoot: boot) : nil)
                let excluded = SessionCapsRuntimeSupport.excludedKeyboardIDs()
                var uncovered: [String] = []
                if needsCaps, !SessionCapsRuntimeSupport.selectedKeyboardOnly() {
                    let fleet = SessionCapsMappingFleet(directory: SessionCapsRuntimeSupport.journalDirectory(),
                                                        backend: SessionCapsHIDUtilTransport.backend())
                    let active = (try? fleet.activeDeviceIDs(bootSessionUUID: boot)) ?? []
                    for keyboard in list.keyboards where !excluded.contains(SessionCapsRuntimeSupport.preferenceID(keyboard.device))
                        && !active.contains(keyboard.id)
                    {
                        let conflict = try? SessionCapsRuntimeSupport.capsConflict(on: keyboard.device)
                        let explanation = conflict?.message ?? "Caps Lock setup is not active on this keyboard yet."
                        uncovered.append("\(keyboard.name): \(explanation)")
                    }
                }
                return (list, boot, rebound ?? stored, gone && rebound == nil, uncovered, excluded)
            }.value
            boot = found.1
            keyboards = found.0.keyboards
            withheld = found.0.withheld
            fleetUncovered = found.4
            excludedIDs = found.5
            let stored = found.2
            device = Self.effectiveDevice(saved: stored?.device, connected: keyboards.map(\.device), withheld: withheld)
            saved = stored?.device == device ? stored : nil
            disconnected = found.3 && saved == nil ? SessionCapsSelectionStore.savedName ?? "Your keyboard" : nil
            if saved != nil { SessionCapsSelectionStore.saveName(keyboards.first { $0.device == device }?.name) }
            conflict = await Self.conflict(on: device, intermediate: saved?.intermediateUsage)
            if !keepMessage { message = nil }
        } catch {
            keyboards = []
            withheld = 0
            device = nil
            disconnected = nil
            conflict = nil
            fleetUncovered = []
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

    /// A Caps row KeyPath did not write. KeyPath's own row (Caps to its
    /// intermediate while the session runs) is not a conflict.
    static func conflict(on device: SessionCapsMappingPolicy.DeviceIdentity?, intermediate: UInt32?) async -> SessionCapsConflict? {
        guard let device else { return nil }
        let found = await Task.detached { try? SessionCapsRuntimeSupport.capsConflict(on: device) }.value
        return ownRow(found ?? nil, intermediate: intermediate) ? nil : found ?? nil
    }

    static func ownRow(_ conflict: SessionCapsConflict?, intermediate: UInt32?) -> Bool {
        guard let conflict, let intermediate else { return false }
        return conflict.destination == SessionCapsMappingPolicy.packed(intermediate)
    }

    @MainActor
    private func choose(_ picked: SessionCapsMappingPolicy.DeviceIdentity) async {
        // Busy means a refresh or another change is running; queue the pick.
        guard let chosen = choices.submit(picked, busy: busy),
              chosen != device || saved?.device != chosen || choosingOneKeyboard else { return }
        let previous = (device, saved)
        device = chosen
        message = nil
        await applySelection(enabled: true)
        if message != nil {
            (device, saved) = previous
            message = "That keyboard could not be set up for Caps Lock. It may have been unplugged; check the list and try again. Existing settings were kept."
            await refreshKeyboards(keepMessage: true)
        }
        if message == nil {
            selectedOnly = true
            choosingOneKeyboard = false
        }
        await applyDeferredWork()
    }

    @MainActor
    private func applySelection(enabled: Bool) async {
        guard !busy else { return }
        let selection: SessionCapsSelection?
        if enabled {
            guard let device else { return }
            // Keep the reserved key across a keyboard change; the next session
            // start re-checks it and moves it if it is no longer free. Read it
            // fresh: a session start may have moved it since Settings opened.
            let stored = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey)
                .flatMap { try? SessionCapsSelection.decode($0, currentBoot: boot) }
            selection = SessionCapsSelection(device: device, bootSessionUUID: boot,
                                             intermediateUsage: stored?.intermediateUsage ?? SessionCapsIntermediate.defaultUsage)
        } else { selection = nil }
        busy = true
        defer { busy = false }
        guard await runtime.setCapsSelection(selection, automaticSetupDisabled: !enabled,
                                             selectedKeyboardOnly: enabled ? true : selectedOnly)
        else {
            message = "Caps Lock setup could not be changed safely. Existing settings were kept. If the keyboard was disconnected, restart your Mac and try again."
            return
        }
        message = nil
        saved = selection
        disconnected = nil
        SessionCapsSelectionStore.saveName(keyboards.first { $0.device == selection?.device }?.name)
        conflict = await Self.conflict(on: selection?.device, intermediate: selection?.intermediateUsage)
    }
}
