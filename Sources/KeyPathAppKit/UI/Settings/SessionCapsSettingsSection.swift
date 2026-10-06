import Foundation
import KeyPathCore
import SwiftUI

struct SessionCapsSettingsSection: View {
    @Environment(KanataViewModel.self) private var runtime
    @State private var device: SessionCapsMappingPolicy.DeviceIdentity?
    @State private var boot = ""
    @State private var reservesF18 = false
    @State private var hasSelection = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Caps Lock Remapping")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Use Caps Lock for a remap or a different action when held. Setup supports one compatible keyboard and reserves F18.")
                .font(.subheadline)
            if device != nil {
                Text("Compatible keyboard connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Reserve F18 for Caps Lock", isOn: $reservesF18)
                .disabled(busy)
                .accessibilityIdentifier("settings-caps-reserve-f18")
            HStack {
                Button("Review Keyboard") { Task { await reviewKeyboard() } }
                    .disabled(busy)
                    .accessibilityIdentifier("settings-caps-review-keyboard")
                Button("Enable Caps Lock Remapping") { Task { await applySelection(enabled: true) } }
                    .disabled(busy || device == nil || !reservesF18)
                    .accessibilityIdentifier("settings-caps-enable")
                if hasSelection {
                    Button("Disable") { Task { await applySelection(enabled: false) } }
                        .disabled(busy)
                        .accessibilityIdentifier("settings-caps-disable")
                }
            }
            .buttonStyle(.bordered)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Text("Select the keyboard again after restarting your Mac. If a disconnected keyboard leaves a recovery warning, restart your Mac before selecting it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await reviewKeyboard() }
    }

    @MainActor
    private func reviewKeyboard() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        hasSelection = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey) != nil
        do {
            let found = try await Task.detached {
                (try SessionCapsHIDUtilTransport.backend().enumerate(), try SessionCapsRuntimeSupport.bootSessionUUID())
            }.value
            boot = found.1
            device = found.0.count == 1 ? found.0.first : nil
            if let data = UserDefaults.standard.data(forKey: SessionCapsRuntimeSupport.selectionKey),
               let selection = try? SessionCapsSelection.decode(data, currentBoot: boot),
               selection.device == device {
                reservesF18 = true
                message = "Caps Lock setup is saved for this keyboard."
            } else {
                reservesF18 = false
                message = device == nil ? "Connect exactly one compatible keyboard to enable Caps Lock remapping." : "Confirm that you do not use F18, then enable Caps Lock remapping."
            }
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
        guard await runtime.setCapsSelection(selection) else {
            message = "Caps Lock setup could not be changed safely. Existing settings were kept. If the keyboard was disconnected, restart your Mac and try again."
            return
        }
        hasSelection = enabled
        message = enabled ? "Caps Lock setup saved. Start KeyPath Runtime to apply your rules." : "Caps Lock setup disabled. To run a profile with Caps Lock rules, enable setup again or use Rules → Edit Configuration to change those rules."
    }
}
