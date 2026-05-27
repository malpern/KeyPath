import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Main view for the Quick Launcher collection configuration.
///
/// Displays a keyboard visualization with app/website icons on mapped keys,
/// alongside a drawer with the list of mappings for editing.
/// Supports activation mode switching (Hold Hyper vs Leader→L sequence).
struct LauncherCollectionView: View {
    @Binding var config: LauncherGridConfig
    let onConfigChanged: (LauncherGridConfig) -> Void
    var windowSnappingActive: Bool = false

    @State private var selectedKey: String?
    @State private var showBrowserHistory = false

    /// Local state for immediate UI response
    @State private var localHyperTriggerMode: HyperTriggerMode = .hold

    private var existingDomains: Set<String> {
        Set(config.mappings.compactMap { mapping in
            if case let .openURL(domain) = mapping.action {
                return normalizeDomain(domain)
            }
            return nil
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Activation mode picker
            activationModeSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Keyboard visualization (full width)
            VStack(spacing: 8) {
                LauncherKeyboardView(
                    config: $config,
                    selectedKey: selectedKey,
                    onKeyClicked: handleKeyClicked
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 12)

                Text("Click any key to configure")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // Mappings list (full width)
            LauncherDrawerView(
                config: $config,
                selectedKey: $selectedKey,
                onConfigChanged: onConfigChanged,
                windowSnappingActive: windowSnappingActive
            )
            .onChange(of: config) { _, newValue in
                onConfigChanged(newValue)
            }
        }
        .sheet(isPresented: $showBrowserHistory) {
            BrowserHistorySuggestionsView(existingDomains: existingDomains) { selectedSites in
                addSuggestedSites(selectedSites)
            }
        }
        // Note: .launcherSelectKey is handled by LauncherDrawerView directly
    }

    // MARK: - Activation Mode Section

    private var activationModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Launcher Settings")
                    .font(.headline)

                Spacer()

                Button(action: { showBrowserHistory = true }) {
                    Label("Suggest from History", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("launcher-suggest-button")
            }

            Picker("Activation Mode", selection: Binding(
                get: { config.activationMode },
                set: { newMode in
                    config.activationMode = newMode
                    onConfigChanged(config)
                }
            )) {
                Text(LauncherActivationMode.holdHyper.displayName).tag(LauncherActivationMode.holdHyper)
                Text(LauncherActivationMode.leaderSequence.displayName).tag(LauncherActivationMode.leaderSequence)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("launcher-activation-mode-picker")
            .accessibilityLabel("Launcher activation mode")

            // Hyper trigger mode segmented picker (only shown when Hyper mode is selected)
            if config.activationMode == .holdHyper {
                Picker("Trigger Mode", selection: Binding(
                    get: { localHyperTriggerMode },
                    set: { newMode in
                        localHyperTriggerMode = newMode
                        var updated = config
                        updated.hyperTriggerMode = newMode
                        onConfigChanged(updated)
                    }
                )) {
                    Text(HyperTriggerMode.hold.displayName).tag(HyperTriggerMode.hold)
                    Text(HyperTriggerMode.tap.displayName).tag(HyperTriggerMode.tap)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("launcher-hyper-trigger-picker")
                .accessibilityLabel("Hyper trigger mode")
                .onAppear {
                    localHyperTriggerMode = config.hyperTriggerMode
                }
            }

            Text(activationDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var activationDescription: String {
        switch config.activationMode {
        case .holdHyper:
            localHyperTriggerMode.description + " Then press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    // MARK: - Actions

    private func handleKeyClicked(_ key: String) {
        selectedKey = key
        // Post notification so the drawer picks it up and opens the editor
        NotificationCenter.default.post(
            name: .launcherSelectKey,
            object: nil,
            userInfo: ["key": key]
        )
    }

    private func addSuggestedSites(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        let usedKeys = Set(config.mappings.map { LauncherGridConfig.normalizeKey($0.key) })
        let availableKeys = LauncherGridConfig.suggestionKeyOrder.filter { !usedKeys.contains($0) }
        let existing = existingDomains

        for (site, key) in zip(sites, availableKeys) {
            if existing.contains(normalizeDomain(site.domain)) {
                continue
            }
            let mapping = LauncherMapping(
                key: key,
                action: .openURL(site.domain),
                isEnabled: true
            )
            config.mappings.append(mapping)
        }
        onConfigChanged(config)
    }

    private func normalizeDomain(_ domain: String) -> String {
        let lower = domain.lowercased()
        if lower.hasPrefix("www.") {
            return String(lower.dropFirst(4))
        }
        return lower
    }
}

// MARK: - Preview

#Preview("Launcher Collection View") {
    LauncherCollectionView(
        config: .constant(LauncherGridConfig.defaultConfig),
        onConfigChanged: { _ in }
    )
    .frame(width: 900, height: 400)
}

#Preview("Launcher Collection - Empty") {
    LauncherCollectionView(
        config: .constant(LauncherGridConfig(activationMode: .leaderSequence, mappings: [])),
        onConfigChanged: { _ in }
    )
    .frame(width: 900, height: 400)
}
