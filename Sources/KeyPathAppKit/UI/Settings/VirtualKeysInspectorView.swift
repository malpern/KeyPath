import KeyPathCore
import SwiftUI

/// Read-only inspector for virtual keys defined in the Kanata configuration
/// Displays keys from `defvirtualkeys` and `deffakekeys` blocks with test functionality
struct VirtualKeysInspectorView: View {
    @State private var virtualKeys: [VirtualKey] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var testingKey: String?
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String)
        case failure(String)
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
                Spacer()
                Button(action: { Task { await loadVirtualKeys() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh virtual keys")
            }

            Text("Virtual keys defined in your config can be triggered via deep links")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

            Text("Add `defvirtualkeys` or `deffakekeys` blocks to your config to define triggerable macros.")
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
            // Group by source
            let grouped = Dictionary(grouping: virtualKeys, by: { $0.source })

            ForEach([VirtualKey.VirtualKeySource.virtualkeys, .fakekeys], id: \.self) { source in
                if let keys = grouped[source], !keys.isEmpty {
                    sourceSection(source: source, keys: keys)
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
            .accessibilityLabel("Copy deep link")

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
            .accessibilityLabel(testingKey == key.name ? "Testing" : "Test virtual key")
            .buttonStyle(.borderless)
            .disabled(testingKey != nil)
            .help("Test this virtual key")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
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
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func loadVirtualKeys() async {
        isLoading = true
        errorMessage = nil

        do {
            let configPath = KeyPathConstants.Config.mainConfigPath
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            virtualKeys = VirtualKeyParser.parse(config: content)
        } catch {
            errorMessage = "Could not read config: \(error.localizedDescription)"
            virtualKeys = []
        }

        isLoading = false
    }

    private func copyDeepLink(_ key: VirtualKey) {
        let url = "keypath://fakekey/\(key.name)/tap"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        // Show brief feedback
        withAnimation {
            testResult = .success("Copied: \(url)")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
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

        let port = PreferencesService.shared.tcpServerPort
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
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
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
