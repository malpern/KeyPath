import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore
import SwiftUI

struct AdvancedSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager

    @State private var showingUninstall = false
    @State private var duplicateAppCopies: [String] = []
    @State private var removeDuplicatesInProgress = false

    @State private var showingRemoveDuplicatesConfirm = false

    @State private var backups: [BackupInfo] = []
    @State private var backupToRestore: BackupInfo?
    @State private var showingRestoreConfirm = false
    @State private var restoreInProgress = false

    @State private var settingsToastManager = WizardToastManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Section with Uninstall
                HStack(alignment: .top, spacing: 40) {
                    // Left: Uninstall section
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.15))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "trash.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                            }

                            VStack(spacing: 4) {
                                Text("Uninstall KeyPath")
                                    .font(.title3.weight(.semibold))
                                    .multilineTextAlignment(.center)
                            }
                        }

                        Text("Back up your rules and settings, then remove KeyPath. Reinstalling starts fresh.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 220)

                        Button("Uninstall KeyPath…", role: .destructive) { showingUninstall = true }
                            .settingsAction()
                            .accessibilityIdentifier("settings-uninstall-keypath-button")
                    }
                    .frame(minWidth: 220)

                    // Right: Repair tools in priority order
                    VStack(alignment: .leading, spacing: 20) {
                        // Simulator
                        SettingsSection(title: "Simulator") {
                            Text("Advanced virtual keyboard testing for key behaviors, app context, and timing.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                SimulatorWindowController.shared.showWindow()
                            } label: {
                                Label("Open Simulator", systemImage: "keyboard")
                            }
                            .settingsAction()
                            .accessibilityIdentifier("settings-open-simulator-button")
                            .accessibilityLabel("Open Simulator")
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, SettingsDesign.pageInset)
                .padding(.top, 24)

                // Duplicate apps warning
                if duplicateAppCopies.count > 1 {
                    SettingsSection(title: "Other Copies of KeyPath") {
                        duplicateAppsSection
                    }
                    .padding(.horizontal, SettingsDesign.pageInset)
                    .padding(.top, 20)
                }

                // Configuration Backups
                configBackupsSection
                    .padding(.horizontal, SettingsDesign.pageInset)
                    .padding(.top, 20)
            }
        }
        .sheet(isPresented: $showingUninstall) {
            UninstallKeyPathDialog().environment(kanataManager)
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .task {
            duplicateAppCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
            backups = kanataManager.underlyingManager.configBackupManager.getAvailableBackups()
        }
        .alert("Move Extra Copies to Trash?", isPresented: $showingRemoveDuplicatesConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await removeDuplicateAppCopies() }
            }
        } message: {
            Text("The copy in Applications stays. You can restore the others from the Trash.")
        }
        .alert("Restore Configuration?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) {
                backupToRestore = nil
            }
            Button("Restore", role: .destructive) {
                if let backup = backupToRestore {
                    Task { await restoreBackup(backup) }
                }
            }
        } message: {
            if let backup = backupToRestore {
                Text("Restore rules and configuration from \(backup.formattedDate)?")
            }
        }
    }

    // MARK: - Sections

    private var duplicateAppsSection: some View {
        let extras = duplicateAppCopies.filter { $0 != "/Applications/KeyPath.app" }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Extra copies can confuse macOS permissions. Keep only the one in Applications.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(extras, id: \.self) { path in
                HStack(spacing: 10) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text(HelperMaintenance.displayLocation(forAppAt: path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Spacer()
                    Button("Show") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .settingsAction()
                    .accessibilityIdentifier("settings-show-duplicate-\(abs(path.hashValue))")
                }
            }

            Button(role: .destructive) {
                showingRemoveDuplicatesConfirm = true
            } label: {
                Text(removeDuplicatesInProgress ? "Moving to Trash\u{2026}" : "Move Extras to Trash")
            }
            .settingsAction()
            .disabled(removeDuplicatesInProgress)
            .accessibilityIdentifier("settings-remove-duplicates-button")
            .accessibilityLabel("Move extra copies to Trash")
        }
    }

    // MARK: - Configuration Backups

    private var configBackupsSection: some View {
        SettingsSection(title: "Configuration Backups") {
            Text("KeyPath keeps up to 5 recent rule and configuration backups. Older config-only backups can be opened for manual recovery.")
                .font(.caption)
                .foregroundColor(.secondary)

            if backups.isEmpty {
                Text("No backups yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(backups.enumerated()), id: \.element.filename) { index, backup in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.createdAt.relativeDescription)
                                    .font(.subheadline)
                                Text("\(backup.formattedDate) \u{2022} \(backup.formattedSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Open") {
                                openFileInPreferredEditor(URL(fileURLWithPath: backup.fullPath))
                            }
                            .accessibilityIdentifier("settings-open-backup-\(index)")

                            Button("Restore") {
                                backupToRestore = backup
                                showingRestoreConfirm = true
                            }
                            .settingsAction()
                            .accessibilityIdentifier("settings-restore-backup-\(index)")
                            .disabled(restoreInProgress || !FileManager.default.fileExists(atPath: backup.fullPath + ".json"))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        if index < backups.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @MainActor
    private func restoreBackup(_ backup: BackupInfo) async {
        guard !restoreInProgress else { return }
        restoreInProgress = true
        defer { restoreInProgress = false; backupToRestore = nil }
        let result = await kanataManager.underlyingManager.restoreFromBackup(backup)
        backups = kanataManager.underlyingManager.configBackupManager.getAvailableBackups()
        if result.success {
            if result.reloadResult?.disposition == .pending {
                settingsToastManager.showInfo("Rules restored. Start KeyPath to apply them.")
            } else {
                settingsToastManager.showSuccess("Restored rules from \(backup.createdAt.relativeDescription)")
            }
        } else {
            settingsToastManager.showError("Restore failed: \(result.error?.localizedDescription ?? "Your current setup was kept.")")
        }
    }

    // MARK: - Actions

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
        let manager = Foundation.FileManager()
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
                settingsToastManager.showSuccess(
                    "Removed \(removed) extra copy\(removed == 1 ? "" : "ies")"
                )
            } else {
                settingsToastManager.showInfo("No extra copies removed")
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

private extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
