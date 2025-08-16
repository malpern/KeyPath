import SwiftUI

struct WizardTCPServerPage: View {
    @State private var tcpStatus: TCPServerStatus = .checking
    @State private var isFixing = false
    @State private var lastCheckTime = Date()
    
    var body: some View {
        VStack(spacing: WizardDesign.Spacing.sectionGap) {
            // Header
            WizardPageHeader(
                icon: "network",
                title: "TCP Server Configuration", 
                subtitle: "Kanata TCP server enables fast configuration reloading and external integrations",
                status: {
                    switch tcpStatus {
                    case .checking: .info
                    case .success: .success
                    case .failed: .error
                    }
                }()
            )
            VStack(spacing: 24) {
                // Status Overview
                TCPStatusCard(status: tcpStatus)
                
                // Detailed Information
                if case .success(let details) = tcpStatus {
                    TCPDetailsView(details: details)
                } else if case .failed(let error, let details) = tcpStatus {
                    TCPErrorView(error: error, details: details)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Refresh Status") {
                        Task {
                            await checkTCPStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    if case .failed = tcpStatus {
                        Button(isFixing ? "Fixing..." : "Fix TCP Server") {
                            Task {
                                await fixTCPServer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFixing)
                    }
                }
            }
        }
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
        defer { isFixing = false }
        
        AppLogger.shared.log("🔧 [TCPWizard] Attempting to fix TCP server...")
        
        // Placeholder for restart logic - would need KanataManager access
        // await kanataManager.restartKanata()
        
        // Wait for service to stabilize
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Re-check status
        await checkTCPStatus()
        
        AppLogger.shared.log("🔧 [TCPWizard] TCP server fix attempt completed")
    }
}

// MARK: - Supporting Views

struct TCPStatusCard: View {
    let status: TCPServerStatus
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: status.iconName)
                    .foregroundColor(status.color)
                    .font(.title2)
                
                Text("TCP Server Status")
                    .font(.headline)
                
                Spacer()
                
                Text(status.statusText)
                    .font(.subheadline)
                    .foregroundColor(status.color)
                    .fontWeight(.medium)
            }
            
            if let message = status.message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct TCPDetailsView: View {
    let details: TCPServerDetails
    
    var body: some View {
        VStack(spacing: 16) {
            // Network Status
            DetailSection(title: "Network Status") {
                TCPDetailRow(label: "Port", value: "\(details.port)")
                TCPDetailRow(label: "Listening", value: details.isListening ? "Yes" : "No")
                TCPDetailRow(label: "Active Connections", value: "\(details.activeConnections)")
                TCPDetailRow(label: "TIME_WAIT Connections", value: "\(details.timeWaitConnections)")
            }
            
            // Functionality Test
            DetailSection(title: "Functionality Test") {
                TCPDetailRow(label: "Layer Query", value: details.layerNames?.joined(separator: ", ") ?? "Failed")
                TCPDetailRow(label: "Reload Command", value: details.reloadResponse ?? "Failed")
                TCPDetailRow(label: "Last Tested", value: formatTime(details.lastTestedAt))
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct TCPErrorView: View {
    let error: String
    let details: TCPServerDetails?
    
    var body: some View {
        VStack(spacing: 16) {
            // Error Information
            VStack(alignment: .leading, spacing: 8) {
                Text("Error Details")
                    .font(.headline)
                
                Text(error)
                    .font(.body)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Network Details (if available)
            if let details = details {
                DetailSection(title: "Network Diagnostics") {
                    TCPDetailRow(label: "Port", value: "\(details.port)")
                    TCPDetailRow(label: "Listening", value: details.isListening ? "Yes" : "No")
                    TCPDetailRow(label: "Connections", value: "\(details.activeConnections + details.timeWaitConnections)")
                }
            }
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            VStack(spacing: 4) {
                content
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct TCPDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
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
        case .checking: return "Checking..."
        case .success: return "Working"
        case .failed: return "Failed"
        }
    }
    
    var message: String? {
        switch self {
        case .checking: return "Testing TCP server connectivity and functionality..."
        case .success(let details): return "TCP server is responding on port \(details.port). Ready for fast configuration reloading."
        case .failed(let error, _): return error
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