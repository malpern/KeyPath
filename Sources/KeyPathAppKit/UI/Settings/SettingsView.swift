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
    @State var tcpConfigured: Bool?
    @State var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State var showingPermissionAlert = false
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
        ScrollView {
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

            keyboardDetailsSection
                .padding(.horizontal, 20)
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
            Task {
                await refreshStatus()
            }
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

    @State private var showKeyboardDetails = false

    @ViewBuilder
    private var keyboardDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connected Keyboard")
                .font(.headline)
                .foregroundColor(.secondary)

            if let activeKeyboard = autoDetectController.activeKeyboard {
                VStack(alignment: .leading, spacing: 16) {
                    // Hero: icon + name + status
                    HStack(spacing: 14) {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeKeyboard.keyboardName)
                                .font(.body.weight(.semibold))

                            if let manufacturer = activeKeyboard.manufacturer {
                                Text(manufacturer)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 5) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text(activeKeyboard.status == .remembered ? "Remembered" : "Connected")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Layout picker row
                    HStack {
                        Text("Layout")
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            autoDetectController.presentKeyboardSearch(for: activeKeyboard.id)
                            LiveKeyboardOverlayController.shared.showForQuickLaunch()
                        } label: {
                            HStack(spacing: 4) {
                                Text(activeKeyboard.layoutId.flatMap { PhysicalLayout.find(id: $0)?.name } ?? "Not selected")
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                        .accessibilityIdentifier("status-search-keyboard-layouts-button")
                    }

                    // Technical details disclosure
                    DisclosureGroup("Details", isExpanded: $showKeyboardDetails) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            keyboardInfoRow(title: "VID:PID", value: activeKeyboard.vidPidKey)
                            keyboardInfoRow(title: "Source", value: activeKeyboard.source?.rawValue.capitalized ?? "Manual")
                            keyboardInfoRow(title: "Match", value: activeKeyboard.matchType?.rawValue ?? "None")
                            keyboardInfoRow(title: "Confidence", value: activeKeyboard.confidence?.rawValue.capitalized ?? "Unknown")
                        }
                        .padding(.top, 6)
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)

                    // Destructive action
                    Button(role: .destructive) {
                        autoDetectController.forgetKeyboard(activeKeyboard.id)
                    } label: {
                        Text("Forget This Keyboard")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("status-forget-keyboard-button")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .accessibilityIdentifier("status-connected-keyboard-panel")
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)

                    Text("No keyboard connected")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                .accessibilityIdentifier("status-no-connected-keyboard-panel")
            }
        }
    }

    @ViewBuilder
    private func keyboardInfoRow(title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        let controller = MainAppStateController.shared

        // Trigger a revalidation if stale, then read the published state.
        await controller.revalidate()

        let context = controller.lastValidatedSystemContext ?? .empty
        let duplicates = HelperMaintenance.shared.detectDuplicateAppCopies()
        let tcpOk = controller.lastTCPConfigured ?? false

        permissionSnapshot = context.permissions
        systemContext = context
        wizardSystemState = controller.lastAdaptedState
        wizardIssues = controller.issues
        tcpConfigured = controller.lastTCPConfigured
        showSetupBanner = !(context.permissions.isSystemReady && context.services.isHealthy)
            || duplicates.count > 1
            || (context.services.kanataRunning && !tcpOk)
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
