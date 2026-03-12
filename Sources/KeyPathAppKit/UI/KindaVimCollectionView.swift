import KeyPathCore
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct KindaVimCollectionView: View {
    let mappings: [KeyMapping]
    @Environment(\.services) private var services
    @State private var selectedHUDMode: KindaVimLeaderHUDMode = PreferencesService.shared.kindaVimLeaderHUDMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            installationBanner
            integrationSummary
            hudModeSection
            strategyTip
        }
        .onAppear {
            selectedHUDMode = services.preferences.kindaVimLeaderHUDMode
        }
        .onChange(of: selectedHUDMode) { _, newValue in
            services.preferences.kindaVimLeaderHUDMode = newValue
        }
    }

    private var strategyTip: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.caption)
            Text("KindaVim auto-detects strategy. Hold fn while moving to force Keyboard Strategy.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var installationBanner: some View {
        let installed = KindaVimDetector.isInstalled
        HStack(alignment: .center, spacing: 12) {
            kindaVimLogo

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(installed ? .green : .orange)
                        .font(.body.weight(.semibold))
                    Text(installed ? "KindaVim is installed" : "KindaVim not found")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                Text(installed ? "KeyPath detected KindaVim and your Rules collection is ready." : "Install KindaVim to enable modal editing in macOS apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if !installed {
                Button {
                    NSWorkspace.shared.open(KindaVimDetector.downloadURL)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("kindavim-download-button")
                .accessibilityLabel("Download KindaVim")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var kindaVimLogo: some View {
        Group {
            if let image = Self.kindaVimLogoImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "command.square.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var integrationSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KindaVim handles real Normal/Visual/Insert behavior. KeyPath configures \(mappings.count) leader-layer shortcuts for quick actions while you keep typing.")
                .font(.subheadline)
                .foregroundColor(.primary)
            Text("Rules here are for integration settings only. Teaching and quick-reference appear on leader hold.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var hudModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leader-Hold KindaVim View")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)

            Picker(
                "Leader-hold KindaVim view mode",
                selection: $selectedHUDMode
            ) {
                ForEach(KindaVimLeaderHUDMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("kindavim-leader-hud-mode-picker")
            .accessibilityLabel("KindaVim leader hold view mode")

            Text(selectedHUDMode.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private static let kindaVimLogoImage: NSImage? = {
        let resourceName = "kindavim-icon"
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks

        for bundle in bundles {
            if let url = bundle.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }

        if let mainResourceURL = Bundle.main.resourceURL {
            let keyPathBundleURL = mainResourceURL.appendingPathComponent("KeyPath_KeyPath.bundle")
            if let keyPathBundle = Bundle(url: keyPathBundleURL),
               let url = keyPathBundle.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }

        return nil
    }()
}
