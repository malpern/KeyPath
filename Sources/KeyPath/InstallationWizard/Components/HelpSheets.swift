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
                            Text("3. Add both KeyPath.app and /Library/KeyPath/bin/kanata")
                            Text("4. Navigate to Accessibility")
                            Text("5. Add both KeyPath.app and /Library/KeyPath/bin/kanata")
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
            let (keyPathHas, kanataHas, details) = await kanataManager.checkBothAppsHavePermissions()

            let hasAccessibility = await kanataManager.hasAccessibilityPermission()

            await MainActor.run {
                var report = "=== Permission Status Report ===\n\n"
                report += "KeyPath.app:\n"
                report +=
                    "• Input Monitoring: ❌ Not Granted (check disabled to prevent auto-addition)\n"
                report +=
                    "• Accessibility: \(hasAccessibility ? "✅ Granted" : "❌ Not Granted")\n"
                report += "• TCC Database: \(keyPathHas ? "✅ Found" : "❌ Not Found")\n\n"

                report += "kanata (/Library/KeyPath/bin/kanata):\n"
                report += "• Input Monitoring (TCC): \(kanataHas ? "✅ Granted" : "❌ Not Granted")\n"
                // Accessibility check removed - now handled by attempt-based detection
                report += "• Accessibility: Will verify on actual use\n\n"

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

                    if PermissionService.lastTCCAuthorizationDenied {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("To verify kanata’s permission, please grant Full Disk Access to KeyPath.")
                            }
                            Button("Open Full Disk Access Settings") {
                                if let url = URL(string: WizardSystemPaths.fullDiskAccessSettings) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(8)
                    }

                    VStack(spacing: 12) {
                        Button("Check Permission Status") {
                            Task {
                                // Refresh permission status - ViewModel will update automatically
                                await kanataManager.updateStatus()
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
                                // Refresh permission status - ViewModel will update automatically
                                await kanataManager.updateStatus()
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

// MARK: - Background Services Help Sheet

struct BackgroundServicesHelpSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Background Services Setup Help")
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
                        Text(
                            "Karabiner background services may not appear in System Settings by default. You need to manually add them as Login Items:"
                        )
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                        Text("How to add Login Items:")
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
                                Text("Go to General → Login Items & Extensions")
                            }
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click the \"Open at Login\" section in the left sidebar")
                            }
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Click the \"+\" button to add new items")
                            }
                            HStack(alignment: .top) {
                                Text("5.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Navigate to: /Library/Application Support/org.pqrs/Karabiner-Elements/")
                                    .font(.system(.subheadline, design: .monospaced))
                            }
                            HStack(alignment: .top) {
                                Text("6.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Add these two applications (drag & drop or use + button):")
                                    Text("• Karabiner-Elements Non-Privileged Agents.app")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text("• Karabiner-Elements Privileged Daemons.app")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            HStack(alignment: .top) {
                                Text("7.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Restart your Mac or log out/log in for changes to take effect")
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Helpful Tools:")
                            .font(.headline)

                        Text("• Use 'Open Karabiner Folder' to browse directly to the apps")
                        Text("• Use 'Copy File Paths' to get the full paths for manual navigation")
                        Text("• Services may not appear in \"By Category\" view even when working")
                        Text("• You can verify services with: launchctl list | grep karabiner")
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button("Open System Settings") {
                                if let url = URL(
                                    string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open Karabiner Folder") {
                                openKarabinerFolderInFinder()
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 12) {
                            Button("Copy File Paths") {
                                copyKarabinerPathsToClipboard()
                            }
                            .buttonStyle(.bordered)

                            Button("Check Service Status") {
                                Task {
                                    // Refresh service status - ViewModel will update automatically
                                    await kanataManager.updateStatus()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 650, height: 600)
        .padding()
    }

    private func openKarabinerFolderInFinder() {
        let karabinerPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/"
        if let url = URL(
            string:
            "file://\(karabinerPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? karabinerPath)"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyKarabinerPathsToClipboard() {
        let paths = """
        Karabiner-Elements Non-Privileged Agents.app
        Karabiner-Elements Privileged Daemons.app

        Full paths:
        /Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents.app
        /Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Privileged Daemons.app
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths, forType: .string)
    }
}

// MARK: - Karabiner Installation Guide Sheet

struct KarabinerInstallationGuideSheet: View {
    let kanataManager: KanataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isCheckingStatus = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Install Karabiner-Elements")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Required for virtual keyboard functionality")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Why it's needed
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Why Karabiner-Elements is needed:")
                                .font(.headline)
                        }
                        
                        Text("KeyPath uses Karabiner-Elements' virtual HID device driver to safely remap keys at the system level. This driver must be installed separately.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)
                    
                    // Installation steps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Installation Steps:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Text("1.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Download Karabiner-Elements from the official website")
                            }
                            HStack(alignment: .top) {
                                Text("2.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Run the installer (.dmg file)")
                            }
                            HStack(alignment: .top) {
                                Text("3.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Grant permissions when prompted (you can ignore Karabiner-Elements setup)")
                            }
                            HStack(alignment: .top) {
                                Text("4.")
                                    .fontWeight(.medium)
                                    .frame(width: 20)
                                Text("Return here and click 'I've Installed It' to continue")
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Important note
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                            Text("Important:")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• You only need to install Karabiner-Elements - you don't need to configure it")
                            Text("• KeyPath will use its driver but manage all keyboard settings itself")
                            Text("• You can ignore Karabiner-Elements' own setup wizard")
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button("Download Karabiner-Elements") {
                    if let url = URL(string: "https://karabiner-elements.pqrs.org/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                HStack(spacing: 12) {
                    Button("I've Installed It - Check Again") {
                        recheckSystemStatus()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCheckingStatus)
                    
                    if isCheckingStatus {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
        .frame(width: 550, height: 500)
        .padding()
    }
    
    private func recheckSystemStatus() {
        isCheckingStatus = true
        Task {
            // Give a brief delay for user to see the loading state
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Trigger a system state refresh - ViewModel will update automatically
            await kanataManager.updateStatus()

            await MainActor.run {
                isCheckingStatus = false

                // Close the dialog after rechecking
                dismiss()
            }
        }
    }
}

// MARK: - Visual Effect Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .contentBackground
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
