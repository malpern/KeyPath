import AppKit
import KeyPathCore
import SwiftUI

/// About window for KeyPath - app identity, system health, updates, links, and attribution
struct AboutView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var recentKeypresses = RecentKeypressesService.shared

    private let buildInfo = BuildInfo.current()
    private let currentYear = Calendar.current.component(.year, from: Date())

    @State private var systemContext: SystemContext?
    @State private var isRefreshingStatus = false
    @State private var isRepairing = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                sectionDivider

                statusSection

                sectionDivider

                updatesSection

                sectionDivider

                linksSection

                sectionDivider

                attributionSection

                sectionDivider

                footerSection
            }
            .frame(width: 500)
            .padding(.vertical, 20)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .task {
            await refreshSystemStatus()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }

            Text("KeyPath")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 4) {
                Text("Version \(buildInfo.version) (Build \(buildInfo.build))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Built \(formattedBuildDate(buildInfo.date))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let kanataVersion = buildInfo.kanataVersion {
                    Text("Kanata \(kanataVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Text("Reliable keyboard remapping with system-level diagnostics.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("System Status")

            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    label: "Engine",
                    value: engineStatusText,
                    color: engineStatusColor
                )

                statusRow(
                    label: "Active Layer",
                    value: recentKeypresses.currentLayer,
                    color: .secondary
                )

                statusRow(
                    label: "Permissions",
                    value: permissionHealthText,
                    color: permissionHealthColor
                )

                if let context = systemContext {
                    statusRow(
                        label: "Input Monitoring",
                        value: context.permissions.keyPath.inputMonitoring.description,
                        color: context.permissions.keyPath.inputMonitoring.isReady ? .green : .orange
                    )

                    statusRow(
                        label: "Accessibility",
                        value: context.permissions.keyPath.accessibility.description,
                        color: context.permissions.keyPath.accessibility.isReady ? .green : .orange
                    )
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                Button {
                    Task { await runRepair() }
                } label: {
                    Label(isRepairing ? "Fixing..." : "Fix Now", systemImage: "wrench.and.screwdriver")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRepairing)
                .accessibilityIdentifier("about-fix-now-button")

                Button {
                    Task { await refreshSystemStatus() }
                } label: {
                    Label(isRefreshingStatus ? "Refreshing..." : "Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingStatus)
                .accessibilityIdentifier("about-refresh-status-button")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Updates")

            Toggle("Check for updates automatically", isOn: Binding(
                get: { updateService.automaticallyChecksForUpdates },
                set: { updateService.setAutomaticChecks(enabled: $0) }
            ))
            .accessibilityIdentifier("about-auto-update-toggle")

            HStack(alignment: .center, spacing: 12) {
                Text("Update Channel")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 110, alignment: .leading)

                Picker("Update Channel", selection: Binding(
                    get: { updateService.updateChannel },
                    set: { updateService.setUpdateChannel($0) }
                )) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.rawValue).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .accessibilityIdentifier("about-update-channel-picker")
            }

            Text("Stable releases plus beta previews.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                updateService.checkForUpdates()
            } label: {
                Label("Check for Updates...", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!updateService.canCheckForUpdates)
            .accessibilityIdentifier("about-check-updates-button")
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Links")

            LinkButton(
                title: "GitHub",
                url: "https://github.com/malpern/KeyPath",
                icon: "chevron.left.forwardslash.chevron.right",
                accessibilityId: "about-link-github"
            )

            LinkButton(
                title: "Website",
                url: "http://keypath-app.com/",
                icon: "globe",
                accessibilityId: "about-link-website"
            )

            LinkButton(
                title: "Email",
                url: "mailto:malpern@gmail.com",
                icon: "envelope",
                accessibilityId: "about-link-email"
            )

            HStack(spacing: 8) {
                Button("Copy Diagnostics") {
                    copyDiagnosticsToClipboard()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("about-copy-diagnostics-button")

                Button("Open Logs") {
                    openLogsDirectory()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("about-open-logs-button")

                Button("Reveal Config") {
                    revealConfigFile()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("about-reveal-config-button")
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Built With")

            AttributionRow(
                name: "Kanata",
                description: "By jtroo. Advanced keyboard remapping engine.",
                license: "LGPL v3",
                url: "https://github.com/jtroo/kanata",
                accessibilityId: "about-attribution-kanata"
            )
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Made by Micah Alpern for the macOS and mechanical keyboard communities.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("© \(currentYear) Micah Alpern. MIT License.")
                .font(.system(size: 10))
                .foregroundColor(Color.secondary.opacity(0.75))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 32)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private var engineStatusText: String {
        guard let context = systemContext else {
            return "Loading"
        }

        if context.services.kanataRunning {
            return "Running"
        }
        return "Stopped"
    }

    private var engineStatusColor: Color {
        guard let context = systemContext else {
            return .secondary
        }
        return context.services.kanataRunning ? .green : .orange
    }

    private var permissionHealthText: String {
        guard let context = systemContext else {
            return "Loading"
        }
        return context.permissions.isSystemReady ? "Healthy" : "Needs Attention"
    }

    private var permissionHealthColor: Color {
        guard let context = systemContext else {
            return .secondary
        }
        return context.permissions.isSystemReady ? .green : .orange
    }

    private func formattedBuildDate(_ buildDate: String) -> String {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: buildDate) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return buildDate
    }

    @MainActor
    private func refreshSystemStatus() async {
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let context = await InstallerEngine().inspectSystem()
        systemContext = context
        statusMessage = "Last checked \(relativeTimeString(from: context.timestamp))."
    }

    @MainActor
    private func runRepair() async {
        isRepairing = true
        statusMessage = "Running repair..."

        let report = await InstallerEngine().run(intent: .repair, using: PrivilegeBroker())
        if report.success {
            statusMessage = "Repair completed successfully."
        } else {
            statusMessage = report.failureReason ?? "Repair completed with issues."
        }

        isRepairing = false
        await refreshSystemStatus()
    }

    private func copyDiagnosticsToClipboard() {
        var lines: [String] = [
            "KeyPath Diagnostics",
            "Version: \(buildInfo.version) (\(buildInfo.build))",
            "Build Date: \(buildInfo.date)",
            "Kanata: \(buildInfo.kanataVersion ?? "unknown")",
            "Active Layer: \(recentKeypresses.currentLayer)"
        ]

        if let context = systemContext {
            lines.append("Engine Running: \(context.services.kanataRunning)")
            lines.append("Permissions Ready: \(context.permissions.isSystemReady)")
            lines.append("Helper Ready: \(context.helper.isReady)")
            lines.append("Snapshot: \(context.timestamp)")
            lines.append("")
            lines.append(context.permissions.diagnosticSummary)
        }

        let diagnosticsText = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
        statusMessage = "Diagnostics copied to clipboard."
    }

    private func openLogsDirectory() {
        let logsDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/KeyPath")

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsDir.path)
    }

    private func revealConfigFile() {
        let configPath = KeyPathConstants.Config.mainConfigPath
        let exists = FileManager.default.fileExists(atPath: configPath)

        if exists {
            NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: KeyPathConstants.Config.directory))
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 2 {
            return "just now"
        }
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }
}

// MARK: - Link Button Component

private struct LinkButton: View {
    let title: String
    let url: String
    let icon: String
    let accessibilityId: String

    var body: some View {
        Button {
            if let resolvedURL = URL(string: url) {
                NSWorkspace.shared.open(resolvedURL)
            }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityIdentifier(accessibilityId)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Attribution Row Component

private struct AttributionRow: View {
    let name: String
    let description: String
    let license: String
    let url: String
    let accessibilityId: String

    var body: some View {
        Button {
            if let resolvedURL = URL(string: url) {
                NSWorkspace.shared.open(resolvedURL)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Text(license)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityIdentifier(accessibilityId)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Window Controller

@MainActor
class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = AboutView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 780),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "About KeyPath"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance.currentDrawing()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window = nil
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
        .frame(width: 500, height: 780)
}
