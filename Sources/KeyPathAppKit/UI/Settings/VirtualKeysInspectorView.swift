import KeyPathCore
import SwiftUI

/// Read-only inspector for virtual keys defined in the Kanata configuration
/// Displays keys from `defvirtualkeys` and `deffakekeys` blocks with test functionality
struct VirtualKeysInspectorView: View {
    @Environment(\.services) private var services
    @State private var virtualKeys: [VirtualKey] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var testingKey: String?
    @State private var testResult: TestResult?
    @State private var loadSource: LoadSource?

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    /// Which path produced the currently displayed keys.
    ///
    /// The live-TCP path can only return fake-key *names* — Kanata's TCP API doesn't
    /// distinguish `defvirtualkeys` from `deffakekeys` — so those results can't be
    /// grouped by source. The config-file parser labels sources accurately.
    private enum LoadSource {
        case liveTCP
        case configFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if virtualKeys.isEmpty {
                emptyStateView
            } else {
                keyListView
            }
        }
        .padding()
        .task {
            await loadVirtualKeys()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "keyboard.badge.ellipsis")
                    .foregroundStyle(.secondary)
                Text("Virtual Keys")
                    .font(.headline)
                if !isLoading, let loadSource {
                    sourceBadge(loadSource)
                }
                Spacer()
                Button(action: { Task { await loadVirtualKeys() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityIdentifier("virtual-keys-refresh-button")
                .accessibilityLabel("Refresh virtual keys")
            }

            Text("Run these actions from Shortcuts, Raycast, scripts, or `keypath://` URLs when you need to trigger Kanata behavior outside normal typing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Badge indicating whether keys came from the running service (live) or the config file.
    private func sourceBadge(_ source: LoadSource) -> some View {
        let isLive = source == .liveTCP
        return Text(isLive ? "Live" : "From config file")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isLive ? Color.green : Color.secondary).opacity(0.15))
            .foregroundStyle(isLive ? Color.green : Color.secondary)
            .clipShape(.rect(cornerRadius: 4))
            .help(isLive
                ? "Read live from the running Kanata service. Source type (virtual vs fake keys) isn't reported over the live connection."
                : "Parsed from your config file. The service isn't reporting keys right now.")
            .accessibilityIdentifier("virtual-keys-source-badge")
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading configuration...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("No Virtual Keys Defined")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Add `defvirtualkeys` or `deffakekeys` when you want reusable actions you can trigger from URLs, scripts, or automations.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link(destination: URL(string: "https://github.com/jtroo/kanata/blob/main/docs/config.adoc#fake-keys")!) {
                Label("Learn More", systemImage: "book")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Key List

    private var keyListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The live-TCP path can't report whether each key is a virtual or fake key,
            // so group-by-source would be misleading there — show a flat list instead.
            // Config-file parsing knows the source, so keep the labeled sections.
            if loadSource == .liveTCP {
                ForEach(virtualKeys) { key in
                    keyRow(key)
                }
            } else {
                let grouped = Dictionary(grouping: virtualKeys, by: { $0.source })

                ForEach([VirtualKey.VirtualKeySource.virtualkeys, .fakekeys], id: \.self) { source in
                    if let keys = grouped[source], !keys.isEmpty {
                        sourceSection(source: source, keys: keys)
                    }
                }
            }

            // Test result feedback
            if let result = testResult {
                testResultView(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sourceSection(source: VirtualKey.VirtualKeySource, keys: [VirtualKey]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(keys) { key in
                keyRow(key)
            }
        }
    }

    private func keyRow(_ key: VirtualKey) -> some View {
        HStack(spacing: 12) {
            // Key name
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                Text(key.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Deep link copy button
            Button(action: { copyDeepLink(key) }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy deep link URL")
            .accessibilityIdentifier("virtual-keys-copy-button-\(key.name)")
            .accessibilityLabel("Copy deep link for \(key.name)")

            // Test button
            Button(action: { Task { await testKey(key) } }) {
                if testingKey == key.name {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .disabled(testingKey != nil)
            .help("Test this virtual key")
            .accessibilityIdentifier("virtual-keys-test-button-\(key.name)")
            .accessibilityLabel("Test virtual key \(key.name)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(.rect(cornerRadius: 6))
    }

    private func testResultView(_ result: TestResult) -> some View {
        HStack(spacing: 8) {
            switch result {
            case let .success(message):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .foregroundStyle(.green)
            case let .failure(message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 6))
    }

    // MARK: - Actions

    private func loadVirtualKeys() async {
        isLoading = true
        errorMessage = nil

        // Try live TCP query first (returns keys from running kanata, including dynamic includes).
        // The TCP API can't distinguish virtual vs fake keys, so source is left as .fakekeys
        // and the UI renders these as a flat (ungrouped) "Live" list.
        let liveNames = await loadVirtualKeysFromTCP()
        if let liveNames, !liveNames.isEmpty {
            virtualKeys = liveNames.map { VirtualKey(name: $0, action: "", source: .fakekeys) }
            loadSource = .liveTCP
            isLoading = false
            return
        }

        // Fall back to static config file parsing (source labels are accurate here)
        do {
            let configPath = KeyPathConstants.Config.mainConfigPath
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            virtualKeys = VirtualKeyParser.parse(config: content)
            loadSource = .configFile
        } catch {
            errorMessage = "Could not read config: \(error.localizedDescription)"
            virtualKeys = []
            loadSource = nil
        }

        isLoading = false
    }

    private func loadVirtualKeysFromTCP() async -> [String]? {
        let port = services.preferences.tcpServerPort
        let client = KanataTCPClient(port: port, timeout: 3.0)
        defer { Task { await client.cancelInflightAndCloseConnection() } }

        guard await client.checkServerStatus() else { return nil }

        do {
            return try await client.requestFakeKeyNames()
        } catch {
            return nil
        }
    }

    private func copyDeepLink(_ key: VirtualKey) {
        let url = "keypath://fakekey/\(key.name)/tap"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        // Show brief feedback
        withAnimation {
            testResult = .success("Copied: \(url)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if case .success = testResult {
                    testResult = nil
                }
            }
        }
    }

    private func testKey(_ key: VirtualKey) async {
        testingKey = key.name
        testResult = nil

        let port = services.preferences.tcpServerPort
        let client = KanataTCPClient(port: port, timeout: 3.0)

        // First check if Kanata is running
        let serverUp = await client.checkServerStatus()
        guard serverUp else {
            await MainActor.run {
                testingKey = nil
                withAnimation {
                    testResult = .failure("Kanata not running. Start the service first.")
                }
            }
            await client.cancelInflightAndCloseConnection()
            return
        }

        let result = await client.actOnFakeKey(name: key.name, action: .tap)
        await client.cancelInflightAndCloseConnection()

        await MainActor.run {
            testingKey = nil
            withAnimation {
                switch result {
                case .success:
                    testResult = .success("Triggered '\(key.name)' successfully")
                case let .error(message):
                    // Improve error messages for common cases
                    if message.lowercased().contains("not found") || message.lowercased().contains("unknown") {
                        testResult = .failure("Key '\(key.name)' not recognized by Kanata. Try reloading config.")
                    } else {
                        testResult = .failure(message)
                    }
                case let .networkError(message):
                    testResult = .failure("Connection lost: \(message)")
                }
            }

            // Clear result after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    testResult = nil
                }
            }
        }
    }
}

#Preview {
    VirtualKeysInspectorView()
        .frame(width: 400, height: 300)
}

#Preview("Virtual Keys Inspector - Large") {
    VirtualKeysInspectorView()
        .frame(width: 640, height: 500)
        .padding()
}
