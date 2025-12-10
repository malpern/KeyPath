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
    @State private var localServiceRunning: Bool? // Optimistic local state for instant toggle feedback
    @State private var systemContext: SystemContext?

    private var isServiceRunning: Bool {
        systemContext?.services.kanataRunning ?? false
    }

    /// Effective service running state: use local optimistic value if set, otherwise actual state
    private var effectiveServiceRunning: Bool {
        localServiceRunning ?? isServiceRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 40) {
                // Left: On/Off Hero Section
                VStack(spacing: 16) {
                    // Big on/off icon
                    ZStack {
                        Circle()
                            .fill(effectiveServiceRunning ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: effectiveServiceRunning ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(effectiveServiceRunning ? .green : .secondary)
                    }

                    // Toggle with ON/OFF label
                    HStack(spacing: 12) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { effectiveServiceRunning },
                                set: { newValue in
                                    localServiceRunning = newValue
                                    Task {
                                        if newValue {
                                            let success = await kanataManager.startKanata(reason: "General tab toggle")
                                            await MainActor.run {
                                                if success {
                                                    settingsToastManager.showSuccess("KeyPath activated")
                                                } else {
                                                    settingsToastManager.showError("Start failed")
                                                    localServiceRunning = nil
                                                }
                                            }
                                        } else {
                                            let success = await kanataManager.stopKanata(reason: "General tab toggle")
                                            await MainActor.run {
                                                if success {
                                                    settingsToastManager.showInfo("KeyPath deactivated")
                                                } else {
                                                    settingsToastManager.showError("Stop failed")
                                                    localServiceRunning = nil
                                                }
                                            }
                                        }
                                    }
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .controlSize(.large)

                        Text(effectiveServiceRunning ? "ON" : "OFF")
                            .font(.body.weight(.medium))
                            .foregroundStyle(effectiveServiceRunning ? .green : Color.secondary)
                    }

                    // Active rules count
                    Button(action: {
                        NotificationCenter.default.post(name: .openSettingsRules, object: nil)
                    }) {
                        let enabledCollections = kanataManager.ruleCollections.filter(\.isEnabled).count
                        let enabledCustomRules = kanataManager.customRules.filter(\.isEnabled).count
                        let activeCount = enabledCollections + enabledCustomRules
                        Text("\(activeCount) active rule\(activeCount == 1 ? "" : "s")")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minWidth: 180)

                // Right: Settings
                VStack(alignment: .leading, spacing: 20) {
                    // Capture Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Capture Mode")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { PreferencesService.shared.isSequenceMode },
                                set: { PreferencesService.shared.isSequenceMode = $0 }
                            )
                        ) {
                            Label("Sequences — Keys one after another", systemImage: "arrow.forward.to.line").tag(true)
                            Label("Combos — Keys pressed together", systemImage: "square.stack.3d.up").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    // Recording Behavior
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recording Behavior")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { PreferencesService.shared.applyMappingsDuringRecording },
                                set: { PreferencesService.shared.applyMappingsDuringRecording = $0 }
                            )
                        ) {
                            Label("Record physical keys (pause remapping)", systemImage: "keyboard").tag(false)
                            Label("Record with remapping active", systemImage: "bolt").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    // Verbose Logging with log buttons underneath
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verbose Logging")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        VerboseLoggingToggle()

                        // Log file buttons
                        HStack(spacing: 12) {
                            Button {
                                openLogFile(NSHomeDirectory() + "/Library/Logs/KeyPath/keypath-debug.log")
                            } label: {
                                Label("KeyPath Log", systemImage: "doc.text")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                openLogFile("/var/log/kanata.log")
                            } label: {
                                Label("Kanata Log", systemImage: "doc.text")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }

                    // Overlay Settings (R2+)
                    if FeatureFlags.overlayEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keyboard Overlay")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Picker("Layout", selection: $selectedLayoutId) {
                                ForEach(PhysicalLayout.all) { layout in
                                    Text(layout.name).tag(layout.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                    }

                    // App Launch Security (R2+)
                    if FeatureFlags.appLaunchSecuritySettingsEnabled {
                        AppLaunchSecuritySection()
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Virtual Keys Inspector (R2+)
            if FeatureFlags.virtualKeysInspectorEnabled {
                VirtualKeysInspectorView()
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .settingsBackground()
        .withToasts(settingsToastManager)
        .onChange(of: isServiceRunning) { _, _ in
            localServiceRunning = nil
        }
        .task {
            await refreshStatus()
            // Background refresh every 5 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshStatus()
            }
        }
    }

    private func refreshStatus() async {
        let context = await kanataManager.inspectSystemContext()
        await MainActor.run {
            systemContext = context
        }
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
}

// MARK: - System Status Level

private enum SystemStatusLevel {
    case success
    case warning
    case error
    case checking
    case inactive // For optional/not-started items
}

// MARK: - Status Settings Tab

struct StatusSettingsTabView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    @State private var showSetupBanner = false
    @State private var permissionSnapshot: PermissionOracle.Snapshot?
    @State private var systemContext: SystemContext?
    @State private var duplicateAppCopies: [String] = []
    @State private var settingsToastManager = WizardToastManager()
    @State private var showingPermissionAlert = false
    @State private var refreshRetryScheduled = false
    @State private var gearRotation: Double = 0
    @State private var wizardInitialPage: WizardPage? // nil = don't show, non-nil = show with that page

    private var isLoading: Bool {
        systemContext == nil
    }

    private var heroIconBackgroundColor: Color {
        if isLoading {
            return Color.secondary.opacity(0.15)
        }
        return isSystemHealthy ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)
    }

    private var isSystemHealthy: Bool {
        (systemContext?.services.isHealthy ?? false) && (permissionSnapshot?.isSystemReady ?? false)
    }

    private var systemHealthMessage: String {
        guard let context = systemContext else { return "Checking status…" }
        if !context.services.kanataRunning {
            return kanataServiceStatus
        }
        if !(permissionSnapshot?.isSystemReady ?? false) {
            return "Permissions Required"
        }
        return "Everything's Working"
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
            action: StatusDetailAction(title: "Open Wizard", icon: "wand.and.stars") {
                wizardInitialPage = .summary
            }
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

        return StatusDetail(
            title: "Permissions",
            message: lines.joined(separator: "\n"),
            icon: "exclamationmark.shield",
            level: evaluation.hasErrors ? .critical : .warning,
            action: StatusDetailAction(title: "Fix", icon: "wand.and.stars") {
                showingPermissionAlert = true
            }
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
            action: StatusDetailAction(title: "Review", icon: "arrow.right") {
                NotificationCenter.default.post(name: .openSettingsAdvanced, object: nil)
            }
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

        // NOTE: Only KeyPath needs TCC permissions. Kanata uses the Karabiner VirtualHIDDevice
        // driver and runs as root via SMAppService/LaunchDaemon, so it doesn't need TCC entries.
        append(status: snapshot.keyPath.accessibility, label: "KeyPath Accessibility")
        append(status: snapshot.keyPath.inputMonitoring, label: "KeyPath Input Monitoring")

        return (labels, hasErrors)
    }

    // MARK: - System Status Items

    fileprivate struct SystemStatusItem {
        let title: String
        let icon: String
        let status: SystemStatusLevel
        let targetPage: WizardPage
        let tooltip: String
        let issueMessage: String? // Overrides tooltip when there's an error/warning

        init(title: String, icon: String, status: SystemStatusLevel, targetPage: WizardPage, tooltip: String, issueMessage: String? = nil) {
            self.title = title
            self.icon = icon
            self.status = status
            self.targetPage = targetPage
            self.tooltip = tooltip
            self.issueMessage = issueMessage
        }

        /// Returns issueMessage if present, otherwise the default tooltip
        var effectiveTooltip: String {
            issueMessage ?? tooltip
        }
    }

    private var systemStatusItems: [SystemStatusItem] {
        guard let context = systemContext else {
            // Still loading - show checking state for all
            return [
                SystemStatusItem(title: "Privileged Helper", icon: "shield.checkered", status: .checking, targetPage: .helper, tooltip: "Checking..."),
                SystemStatusItem(title: "Accessibility", icon: "accessibility", status: .checking, targetPage: .accessibility, tooltip: "Checking..."),
                SystemStatusItem(title: "Input Monitoring", icon: "eye", status: .checking, targetPage: .inputMonitoring, tooltip: "Checking..."),
                SystemStatusItem(title: "Karabiner Driver", icon: "keyboard.macwindow", status: .checking, targetPage: .karabinerComponents, tooltip: "Checking..."),
                SystemStatusItem(title: "Kanata Service", icon: "app.badge.checkmark", status: .checking, targetPage: .service, tooltip: "Checking...")
            ]
        }

        var items: [SystemStatusItem] = []

        // 1. Privileged Helper
        let helperStatus: SystemStatusLevel
        let helperIssue: String?
        if context.helper.isReady {
            helperStatus = .success
            helperIssue = nil
        } else if context.helper.isInstalled {
            helperStatus = .warning
            helperIssue = "Helper installed but not responding. Click to reinstall."
        } else {
            helperStatus = .error
            helperIssue = "Privileged helper not installed. Click to install."
        }
        items.append(SystemStatusItem(
            title: "Privileged Helper",
            icon: "shield.checkered",
            status: helperStatus,
            targetPage: .helper,
            tooltip: "Required. Runs keyboard remapping with system privileges. Without this, KeyPath cannot intercept or modify key events.",
            issueMessage: helperIssue
        ))

        // 2. Full Disk Access (optional)
        let fdaGranted = !PermissionService.lastTCCAuthorizationDenied
        items.append(SystemStatusItem(
            title: "Full Disk Access",
            icon: "folder",
            status: fdaGranted ? .success : .inactive,
            targetPage: .fullDiskAccess,
            tooltip: "Optional. Enables permission pre-flight checks to provide a smoother setup experience. KeyPath works without this."
        ))

        // 3. Accessibility (KeyPath only - Kanata doesn't need TCC with Karabiner driver)
        let keyPathAccessibilityOK = permissionSnapshot?.keyPath.accessibility.isReady ?? false
        let accessibilityIssue: String? = keyPathAccessibilityOK ? nil : "Accessibility permission required for KeyPath. Click to grant."
        items.append(SystemStatusItem(
            title: "Accessibility",
            icon: "accessibility",
            status: keyPathAccessibilityOK ? .success : .error,
            targetPage: .accessibility,
            tooltip: "Required. Allows KeyPath to send synthetic key events. Without this, remapped keys cannot be output to applications.",
            issueMessage: accessibilityIssue
        ))

        // 4. Input Monitoring (KeyPath only - Kanata doesn't need TCC with Karabiner driver)
        let keyPathInputMonitoringOK = permissionSnapshot?.keyPath.inputMonitoring.isReady ?? false
        let inputMonitoringIssue: String? = keyPathInputMonitoringOK ? nil : "Input Monitoring permission required for KeyPath. Click to grant."
        items.append(SystemStatusItem(
            title: "Input Monitoring",
            icon: "eye",
            status: keyPathInputMonitoringOK ? .success : .error,
            targetPage: .inputMonitoring,
            tooltip: "Required. Allows KeyPath to read keyboard input. Without this, your key presses cannot be detected or remapped.",
            issueMessage: inputMonitoringIssue
        ))

        // 5. System Conflicts
        if context.conflicts.hasConflicts {
            // Build a human-readable list of conflict names
            let conflictNames = context.conflicts.conflicts.map { conflict -> String in
                switch conflict {
                case .kanataProcessRunning: return "Kanata"
                case .karabinerGrabberRunning: return "Karabiner Grabber"
                case .karabinerVirtualHIDDeviceRunning: return "Karabiner VirtualHID"
                case .karabinerVirtualHIDDaemonRunning: return "Karabiner VirtualHID Daemon"
                case let .exclusiveDeviceAccess(device): return device
                }
            }
            let conflictMessage = conflictNames.isEmpty
                ? "Conflicting keyboard software detected. Click to resolve."
                : "Conflict with \(conflictNames.joined(separator: ", ")). Click to resolve."
            items.append(SystemStatusItem(
                title: "System Conflicts",
                icon: "exclamationmark.triangle",
                status: .warning,
                targetPage: .conflicts,
                tooltip: "Other keyboard software is running that may interfere with KeyPath. Resolve conflicts for reliable operation.",
                issueMessage: conflictMessage
            ))
        }

        // 6. Karabiner Driver
        let driverStatus: SystemStatusLevel
        let driverIssue: String?
        if !context.components.karabinerDriverInstalled {
            driverStatus = .error
            driverIssue = "Karabiner Virtual HID driver not installed. Click to install."
        } else if context.components.vhidVersionMismatch {
            driverStatus = .warning
            driverIssue = "Driver version mismatch. Click to fix."
        } else {
            driverStatus = .success
            driverIssue = nil
        }
        items.append(SystemStatusItem(
            title: "Karabiner Driver",
            icon: "keyboard.macwindow",
            status: driverStatus,
            targetPage: .karabinerComponents,
            tooltip: "Required. The Karabiner Virtual HID driver creates a virtual keyboard that KeyPath uses to output remapped keys.",
            issueMessage: driverIssue
        ))

        // 7. Kanata Service
        let serviceStatus: SystemStatusLevel
        let serviceIssue: String?
        if context.services.kanataRunning {
            serviceStatus = .success
            serviceIssue = nil
        } else if context.components.launchDaemonServicesHealthy {
            serviceStatus = .warning
            serviceIssue = "Service starting or failed to run. Click to troubleshoot."
        } else {
            serviceStatus = .inactive
            serviceIssue = nil // Inactive is expected when service is stopped
        }
        items.append(SystemStatusItem(
            title: "Kanata Service",
            icon: "app.badge.checkmark",
            status: serviceStatus,
            targetPage: .service,
            tooltip: "Required. The Kanata engine processes your key remapping rules. This runs as a background service.",
            issueMessage: serviceIssue
        ))

        // 8. TCP Communication (only relevant if service is running)
        if context.services.kanataRunning {
            // If kanata is running, assume TCP is working (detailed check is expensive)
            items.append(SystemStatusItem(
                title: "TCP Communication",
                icon: "network",
                status: .success,
                targetPage: .communication,
                tooltip: "Required. KeyPath communicates with the Kanata service over TCP to reload configs and monitor status."
            ))
        }

        // 9. Duplicate App Copies (warning if detected)
        if duplicateAppCopies.count > 1 {
            let duplicateMessage = "Found \(duplicateAppCopies.count) copies of KeyPath. Keep only one copy in /Applications."
            items.append(SystemStatusItem(
                title: "Duplicate App Copies",
                icon: "doc.on.doc",
                status: .warning,
                targetPage: .helper,
                tooltip: "Multiple copies of KeyPath detected. This can cause helper signature mismatches. Keep only one copy in /Applications.",
                issueMessage: duplicateMessage
            ))
        }

        return items
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
                // Large status indicator with action button
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        // Status icon
                        ZStack {
                            Circle()
                                .fill(heroIconBackgroundColor)
                                .frame(width: 80, height: 80)

                            if isLoading {
                                // Spinning gear while loading
                                Image(systemName: "gear")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(gearRotation))
                                    .onAppear {
                                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                            gearRotation = 360
                                        }
                                    }
                            } else {
                                Image(
                                    systemName: isSystemHealthy
                                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                                )
                                .font(.system(size: 40))
                                .foregroundStyle(isSystemHealthy ? .green : .orange)
                            }
                        }

                        VStack(spacing: 4) {
                            Text(systemHealthMessage)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)

                            if !isLoading, let issue = primaryIssueDetail {
                                Text(issue.message)
                                    .font(.footnote)
                                    .foregroundStyle(issue.level.tintColor)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Primary action button under status icon
                    if !isLoading {
                        if isSystemHealthy {
                            // Subtle "Launch Wizard" when everything is OK
                            Button(action: {
                                wizardInitialPage = .summary
                            }) {
                                Label("Launch Wizard", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        } else {
                            // Prominent "Fix it" when there's a problem
                            Button(action: {
                                wizardInitialPage = .summary
                            }) {
                                Label("Fix it", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                }
                .frame(minWidth: 220)

                // System Status grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Status")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(systemStatusItems, id: \.title) { item in
                            SystemStatusRow(
                                title: item.title,
                                icon: item.icon,
                                status: item.status,
                                tooltip: item.effectiveTooltip,
                                onTap: {
                                    AppLogger.shared.log("🔍 [SettingsView] Status row tapped: \(item.title), targetPage: \(item.targetPage)")
                                    wizardInitialPage = item.targetPage
                                    AppLogger.shared.log("🔍 [SettingsView] wizardInitialPage set to: \(String(describing: wizardInitialPage))")
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
        .frame(maxHeight: 350)
        .settingsBackground()
        .withToasts(settingsToastManager)
        .sheet(item: $wizardInitialPage) { page in
            InstallationWizardView(initialPage: page)
                .customizeSheetWindow()
                .environmentObject(kanataManager)
                .onAppear {
                    AppLogger.shared.log("🔍 [SettingsView] Sheet creating wizard with initialPage = \(page)")
                }
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
            // Start background refresh timer (every 5 seconds)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshStatus()
            }
        }
        // Removed legacy onReceive(currentState)
        .onReceive(NotificationCenter.default.publisher(for: .wizardClosed)) { _ in
            Task {
                await refreshStatus()
            }
        }
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        // Use RuntimeCoordinator (via façade) to get fresh status
        let context = await kanataManager.inspectSystemContext()
        let snapshot = context.permissions
        let duplicates = HelperMaintenance.shared.detectDuplicateAppCopies()

        await MainActor.run {
            permissionSnapshot = snapshot
            systemContext = context
            showSetupBanner = !(snapshot.isSystemReady && context.services.isHealthy)
            duplicateAppCopies = duplicates
        }

        // If services look “starting” (daemons loaded/healthy but kanata not yet running), retry once shortly.
        if !context.services.kanataRunning,
           context.components.launchDaemonServicesHealthy || context.services.karabinerDaemonRunning,
           refreshRetryScheduled == false
        {
            refreshRetryScheduled = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                refreshRetryScheduled = false
                await refreshStatus()
            }
        }
    }
}

// MARK: - Supporting Views

private struct SystemStatusRow: View {
    let title: String
    let icon: String
    let status: SystemStatusLevel
    let tooltip: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                statusIndicator
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.001)) // Nearly invisible but captures hover
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(StatusRowButtonStyle(hasIssue: status == .warning || status == .error))
        .help(tooltip)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        case .warning:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.body)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.body)
        case .checking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .inactive:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.body)
        }
    }

    private var iconColor: Color {
        switch status {
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .checking: .secondary
        case .inactive: .secondary
        }
    }
}

