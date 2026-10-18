import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - Status Settings Tab

struct StatusSettingsTabView: View {
    @Environment(KanataViewModel.self) var kanataManager
    @State private var autoDetectController = AutoDetectKeyboardController.shared

    @State var wizardInitialPage: WizardPage? // nil = don't show wizard
    @State private var showSetupBanner = false
    @State var permissionSnapshot: PermissionOracle.Snapshot?
    @State var systemContext: SystemContext?
    @State var wizardSystemState: WizardSystemState = .initializing
    @State var wizardIssues: [WizardIssue] = []
    var isDriverless: Bool {
        (permissionSnapshot?.backend ?? KanataRuntimeBackend.selected) == .session
    }

    @State var tcpConfigured: Bool?
    @State var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State var showingPermissionAlert = false
    @State private var localServiceRunning: Bool? // Optimistic local state for instant toggle feedback

    /// Persisted record that the user explicitly switched the service off (as
    /// opposed to it being unexpectedly down). Drives the calm "KeyPath is Off"
    /// presentation, survives relaunch, and — unlike the optimistic
    /// `localServiceRunning` — is NOT cleared when the actual service state
    /// changes (see the `onChange(of: isServiceRunning)` handler). Cleared when
    /// the user switches the service back on.
    @AppStorage("KeyPath.Status.UserDisabledService") private var userDisabledService = false

    private var isServiceRunning: Bool {
        systemContext?.services.kanataRunning ?? false
    }

    /// Effective service running state: use local optimistic value if set, otherwise actual state
    private var effectiveServiceRunning: Bool {
        localServiceRunning ?? isServiceRunning
    }

    private var activeRulesCount: Int {
        kanataManager.ruleCollections.filter(\.isEnabled).count
            + kanataManager.customRules.filter(\.isEnabled).count
    }

    private var isSystemHealthy: Bool {
        overallHealthLevel == .success
    }

    /// True when the user has deliberately switched the service off, as opposed
    /// to the service being unexpectedly down. Drives the calm "disabled"
    /// presentation (gray, no "Fix it") instead of treating an intentional OFF
    /// as a fault. Uses the optimistic `effectiveServiceRunning` so the calm
    /// state appears the instant the toggle flips, and only asserts while the
    /// service is actually not running. Accessible from the StatusDetails
    /// extension.
    var isIntentionallyDisabled: Bool {
        userDisabledService && !effectiveServiceRunning
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if FeatureFlags.allowOptionalWizard, showSetupBanner {
                    SetupBanner {
                        wizardInitialPage = .summary
                    }
                    .padding(.horizontal, SettingsDesign.pageInset)
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
                                .accessibilityValue(overallHealthLevel.accessibilityValue)
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
                                    Text(activeRulesText(count: activeRulesCount))
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("status-active-rules-button")
                                .accessibilityLabel("View active rules")
                                .accessibilityValue(activeRulesText(count: activeRulesCount))
                            }
                        }

                        // Action button when there are problems. Suppressed when the
                        // user has intentionally turned the service off — nothing is
                        // broken, so there's nothing to fix.
                        if !isSystemHealthy, !isIntentionallyDisabled {
                            Button(action: { wizardInitialPage = .summary }) {
                                Label("Fix it", systemImage: "wand.and.stars")
                                    .font(.body.weight(.semibold))
                            }
                            .settingsPrimaryAction()
                            .controlSize(.large)
                            .tint(overallHealthLevel == .critical ? .red : .orange)
                            .accessibilityIdentifier("status-fix-it-button")
                            .accessibilityLabel("Fix system issues")
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
                                        // Record explicit user intent (persists across
                                        // relaunch and the isServiceRunning onChange reset).
                                        userDisabledService = !newValue
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
                            .accessibilityValue(effectiveServiceRunning ? "on" : "off")

                            Text(effectiveServiceRunning ? "ON" : "OFF")
                                .font(.body.weight(.medium))
                                .foregroundColor(effectiveServiceRunning ? .green : .secondary)
                        }

