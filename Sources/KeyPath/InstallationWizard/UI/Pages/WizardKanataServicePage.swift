import SwiftUI

struct WizardKanataServicePage: View {
    @ObservedObject var kanataManager: KanataManager
    @State private var isPerformingAction = false
    @State private var lastError: String?
    @State private var serviceStatus: ServiceStatus = .unknown
    @State private var refreshTimer: Timer?

    // Integration with SimpleKanataManager for better error context
    @State private var simpleKanataManager: SimpleKanataManager?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    enum ServiceStatus: Equatable {
        case unknown
        case running
        case stopped
        case crashed(error: String)
        case starting
        case stopping

        var color: Color {
            switch self {
            case .running: .green
            case .stopped: .orange
            case .crashed: .red
            case .starting, .stopping: .blue
            case .unknown: .gray
            }
        }

        var icon: String {
            switch self {
            case .running: "checkmark.circle.fill"
            case .stopped: "stop.circle.fill"
            case .crashed: "exclamationmark.triangle.fill"
            case .starting, .stopping: "arrow.clockwise.circle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .running: "Service is running"
            case .stopped: "Service is stopped"
            case let .crashed(error): "Service crashed: \(error)"
            case .starting: "Service is starting..."
            case .stopping: "Service is stopping..."
            case .unknown: "Checking service status..."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when service is running
            if serviceStatus == .running {
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green gears icon with green check overlay
                        ZStack {
                            Image(systemName: "gearshape.2")
                                .font(.system(size: 115, weight: .light))
                                .foregroundColor(WizardDesign.Colors.success)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
                            // Green check overlay in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(WizardDesign.Colors.success)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 15, y: -5) // Move to the right
                                }
                                Spacer()
                            }
                            .frame(width: 115, height: 115)
                        }
                        
                        // Headline
                        Text("Kanata Service")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        // Subtitle
                        Text("Service is running and processing keyboard events")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                        
                        // Service control links below the subheader
                        HStack(spacing: WizardDesign.Spacing.itemGap) {
                            Button(action: startService) {
                                Text("Start")
                            }
                            .buttonStyle(.link)
                            .disabled(true)
                            .foregroundColor(.secondary)

                            Text("•")
                                .foregroundColor(.secondary)

                            Button(action: restartService) {
                                Text("Restart")
                            }
                            .buttonStyle(.link)
                            .foregroundColor(.red)
                            .disabled(isPerformingAction)

                            Text("•")
                                .foregroundColor(.secondary)

                            Button(action: stopService) {
                                Text("Stop")
                            }
                            .buttonStyle(.link)
                            .foregroundColor(.red)
                            .disabled(isPerformingAction)
                        }
                        .padding(.top, WizardDesign.Spacing.elementGap)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Header for other states with action link  
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Custom header with colored play icon
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Colored gears icon with appropriate overlay
                        ZStack {
                            Image(systemName: "gearshape.2")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(serviceStatus.color)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)
                            
                            // Status overlay in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: serviceStatus.icon)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(serviceStatus.color)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -3) // Move to the right for smaller icon
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                Spacer()
                            }
                            .frame(width: 60, height: 60)
                        }
                        .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)
                        
                        // Title
                        Text("Kanata Service")
                            .font(WizardDesign.Typography.sectionTitle)
                            .fontWeight(.semibold)
                        
                        // Subtitle
                        Text("Monitor and control the keyboard remapping service")
                            .font(WizardDesign.Typography.subtitle)
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .wizardContentSpacing()
                    }
                    .padding(.top, 12)

                    // Check Status link under the subheader
                    Button("Check Status") {
                        refreshStatus()
                    }
                    .buttonStyle(.link)
                }
            }

            // No content card - service status is shown in hero section
            if serviceStatus != .running {
                VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        Text("Service Status: \(serviceStatus.description)")
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(.primary)

                        Text("Service Details:")
                            .font(WizardDesign.Typography.subsectionTitle)
                            .foregroundColor(.primary)
                            .padding(.top, WizardDesign.Spacing.itemGap)

                        VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                            DetailRow(label: "Process ID", value: pidValue)
                            DetailRow(label: "Config File", value: configPath)
                            DetailRow(label: "Log File", value: WizardSystemPaths.displayPath(for: WizardSystemPaths.kanataLogFile))
                            DetailRow(label: "Status", value: uptimeValue)
                        }

                        if let error = lastError {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Last Error", systemImage: "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)

                                Text(error)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(12)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 8)
                        }

                        if case .crashed = serviceStatus {
                            Text("If the service keeps crashing, check the log file for details or try restarting.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, WizardDesign.Spacing.itemGap)
                        }
                    }

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
                .padding(WizardDesign.Spacing.cardPadding)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, WizardDesign.Spacing.pageVertical)
            }

            Spacer()

            // Centered buttons
            VStack(spacing: WizardDesign.Spacing.elementGap) {
                // Service control buttons - only show for non-running states
                if serviceStatus != .running {
                    HStack(spacing: WizardDesign.Spacing.itemGap) {
                        Button(action: startService) {
                            HStack(spacing: 4) {
                                if serviceStatus == .starting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text("Start")
                            }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isPerformingAction || serviceStatus == .running)

                        Button(action: restartService) {
                            HStack(spacing: 4) {
                                if serviceStatus == .stopping || serviceStatus == .starting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text("Restart")
                            }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isPerformingAction)

                        Button(action: stopService) {
                            HStack(spacing: 4) {
                                if serviceStatus == .stopping {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle())
                                }
                                Text("Stop")
                            }
                        }
                        .buttonStyle(WizardDesign.Component.SecondaryButton())
                        .disabled(isPerformingAction || serviceStatus == .stopped)
                    }
                }

                // Primary done button (centered)
                HStack {
                    Spacer()
                    Button("Done") {
                        AppLogger.shared.log("ℹ️ [Wizard] User completing setup from Kanata Service page")
                        navigateToNextPage()
                    }
                    .buttonStyle(WizardDesign.Component.PrimaryButton())
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, WizardDesign.Spacing.sectionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WizardDesign.Colors.wizardBackground)
        .onAppear {
            startAutoRefresh()
            refreshStatus()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        // Return to Summary page from Kanata Service with backward navigation animation
        // Use spring animation to suggest moving "back" in the navigation stack
        navigationCoordinator.navigateToPage(.summary, animation: .spring(response: 0.4, dampingFraction: 0.8))
        AppLogger.shared.log("⬅️ [Kanata Service] Navigated back to Summary page")
    }

    // MARK: - Computed Properties

    private var statusForHeader: WizardPageHeader.HeaderStatus {
        switch serviceStatus {
        case .running: .success
        case .stopped, .unknown: .info
        case .crashed: .error
        case .starting, .stopping: .warning
        }
    }

    private var statusTitle: String {
        switch serviceStatus {
        case .running: "Service Running"
        case .stopped: "Service Stopped"
        case .crashed: "Service Crashed"
        case .starting: "Starting Service"
        case .stopping: "Stopping Service"
        case .unknown: "Unknown Status"
        }
    }

    private var pidValue: String {
        if kanataManager.isRunning {
            // Get PID from kanataManager if available
            "Active"
        } else {
            "Not running"
        }
    }

    private var configPath: String {
        if WizardSystemPaths.userConfigExists {
            WizardSystemPaths.displayPath(for: WizardSystemPaths.userConfigPath)
        } else {
            "Not found"
        }
    }

    private var uptimeValue: String {
        // This would need to track service start time
        if kanataManager.isRunning {
            "Active"
        } else {
            "—"
        }
    }

    // MARK: - Actions

    private func startService() {
        isPerformingAction = true
        serviceStatus = .starting
        lastError = nil

        Task {
            await kanataManager.startKanataWithSafetyTimeout()

            await MainActor.run {
                isPerformingAction = false
                refreshStatus()
            }
        }
    }

    private func restartService() {
        isPerformingAction = true
        serviceStatus = .stopping
        lastError = nil

        Task {
            await kanataManager.stopKanata()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                serviceStatus = .starting
            }

            await kanataManager.startKanataWithSafetyTimeout()

            await MainActor.run {
                isPerformingAction = false
                refreshStatus()
            }
        }
    }

    private func stopService() {
        isPerformingAction = true
        serviceStatus = .stopping

        Task {
            await kanataManager.stopKanata()

            // Give it a moment to stop
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                isPerformingAction = false
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        // Check if service is running
        if kanataManager.isRunning {
            serviceStatus = .running
            lastError = nil
        } else {
            // Check if it crashed by looking for recent errors
            checkForCrash()
        }
    }

    private func checkForCrash() {
        // Check log file for recent crash indicators
        let logPath = WizardSystemPaths.kanataLogFile

        if let logData = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = logData.components(separatedBy: .newlines)
            let recentLines = lines.suffix(20) // Check last 20 lines

            for line in recentLines.reversed() {
                if line.contains("ERROR") || line.contains("FATAL") || line.contains("panic") {
                    serviceStatus = .crashed(error: extractErrorMessage(from: line))
                    lastError = line
                    return
                }
            }
        }

        // No crash detected, just stopped
        serviceStatus = .stopped
    }

    private func extractErrorMessage(from logLine: String) -> String {
        // Extract meaningful error message from log line
        if logLine.contains("Permission denied") {
            "Permission denied - check Input Monitoring settings"
        } else if logLine.contains("Config error") {
            "Configuration error - check your keypath.kbd file"
        } else if logLine.contains("Device not found") {
            "Keyboard device not found"
        } else {
            "Check log file for details"
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        // DISABLED: This timer calls refreshStatus() which may trigger invasive permission checks
        // that cause KeyPath to auto-add to Input Monitoring system preferences

        AppLogger.shared.log(
            "🔄 [WizardKanataServicePage] Auto-refresh timer DISABLED to prevent invasive permission checks"
        )
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Views

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

// MARK: - Preview

struct WizardKanataServicePage_Previews: PreviewProvider {
    static var previews: some View {
        WizardKanataServicePage(kanataManager: KanataManager())
    }
}
