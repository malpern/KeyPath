import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

struct GeneralSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var settingsToastManager = WizardToastManager()
    @AppStorage("overlayLayoutId") private var selectedLayoutId: String = "macbook-us"
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"
    @State private var showingKeymapInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 40) {
                // Left: Logs
                VStack(alignment: .leading, spacing: 12) {
                    Text("Logs")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 30) {
                        // KeyPath Log
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)

                            Text("KeyPath log")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("Open") {
                                openLogFile(NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        // Kanata Log
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)

                            Text("Kanata log")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("Open") {
                                openLogFile("/var/log/kanata.log")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Verbose Logging Toggle
                    VerboseLoggingToggle()
                }
                .frame(minWidth: 220)

                // Right: Recording Settings
                VStack(alignment: .leading, spacing: 20) {
                    // Capture Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Capture Mode")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { PreferencesService.shared.isSequenceMode },
                                set: { PreferencesService.shared.isSequenceMode = $0 }
                            )
                        ) {
                            Label {
                                Text("Sequences - Keys one after another")
                            } icon: {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                            }
                            .tag(true)

                            Label {
                                Text("Combos - Keys together")
                            } icon: {
                                Image(systemName: "command")
                                    .foregroundColor(.secondary)
                            }
                            .tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    // Recording Behavior
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recording Behavior")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { PreferencesService.shared.applyMappingsDuringRecording },
                                set: { PreferencesService.shared.applyMappingsDuringRecording = $0 }
                            )
                        ) {
                            Label {
                                Text("Physical keys only (pause mappings)")
                            } icon: {
                                Image(systemName: "keyboard")
                                    .foregroundColor(.secondary)
                            }
                            .tag(false)

                            Label {
                                Text("Include KeyPath mappings")
                            } icon: {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(.blue)
                            }
                            .tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    // Overlay Settings
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Overlay")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Picker("Layout", selection: $selectedLayoutId) {
                            ForEach(PhysicalLayout.all) { layout in
                                Text(layout.name).tag(layout.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)

                        HStack(spacing: 6) {
                            Picker("Keymap", selection: $selectedKeymapId) {
                                ForEach(LogicalKeymap.all) { keymap in
                                    Text(keymap.name).tag(keymap.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)

                            Button {
                                showingKeymapInfo.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Keymap details")
                            .popover(isPresented: $showingKeymapInfo) {
                                KeymapInfoPopover(keymap: selectedKeymap)
                            }
                        }

                        Toggle("Include number row & punctuation", isOn: includePunctuationBinding)
                            .toggleStyle(.switch)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Divider()
                .padding(.vertical, 12)

            if FeatureFlags.simulatorAndVirtualKeysEnabled {
                // Virtual Keys Inspector
                VirtualKeysInspectorView()
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
    }

    private func openLogFile(_ filePath: String) {
        // Try to open with Zed editor first (if available)
        let zedProcess = Process()
        zedProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/zed")
        zedProcess.arguments = [filePath]

        do {
            try zedProcess.run()
            AppLogger.shared.log("📝 [Settings] Opened log in Zed: \(filePath)")
            return
        } catch {
            // Fallback: Try to open with default text editor
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallbackProcess.arguments = ["-t", filePath]

            do {
                try fallbackProcess.run()
                AppLogger.shared.log("📝 [Settings] Opened log in default text editor: \(filePath)")
            } catch {
                AppLogger.shared.log("❌ [Settings] Failed to open log file: \(error.localizedDescription)")
                settingsToastManager.showError("Failed to open log file")
            }
        }
    }

    private var selectedKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
    }

    private var includePunctuationBinding: Binding<Bool> {
        Binding(
            get: {
                KeymapPreferences.includePunctuation(
                    for: selectedKeymapId,
                    store: keymapIncludePunctuationStore
                )
            },
            set: { newValue in
                keymapIncludePunctuationStore = KeymapPreferences.updatedIncludePunctuationStore(
                    from: keymapIncludePunctuationStore,
                    keymapId: selectedKeymapId,
                    includePunctuation: newValue
                )
            }
        )
    }
}

private struct KeymapInfoPopover: View {
    let keymap: LogicalKeymap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keymap.name)
                .font(.headline)
            Text(keymap.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Learn more", destination: keymap.learnMoreURL)
        }
        .padding(12)
        .frame(maxWidth: 260)
    }
}

// MARK: - Status Settings Tab

struct StatusSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    @State private var wizardInitialPage: WizardPage? // nil = don't show wizard
    @State private var showSetupBanner = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    @State private var systemContext: SystemContext?
    @State private var wizardSystemState: WizardSystemState = .initializing
    @State private var wizardIssues: [WizardIssue] = []
    @State private var tcpConfigured: Bool?
    @State private var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State private var showingPermissionAlert = false
    @State private var refreshRetryScheduled = false
    @State private var localServiceRunning: Bool? // Optimistic local state for instant toggle feedback

    private var isServiceRunning: Bool {
        systemContext?.services.kanataRunning ?? false
    }

    /// Effective service running state: use local optimistic value if set, otherwise actual state
    private var effectiveServiceRunning: Bool {
        localServiceRunning ?? isServiceRunning
    }

    private var isSystemHealthy: Bool {
        overallHealthLevel == .success
    }

    private enum OverallHealthLevel: Int {
        case success = 0
        case warning = 1
        case critical = 2
        case checking = 3
    }

    private var overallHealthLevel: OverallHealthLevel {
        guard let context = systemContext, permissionSnapshot != nil else { return .checking }

        let hasBlockingIssues = wizardIssues.contains { $0.severity == .critical || $0.severity == .error }
        if hasBlockingIssues {
            return .critical
        }

        if context.services.kanataRunning, tcpConfigured == false {
            return .critical
        }

        if duplicateAppCopies.count > 1 {
            return .warning
        }

        if !context.services.isHealthy || !(permissionSnapshot?.isSystemReady ?? false) {
            return .warning
        }

        return .success
    }

    private var systemHealthIcon: String {
        switch overallHealthLevel {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .critical:
            "xmark.circle.fill"
        case .checking:
            "gear"
        }
    }

    private var systemHealthTint: Color {
        switch overallHealthLevel {
        case .success:
            .green
        case .warning:
            .orange
        case .critical:
            .red
        case .checking:
            .secondary
        }
    }

    private var systemHealthMessage: String {
        guard let context = systemContext else { return "Checking status…" }
        if !context.services.kanataRunning {
            return kanataServiceStatus
        }
        if tcpConfigured == false {
            return "TCP Communication Required"
        }
        if !(permissionSnapshot?.isSystemReady ?? false) {
            return "Permissions Required"
        }
        return overallHealthLevel == .success ? "Everything's Working" : "Setup Needed"
    }

    private var kanataServiceStatus: String {
        guard let context = systemContext else { return "Checking…" }
        if context.services.kanataRunning {
            return "Service Running"
        }
        if context.components.launchDaemonServicesHealthy || context.services.karabinerDaemonRunning {
            return "Service Starting"
        }
        return "Service Stopped"
    }

    private var primaryIssueDetail: StatusDetail? {
        statusDetails
            .sorted { $0.level.rawValue > $1.level.rawValue }
            .first(where: { $0.level.isIssue })
    }

    private var statusDetails: [StatusDetail] {
        var details: [StatusDetail] = [serviceStatusDetail]

        if let detail = permissionDetail {
            details.append(detail)
        }

        if let detail = tcpDetail {
            details.append(detail)
        }

        if let detail = karabinerDetail {
            details.append(detail)
        }

        if let detail = kanataLogsDetail {
            details.append(detail)
        }

        if let detail = karabinerLogsDetail {
            details.append(detail)
        }

        if let duplicateDetail = duplicateAppsDetail {
            details.append(duplicateDetail)
        }

        return details
    }

    private var serviceStatusDetail: StatusDetail {
        guard let context = systemContext else {
            return StatusDetail(
                title: "Kanata Service",
                message: "Checking current status…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        if context.services.kanataRunning {
            return StatusDetail(
                title: "Kanata Service",
                message: "Running normally.",
                icon: "bolt.fill",
                level: .success
            )
        }

        if context.components.launchDaemonServicesHealthy || context.services.karabinerDaemonRunning {
            return StatusDetail(
                title: "Kanata Service",
                message: "Starting…",
                icon: "hourglass.circle",
                level: .info
            )
        }

        return StatusDetail(
            title: "Kanata Service",
            message: "Service is stopped. Use the switch above to turn it on.",
            icon: "pause.circle",
            level: .warning,
            actions: [
                StatusDetailAction(title: "Open Login Items", icon: "list.bullet") {
                    SystemDiagnostics.open(.loginItems)
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .summary
                }
            ]
        )
    }

    private var permissionDetail: StatusDetail? {
        guard let snapshot = permissionSnapshot else {
            return StatusDetail(
                title: "Permissions",
                message: "Checking current permissions…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        let evaluation = permissionGaps(in: snapshot)

        if evaluation.labels.isEmpty {
            return StatusDetail(
                title: "Permissions",
                message: "All required permissions are granted.",
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        var lines: [String] = []
        if let blocking = snapshot.blockingIssue {
            lines.append(blocking)
        }
        lines.append("Missing: \(evaluation.labels.joined(separator: ", "))")

        var actions: [StatusDetailAction] = [
            StatusDetailAction(title: "Fix", icon: "wand.and.stars") {
                showingPermissionAlert = true
            }
        ]

        if !snapshot.keyPath.inputMonitoring.isReady || !snapshot.kanata.inputMonitoring.isReady {
            actions.append(
                StatusDetailAction(title: "Open Input Monitoring", icon: "lock.shield") {
                    SystemDiagnostics.open(.inputMonitoring)
                }
            )
        }

        if !snapshot.keyPath.accessibility.isReady || !snapshot.kanata.accessibility.isReady {
            actions.append(
                StatusDetailAction(title: "Open Accessibility", icon: "figure.walk") {
                    SystemDiagnostics.open(.accessibility)
                }
            )
        }

        return StatusDetail(
            title: "Permissions",
            message: lines.joined(separator: "\n"),
            icon: "exclamationmark.shield",
            level: evaluation.hasErrors ? .critical : .warning,
            actions: actions
        )
    }

    private var tcpDetail: StatusDetail? {
        guard systemContext?.services.kanataRunning == true else { return nil }
        guard let tcpConfigured else {
            return StatusDetail(
                title: "TCP Communication",
                message: "Checking TCP configuration…",
                icon: "ellipsis.circle",
                level: .info
            )
        }

        if tcpConfigured {
            return StatusDetail(
                title: "TCP Communication",
                message: "Configured.",
                icon: "checkmark.shield.fill",
                level: .success
            )
        }

        return StatusDetail(
            title: "TCP Communication",
            message: "Service is missing the TCP port configuration. Open the wizard to repair communication settings.",
            icon: "exclamationmark.triangle",
            level: .critical,
            actions: [
                StatusDetailAction(title: "Open Kanata Logs", icon: "doc.text.magnifyingglass") {
                    SystemDiagnostics.openKanataLogsInEditor()
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .communication
                }
            ]
        )
    }

    private var karabinerDetail: StatusDetail? {
        let status = KarabinerComponentsStatusEvaluator.evaluate(
            systemState: wizardSystemState,
            issues: wizardIssues
        )
        guard status != .completed else { return nil }

        let level: StatusDetail.Level = wizardIssues.contains(where: { $0.severity == .critical || $0.severity == .error })
            ? .critical
            : .warning

        let message: String = {
            let relevant = wizardIssues.filter { issue in
                (issue.category == .installation && issue.identifier.isVHIDRelated)
                    || issue.category == .backgroundServices
                    || (issue.category == .daemon && issue.identifier == .component(.karabinerDaemon))
            }
            if let first = relevant.first {
                return first.title
            }
            return "Karabiner driver or related services are not healthy."
        }()

        return StatusDetail(
            title: "Karabiner Driver",
            message: message,
            icon: "keyboard.macwindow",
            level: level,
            actions: [
                StatusDetailAction(title: "Open Karabiner Logs", icon: "doc.on.doc") {
                    SystemDiagnostics.openKarabinerLogsDirectory()
                },
                StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                    wizardInitialPage = .karabinerComponents
                }
            ]
        )
    }

    private var kanataLogsDetail: StatusDetail? {
        // Show logs affordance when service isn't healthy or has daemon issues.
        guard serviceStatusDetail.level != .success else { return nil }
        return StatusDetail(
            title: "Kanata Logs",
            message: "Open the daemon stderr log for startup errors and permission failures.",
            icon: "doc.text.magnifyingglass",
            level: .info,
            actions: [
                StatusDetailAction(title: "Open", icon: "doc.text") {
                    SystemDiagnostics.openKanataLogsInEditor()
                }
            ]
        )
    }

    private var karabinerLogsDetail: StatusDetail? {
        guard karabinerDetail != nil else { return nil }
        return StatusDetail(
            title: "Karabiner Logs",
            message: "Open the Karabiner log directory for VirtualHID daemon/manager logs.",
            icon: "doc.on.doc",
            level: .info,
            actions: [
                StatusDetailAction(title: "Open", icon: "folder") {
                    SystemDiagnostics.openKarabinerLogsDirectory()
                }
            ]
        )
    }

    private var duplicateAppsDetail: StatusDetail? {
        guard duplicateAppCopies.count > 1 else { return nil }
        let count = duplicateAppCopies.count
        return StatusDetail(
            title: "Duplicate Installations",
            message: "Found \(count) copies of KeyPath. Extra copies can confuse macOS permissions.",
            icon: "exclamationmark.triangle",
            level: .warning,
            actions: [
                StatusDetailAction(title: "Review", icon: "arrow.right") {
                    NotificationCenter.default.post(name: .openSettingsAdvanced, object: nil)
                }
            ]
        )
    }

    private func permissionGaps(in snapshot: PermissionOracle.Snapshot) -> (
        labels: [String], hasErrors: Bool
    ) {
        var labels: [String] = []
        var hasErrors = false

        func append(status: PermissionOracle.Status, label: String) {
            guard !status.isReady else { return }
            labels.append(label)
            if case .error = status {
                hasErrors = true
            }
        }

        append(status: snapshot.keyPath.accessibility, label: "KeyPath Accessibility")
        append(status: snapshot.keyPath.inputMonitoring, label: "KeyPath Input Monitoring")
        append(status: snapshot.kanata.accessibility, label: "Kanata Accessibility")
        append(status: snapshot.kanata.inputMonitoring, label: "Kanata Input Monitoring")

        return (labels, hasErrors)
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
                                    .font(.system(size: 40))
                                    .foregroundColor(systemHealthTint)
                            }
                            .buttonStyle(.plain)
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
                                Text("\(activeCount) active rule\(activeCount == 1 ? "" : "s")")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Wizard button when there are problems
                    if !isSystemHealthy {
                        Button(action: { wizardInitialPage = .summary }) {
                            Label("Fix it", systemImage: "wand.and.stars")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(overallHealthLevel == .critical ? .red : .orange)
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

                        Text(effectiveServiceRunning ? "ON" : "OFF")
                            .font(.body.weight(.medium))
                            .foregroundColor(effectiveServiceRunning ? .green : .secondary)
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
                            granted: permissionSnapshot?.keyPath.accessibility.isReady,
                            onTap: { wizardInitialPage = .accessibility }
                        )

                        PermissionStatusRow(
                            title: "KeyPath Input Monitoring",
                            icon: "keyboard",
                            granted: permissionSnapshot?.keyPath.inputMonitoring.isReady,
                            onTap: { wizardInitialPage = .inputMonitoring }
                        )

                        PermissionStatusRow(
                            title: "Kanata Accessibility",
                            icon: "checkmark.shield",
                            granted: permissionSnapshot?.kanata.accessibility.isReady,
                            onTap: { wizardInitialPage = .accessibility }
                        )

                        PermissionStatusRow(
                            title: "Kanata Input Monitoring",
                            icon: "keyboard",
                            granted: permissionSnapshot?.kanata.inputMonitoring.isReady,
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
        .sheet(item: $wizardInitialPage) { page in
            InstallationWizardView(initialPage: page)
                .customizeSheetWindow()
                .environmentObject(kanataManager)
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
           context.components.launchDaemonServicesHealthy || context.services.karabinerDaemonRunning,
           refreshRetryScheduled == false {
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

    private func openConfigInEditor() {
        let url = URL(fileURLWithPath: kanataManager.configPath)
        openFileInPreferredEditor(url)
    }

    private func openBackupsFolder() {
        let backupsPath = "\(NSHomeDirectory())/.config/keypath/.backups"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsPath)
    }

    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.resetToDefaultConfig()
                settingsToastManager.showSuccess("Configuration reset to default")
            } catch {
                settingsToastManager.showError("Reset failed: \(error.localizedDescription)")
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
        guard FileManager.default.fileExists(atPath: plistPath) else { return false }

        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String]
        else {
            return false
        }

        return args.contains("--port")
    }

    private var systemStatusRows: [SettingsSystemStatusRowModel] {
        let hasFullDiskAccess = !PermissionService.lastTCCAuthorizationDenied
        return SettingsSystemStatusRowsBuilder.rows(
            wizardSystemState: wizardSystemState,
            wizardIssues: wizardIssues,
            systemContext: systemContext,
            tcpConfigured: tcpConfigured,
            hasFullDiskAccess: hasFullDiskAccess
        )
    }
}

// MARK: - Supporting Views

private struct PermissionStatusRow: View {
    let title: String
    let icon: String
    let granted: Bool?
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(statusColor)
                    .frame(width: 20)

                Text(title)
                    .font(.body)

                Spacer()

                if let granted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(granted ? .green : .red)
                        .font(.body)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var statusColor: Color {
        if let granted {
            granted ? .green : .red
        } else {
            .secondary
        }
    }
}

private struct StatusDetailAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let handler: () -> Void
}

private struct StatusDetail: Identifiable {
    enum Level: Int {
        case success = 0
        case info = 1
        case warning = 2
        case critical = 3
    }

    let title: String
    let message: String
    let icon: String
    let level: Level
    let actions: [StatusDetailAction]

    var id: String {
        "\(title)|\(message)"
    }

    init(
        title: String,
        message: String,
        icon: String,
        level: Level,
        actions: [StatusDetailAction] = []
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.level = level
        self.actions = actions
    }
}

private extension StatusDetail.Level {
    var tintColor: Color {
        switch self {
        case .success: .green
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    var isIssue: Bool {
        switch self {
        case .warning, .critical: true
        case .success, .info: false
        }
    }
}

private struct StatusDetailRow: View {
    let detail: StatusDetail

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detail.icon)
                .foregroundColor(detail.level.tintColor)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.subheadline.weight(.semibold))

                Text(detail.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !detail.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.actions) { action in
                        Button {
                            action.handler()
                        } label: {
                            if let icon = action.icon {
                                Label(action.title, systemImage: icon)
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Text(action.title)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}
