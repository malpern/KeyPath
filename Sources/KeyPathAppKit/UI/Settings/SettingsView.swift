import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - Status Settings Tab

struct StatusSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager

    @State var wizardInitialPage: WizardPage? // nil = don't show wizard
    @State private var showSetupBanner = false
    @State var permissionSnapshot: PermissionOracle.Snapshot?
    @State var systemContext: SystemContext?
    @State var wizardSystemState: WizardSystemState = .initializing
    @State var wizardIssues: [WizardIssue] = []
    @State var tcpConfigured: Bool?
    @State var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State var showingPermissionAlert = false
    @State private var refreshRetryScheduled = false
    @State private var localServiceRunning: Bool? // Optimistic local state for instant toggle feedback

    private var isServiceRunning: Bool {
        systemContext?.services.kanataRunning ?? false
    }

    /// Effective service running state: use local optimistic value if set, otherwise actual state
    private var effectiveServiceRunning: Bool {
        localServiceRunning ?? isServiceRunning
    }

    var hasFullDiskAccess: Bool {
        FullDiskAccessChecker.shared.hasFullDiskAccess()
    }

    private var isSystemHealthy: Bool {
        overallHealthLevel == .success
    }

    /// True when the only permission issue is unverified kanata (no FDA to check)
    private var isOnlyKanataUnverified: Bool {
        guard let snapshot = permissionSnapshot, !hasFullDiskAccess else { return false }
        let evaluation = permissionGaps(in: snapshot)
        return evaluation.missingOrDenied.isEmpty && !evaluation.unknown.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if FeatureFlags.allowOptionalWizard, showSetupBanner {
                SetupBanner {
                    wizardInitialPage = .summary
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            // System Status Hero Section
            HStack(alignment: .top, spacing: 40) {
                // Large status indicator with centered toggle
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(systemHealthTint.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Button(action: { wizardInitialPage = .summary }) {
                                Image(systemName: systemHealthIcon)
                                    .font(.largeTitle)
                                    .foregroundColor(systemHealthTint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("status-system-health-button")
                            .accessibilityLabel("System status: \(systemHealthMessage)")
                        }

                        VStack(spacing: 4) {
                            Text(systemHealthMessage)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)

                            if let issue = primaryIssueDetail {
                                Text(issue.message)
                                    .font(.footnote)
                                    .foregroundColor(issue.level.tintColor)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button(action: {
                                NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                            }) {
                                let enabledCollections = kanataManager.ruleCollections.filter(\.isEnabled).count
                                let enabledCustomRules = kanataManager.customRules.filter(\.isEnabled).count
                                let activeCount = enabledCollections + enabledCustomRules
                                Text(activeRulesText(count: activeCount))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("status-active-rules-button")
                            .accessibilityLabel("View active rules")
                        }
                    }

                    // Action button when there are problems
                    if !isSystemHealthy {
                        if isOnlyKanataUnverified {
                            // Only issue is unverified kanata — lead with FDA
                            Button(action: { SystemDiagnostics.open(.fullDiskAccess) }) {
                                Label("Enable Enhanced Diagnostics", systemImage: "checkmark.shield")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.blue)
                            .accessibilityIdentifier("status-enable-fda-button")
                        } else {
                            Button(action: { wizardInitialPage = .summary }) {
                                Label("Fix it", systemImage: "wand.and.stars")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(overallHealthLevel == .critical ? .red : .orange)
                            .accessibilityIdentifier("status-fix-it-button")
                            .accessibilityLabel("Fix system issues")
                        }
                    }

                    // Centered toggle
                    HStack(spacing: 12) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { effectiveServiceRunning },
                                set: { newValue in
                                    // Optimistic update: change UI immediately
                                    localServiceRunning = newValue
                                    // Then trigger async operation
                                    Task {
                                        if newValue {
                                            await startViaInstallerEngine()
                                        } else {
                                            await stopViaInstallerEngine()
                                        }
                                        await refreshStatus()
                                    }
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .accessibilityIdentifier("status-service-toggle")
                        .accessibilityLabel("KeyPath Runtime")

                        Text(effectiveServiceRunning ? "ON" : "OFF")
                            .font(.body.weight(.medium))
                            .foregroundColor(effectiveServiceRunning ? .green : .secondary)
                    }

                    if let runtimePathTitle = kanataManager.activeRuntimePathTitle {
                        VStack(spacing: 4) {
                            Text(runtimePathTitle)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.secondary)

                            if let runtimePathDetail = kanataManager.activeRuntimePathDetail {
                                Text(runtimePathDetail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: 220)
                        .accessibilityIdentifier("status-runtime-path")
                        .accessibilityLabel(
                            "Active runtime path: \(runtimePathTitle)\(kanataManager.activeRuntimePathDetail.map { ", \($0)" } ?? "")"
                        )
                    }
                }
                .frame(minWidth: 220)

                // Permissions grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        PermissionStatusRow(
                            title: "KeyPath Accessibility",
                            icon: "checkmark.shield",
                            status: permissionSnapshot?.keyPath.accessibility,
                            isKanata: false,
                            hasFullDiskAccess: hasFullDiskAccess,
                            onTap: { wizardInitialPage = .accessibility }
                        )

                        PermissionStatusRow(
                            title: "KeyPath Input Monitoring",
                            icon: "keyboard",
                            status: permissionSnapshot?.keyPath.inputMonitoring,
                            isKanata: false,
                            hasFullDiskAccess: hasFullDiskAccess,
                            onTap: { wizardInitialPage = .inputMonitoring }
                        )

                        PermissionStatusRow(
                            title: "Kanata Accessibility",
                            icon: "checkmark.shield",
                            status: permissionSnapshot?.kanata.accessibility,
                            isKanata: true,
                            hasFullDiskAccess: hasFullDiskAccess,
                            onTap: { wizardInitialPage = .accessibility }
                        )

                        PermissionStatusRow(
                            title: "Kanata Input Monitoring",
                            icon: "keyboard",
                            status: permissionSnapshot?.kanata.inputMonitoring,
                            isKanata: true,
                            hasFullDiskAccess: hasFullDiskAccess,
                            onTap: { wizardInitialPage = .inputMonitoring }
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Status")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 10)

                        ForEach(systemStatusRows) { row in
                            SettingsSystemStatusRow(
                                title: row.title,
                                icon: row.icon,
                                status: row.status,
                                message: row.message,
                                onTap: row.targetPage.map { page in
                                    { wizardInitialPage = page }
                                }
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer()
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .sheet(item: $wizardInitialPage, onDismiss: {
            Task { await refreshStatus() }
        }) { page in
            InstallationWizardView(initialPage: page)
                .customizeSheetWindow()
                .environment(kanataManager)
                .environment(\.runtimeCoordinator, WizardDependencies.runtimeCoordinator)
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("Open Wizard") {
                wizardInitialPage = .summary
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "KeyPath needs system permissions to remap your keyboard. The installation wizard will guide you through granting the necessary permissions."
            )
        }
        .task {
            await refreshStatus()
        }
        // Removed legacy onReceive(currentState)
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task {
                await refreshStatus()
            }
        }
        .onChange(of: isServiceRunning) { _, _ in
            // Sync local optimistic state when actual service state updates
            localServiceRunning = nil
        }
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        // Use RuntimeCoordinator (via façade) to get fresh status
        let context = await kanataManager.inspectSystemContext()
        let snapshot = context.permissions
        let adapted = await MainActor.run { SystemContextAdapter.adapt(context) }
        let tcpOk = await checkTCPConfiguration()
        let duplicates = HelperMaintenance.shared.detectDuplicateAppCopies()

        await MainActor.run {
            permissionSnapshot = snapshot
            systemContext = context
            wizardSystemState = adapted.state
            wizardIssues = adapted.issues
            tcpConfigured = tcpOk
            showSetupBanner = !(snapshot.isSystemReady && context.services.isHealthy)
                || duplicates.count > 1
                || (context.services.kanataRunning && !tcpOk)
            duplicateAppCopies = duplicates
        }

        // If services look “starting” (daemons loaded/healthy but kanata not yet running), retry once shortly.
        if !context.services.kanataRunning,
           context.services.karabinerDaemonRunning,
           refreshRetryScheduled == false
        {
            refreshRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    refreshRetryScheduled = false
                    await refreshStatus()
                }
            }
        }
    }

    private func startViaInstallerEngine() async {
        await MainActor.run {
            settingsToastManager.showInfo("Starting…")
        }

        let started = await kanataManager.startKanata(reason: "Status tab start button")
        await refreshStatus()

        await MainActor.run {
            if started {
                settingsToastManager.showSuccess("KeyPath activated")
            } else {
                let reason = kanataManager.lastError ?? "Service did not start"
                settingsToastManager.showError("Start failed: \(reason)")
            }
        }
    }

    private func stopViaInstallerEngine() async {
        let stopped = await kanataManager.stopKanata(reason: "Status tab stop button")
        await refreshStatus()
        await MainActor.run {
            if stopped {
                settingsToastManager.showInfo("KeyPath deactivated")
            } else {
                let reason = kanataManager.lastError ?? "Service did not stop"
                settingsToastManager.showError("Stop failed: \(reason)")
            }
        }
    }

    private func checkTCPConfiguration() async -> Bool {
        // Keep this fast and predictable: only verify the active plist contains a --port argument.
        let plistPath = KanataDaemonManager.getActivePlistPath()
        guard Foundation.FileManager().fileExists(atPath: plistPath) else { return false }

        let args: [String]
        do {
            let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
            guard let plist = try PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil
            ) as? [String: Any],
                let programArgs = plist["ProgramArguments"] as? [String]
            else {
                return false
            }
            args = programArgs
        } catch {
            AppLogger.shared.warn("⚠️ [SettingsView] Failed to read daemon plist: \(error.localizedDescription)")
            return false
        }

        return args.contains("--port")
    }

    private var systemStatusRows: [SettingsSystemStatusRowModel] {
        SettingsSystemStatusRowsBuilder.rows(
            wizardSystemState: wizardSystemState,
            wizardIssues: wizardIssues,
            systemContext: systemContext,
            tcpConfigured: tcpConfigured,
            hasFullDiskAccess: hasFullDiskAccess
        )
    }

    /// Returns localized "X active rule(s)" text with proper pluralization
    private func activeRulesText(count: Int) -> String {
        String(
            localized: "\(count) active rules",
            comment: "Count of active keyboard rules"
        )
    }
}
