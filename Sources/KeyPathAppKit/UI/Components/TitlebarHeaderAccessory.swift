import AppKit
import KeyPathCore
import SwiftUI

/// Titlebar accessory for the main window - displays KeyPath label, status, and controls
/// This uses NSTitlebarAccessoryViewController to place content in the actual titlebar
/// alongside the traffic light window controls.
final class TitlebarHeaderAccessory: NSTitlebarAccessoryViewController {
    private let viewModel: KanataViewModel

    init(viewModel: KanataViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        // Use a fixed width that spans the remaining titlebar space (window is ~500px, traffic lights ~78px)
        let headerView = TitlebarHeaderView(viewModel: viewModel)
            .frame(width: 420, height: 28)
        let hostingView = NSHostingView(rootView: headerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 28)

        view = hostingView
        layoutAttribute = .left // After traffic lights, on same line
        fullScreenMinHeight = 28
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// SwiftUI view for the titlebar header content
private struct TitlebarHeaderView: View {
    @ObservedObject var viewModel: KanataViewModel
    @ObservedObject var appState = MainAppStateController.shared
    @State private var systemStatus: SystemStatusState = .checking
    @State private var statusRotation: Double = 0
    @State private var mappingsPaused: Bool = false

    private let statusTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    enum SystemStatusState {
        case checking
        case healthy
        case unhealthy
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("KeyPath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            // Only show status indicator when checking or unhealthy (hide when green)
            if systemStatus != .healthy {
                statusIndicator
            }

            Spacer()
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 28)
        .onAppear {
            checkSystemStatus()
            // Start periodic refresh
            startPeriodicRefresh()
        }
        .onReceive(statusTimer) { _ in
            if systemStatus == .checking {
                statusRotation += 3
            }
        }
    }

    private func startPeriodicRefresh() {
        // Refresh status every 5 seconds
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshStatus()
            }
        }
    }

    private func refreshStatus() async {
        // Prefer the app-wide validation result for consistency with the main banner
        if appState.validationState == .success {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    systemStatus = .healthy
                }
            }
            return
        }

        let context = await viewModel.inspectSystemContext()
        let isHealthy = context.services.isHealthy && context.permissions.isSystemReady

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                systemStatus = isHealthy ? .healthy : .unhealthy
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        Button {
            NotificationCenter.default.post(name: NSNotification.Name("ShowWizard"), object: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(statusBackgroundColor)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(statusBorderColor, lineWidth: 0.5))

                statusIcon
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusIconColor)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(statusTooltip)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch systemStatus {
        case .checking:
            Image(systemName: "gear")
                .rotationEffect(.degrees(statusRotation))
        case .healthy:
            Image(systemName: "checkmark.circle.fill")
        case .unhealthy:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var statusBackgroundColor: Color {
        switch systemStatus {
        case .checking: Color.secondary.opacity(0.12)
        case .healthy: Color.green.opacity(0.15)
        case .unhealthy: Color.orange.opacity(0.15)
        }
    }

    private var statusBorderColor: Color {
        switch systemStatus {
        case .checking: Color.secondary.opacity(0.25)
        case .healthy: Color.green.opacity(0.3)
        case .unhealthy: Color.orange.opacity(0.3)
        }
    }

    private var statusIconColor: Color {
        switch systemStatus {
        case .checking: .secondary
        case .healthy: .green
        case .unhealthy: .orange
        }
    }

    private var statusTooltip: String {
        switch systemStatus {
        case .checking: "Checking system status..."
        case .healthy: "System healthy - click for details"
        case .unhealthy: "Issues detected - click to fix"
        }
    }

    private func checkSystemStatus() {
        Task {
            systemStatus = .checking
            try? await Task.sleep(for: .milliseconds(500))

            // Prefer the app-wide validation result; fall back to direct inspection.
            let validationReady = appState.validationState == .success
            let isHealthy: Bool
            if validationReady {
                isHealthy = true
            } else {
                let context = await viewModel.inspectSystemContext()
                isHealthy = context.services.isHealthy && context.permissions.isSystemReady
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    systemStatus = isHealthy ? .healthy : .unhealthy
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleMappingsPaused() {
        Task {
            if mappingsPaused {
                let success = await viewModel.startKanata(reason: "Resume from titlebar")
                await MainActor.run { mappingsPaused = !success }
            } else {
                let success = await viewModel.stopKanata(reason: "Pause from titlebar")
                await MainActor.run { mappingsPaused = success }
            }
            checkSystemStatus()
        }
    }

    private func openSettings() {
        if let appMenu = NSApp.mainMenu?.items.first?.submenu {
            for item in appMenu.items {
                if item.title.contains("Settings") || item.title.contains("Preferences"),
                   let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                    return
                }
            }
        }
        if #available(macOS 13, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
