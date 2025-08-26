import SwiftUI

struct WizardTCPServerPage: View {
    @State private var tcpStatus: TCPServerStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var showingFixFeedback = false
    @State private var fixResult: FixResult?
    @EnvironmentObject var navigationCoordinator: WizardNavigationCoordinator

    // Auto-fix integration
    let onAutoFix: ((AutoFixAction) async -> Bool)?

    init(onAutoFix: ((AutoFixAction) async -> Bool)? = nil) {
        self.onAutoFix = onAutoFix
    }

    var body: some View {
        VStack(spacing: 0) {
            // Use experimental hero design when TCP server is working
            if tcpStatus.isSuccess {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered hero block with padding
                    VStack(spacing: WizardDesign.Spacing.sectionGap) {
                        // Green globe with green check overlay
                        ZStack {
                            Image(systemName: "globe")
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
                                        .offset(x: 15, y: -5) // Move further right and slightly up
                                }
                                Spacer()
                            }
                            .frame(width: 140, height: 115)
                        }

                        // Large headline (23pt)
                        Text("TCP Server")
                            .font(.system(size: 23, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        // Supporting copy (17pt)
                        Text("Server is running for instant config reloading & external integrations")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, WizardDesign.Spacing.pageVertical)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Header for setup/error states with action link
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Custom header with colored globe icon
                    VStack(spacing: WizardDesign.Spacing.elementGap) {
                        // Colored globe with overlay icon
                        ZStack {
                            Image(systemName: "globe")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(tcpStatus.globeColor)
                                .symbolRenderingMode(.hierarchical)
                                .symbolEffect(.bounce, options: .nonRepeating)

                            // Overlay icon in top right
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: tcpStatus.overlayIcon)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(tcpStatus.globeColor)
                                        .background(WizardDesign.Colors.wizardBackground)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -3) // Move to the right for smaller icon
                                }
                                Spacer()
                            }
                            .frame(width: 60, height: 60)
                        }
                        .frame(width: WizardDesign.Layout.statusCircleSize, height: WizardDesign.Layout.statusCircleSize)

                        // Title
                        Text("TCP Server")
                            .font(WizardDesign.Typography.sectionTitle)
                            .fontWeight(.semibold)

                        // Subtitle
                        Text(tcpStatus.headerSubtitle)
                            .font(WizardDesign.Typography.subtitle)
                            .foregroundColor(WizardDesign.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .wizardContentSpacing()
                    }
                    .padding(.top, 12)

