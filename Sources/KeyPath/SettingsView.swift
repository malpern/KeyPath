import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var kanataManager: KanataManager
    
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
                VStack(spacing: 24) {
                    // Installation Status Section
                    SettingsSection(title: "Installation Status") {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(kanataManager.isCompletelyInstalled() ? .green : .orange)
                                .frame(width: 8, height: 8)
                            
                            Text(kanataManager.getInstallationStatus())
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    
                    // Service Control Section
                    SettingsSection(title: "Manual Controls") {
                        VStack(spacing: 0) {
                            Text("Kanata starts automatically when KeyPath launches.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 16)
                            
                            // Control buttons in a grid
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ControlButton(
                                    title: kanataManager.isRunning ? "Stop Kanata" : "Start Kanata",
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
                                
                                ControlButton(
                                    title: "Restart Kanata",
                                    systemImage: "arrow.clockwise.circle",
                                    disabled: !kanataManager.isRunning,
                                    action: {
                                        Task {
                                            await kanataManager.restartKanata()
                                        }
                                    }
                                )
                                
                                ControlButton(
                                    title: "Emergency Stop",
                                    systemImage: "exclamationmark.triangle",
                                    style: .destructive,
                                    disabled: !kanataManager.isRunning,
                                    action: {
                                        Task {
                                            await kanataManager.emergencyStop()
                                        }
                                    }
                                )
                                
                                ControlButton(
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
                    }
                    
                    // Error Section (if any)
                    if let error = kanataManager.lastError {
                        SettingsSection(title: "Status") {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Service Issue")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    Text(error)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
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
    }
}

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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ControlButton: View {
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
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .foregroundColor(style == .destructive ? .white : .blue)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(style == .destructive ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(style == .destructive ? Color.red : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }
}

#Preview {
    SettingsView()
        .environmentObject(KanataManager())
}