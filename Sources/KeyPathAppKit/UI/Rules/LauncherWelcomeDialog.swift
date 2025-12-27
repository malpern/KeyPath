import AppKit
import SwiftUI

/// Welcome dialog shown when user first enables the Launcher collection.
///
/// Introduces the feature and offers three paths:
/// - Use defaults as-is
/// - Customize the shortcuts
/// - Import from browser history
struct LauncherWelcomeDialog: View {
    @Binding var config: LauncherGridConfig
    let onComplete: (LauncherGridConfig, WelcomeAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: Step = .welcome

    enum Step {
        case welcome
        case preview
        case customize
        case browserHistory
    }

    enum WelcomeAction {
        case useDefaults
        case customized
        case importedFromHistory
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .preview:
                    previewStep
                case .customize:
                    customizeStep
                case .browserHistory:
                    browserHistoryStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 560)
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon and title
            VStack(spacing: 16) {
                Image(systemName: "rocket.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Quick Launcher")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Launch your favorite apps and websites\nwith a single keystroke")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // How it works
            VStack(alignment: .leading, spacing: 16) {
                howItWorksRow(
                    icon: "hand.point.up.left.fill",
                    title: "Hold Hyper",
                    description: "Press and hold your Hyper key (Caps Lock when held)"
                )
                howItWorksRow(
                    icon: "keyboard.fill",
                    title: "Press a Shortcut",
                    description: "S for Safari, T for Terminal, 1 for GitHub..."
                )
                howItWorksRow(
                    icon: "arrow.up.forward.app.fill",
                    title: "App Opens Instantly",
                    description: "Your app or website launches immediately"
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: { currentStep = .preview }) {
                    Text("See What's Included")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("launcher-welcome-see-included-button")

                HStack(spacing: 16) {
                    Button("Customize First") {
                        currentStep = .customize
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("launcher-welcome-customize-button")

                    Button("Import from Browser History") {
                        currentStep = .browserHistory
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("launcher-welcome-import-history-button")
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    private func howItWorksRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Preview Step

    private var previewStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Default Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("These shortcuts are ready to use out of the box")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Shortcuts preview
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Apps section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apps", systemImage: "app.fill")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                            ForEach(appMappings) { mapping in
                                PreviewMappingRow(mapping: mapping)
                            }
                        }
                    }

                    // Websites section
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Websites", systemImage: "globe")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                            ForEach(websiteMappings) { mapping in
                                PreviewMappingRow(mapping: mapping)
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack {
                Button("Back") {
                    currentStep = .welcome
                }
                .accessibilityIdentifier("launcher-preview-back-button")

                Spacer()

                Button("Customize...") {
                    currentStep = .customize
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("launcher-preview-customize-button")

                Button("Use These Defaults") {
                    complete(action: .useDefaults)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("launcher-preview-use-defaults-button")
            }
            .padding(16)
        }
    }

    private var appMappings: [LauncherMapping] {
        config.mappings.filter(\.target.isApp)
    }

    private var websiteMappings: [LauncherMapping] {
        config.mappings.filter { !$0.target.isApp }
    }

    // MARK: - Customize Step

    private var customizeStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Customize Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Toggle off shortcuts you don't need, or edit them")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Editable list
            ScrollView {
                LauncherCollectionView(
                    config: $config,
                    onConfigChanged: { _ in }
                )
                .padding(20)
            }

            Divider()

            // Actions
            HStack {
                Button("Back") {
                    currentStep = .welcome
                }
                .accessibilityIdentifier("launcher-customize-back-button")

                Spacer()

                Button("Done") {
                    complete(action: .customized)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("launcher-customize-done-button")
            }
            .padding(16)
        }
    }

    // MARK: - Browser History Step

    private var browserHistoryStep: some View {
        BrowserHistorySuggestionsView { selectedSites in
            // Add selected sites to config
            let usedKeys = Set(config.mappings.map(\.key))
            let availableKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
                .filter { !usedKeys.contains($0) }

            for (site, key) in zip(selectedSites, availableKeys) {
                let mapping = LauncherMapping(
                    key: key,
                    target: .url(site.domain),
                    isEnabled: true
                )
                config.mappings.append(mapping)
            }

            complete(action: .importedFromHistory)
        }
    }

    // MARK: - Helpers

    private func complete(action: WelcomeAction) {
        onComplete(config, action)
        dismiss()
    }
}

// MARK: - Preview Mapping Row

private struct PreviewMappingRow: View {
    let mapping: LauncherMapping
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: mapping.target.isApp ? "app" : "globe")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.secondary)
                }
            }

            // Key badge
            Text(mapping.key.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.2))
                )
                .foregroundColor(.accentColor)

            // Name
            Text(mapping.target.displayName)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .task {
            await loadIcon()
        }
    }

    private func loadIcon() async {
        switch mapping.target {
        case .app:
            icon = AppIconResolver.icon(for: mapping.target)
        case let .url(urlString):
            icon = await FaviconLoader.shared.favicon(for: urlString)
        }
    }
}
