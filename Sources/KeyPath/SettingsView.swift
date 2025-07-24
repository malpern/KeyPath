import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Status Section
                    SettingsSection(title: "Status") {
                        StatusRow(
                            label: "Kanata Service",
                            status: kanataManager.isRunning ? "Running" : "Stopped",
                            isActive: kanataManager.isRunning
                        )
                        
                        StatusRow(
                            label: "Installation",
                            status: kanataManager.isCompletelyInstalled() ? "Installed" : "Not Installed",
                            isActive: kanataManager.isCompletelyInstalled()
                        )
                    }
                    
                    Divider()
                    
                    // Service Control Section
                    SettingsSection(title: "Service Control") {
                        VStack(spacing: 10) {
                            SettingsButton(
                                title: kanataManager.isRunning ? "Stop Service" : "Start Service",
                                systemImage: kanataManager.isRunning ? "stop.circle" : "play.circle",
                                action: {
                                    Task {
                                        if kanataManager.isRunning {
                                            await kanataManager.stopKanata()
                                        } else {
                                            await kanataManager.startKanata()
                                        }
                                    }
                                }
                            )
                            
                            SettingsButton(
                                title: "Restart Service",
                                systemImage: "arrow.clockwise.circle",
                                disabled: !kanataManager.isRunning,
                                action: {
                                    Task {
                                        await kanataManager.restartKanata()
                                    }
                                }
                            )
                            
                            SettingsButton(
                                title: "Refresh Status",
                                systemImage: "arrow.clockwise",
                                action: {
                                    Task {
                                        await kanataManager.updateStatus()
                                    }
                                }
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Configuration Section
                    SettingsSection(title: "Configuration") {
                        VStack(spacing: 10) {
                            SettingsButton(
                                title: "Edit Configuration",
                                systemImage: "doc.text",
                                action: {
                                    openConfigInZed()
                                }
                            )
                            
                            SettingsButton(
                                title: "Reset to Default",
                                systemImage: "arrow.counterclockwise",
                                style: .destructive,
                                action: {
                                    showingResetConfirmation = true
                                }
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Advanced Section
                    SettingsSection(title: "Advanced") {
                        VStack(spacing: 10) {
                            SettingsButton(
                                title: "Emergency Stop",
                                systemImage: "exclamationmark.triangle",
                                style: .destructive,
                                disabled: !kanataManager.isRunning,
                                action: {
                                    Task {
                                        await kanataManager.stopKanata()
                                    }
                                }
                            )
                        }
                    }
                    
                    // Error Display
                    if let error = kanataManager.lastError {
                        Divider()
                        
                        SettingsSection(title: "Issues") {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                                
                                Text(error)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task {
                await kanataManager.updateStatus()
            }
        }
        .alert("Reset Configuration", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaultConfig()
            }
        } message: {
            Text("This will reset your Kanata configuration to default with no custom mappings. All current key mappings will be lost. This action cannot be undone.")
        }
    }
    
    private func openConfigInZed() {
        let configPath = kanataManager.configPath
        let process = Process()
        process.launchPath = "/usr/local/bin/zed"
        process.arguments = [configPath]
        
        do {
            try process.run()
        } catch {
            // If Zed isn't installed at the expected path, try the common Homebrew path
            let fallbackProcess = Process()
            fallbackProcess.launchPath = "/opt/homebrew/bin/zed"
            fallbackProcess.arguments = [configPath]
            
            do {
                try fallbackProcess.run()
            } catch {
                // If neither works, try using 'open' command with Zed
                let openProcess = Process()
                openProcess.launchPath = "/usr/bin/open"
                openProcess.arguments = ["-a", "Zed", configPath]
                
                do {
                    try openProcess.run()
                } catch {
                    AppLogger.shared.log("Failed to open config file in Zed: \(error)")
                    // As a last resort, just open the file with default app
                    NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
                }
            }
        }
    }
    
    private func resetToDefaultConfig() {
        Task {
            do {
                try await kanataManager.saveConfiguration(input: "", output: "")
                AppLogger.shared.log("✅ Successfully reset config to default")
            } catch {
                AppLogger.shared.log("❌ Failed to reset config: \(error)")
            }
        }
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusRow: View {
    let label: String
    let status: String
    let isActive: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(status)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsButton: View {
    let title: String
    let systemImage: String
    var style: ButtonStyle = .standard
    var disabled: Bool = false
    let action: () -> Void
    
    enum ButtonStyle {
        case standard, destructive
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .foregroundColor(style == .destructive ? .red : .primary)
    }
}

#Preview {
    SettingsView()
        .environmentObject(KanataManager())
}