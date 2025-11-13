import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case general
    case rules
    case advanced

    var title: String {
        switch self {
        case .general: "General"
        case .rules: "Rules"
        case .advanced: "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .rules: "list.bullet"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}
struct SettingsContainerView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabPicker(selection: $selection)
                .padding(.bottom, 12)

            Group {
                switch selection {
                case .general:
                    SettingsView()
                case .rules:
                    RulesTabView()
                case .advanced:
                    AdvancedSettingsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, maxWidth: 680, minHeight: 550, idealHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsGeneral)) { _ in
            selection = .general
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRules)) { _ in
            selection = .rules
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAdvanced)) { _ in
            selection = .advanced
        }
    }
}

// MARK: - Settings Tab Picker

private struct SettingsTabPicker: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 24) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selection = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor),
                                    lineWidth: isSelected ? 2 : 1)
                    )

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(width: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    @State private var helperInstalled: Bool = HelperManager.shared.isHelperInstalled()
    @State private var helperVersion: String?
    @State private var helperInProgress = false
    @State private var helperMessage: String?
    @State private var duplicateAppCopies: [String] = []
    @State private var removeDuplicatesInProgress = false

    @State private var showingCleanupRepair = false
    @State private var showingHelperUninstallConfirm = false
    @State private var showingRemoveDuplicatesConfirm = false
    @State private var showingResetEverythingConfirmation = false

    @State private var settingsToastManager = WizardToastManager()

    // Service management state
    @State private var activeMethod: ServiceMethod = .unknown
    @State private var isMigrating = false

    enum ServiceMethod {
        case smappservice
        case launchctl
        case unknown
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Duplicate apps warning - show prominently at top if detected
                if duplicateAppCopies.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("⚠️ Multiple Installations Detected")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        duplicateAppsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // Service Management - only show if there's an issue
                if activeMethod != .smappservice {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Service Management")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        serviceManagementSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, duplicateAppCopies.count > 1 ? 0 : 20)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Privileged Helper")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    helperSection
                }
                .padding(.horizontal, 20)
                .padding(.top, (duplicateAppCopies.count > 1 || activeMethod != .smappservice) ? 0 : 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery Tools")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    recoverySection
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .task {
            await refreshHelperStatus()
            await refreshServiceStatus()
            duplicateAppCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
        }
        .sheet(isPresented: $showingCleanupRepair) {
            CleanupAndRepairView()
                .onDisappear {
                    Task {
                        await refreshHelperStatus()
                        duplicateAppCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
                    }
                }
        }
        .alert("Uninstall Privileged Helper?", isPresented: $showingHelperUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await uninstallHelper() }
            }
        } message: {
            Text("The helper enables privileged actions without repeated admin prompts. You can reinstall it from the Setup Wizard.")
        }
        .alert("Remove Extra Copies?", isPresented: $showingRemoveDuplicatesConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Extras", role: .destructive) {
                Task { await removeDuplicateAppCopies() }
            }
        } message: {
            Text("All KeyPath.app copies outside /Applications will be moved to the Trash.")
        }
        .alert("Reset Everything?", isPresented: $showingResetEverythingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await performResetEverything() }
            }
        } message: {
            Text("Force kill Kanata, remove PID files, and clear transient state. Service does not restart automatically.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var duplicateAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Found \(duplicateAppCopies.count) copies of KeyPath installed")
                        .font(.body.weight(.semibold))

                    Text("Extra copies can cause stale TCC approvals and permission issues. We recommend keeping only the copy in /Applications.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Copies found at:")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(duplicateAppCopies, id: \.self) { path in
                            Text("• \(path)")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Button(action: {
                showingRemoveDuplicatesConfirm = true
            }) {
                Label(removeDuplicatesInProgress ? "Removing…" : "Remove Extra Copies", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(removeDuplicatesInProgress)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var serviceManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: activeMethodIcon)
                    .foregroundColor(activeMethodColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeMethodText)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(activeMethodDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Migration button - only show if legacy is detected
            if activeMethod == .launchctl && KanataDaemonManager.shared.hasLegacyInstallation() {
                HStack(spacing: 8) {
                    Button(isMigrating ? "Migrating…" : "Migrate to SMAppService") {
                        guard !isMigrating else { return }
                        isMigrating = true
                        Task { @MainActor in
                            do {
                                try await KanataDaemonManager.shared.migrateFromLaunchctl()
                                settingsToastManager.showSuccess("Migrated to SMAppService")
                                await refreshServiceStatus()
                            } catch {
                                settingsToastManager.showError("Migration failed: \(error.localizedDescription)")
                            }
                            isMigrating = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isMigrating)

                    Spacer()
                }
            }
        }
    }

    private var activeMethodIcon: String {
        switch activeMethod {
        case .smappservice: "checkmark.circle.fill"
        case .launchctl: "gear.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var activeMethodColor: Color {
        switch activeMethod {
        case .smappservice: .green
        case .launchctl: .orange
        case .unknown: .gray
        }
    }

    private var activeMethodText: String {
        switch activeMethod {
        case .smappservice: "Using SMAppService"
        case .launchctl: "Using launchctl (Legacy)"
        case .unknown: "Checking service method..."
        }
    }

    private var activeMethodDescription: String {
        switch activeMethod {
        case .smappservice: "Modern service management via System Settings"
        case .launchctl: "Traditional service management via launchctl"
        case .unknown: "Determining active service method"
        }
    }

    @ViewBuilder
    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HelperStatusDot(color: helperInstalled ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    if helperInstalled {
                        Text("Installed\(helperVersion.map { " (v\($0))" } ?? "")")
                            .font(.body)
                            .fontWeight(.medium)
                    } else {
                        Text("Not Installed")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Text("The helper performs privileged actions like service registration and cleanup.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    showingCleanupRepair = true
                } label: {
                    Label("Cleanup & Repair…", systemImage: "wrench.adjustable.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(helperInProgress)

                Button(role: .destructive) {
                    showingHelperUninstallConfirm = true
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(helperInProgress || !helperInstalled)
            }

            if helperInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Working…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if let helperMessage, !helperMessage.isEmpty {
                Text(helperMessage)
                    .font(.footnote)
                    .foregroundColor(helperMessage.contains("successfully") ? .green : .orange)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use this when the service is completely wedged and won't respond to normal controls.")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button {
                showingResetEverythingConfirmation = true
            } label: {
                Label("Reset Everything", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button(role: .destructive) {
                NotificationCenter.default.post(name: NSNotification.Name("ShowUninstall"), object: nil)
            } label: {
                Label("Uninstall KeyPath…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func refreshHelperStatus() async {
        await MainActor.run {
            helperInstalled = HelperManager.shared.isHelperInstalled()
        }
        let version = await HelperManager.shared.getHelperVersion()
        await MainActor.run { helperVersion = version }
    }

    private func uninstallHelper() async {
        await MainActor.run {
            helperInProgress = true
            helperMessage = nil
        }
        defer {
            Task {
                await MainActor.run {
                    helperInProgress = false
                    showingHelperUninstallConfirm = false
                }
            }
        }

        do {
            try await HelperManager.shared.uninstallHelper()
            await MainActor.run {
                helperMessage = "Helper uninstalled"
                settingsToastManager.showSuccess("Helper uninstalled")
            }
        } catch {
            await MainActor.run {
                helperMessage = "Uninstall failed: \(error.localizedDescription)"
                settingsToastManager.showError("Uninstall failed")
            }
        }
        await refreshHelperStatus()
    }

    private func removeDuplicateAppCopies() async {
        await MainActor.run { removeDuplicatesInProgress = true }
        defer {
            Task {
                await MainActor.run {
                    removeDuplicatesInProgress = false
                }
            }
        }

        let keepPath = "/Applications/KeyPath.app"
        let manager = FileManager.default
        var removed = 0
        for path in duplicateAppCopies where path != keepPath {
            let url = URL(fileURLWithPath: path)
            if manager.fileExists(atPath: path) {
                do {
                    try manager.trashItem(at: url, resultingItemURL: nil)
                    removed += 1
                } catch {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }

        let refreshed = HelperMaintenance.shared.detectDuplicateAppCopies()
        await MainActor.run {
            duplicateAppCopies = refreshed
            if removed > 0 {
                settingsToastManager.showSuccess("Removed \(removed) extra copy\(removed == 1 ? "" : "ies")")
            } else {
                settingsToastManager.showInfo("No extra copies removed")
            }
        }
    }

    private func performResetEverything() async {
        let autoFixer = WizardAutoFixer(kanataManager: kanataManager.underlyingManager)
        _ = await autoFixer.resetEverything()
        await kanataManager.forceRefreshStatus()
        await MainActor.run {
            settingsToastManager.showInfo("Reset everything complete")
        }
    }

    private func refreshServiceStatus() async {
        await MainActor.run {
            let state = KanataDaemonManager.determineServiceManagementState()
            switch state {
            case .legacyActive:
                activeMethod = .launchctl
            case .smappserviceActive, .smappservicePending:
                activeMethod = .smappservice
            case .conflicted:
                activeMethod = .launchctl  // Show migration section when conflicted!
            case .unknown, .uninstalled:
                activeMethod = .unknown
            }
        }
    }
}

// MARK: - Local Components

private struct HelperStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

private struct AdvancedDuplicateCallout: View {
    let count: Int
    let isBusy: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected \(count) KeyPath installations.")
                        .font(.subheadline.weight(.semibold))
                    Text("Extra copies can cause stale approvals. Remove extras to keep permissions healthy.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Button(action: onRemove) {
                Label("Remove Extras", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
