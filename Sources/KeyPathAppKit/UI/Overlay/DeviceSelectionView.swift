import KeyPathCore
import SwiftUI

/// Displays connected keyboards with toggles to enable/disable remapping per device.
/// VirtualHID devices are filtered out (never shown to users).
struct DeviceSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var connectedDevices: [ConnectedDevice] = []
    @State private var selections: [String: DeviceSelection] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var needsRestart = false
    @State private var isRestarting = false

    /// Physical (non-VirtualHID) devices currently connected.
    private var physicalConnected: [ConnectedDevice] {
        connectedDevices.filter { !$0.isVirtualHID }
    }

    /// Previously-seen devices that are no longer connected.
    private var disconnectedSelections: [DeviceSelection] {
        let connectedHashes = Set(connectedDevices.map(\.hash))
        return selections.values
            .filter { !connectedHashes.contains($0.hash) }
            .sorted { $0.productKey < $1.productKey }
    }

    /// True if every physical device would be disabled.
    private var allDisabled: Bool {
        let connected = physicalConnected
        guard !connected.isEmpty else { return false }
        return connected.allSatisfy { !isEnabled(hash: $0.hash) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorView(errorMessage)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        connectedSection
                        disconnectedSection
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 0)
                footerView
            }
        }
        .task {
            await loadDevices()
        }
    }

    // MARK: - Connected Section

    @ViewBuilder
    private var connectedSection: some View {
        if !physicalConnected.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(physicalConnected) { device in
                    DeviceRow(
                        displayName: device.displayName,
                        detail: device.vendorProductHex,
                        isEnabled: isEnabled(hash: device.hash),
                        isConnected: true,
                        onToggle: { toggleDevice(hash: device.hash, productKey: device.productKey) }
                    )
                }
            }
        }
    }

    // MARK: - Disconnected Section

    @ViewBuilder
    private var disconnectedSection: some View {
        if !disconnectedSelections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Previously Seen")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(disconnectedSelections, id: \.hash) { selection in
                    DeviceRow(
                        displayName: selection.displayName,
                        detail: "disconnected",
                        isEnabled: selection.isEnabled,
                        isConnected: false,
                        onToggle: { toggleDevice(hash: selection.hash, productKey: selection.productKey) }
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            if allDisabled {
                Label("No keyboards will be remapped.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Unchecked keyboards pass through without remapping.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if needsRestart {
                Button(action: applyChanges) {
                    if isRestarting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restart to Apply")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRestarting)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Could not list devices")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Data Loading

    private func loadDevices() async {
        isLoading = true
        defer { isLoading = false }

        #if os(macOS)
            // Dispatch device enumeration off the main thread to avoid blocking UI
            let devices = await Task.detached(priority: .userInitiated) {
                DeviceEnumerationService.enumerateConnectedDevices()
            }.value
            if devices.isEmpty {
                errorMessage = "Kanata binary not found or returned no devices."
                return
            }
            connectedDevices = devices
        #else
            errorMessage = "Device enumeration is only available on macOS."
            return
        #endif

        // Load persisted selections
        let stored = await DeviceSelectionStore.shared.loadSelections()
        selections = Dictionary(stored.map { ($0.hash, $0) }, uniquingKeysWith: { _, new in new })

        // Update lastSeen for connected devices
        let now = Date()
        for device in connectedDevices where !device.isVirtualHID {
            if selections[device.hash] == nil {
                // New device — default to enabled, don't mark dirty
                selections[device.hash] = DeviceSelection(
                    hash: device.hash,
                    productKey: device.productKey,
                    isEnabled: true,
                    lastSeen: now
                )
            } else {
                selections[device.hash]?.lastSeen = now
            }
        }

        // Persist updated lastSeen timestamps
        do {
            try await DeviceSelectionStore.shared.saveSelections(Array(selections.values))
        } catch {
            AppLogger.shared.warn("⚠️ [DeviceSelectionView] Failed to persist lastSeen updates: \(error)")
        }
    }

    // MARK: - Actions

    private func isEnabled(hash: String) -> Bool {
        selections[hash]?.isEnabled ?? true
    }

    private func toggleDevice(hash: String, productKey: String) {
        if var existing = selections[hash] {
            existing.isEnabled.toggle()
            selections[hash] = existing
        } else {
            selections[hash] = DeviceSelection(
                hash: hash,
                productKey: productKey,
                isEnabled: false,
                lastSeen: Date()
            )
        }
        needsRestart = true

        // Persist immediately so selections survive tab navigation
        Task {
            do {
                try await DeviceSelectionStore.shared.saveSelections(Array(selections.values))
            } catch {
                AppLogger.shared.warn("⚠️ [DeviceSelectionView] Failed to persist toggle: \(error)")
            }
        }
    }

    private func applyChanges() {
        isRestarting = true
        Task {
            NotificationCenter.default.post(name: .deviceSelectionChanged, object: nil)
            needsRestart = false
            isRestarting = false
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let displayName: String
    let detail: String
    let isEnabled: Bool
    let isConnected: Bool
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                    .font(.body)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConnected ? .primary : .secondary)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering
                        ? (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        : (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)))
            )
            .opacity(isConnected ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
