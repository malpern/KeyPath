// M1 Phase 2 placeholder — will be replaced in Phase 3 with the
// Direction-C in-place modification panel.
// For now, presents a simple NSAlert so we can verify Gallery → Pack Detail
// click-through works end to end.

import AppKit
import SwiftUI

@MainActor
final class PackDetailPresenter {
    static let shared = PackDetailPresenter()

    private var sheetWindow: NSWindow?

    /// Present Pack Detail for the given pack. In Phase 2 this is a basic
    /// sheet with install/uninstall/cancel; Phase 3 replaces it with the
    /// Direction-C interaction that dims the main keyboard and shows the
    /// pending-state tint on affected keys.
    func present(_ pack: Pack, kanataManager: KanataViewModel) {
        // If a sheet is already open for any pack, replace it.
        sheetWindow?.close()

        let content = PackDetailPlaceholderView(
            pack: pack,
            kanataManager: kanataManager,
            onClose: { [weak self] in
                self?.dismissSheet()
            }
        )

        let hosting = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = pack.name
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        sheetWindow = window
    }

    private func dismissSheet() {
        sheetWindow?.close()
        sheetWindow = nil
    }
}

/// Phase 2 placeholder content. Phase 3 replaces this with the
/// Direction-C `PackDetailPanelView` anchored over the main keyboard.
private struct PackDetailPlaceholderView: View {
    let pack: Pack
    let kanataManager: KanataViewModel
    let onClose: () -> Void

    @State private var isInstalled = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var quickSettingValues: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            description
            if !pack.quickSettings.isEmpty {
                quickSettings
            }
            Spacer()
            status
            actionRow
        }
        .padding(20)
        .task {
            await refreshInstallState()
            loadDefaultQuickSettings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pack.name)
                .font(.system(size: 17, weight: .semibold))
            Text(pack.tagline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var description: some View {
        Text(pack.longDescription)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Quick settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(pack.quickSettings) { setting in
                switch setting.kind {
                case let .slider(_, min: lo, max: hi, step: step, unitSuffix: suffix):
                    HStack(spacing: 8) {
                        Text(setting.label)
                            .font(.system(size: 12))
                            .frame(width: 110, alignment: .leading)
                        Slider(
                            value: sliderBinding(for: setting.id),
                            in: Double(lo) ... Double(hi),
                            step: Double(step)
                        )
                        Text("\(quickSettingValues[setting.id] ?? 0)\(suffix)")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = statusMessage {
            HStack(spacing: 6) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? .orange : .green)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? .orange : .secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if isInstalled {
                Button("Uninstall", role: .destructive) { Task { await uninstall() } }
                    .disabled(isWorking)
            } else {
                Button("Install") { Task { await install() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
            }
        }
    }

    // MARK: - Actions

    private func sliderBinding(for id: String) -> Binding<Double> {
        Binding(
            get: { Double(quickSettingValues[id] ?? 0) },
            set: { quickSettingValues[id] = Int($0) }
        )
    }

    private func loadDefaultQuickSettings() {
        for setting in pack.quickSettings {
            if quickSettingValues[setting.id] == nil,
               let defaultVal = setting.defaultSliderValue
            {
                quickSettingValues[setting.id] = defaultVal
            }
        }
    }

    private func refreshInstallState() async {
        let installed = await PackInstaller.shared.isInstalled(packID: pack.id)
        let currentSettings = await PackInstaller.shared.quickSettings(for: pack.id)
        await MainActor.run {
            isInstalled = installed
            if installed, !currentSettings.isEmpty {
                // Reflect the user's saved settings when they reopen the pack.
                quickSettingValues = currentSettings
            }
        }
    }

    private func install() async {
        isWorking = true
        statusMessage = "Installing…"
        isError = false

        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            _ = try await PackInstaller.shared.install(
                pack,
                quickSettingValues: quickSettingValues,
                manager: manager
            )
            await refreshInstallState()
            statusMessage = "Installed."
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }

        isWorking = false
    }

    private func uninstall() async {
        isWorking = true
        statusMessage = "Uninstalling…"
        isError = false

        do {
            let manager = kanataManager.underlyingManager.ruleCollectionsManager
            try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)
            await refreshInstallState()
            statusMessage = "Uninstalled."
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }

        isWorking = false
    }
}
