import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
  case status
  case rules
  case general
  case advanced

  var title: String {
    switch self {
    case .general: "General"
    case .status: "Status"
    case .rules: "Rules"
    case .advanced: "Repair/Remove"
    }
  }

  var icon: String {
    switch self {
    case .general: "gearshape"
    case .status: "gauge.with.dots.needle.bottom.50percent"
    case .rules: "list.bullet"
    case .advanced: "wrench.and.screwdriver"
    }
  }
}

struct SettingsContainerView: View {
  @EnvironmentObject var kanataManager: KanataViewModel
  @State private var selection: SettingsTab = .status

  var body: some View {
    VStack(spacing: 0) {
      SettingsTabPicker(selection: $selection)
        .padding(.bottom, 12)

      Group {
        switch selection {
        case .general:
          GeneralSettingsTabView()
        case .status:
          StatusSettingsTabView()
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
    .onReceive(NotificationCenter.default.publisher(for: .openSettingsStatus)) { _ in
      selection = .status
    }
    .onReceive(NotificationCenter.default.publisher(for: .showDiagnostics)) { _ in
      selection = .advanced
      // Post another notification to switch to errors tab within advanced settings
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NotificationCenter.default.post(name: .showErrorsTab, object: nil)
      }
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
              .stroke(
                isSelected ? Color.accentColor : Color(NSColor.separatorColor),
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
                .font(.system(size: 40))
                .foregroundColor(.red)
            }

            VStack(spacing: 4) {
              Text("Uninstall KeyPath")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            }
          }

          // Uninstall button
          Button(role: .destructive) {
            NotificationCenter.default.post(name: NSNotification.Name("ShowUninstall"), object: nil)
          } label: {
            Text("Uninstall")
              .frame(minWidth: 100)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
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
              Button {
                showingCleanupRepair = true
              } label: {
                Label("Cleanup & Repair", systemImage: "wrench.adjustable.circle")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(helperInProgress)

              Button(role: .destructive) {
                showingHelperUninstallConfirm = true
              } label: {
                Label("Uninstall Helper", systemImage: "trash")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(helperInProgress || !helperInstalled)
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
          }
        }

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 24)

      // Service Management - only show if there's an issue
      if activeMethod != .smappservice {
        VStack(alignment: .leading, spacing: 12) {
          Text("Service Management")
            .font(.headline)
            .foregroundColor(.secondary)

          serviceManagementSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
      }

      // Duplicate apps warning
      if duplicateAppCopies.count > 1 {
        VStack(alignment: .leading, spacing: 12) {
          Text("⚠️ Multiple Installations")
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
        Label(
          removeDuplicatesInProgress ? "Removing…" : "Remove Extra Copies", systemImage: "trash")
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
      if activeMethod == .launchctl, KanataDaemonManager.shared.hasLegacyInstallation() {
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
        settingsToastManager.showSuccess(
          "Removed \(removed) extra copy\(removed == 1 ? "" : "ies")")
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

// MARK: - Verbose Logging Toggle

struct VerboseLoggingToggle: View {
  @State private var verboseLogging = PreferencesService.shared.verboseKanataLogging
  @State private var showingRestartAlert = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: $verboseLogging) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Verbose Kanata Logging")
            .font(.body)
            .fontWeight(.medium)

          Text("Enable comprehensive trace logging with event timing")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .toggleStyle(.switch)
      .onChange(of: verboseLogging) { _, newValue in
        Task { @MainActor in
          PreferencesService.shared.verboseKanataLogging = newValue
          showingRestartAlert = true
        }
      }

      if verboseLogging {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
            .font(.caption)

          Text(
            "Trace logging generates large log files. Use for debugging key repeat or performance issues only."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
      }
    }
    .alert("Service Restart Required", isPresented: $showingRestartAlert) {
      Button("Later", role: .cancel) {}
      Button("Restart Now") {
        Task {
          await restartKanataService()
        }
      }
    } message: {
      Text(
        "Kanata needs to restart for the new logging setting to take effect. Would you like to restart now?"
      )
    }
  }

  private func restartKanataService() async {
    AppLogger.shared.log("🔄 [VerboseLogging] Restarting Kanata service with new logging flags")
    // Post notification to trigger service restart
    NotificationCenter.default.post(name: .retryStartService, object: nil)
  }
}