private struct StatusRowButtonStyle: ButtonStyle {
    let hasIssue: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

private struct StatusDetailAction {
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
    let action: StatusDetailAction?

    var id: String {
        "\(title)|\(message)"
    }

    init(
        title: String, message: String, icon: String, level: Level, action: StatusDetailAction? = nil
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.level = level
        self.action = action
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
                .foregroundStyle(detail.level.tintColor)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.subheadline.weight(.semibold))

                Text(detail.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let action = detail.action {
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

// MARK: - App Launch Security Section (R2+)

/// Simple controls for app launch approval settings.
/// - Toggle: Trust all apps (bypass all approval prompts)
/// - Button: Reset all approvals (clear history, re-prompt for each app)
private struct AppLaunchSecuritySection: View {
    @State private var trustAllApps: Bool = ActionDispatcher.shared.isTrustAllAppsEnabled()
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Launch Security")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("When keyboard shortcuts launch apps via keypath:// URLs")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Toggle("Trust all app launches", isOn: $trustAllApps)
                .toggleStyle(.switch)
                .onChange(of: trustAllApps) { _, newValue in
                    ActionDispatcher.shared.setTrustAllApps(newValue)
                }

            if trustAllApps {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Apps will launch without confirmation prompts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showingResetConfirmation = true
            } label: {
                Label("Reset All Approvals", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(trustAllApps) // No point resetting if trust-all is on
        }
        .alert("Reset App Approvals?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                ActionDispatcher.shared.clearAllAppApprovals()
                trustAllApps = false
            }
        } message: {
            Text("You'll be prompted again the first time each app is launched via keyboard shortcut.")
        }
    }
}