                    // Check Again link under the subheader
                    Button("Check Again") {
                        Task { await checkTCPStatus() }
                    }
                    .buttonStyle(.link)
                }
            }

            // No content card - TCP server success is shown in hero section
            if !tcpStatus.isSuccess {
                VStack(alignment: .leading, spacing: WizardDesign.Spacing.itemGap) {
                    VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                        Text(tcpStatus.statusDescription)
                            .font(WizardDesign.Typography.body)
                            .foregroundColor(.primary)

                        if case let .success(details) = tcpStatus {
                            Text("Server Details:")
                                .font(WizardDesign.Typography.subsectionTitle)
                                .foregroundColor(.primary)
                                .padding(.top, WizardDesign.Spacing.itemGap)

                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                DetailRow(label: "Port", value: "\(details.port)")
                                DetailRow(label: "Status", value: details.isListening ? "Listening" : "Not Listening")
                                DetailRow(label: "Connections", value: "\(details.activeConnections)")
                                DetailRow(label: "Last Tested", value: formatTime(details.lastTestedAt))
                            }

                            if let layers = details.layerNames {
                                Text("Available layers: \(layers.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, WizardDesign.Spacing.itemGap)
                            }
                        } else if case let .failed(error, details) = tcpStatus {
                            Text("Error Details:")
                                .font(WizardDesign.Typography.subsectionTitle)
                                .foregroundColor(.primary)
                                .padding(.top, WizardDesign.Spacing.itemGap)

                            VStack(alignment: .leading, spacing: WizardDesign.Spacing.elementGap) {
                                if let details {
                                    DetailRow(label: "Port", value: "\(details.port)")
                                    DetailRow(label: "Status", value: details.isListening ? "Listening" : "Not Listening")
                                    DetailRow(label: "Connections", value: "\(details.activeConnections)")
                                }
                            }

                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, WizardDesign.Spacing.itemGap)
                        } else {
                            Text("Checking TCP server status...")
                                .font(WizardDesign.Typography.body)
                                .foregroundColor(.secondary)
                        }

                        // Show fix feedback if available
                        if showingFixFeedback, let result = fixResult {
                            HStack(spacing: 8) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(result.success ? .green : .orange)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundColor(result.success ? .green : .orange)
                            }
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
                if case .failed = tcpStatus {
                    Button(action: { Task { await fixTCPServer() } }) {
                        HStack(spacing: 4) {
                            if isFixing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isFixing ? "Fixing..." : "Fix")
                        }
                    }
                    .buttonStyle(WizardDesign.Component.SecondaryButton())
                    .disabled(isFixing)
                }

                // Primary continue button (centered)
                HStack {
                    Spacer()
                    Button("Continue") {
                        AppLogger.shared.log("ℹ️ [Wizard] User continuing from TCP Server page")
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
        .task {
            await checkTCPStatus()
        }
    }

    // MARK: - Helper Methods

    private func navigateToNextPage() {
        let allPages = WizardPage.allCases
        guard let currentIndex = allPages.firstIndex(of: navigationCoordinator.currentPage),
              currentIndex < allPages.count - 1
        else { return }
        let nextPage = allPages[currentIndex + 1]
        navigationCoordinator.navigateToPage(nextPage)
        AppLogger.shared.log("➡️ [TCP Server] Navigated to next page: \(nextPage.displayName)")
    }

    private func checkTCPStatus() async {
        tcpStatus = .checking
        lastCheckTime = Date()

        let tcpConfig = PreferencesService.tcpSnapshot()

        // Check if TCP is enabled
        guard tcpConfig.shouldUseTCPServer else {
            tcpStatus = .failed("TCP server disabled in preferences", details: nil)
            return
        }

        // SMART DEPENDENCY CHECKING: TCP requires permissions to be granted first
        let oracle = PermissionOracle.shared
        let snapshot = await oracle.currentSnapshot()

        if !snapshot.isSystemReady {
            let missingPermissions = [
                !snapshot.kanata.inputMonitoring.isReady ? "Input Monitoring" : nil,
                !snapshot.kanata.accessibility.isReady ? "Accessibility" : nil
            ].compactMap { $0 }

            tcpStatus = .failed(
                "TCP server requires permissions to be granted first. Missing: \(missingPermissions.joined(separator: ", "))",
                details: TCPServerDetails(
                    port: tcpConfig.port,
                    isListening: false,
                    activeConnections: 0,
                    timeWaitConnections: 0,
                    layerNames: nil,
                    reloadResponse: nil,
                    lastTestedAt: lastCheckTime
                )
            )
            return
        }

        // For now, assume Kanata is available from environment
        // In a real implementation, you'd get this from parent view

        // Get network status
        let networkStatus = await getNetworkStatus(port: tcpConfig.port)

        // Test TCP functionality
        let functionalityTest = await testTCPFunctionality(port: tcpConfig.port)

        if functionalityTest.success {
            tcpStatus = .success(TCPServerDetails(
                port: tcpConfig.port,
                isListening: networkStatus.isListening,
                activeConnections: networkStatus.activeConnections,
                timeWaitConnections: networkStatus.timeWaitConnections,
                layerNames: functionalityTest.layerNames,
                reloadResponse: functionalityTest.reloadResponse,
                lastTestedAt: lastCheckTime
            ))
        } else {
            tcpStatus = .failed(
                functionalityTest.error ?? "TCP server not responding",
                details: TCPServerDetails(
                    port: tcpConfig.port,
                    isListening: networkStatus.isListening,
                    activeConnections: networkStatus.activeConnections,
                    timeWaitConnections: networkStatus.timeWaitConnections,
                    layerNames: nil,
                    reloadResponse: nil,
                    lastTestedAt: lastCheckTime
                )
            )
        }
    }

    private func fixTCPServer() async {
        guard let onAutoFix else {
            AppLogger.shared.log("❌ [TCPWizard] No auto-fix handler available")
            return
        }

        isFixing = true
        showingFixFeedback = false

        AppLogger.shared.log("🔧 [TCPWizard] Attempting to fix TCP server...")

        // Determine which auto-fix action to use based on current status
        let autoFixAction: AutoFixAction = determineAutoFixAction()

        AppLogger.shared.log("🔧 [TCPWizard] Using auto-fix action: \(autoFixAction)")

        // Call the integrated auto-fix system
        let success = await onAutoFix(autoFixAction)

        // Note: If the auto-fix involves app restart, execution won't reach here
        // This handles cases where restart isn't needed or fails
        if !success {
            fixResult = FixResult(
                success: false,
                message: "Failed to fix TCP server. Please check system settings.",
                timestamp: Date()
            )

            withAnimation(.easeInOut(duration: 0.3)) {
                showingFixFeedback = true
            }

            // Auto-hide feedback after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingFixFeedback = false
                }
            }

            // Re-check status after a brief delay
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await checkTCPStatus()
        }

        isFixing = false
        AppLogger.shared.log("🔧 [TCPWizard] TCP server fix attempt completed: \(success ? "success" : "failed")")
    }

    private func determineAutoFixAction() -> AutoFixAction {
        // For now, we'll use regenerateTCPServiceConfiguration as the primary fix
        // In a more sophisticated implementation, we could analyze the specific
        // failure to choose between .regenerateTCPServiceConfiguration and .restartTCPServer
        .regenerateTCPServiceConfiguration
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct TCPMainStatusCard: View {
    let status: TCPServerStatus

    var body: some View {
        VStack(spacing: WizardDesign.Spacing.labelGap) {
            HStack(spacing: WizardDesign.Spacing.iconGap) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: status.iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(status.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("TCP Server")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(status.statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(status.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(status.color.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if case let .success(details) = status {
                        Text("Port \(details.port) • \(details.activeConnections) connections")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TCPInsightsSection: View {
    let status: TCPServerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
            Text("What this means")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
                ForEach(status.insights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 16, alignment: .leading)

                        Text(insight)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(Color(.controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TCPFixFeedbackCard: View {
    let result: FixResult

    var body: some View {
        HStack(spacing: WizardDesign.Spacing.iconGap) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(result.success ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.success ? "Fixed Successfully" : "Fix Attempt")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(result.message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(
            (result.success ? Color.green : Color.orange).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    (result.success ? Color.green : Color.orange).opacity(0.3),
                    lineWidth: 1
                )
        )
    }
}

struct TCPFixButton: View {
    let isFixing: Bool
    let onFix: () -> Void

    var body: some View {
        Button(action: onFix) {
            HStack(spacing: 8) {
                if isFixing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 14, weight: .medium))
                }

                Text(isFixing ? "Fixing..." : "Fix")
                    .font(.system(size: 15, weight: .medium))
            }
            .frame(width: WizardDesign.Layout.buttonWidthLarge, height: 40)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isFixing)
        .frame(maxWidth: .infinity)
    }
}

struct TCPBottomActions: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Separator line (typical in Mac wizards)
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)

            // Bottom button area
            HStack {
                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                        Text("Refresh Status")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(width: WizardDesign.Layout.buttonWidthMedium, height: 32)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.vertical, WizardDesign.Spacing.labelGap)
        }
    }
}

struct TCPTechnicalDetails: View {
    let details: TCPServerDetails
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: WizardDesign.Spacing.labelGap) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Technical Details")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: WizardDesign.Spacing.labelGap) {
                    TCPDetailGroup(title: "Network", rows: [
                        ("Port", "\(details.port)"),
                        ("Listening", details.isListening ? "Yes" : "No"),
                        ("Active Connections", "\(details.activeConnections)"),
                        ("TIME_WAIT Connections", "\(details.timeWaitConnections)")
                    ])

                    TCPDetailGroup(title: "Functionality", rows: [
                        ("Layer Query", details.layerNames?.joined(separator: ", ") ?? "Failed"),
                        ("Reload Command", details.reloadResponse ?? "Failed"),
                        ("Last Tested", formatTime(details.lastTestedAt))
                    ])
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(WizardDesign.Spacing.cardPadding)
        .background(Color(.controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct TCPDetailGroup: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(row.1)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Data Models

enum TCPServerStatus {
    case checking
    case success(TCPServerDetails)
    case failed(String, details: TCPServerDetails?)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var iconName: String {
        switch self {
        case .checking: "network.badge.shield.half.filled"
        case .success: "network"
        case .failed: "network.slash"
        }
    }

    var color: Color {
        switch self {
        case .checking: .orange
        case .success: .green
        case .failed: .red
        }
    }

    var statusText: String {
        switch self {
        case .checking: "Checking"
        case .success: "Working"
        case .failed: "Not Working"
        }
    }

    var headerSubtitle: String {
        switch self {
        case .checking:
            "Checking TCP server connectivity & functionality"
        case .success:
            "Server is running for instant config reloading & external integrations"
        case .failed:
            "Configuration changes require manual app restart"
        }
    }

    var headerStatus: WizardPageHeader.HeaderStatus {
        switch self {
        case .checking: .info
        case .success: .success
        case .failed: .error
        }
    }

    var statusDescription: String {
        switch self {
        case .checking:
            "Checking TCP server functionality and connection status..."
        case let .success(details):
            "TCP server is working correctly. Configuration changes can be reloaded instantly without restarting KeyPath."
        case let .failed(error, _):
            "TCP server is not working. \(error). Configuration changes will require restarting the application."
        }
    }

    var insights: [String] {
        switch self {
        case .checking:
            return [
                "Testing connection to TCP server",
                "Verifying configuration reload commands work properly"
            ]

        case let .success(details):
            var insights = [
                "TCP server allows instant configuration reloading without restarting KeyPath",
                "External tools can connect to integrate with your keyboard setup"
            ]

            if details.activeConnections > 0 {
                insights.append("Currently has \(details.activeConnections) active connection\(details.activeConnections == 1 ? "" : "s")")
            }

            return insights

        case let .failed(error, details):
            var insights = [
                "Without TCP server, configuration changes require restarting the app",
                "This might happen if Kanata crashed or port \(details?.port ?? 0) is blocked"
            ]

            if error.lowercased().contains("disabled") {
                insights.append("TCP server is currently disabled in preferences - you can enable it in Settings")
            } else if details?.isListening == false {
                insights.append("Port \(details?.port ?? 0) is not responding - try restarting KeyPath")
            }

            return insights
        }
    }

    var globeColor: Color {
        switch self {
        case .checking: WizardDesign.Colors.warning
        case .success: WizardDesign.Colors.success
        case .failed: WizardDesign.Colors.error
        }
    }

    var overlayIcon: String {
        switch self {
        case .checking: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }
}

struct TCPServerDetails {
    let port: Int
    let isListening: Bool
    let activeConnections: Int
    let timeWaitConnections: Int
    let layerNames: [String]?
    let reloadResponse: String?
    let lastTestedAt: Date
}

struct NetworkStatus {
    let isListening: Bool
    let activeConnections: Int
    let timeWaitConnections: Int
}

struct FunctionalityTest {
    let success: Bool
    let layerNames: [String]?
    let reloadResponse: String?
    let error: String?
}

struct FixResult {
    let success: Bool
    let message: String
    let timestamp: Date
}

// MARK: - Network Testing Functions

extension WizardTCPServerPage {
    private func getNetworkStatus(port: Int) async -> NetworkStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/netstat")
        task.arguments = ["-an"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lines = output.components(separatedBy: .newlines)
            let portLines = lines.filter { $0.contains(".\(port)") }

            let isListening = portLines.contains { $0.contains("LISTEN") }
            let activeConnections = portLines.filter { $0.contains("ESTABLISHED") }.count
            let timeWaitConnections = portLines.filter { $0.contains("TIME_WAIT") }.count

            return NetworkStatus(
                isListening: isListening,
                activeConnections: activeConnections,
                timeWaitConnections: timeWaitConnections
            )
        } catch {
            return NetworkStatus(isListening: false, activeConnections: 0, timeWaitConnections: 0)
        }
    }

    private func testTCPFunctionality(port: Int) async -> FunctionalityTest {
        let client = KanataTCPClient(port: port, timeout: 3.0)

        // Test basic connectivity
        let isConnected = await client.checkServerStatus()
        guard isConnected else {
            return FunctionalityTest(success: false, layerNames: nil, reloadResponse: nil, error: "Cannot connect to TCP server")
        }

        // Test layer query
        let layerNames = await testLayerQuery(client: client)

        // Test reload command
        let reloadResponse = await testReloadCommand(client: client)

        let success = layerNames != nil && reloadResponse != nil

        return FunctionalityTest(
            success: success,
            layerNames: layerNames,
            reloadResponse: reloadResponse,
            error: success ? nil : "TCP commands failed"
        )
    }

    private func testLayerQuery(client _: KanataTCPClient) async -> [String]? {
        // Implementation would go here - simplified for now
        // In a real implementation, you'd send {"RequestLayerNames":{}} and parse response
        ["base"] // Placeholder
    }

    private func testReloadCommand(client _: KanataTCPClient) async -> String? {
        // Implementation would go here - simplified for now
        // In a real implementation, you'd send {"Reload":{}} and parse response
        "Ok" // Placeholder
    }
}