                        if !isDriverless, let runtimePathTitle = kanataManager.activeRuntimePathTitle {
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

                    // One flat list: permissions, the runtime's own checks, then system status.
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionStatusRow(
                            title: isDriverless ? AccessibilityPermissionPresentation.current.name : "KeyPath \(AccessibilityPermissionPresentation.current.name)",
                            icon: "checkmark.shield",
                            status: isDriverless ? SettingsPermissionSummary.combine(permissionSnapshot?.keyPath.accessibility, permissionSnapshot?.kanata.accessibility) : permissionSnapshot?
                                .keyPath.accessibility,
                            isKanata: false,
                            onTap: { wizardInitialPage = .accessibility },
                            identifier: isDriverless ? "settings-status-action-button-accessibility"
                                : "settings-status-action-button-keypath-accessibility"
                        )

                        PermissionStatusRow(
                            title: isDriverless ? "Input Monitoring" : "KeyPath Input Monitoring",
                            icon: "keyboard",
                            status: isDriverless ? SettingsPermissionSummary.combine(permissionSnapshot?.keyPath.inputMonitoring, permissionSnapshot?.kanata.inputMonitoring) : permissionSnapshot?
                                .keyPath.inputMonitoring,
                            isKanata: false,
                            onTap: { wizardInitialPage = .inputMonitoring }
                        )

                        // In driverless mode these match the two rows above; only the
                        // legacy backend's separate runtime has its own permissions.
                        if !isDriverless {
                            runtimePermissionRows
                        }

                        ForEach(systemStatusRows) { row in
                            SettingsSystemStatusRow(
                                id: row.id,
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("settings-status-list")

                    Spacer()
                }
                .padding(.horizontal, SettingsDesign.pageInset)
                .padding(.top, 24)

                keyboardDetailsSection
                    .padding(.horizontal, SettingsDesign.pageInset)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
            }
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .sheet(item: $wizardInitialPage, onDismiss: {
            PermissionRequestService.shared.leaveWizardContext()
            Task { await refreshStatus() }
        }) { page in
            InstallationWizardView(initialPage: page)
                .customizeSheetWindow()
                .environment(kanataManager)
                .environment(\.runtimeCoordinator, WizardDependencies.runtimeCoordinator)
                .onAppear { PermissionRequestService.shared.enterWizardContext() }
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
        // Subscribe to background validation from MainAppStateController.
        // When the periodic validation loop (every ~60s) or service health change
        // triggers a revalidation, this ensures the Settings tab updates automatically
        // instead of showing stale data from the initial .task fetch.
        .onChange(of: MainAppStateController.shared.lastValidationDate) { _, _ in
            copyPublishedStatus()
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

    private var keyboardDetailsSection: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionContentGap) {
            SettingsSectionHeader(title: "Connected Keyboard")

            if let activeKeyboard = autoDetectController.activeKeyboard {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(activeKeyboard.keyboardName)
                            .font(.body.weight(.medium))
                        Text([activeKeyboard.manufacturer,
                              activeKeyboard.status == .remembered ? "Remembered" : "Connected"]
                                .compactMap(\.self).joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        autoDetectController.presentKeyboardSearch(for: activeKeyboard.id)
                        LiveKeyboardOverlayController.shared.showForQuickLaunch()
                    } label: {
                        HStack(spacing: 4) {
                            Text(activeKeyboard.layoutId.flatMap { PhysicalLayout.find(id: $0)?.name } ?? "Choose layout")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .accessibilityIdentifier("status-search-keyboard-layouts-button")

                    Button("Forget", role: .destructive) {
                        autoDetectController.forgetKeyboard(activeKeyboard.id)
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundColor(.red)
                    .help("Forget This Keyboard")
                    .accessibilityLabel("Forget This Keyboard")
                    .accessibilityIdentifier("status-forget-keyboard-button")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                // Diagnostics stay reachable without taking space.
                .help("""
                VID:PID \(activeKeyboard.vidPidKey) · \(activeKeyboard.source?.rawValue.capitalized ?? "Manual") · \
                match \(activeKeyboard.matchType?.rawValue ?? "none") · \
                \(activeKeyboard.confidence?.rawValue ?? "unknown") confidence
                """)
                .accessibilityIdentifier("status-connected-keyboard-panel")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.tertiary)
                    Text(permissionSnapshot?.keyPath.inputMonitoring.isReady == true
                        ? "No keyboard detected"
                        : "Keyboard discovery unavailable until Input Monitoring is enabled for KeyPath.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .accessibilityIdentifier("status-no-connected-keyboard-panel")
            }
        }
    }

    private var runtimePermissionRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            PermissionStatusRow(
                title: permissionSnapshot?.backend == .session
                    ? "KeyPath Runtime Accessibility" : "Kanata Accessibility",
                icon: "checkmark.shield",
                status: permissionSnapshot?.kanata.accessibility,
                isKanata: true,
                onTap: { wizardInitialPage = .accessibility }
            )

            PermissionStatusRow(
                title: permissionSnapshot?.backend == .session
                    ? "KeyPath Runtime Input Monitoring" : "Kanata Input Monitoring",
                icon: "keyboard",
                status: permissionSnapshot?.kanata.inputMonitoring,
                isKanata: true,
                onTap: { wizardInitialPage = .inputMonitoring }
            )
        }
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        let controller = MainAppStateController.shared

        // Trigger a revalidation if stale, then read the published state.
        await controller.revalidate()

        copyPublishedStatus()
    }

    /// Copy the controller's latest published evidence without triggering a
    /// second validation. This is used by the validation-date subscription so
    /// observing a completed validation cannot feed back into another capture.
    private func copyPublishedStatus() {
        let controller = MainAppStateController.shared

        let context = controller.lastValidatedSystemContext ?? .empty
        let duplicates = HelperMaintenance.shared.detectDuplicateAppCopies()

        permissionSnapshot = context.permissions
        systemContext = context
        wizardSystemState = controller.lastAdaptedState
        wizardIssues = controller.issues
        tcpConfigured = controller.lastTCPConfigured
        showSetupBanner = !(context.permissions.isSystemReady && context.services.isHealthy)
            || (context.services.kanataRunning && controller.lastTCPConfigured == false)
        duplicateAppCopies = duplicates
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

    private var systemStatusRows: [SettingsSystemStatusRowModel] {
        SettingsSystemStatusRowsBuilder.rows(
            wizardSystemState: wizardSystemState,
            wizardIssues: wizardIssues,
            systemContext: systemContext,
            tcpConfigured: tcpConfigured,
            driverless: isDriverless
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
