import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

// MARK: - General Settings Tab

private enum GeneralSettingsSection: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case virtualKeys = "Virtual Keys"
    case experimental = "Experimental"

    var id: String { rawValue }

    /// Sections to show based on feature flags
    static var visibleSections: [GeneralSettingsSection] {
        if FeatureFlags.simulatorAndVirtualKeysEnabled {
            return allCases
        }
        return allCases.filter { $0 != .virtualKeys }
    }
}

struct GeneralSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel
    @State private var settingsToastManager = WizardToastManager()
    @State private var selectedSection: GeneralSettingsSection = .settings
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @State private var showingKeymapInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control for section switching
            Picker("Section", selection: $selectedSection) {
                ForEach(GeneralSettingsSection.visibleSections) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("settings-general-section-picker")

            // Content based on selected section
            Group {
                switch selectedSection {
                case .settings:
                    generalSettingsContent
                case .virtualKeys:
                    if FeatureFlags.simulatorAndVirtualKeysEnabled {
                        VirtualKeysInspectorView()
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                case .experimental:
                    ExperimentalSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
    }

    // MARK: - General Settings Content

    @ViewBuilder
    private var generalSettingsContent: some View {
        ScrollView {
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
                                .accessibilityIdentifier("settings-open-keypath-log-button")
                                .accessibilityLabel("Open KeyPath log")
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
                                .accessibilityIdentifier("settings-open-kanata-log-button")
                                .accessibilityLabel("Open Kanata log")
                            }
                        }
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
                            .accessibilityIdentifier("settings-capture-mode-picker")
                            .accessibilityLabel("Capture Mode")
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
                            .accessibilityIdentifier("settings-recording-behavior-picker")
                            .accessibilityLabel("Recording Behavior")
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
                            .accessibilityIdentifier("settings-overlay-layout-picker")
                            .accessibilityLabel("Keyboard Overlay Layout")

                            HStack(spacing: 6) {
                                Picker("Keymap", selection: $selectedKeymapId) {
                                    ForEach(LogicalKeymap.all) { keymap in
                                        Text(keymap.name).tag(keymap.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                                .accessibilityIdentifier("settings-overlay-keymap-picker")
                                .accessibilityLabel("Keyboard Overlay Keymap")

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

                            Button("Reset Overlay Size") {
                                LiveKeyboardOverlayController.shared.resetWindowFrame()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Reset the keyboard overlay to its default size and position")
                            .accessibilityIdentifier("settings-reset-overlay-size-button")
                            .accessibilityLabel("Reset Overlay Size")
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Helpers

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

    private var hasFullDiskAccess: Bool {
        FullDiskAccessChecker.shared.hasFullDiskAccess()
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

        if evaluation.missingOrDenied.isEmpty, evaluation.unknown.isEmpty {
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
        if !evaluation.missingOrDenied.isEmpty {
            lines.append("Missing: \(evaluation.missingOrDenied.joined(separator: ", "))")
        }
        if !evaluation.unknown.isEmpty {
            if hasFullDiskAccess {
                lines.append("Not verified: \(evaluation.unknown.joined(separator: ", "))")
            } else {
                lines.append(
                    "Not verified (grant Full Disk Access to verify): \(evaluation.unknown.joined(separator: ", "))"
                )
            }
        }

        var actions: [StatusDetailAction] = [
            StatusDetailAction(title: "Fix", icon: "wand.and.stars") {
                showingPermissionAlert = true
            }
        ]

        if !hasFullDiskAccess, snapshot.kanata.accessibility == .unknown || snapshot.kanata.inputMonitoring == .unknown {
            actions.append(
                StatusDetailAction(title: "Grant Full Disk Access", icon: "folder") {
                    SystemDiagnostics.open(.fullDiskAccess)
                }
            )
        }

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
        missingOrDenied: [String],
        unknown: [String],
        hasErrors: Bool
    ) {
        var missingOrDenied: [String] = []
        var unknown: [String] = []
        var hasErrors = false

        func append(status: PermissionOracle.Status, label: String) {
            guard !status.isReady else { return }
            switch status {
            case .unknown:
                unknown.append(label)
            case .denied:
                missingOrDenied.append(label)
            case .error:
                missingOrDenied.append(label)
                hasErrors = true
            case .granted:
                break
            }
        }

        append(status: snapshot.keyPath.accessibility, label: "KeyPath Accessibility")
        append(status: snapshot.keyPath.inputMonitoring, label: "KeyPath Input Monitoring")
        append(status: snapshot.kanata.accessibility, label: "Kanata Accessibility")
        append(status: snapshot.kanata.inputMonitoring, label: "Kanata Input Monitoring")

        return (missingOrDenied, unknown, hasErrors)
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

                    // Wizard button when there are problems
                    if !isSystemHealthy {
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
                        .accessibilityLabel("Kanata Service")

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

// MARK: - Supporting Views

private struct PermissionStatusRow: View {
    let title: String
    let icon: String
    let status: PermissionOracle.Status?
    let isKanata: Bool
    let hasFullDiskAccess: Bool
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

                if status != nil {
                    Image(systemName: trailingIcon)
                        .foregroundColor(trailingColor)
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
        .accessibilityIdentifier("settings-status-action-button-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityLabel(title)
    }

    private var statusColor: Color {
        guard let status else { return .secondary }
        switch status {
        case .granted:
            return .green
        case .denied, .error:
            return .red
        case .unknown:
            // For Kanata, unknown is commonly due to missing Full Disk Access (TCC not readable).
            // For KeyPath, unknown is usually a transient "still checking" (startup mode).
            return isKanata ? .orange : .secondary
        }
    }

    private var trailingIcon: String {
        guard let status else { return "ellipsis.circle" }
        switch status {
        case .granted:
            return "checkmark.circle.fill"
        case .denied, .error:
            return "xmark.circle.fill"
        case .unknown:
            if isKanata, !hasFullDiskAccess {
                return "questionmark.circle.fill"
            }
            return "questionmark.circle"
        }
    }

    private var trailingColor: Color {
        guard let status else { return .secondary }
        switch status {
        case .granted:
            return .green
        case .denied, .error:
            return .red
        case .unknown:
            return isKanata ? .orange : .secondary
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
                        .accessibilityIdentifier("status-action-\(action.title.lowercased().replacingOccurrences(of: " ", with: "-"))")
                        .accessibilityLabel(action.title)
                    }
                }
            }
        }
    }
}

// MARK: - Script Execution Settings Section

/// Settings section for Script Execution in Quick Launcher
struct ScriptExecutionSettingsSection: View {
    @ObservedObject private var securityService = ScriptSecurityService.shared
    @State private var showingExecutionLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                    .font(.body)
                Text("Script Execution")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow script execution in Quick Launcher")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("Scripts can run commands on your system. Only enable for trusted scripts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $securityService.isScriptExecutionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .accessibilityIdentifier("settings-script-execution-toggle")
            .accessibilityLabel("Allow script execution")

            if securityService.isScriptExecutionEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip confirmation dialog")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("⚠️ Scripts will run immediately without warning")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Toggle("", isOn: $securityService.bypassFirstRunDialog)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.leading, 24)
                .accessibilityIdentifier("settings-script-bypass-dialog-toggle")
                .accessibilityLabel("Skip script confirmation dialog")

                // Execution log button
                HStack {
                    Button(action: { showingExecutionLog = true }) {
                        Label("View Execution Log", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("settings-script-execution-log-button")

                    Text("(\(securityService.executionLog.count) entries)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 24)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingExecutionLog) {
            ScriptExecutionLogView()
        }
    }
}

// MARK: - Script Execution Log View

/// Shows the history of script executions for audit purposes
private struct ScriptExecutionLogView: View {
    @ObservedObject private var securityService = ScriptSecurityService.shared
    @Environment(\.dismiss) private var dismiss

    private var logEntries: [(id: Int, path: String, timestamp: String, success: Bool, error: String)] {
        securityService.executionLog.enumerated().reversed().map { index, entry in
            (
                id: index,
                path: entry["path"] as? String ?? "Unknown",
                timestamp: entry["timestamp"] as? String ?? "Unknown",
                success: entry["success"] as? Bool ?? false,
                error: entry["error"] as? String ?? ""
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Script Execution Log")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings-script-log-done")
            }
            .padding()

            Divider()

            if logEntries.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No scripts have been executed yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Log entries table
                List(logEntries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.success ? .green : .red)

                            Text(entry.path)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text(formatTimestamp(entry.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !entry.error.isEmpty {
                            Text(entry.error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with clear button
            HStack {
                Text("\(logEntries.count) entries (max 100)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Clear Log") {
                    clearLog()
                }
                .buttonStyle(.bordered)
                .disabled(logEntries.isEmpty)
                .accessibilityIdentifier("settings-script-clear-log-button")
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func formatTimestamp(_ iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return iso8601 }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .medium
        return displayFormatter.string(from: date)
    }

    private func clearLog() {
        UserDefaults.standard.removeObject(forKey: "KeyPath.Security.ScriptExecutionLog")
    }
}

// MARK: - AI Config Generation Settings Section

/// Settings section for AI-powered config generation
struct AIConfigGenerationSettingsSection: View {
    @State private var hasAPIKey: Bool = KeychainService.shared.hasClaudeAPIKey
    @State private var hasAPIKeyFromEnv: Bool = KeychainService.shared.hasClaudeAPIKeyFromEnvironment
    @State private var hasAPIKeyInKeychain: Bool = KeychainService.shared.hasClaudeAPIKeyInKeychain
    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var validationError: String?
    @State private var isAddingKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // API Key status row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude API Key")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusButton
            }
            .accessibilityIdentifier("settings-ai-api-key-row")

            // API key input (shown when adding)
            if isAddingKey {
                apiKeyInputView
            }

            // Biometric auth toggle (only show if key is configured)
            if hasAPIKey {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require \(BiometricAuthService.shared.biometricTypeName)")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Confirm before using API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { BiometricAuthService.shared.isEnabled },
                        set: { BiometricAuthService.shared.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .accessibilityIdentifier("settings-ai-biometric-toggle")
                .accessibilityLabel("Require biometric authentication")
            }
        }
        .onAppear {
            refreshStatus()
        }
    }

    private var statusDescription: String {
        if hasAPIKeyFromEnv {
            "Using environment variable"
        } else if hasAPIKeyInKeychain {
            "Stored in Keychain"
        } else {
            "Optional for complex mappings"
        }
    }

    @ViewBuilder
    private var statusButton: some View {
        if hasAPIKeyFromEnv {
            // Environment variable - just show indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if hasAPIKeyInKeychain {
            // Has key - show remove button
            Button("Remove") {
                removeAPIKey()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("settings-ai-remove-key-button")
        } else if isAddingKey {
            // Adding key - show cancel
            Button("Cancel") {
                isAddingKey = false
                apiKeyInput = ""
                validationError = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            // No key - show add button
            Button("Add Key") {
                isAddingKey = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("settings-ai-add-key-button")
        }
    }

    @ViewBuilder
    private var apiKeyInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SecureField("sk-ant-...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isValidating)
                    .accessibilityIdentifier("settings-ai-api-key-field")

                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Save") {
                        Task { await saveAPIKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiKeyInput.isEmpty)
                    .accessibilityIdentifier("settings-ai-save-key-button")
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Link("Get API Key from Anthropic →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
                .accessibilityIdentifier("settings-ai-get-key-link")
        }
        .padding(.leading, 16)
    }

    private func refreshStatus() {
        hasAPIKey = KeychainService.shared.hasClaudeAPIKey
        hasAPIKeyFromEnv = KeychainService.shared.hasClaudeAPIKeyFromEnvironment
        hasAPIKeyInKeychain = KeychainService.shared.hasClaudeAPIKeyInKeychain
    }

    private func saveAPIKey() async {
        guard !apiKeyInput.isEmpty else { return }

        isValidating = true
        validationError = nil

        let result = await APIKeyValidator.shared.validate(apiKeyInput)

        isValidating = false

        if result.isValid {
            do {
                try KeychainService.shared.storeClaudeAPIKey(apiKeyInput)
                apiKeyInput = ""
                isAddingKey = false
                refreshStatus()
            } catch {
                validationError = "Failed to save: \(error.localizedDescription)"
            }
        } else {
            validationError = result.errorMessage ?? "Invalid API key"
        }
    }

    private func removeAPIKey() {
        try? KeychainService.shared.deleteClaudeAPIKey()
        refreshStatus()
    }
}

// MARK: - AI Usage History View

/// Shows the history of AI API usage and estimated costs
private struct AIUsageHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    private var costHistory: [[String: Any]] {
        AICostTracker.shared.costHistory
    }

    private var totalEstimatedCost: Double {
        AICostTracker.shared.totalEstimatedCost
    }

    private var totalTokens: (input: Int, output: Int) {
        AICostTracker.shared.totalTokens
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Usage History")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("settings-done")
                .accessibilityIdentifier("ai-usage-done-button")
            }
            .padding()

            Divider()

            if costHistory.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No AI generations yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Usage will appear here after you create complex mappings with AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("ai-usage-empty-state")
            } else {
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Total Estimated Cost")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(String(format: "%.4f", totalEstimatedCost))")
                                .font(.title2.weight(.semibold))
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("API Calls")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(costHistory.count)")
                                .font(.title2.weight(.semibold))
                        }
                    }

                    Text("Input: \(totalTokens.input) tokens • Output: \(totalTokens.output) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .accessibilityIdentifier("ai-usage-summary")

                // History list
                List(Array(costHistory.enumerated().reversed()), id: \.offset) { _, entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry["timestamp"] as? String ?? "Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            let inputTokens = entry["inputTokens"] as? Int ?? 0
                            let outputTokens = entry["outputTokens"] as? Int ?? 0
                            Text("\(inputTokens) input + \(outputTokens) output tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        let cost = entry["estimatedCost"] as? Double ?? 0
                        Text("~$\(String(format: "%.4f", cost))")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with disclaimer
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠️ These are estimates based on token usage. Actual costs may vary. Check your Anthropic dashboard for exact charges.")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()

                HStack {
                    Link("View Current Anthropic Pricing →", destination: URL(string: "https://www.anthropic.com/pricing")!)
                        .font(.caption2)

                    Spacer()

                    if !costHistory.isEmpty {
                        Button("Clear History") {
                            AICostTracker.shared.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("ai-usage-clear-button")
                    }
                }
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}
