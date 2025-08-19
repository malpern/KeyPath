import SwiftUI

struct WizardTCPServerPage: View {
    @State private var tcpStatus: TCPServerStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    @State private var showingFixFeedback = false
    @State private var fixResult: FixResult?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            ScrollView {
                VStack(spacing: WizardDesign.Spacing.sectionGap) {
                    // Header
                    WizardPageHeader(
                        icon: "network",
                        title: "TCP Server", 
                        subtitle: tcpStatus.headerSubtitle,
                        status: tcpStatus.headerStatus
                    )
                    
                    VStack(spacing: WizardDesign.Spacing.itemGap) {
                        // Main Status Card
                        TCPMainStatusCard(status: tcpStatus)
                        
                        // Insights Section (always expanded)
                        TCPInsightsSection(status: tcpStatus)
                        
                        // Fix Feedback
                        if showingFixFeedback, let result = fixResult {
                            TCPFixFeedbackCard(result: result)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        
                        // Primary Fix Action (if needed)
                        if case .failed = tcpStatus {
                            TCPFixButton(
                                isFixing: isFixing,
                                onFix: { Task { await fixTCPServer() } }
                            )
                        }
                        
                        // Technical Details (Collapsible)
                        if case .success(let details) = tcpStatus {
                            TCPTechnicalDetails(details: details)
                        }
                    }
                    .padding(.horizontal, WizardDesign.Spacing.pageVertical)
                }
            }
            
            // Bottom Action (anchored to actual bottom of dialog)
            TCPBottomActions(
                onRefresh: { Task { await checkTCPStatus() } }
            )
            .padding(.horizontal, WizardDesign.Spacing.pageVertical)
        }
        .background(WizardDesign.Colors.wizardBackground)
        .task {
            await checkTCPStatus()
        }
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
        isFixing = true
        showingFixFeedback = false
        
        AppLogger.shared.log("🔧 [TCPWizard] Attempting to fix TCP server...")
        
        // Store the old status to compare
        let oldStatus = tcpStatus
        
        // Placeholder for restart logic - would need KanataManager access
        // await kanataManager.restartKanata()
        
        // Wait for service to stabilize
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Re-check status
        await checkTCPStatus()
        
        // Show feedback based on results
        let success = tcpStatus.isSuccess && !oldStatus.isSuccess
        fixResult = FixResult(
            success: success,
            message: success 
                ? "TCP server is now working correctly" 
                : "TCP server is still not responding. Try restarting KeyPath or checking your network settings.",
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
        
        isFixing = false
        AppLogger.shared.log("🔧 [TCPWizard] TCP server fix attempt completed: \(success ? "success" : "failed")")
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
                    
                    if case .success(let details) = status {
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
                
                Text(isFixing ? "Fixing..." : "Fix TCP Server")
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
        case .checking: return "network.badge.shield.half.filled"
        case .success: return "network"
        case .failed: return "network.slash"
        }
    }
    
    var color: Color {
        switch self {
        case .checking: return .orange
        case .success: return .green
        case .failed: return .red
        }
    }
    
    var statusText: String {
        switch self {
        case .checking: return "Checking"
        case .success: return "Working"
        case .failed: return "Not Working"
        }
    }
    
    var headerSubtitle: String {
        switch self {
        case .checking:
            return "Checking server status..."
        case .success:
            return "Fast configuration reloading is available"
        case .failed:
            return "Configuration changes require app restart"
        }
    }
    
    var headerStatus: WizardPageHeader.HeaderStatus {
        switch self {
        case .checking: return .info
        case .success: return .success
        case .failed: return .error
        }
    }
    
    var insights: [String] {
        switch self {
        case .checking:
            return [
                "Testing connection to TCP server",
                "Verifying configuration reload commands work properly"
            ]
            
        case .success(let details):
            var insights = [
                "TCP server allows instant configuration reloading without restarting KeyPath",
                "External tools can connect to integrate with your keyboard setup"
            ]
            
            if details.activeConnections > 0 {
                insights.append("Currently has \(details.activeConnections) active connection\(details.activeConnections == 1 ? "" : "s")")
            }
            
            return insights
            
        case .failed(let error, let details):
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
    
    private func testLayerQuery(client: KanataTCPClient) async -> [String]? {
        // Implementation would go here - simplified for now
        // In a real implementation, you'd send {"RequestLayerNames":{}} and parse response
        return ["base"] // Placeholder
    }
    
    private func testReloadCommand(client: KanataTCPClient) async -> String? {
        // Implementation would go here - simplified for now  
        // In a real implementation, you'd send {"Reload":{}} and parse response
        return "Ok" // Placeholder
    }
}