import SwiftUI

// MARK: - Permission Details Sheet

struct PermissionDetailsSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDetails = ""
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Permission Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            if isLoading {
                ProgressView("Checking permissions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TCC Database Check Results:")
                            .font(.headline)
                        
                        Text(permissionDetails)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What to do if permissions are missing:")
                                .font(.headline)
                            
                            Text("1. Open System Settings → Privacy & Security")
                            Text("2. Navigate to Input Monitoring")
                            Text("3. Add both KeyPath.app and /usr/local/bin/kanata")
                            Text("4. Navigate to Accessibility")
                            Text("5. Add both KeyPath.app and /usr/local/bin/kanata")
                            Text("6. You may need to restart KeyPath after granting permissions")
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
        .padding()
        .onAppear {
            loadPermissionDetails()
        }
    }
    
    private func loadPermissionDetails() {
        Task {
            let (keyPathHas, kanataHas, details) = kanataManager.checkBothAppsHavePermissions()
            
            await MainActor.run {
                var report = "=== Permission Status Report ===\n\n"
                report += "KeyPath.app:\n"
                report += "• Input Monitoring: \(kanataManager.hasInputMonitoringPermission() ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• Accessibility: \(kanataManager.hasAccessibilityPermission() ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• TCC Database: \(keyPathHas ? "✅ Found" : "❌ Not Found")\n\n"
                
                report += "kanata (/usr/local/bin/kanata):\n"
                report += "• Input Monitoring (TCC): \(kanataHas ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• Accessibility: \(kanataManager.checkAccessibilityForPath("/usr/local/bin/kanata") ? "✅ Granted" : "❌ Not Granted")\n\n"
                
                report += "=== TCC Database Details ===\n"
                report += details
                
                permissionDetails = report
                isLoading = false
            }
        }
    }
}

// MARK: - Input Monitoring Help Sheet

struct InputMonitoringHelpSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Input Monitoring Permission Help")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to grant permission:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("1.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click 'Open System Settings' below")
                            }
                            HStack(alignment: .top) {
                                Text("2.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Navigate to Privacy & Security → Input Monitoring")
                            }
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Enable the toggle for both KeyPath and kanata")
                            }
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click 'Check Permission Status' to verify")
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    VStack(spacing: 12) {
                        Button("Check Permission Status") {
                            Task {
                                // Refresh permission status
                                await MainActor.run {
                                    kanataManager.objectWillChange.send()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - Accessibility Help Sheet

struct AccessibilityHelpSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Accessibility Permission Help")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to grant permission:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("1.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click 'Open System Settings' below")
                            }
                            HStack(alignment: .top) {
                                Text("2.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Navigate to Privacy & Security → Accessibility")
                            }
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Enable the toggle for both KeyPath and kanata")
                            }
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("You may need to unlock with your password")
                            }
                            HStack(alignment: .top) {
                                Text("5.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click 'Check Permission Status' to verify")
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    VStack(spacing: 12) {
                        Button("Check Permission Status") {
                            Task {
                                // Refresh permission status
                                await MainActor.run {
                                    kanataManager.objectWillChange.send()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 500, height: 450)
        .padding()
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .contentBackground
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}