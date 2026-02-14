import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

struct AdvancedSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager

    @State private var helperInstalled: Bool = false
    @State private var helperVersion: String?
    @State private var helperInProgress = false
    @State private var helperMessage: String?
    @State private var duplicateAppCopies: [String] = []
    @State private var removeDuplicatesInProgress = false

    @State private var showingHelperUninstallConfirm = false
    @State private var showingRemoveDuplicatesConfirm = false
    @State private var showingResetEverythingConfirmation = false
    @State private var showingUninstallDialog = false

    @State private var settingsToastManager = WizardToastManager()

    var body: some View {
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

                    // Uninstall button (primary - Enter key triggers)
                    Button(role: .destructive) {
                        showingUninstallDialog = true
                    } label: {
                        Text("Uninstall")
                            .frame(minWidth: 100)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("settings-uninstall-button")
                    .accessibilityLabel("Uninstall KeyPath")
                }
                .frame(minWidth: 220)

                // Right: Helper and Recovery Tools
                VStack(alignment: .leading, spacing: 20) {
                    // Privileged Helper
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privileged Helper")
                            .font(.headline)
                            .foregroundColor(.secondary)

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
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button(role: .destructive) {
                                showingHelperUninstallConfirm = true
                            } label: {
                                Label("Uninstall Helper", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(helperInProgress || !helperInstalled)
                            .accessibilityIdentifier("settings-uninstall-helper-button")
                            .accessibilityLabel("Uninstall Privileged Helper")
                        }
                    }

                    // Reset Everything
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emergency Recovery")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Use when service is wedged and won't respond")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            showingResetEverythingConfirmation = true
                        } label: {
                            Label("Reset Everything", systemImage: "exclamationmark.triangle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings-reset-everything-button")
                        .accessibilityLabel("Reset Everything")
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            // Duplicate apps warning
            if duplicateAppCopies.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\u{26A0}\u{FE0F} Multiple Installations")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    duplicateAppsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            Spacer()
        }
        .frame(maxHeight: 350)
        .settingsBackground()
        .withToasts(settingsToastManager)
        .sheet(isPresented: $showingUninstallDialog) {
            UninstallKeyPathDialog()
                .environment(kanataManager)
        }
        .task {
            await refreshHelperStatus()
            duplicateAppCopies = HelperMaintenance.shared.detectDuplicateAppCopies()
        }
        .alert("Uninstall Privileged Helper?", isPresented: $showingHelperUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await uninstallHelper() }
            }
        } message: {
            Text(
                "The helper enables privileged actions without repeated admin prompts. You can reinstall it from the Setup Wizard."
            )
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
            Text(
                "Force kill Kanata, remove PID files, and clear transient state. Service does not restart automatically."
            )
        }
    }

    // MARK: - Sections

    private var duplicateAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Found \(duplicateAppCopies.count) copies of KeyPath installed")
                        .font(.body.weight(.semibold))

                    Text(
                        "Extra copies can cause stale TCC approvals and permission issues. We recommend keeping only the copy in /Applications."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Copies found at:")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(duplicateAppCopies, id: \.self) { path in
                            Text("\u{2022} \(path)")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Button(action: {
                showingRemoveDuplicatesConfirm = true
            }) {
                Label(
                    removeDuplicatesInProgress ? "Removing\u{2026}" : "Remove Extra Copies", systemImage: "trash"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(removeDuplicatesInProgress)
            .accessibilityIdentifier("settings-remove-duplicates-button")
            .accessibilityLabel("Remove Extra Copies")
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func refreshHelperStatus() async {
        let installed = await HelperManager.shared.isHelperInstalled()
        await MainActor.run {
            helperInstalled = installed
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
                settingsToastManager.showSuccess(
                    "Removed \(removed) extra copy\(removed == 1 ? "" : "ies")"
                )
            } else {
                settingsToastManager.showInfo("No extra copies removed")
            }
        }
    }

    private func performResetEverything() async {
        let report = await InstallerEngine()
            .runSingleAction(.restartUnhealthyServices, using: PrivilegeBroker())
        await MainActor.run {
            if report.success {
                settingsToastManager.showInfo("Reset everything complete")
            } else {
                settingsToastManager.showError(
                    report.failureReason ?? "Reset everything failed"
                )
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
