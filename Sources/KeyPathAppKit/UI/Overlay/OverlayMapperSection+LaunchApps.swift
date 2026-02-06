import AppKit
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Launch Apps Expanded Content

    /// Content shown when Launch Apps section is expanded
    var launchAppsExpandedContent: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Known Apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // List of known apps
            if knownApps.isEmpty {
                HStack {
                    Text("No apps configured yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(knownApps, id: \.name) { app in
                    knownAppRow(app)
                }
            }

            // "Add App..." option
            Button {
                pickAppForOutput()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.body)
                        .frame(width: 20)
                    Text("Add App...")
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
            .accessibilityIdentifier("overlay-add-app-button")
        }
    }

    /// Button for a known app in the list
    private func knownAppRow(_ app: AppLaunchInfo) -> some View {
        let isSelected = viewModel.selectedApp?.bundleIdentifier == app.bundleIdentifier
        let appIdentifier = (app.bundleIdentifier ?? app.name)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return Button {
            viewModel.selectedApp = app
            viewModel.selectedSystemAction = nil
            viewModel.selectedURL = nil
            selectedLayerOutput = nil
            viewModel.outputLabel = app.name
            isSystemActionPickerOpen = false

            // Auto-save if input is set
            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                Task {
                    await viewModel.save(kanataManager: manager)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
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
        .accessibilityIdentifier("overlay-known-app-\(appIdentifier)")
    }

    /// Load known apps from existing mappings
    func loadKnownApps() {
        Task {
            // Get apps from app-specific keymaps
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            var apps: [AppLaunchInfo] = []
            var seenAppKeys: Set<String> = []

            for keymap in keymaps {
                let bundleId = keymap.mapping.bundleIdentifier
                let name = keymap.mapping.displayName

                // Get icon
                let icon: NSImage
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 32, height: 32)
                } else {
                    icon = NSImage(systemSymbolName: "app.fill", accessibilityDescription: name) ?? NSImage()
                }

                let appKey = bundleId.isEmpty ? name : bundleId
                if seenAppKeys.insert(appKey).inserted {
                    apps.append(AppLaunchInfo(name: name, bundleIdentifier: bundleId, icon: icon))
                }
            }

            // Add running apps
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
            for app in runningApps {
                guard let url = app.bundleURL else { continue }
                guard isUserFacingAppURL(url) else { continue }
                let appInfo = appLaunchInfo(for: url)
                let appKey = appInfo.bundleIdentifier ?? url.path
                if seenAppKeys.insert(appKey).inserted {
                    apps.append(appInfo)
                }
            }

            await MainActor.run {
                knownApps = apps.sorted { $0.name < $1.name }
            }
        }
    }

    private func appLaunchInfo(for url: URL) -> AppLaunchInfo {
        let displayName = url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        let bundleId = Bundle(url: url)?.bundleIdentifier
        return AppLaunchInfo(name: displayName, bundleIdentifier: bundleId, icon: icon)
    }

    private func isUserFacingAppURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/") ||
            path.hasPrefix("/System/Applications/") ||
            path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
    }
}
