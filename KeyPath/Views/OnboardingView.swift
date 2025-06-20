import SwiftUI

struct OnboardingView: View {
    var securityManager: SecurityManager
    @Binding var showOnboarding: Bool
    @State private var currentStep = 0
    @Environment(\.colorScheme) var colorScheme
    @State private var anthropicAPIKey = ""
    @State private var tempAPIKey = ""
    @State private var showAPIKey = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("KeyPath Setup")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Skip") {
                    showOnboarding = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skip onboarding setup")
            }
            .padding()

            // Progress indicator
            ProgressView(value: Double(currentStep + 1), total: 5)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            // Content
            ZStack {
                switch currentStep {
                case 0:
                    WelcomeStep()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 1:
                    APIKeyStep(tempAPIKey: $tempAPIKey, showAPIKey: $showAPIKey)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 2:
                    KarabinerConflictStep()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 3:
                    KanataInstallStep(isInstalled: securityManager.isKanataInstalled)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 4:
                    ConfigurationStep(hasAccess: securityManager.hasConfigAccess)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                default:
                    WelcomeStep()
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Previous") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    // Invisible spacer for alignment
                    Button("Previous") {
                        // Do nothing
                    }
                    .buttonStyle(.plain)
                    .opacity(0)
                    .disabled(true)
                }

                Spacer()

                if currentStep < 4 {
                    Button("Continue") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Get Started") {
                        // Save the API key if entered
                        if !tempAPIKey.isEmpty {
                            do {
                                try KeychainManager.shared.setAPIKey(tempAPIKey)
                            } catch {
                                // Log error but don't block onboarding
                                print("Failed to save API key: \(error)")
                            }
                        }
                        showOnboarding = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .padding(.top, 16)
        }
        .frame(width: 600, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor) :
                      Color.white)
        )
    }
}

struct KanataInstallStep: View {
    let isInstalled: Bool
    @State private var showInstallCommands = false
    @State private var isInstalling = false
    @State private var installationError: String?
    @State private var installationSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: (isInstalled || installationSuccess) ? "checkmark.circle.fill" :
                  isInstalling ? "gear" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor((isInstalled || installationSuccess) ? .green :
                               isInstalling ? .blue : .red)

            Text((isInstalled || installationSuccess) ? "Kanata Ready" :
                 isInstalling ? "Installing Kanata..." : "Kanata Not Found")
                .font(.title)
                .fontWeight(.semibold)

            if isInstalled || installationSuccess {
                Text("Great! Kanata is installed on your system.")
                    .foregroundColor(.secondary)
            } else if isInstalling {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Installing Kanata via Homebrew...")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Text("KeyPath requires Kanata to remap your keyboard.")
                        .foregroundColor(.secondary)

                    if installationError != nil {
                        Label(installationError!, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    let installer = KanataInstaller()
                    if installer.isHomebrewInstalled() {
                        Button("Auto-Install Kanata") {
                            autoInstallKanata()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isInstalling)

                        Text("or")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    Button("Show Manual Installation Steps") {
                        showInstallCommands.toggle()
                    }

                    if showInstallCommands {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. Download Kanata:")
                                .fontWeight(.medium)
                            Link("github.com/jtroo/kanata",
                                 destination: URL(string: "https://github.com/jtroo/kanata/releases")!)

                            Text("2. Install the binary:")
                                .fontWeight(.medium)
                                .padding(.top, 8)

                            CodeBlock(code: """
                                # Move to /usr/local/bin
                                sudo mv kanata /usr/local/bin/

                                # Make executable
                                sudo chmod +x /usr/local/bin/kanata
                                """)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 40)
    }

    private func autoInstallKanata() {
        isInstalling = true
        installationError = nil

        let installer = KanataInstaller()
        installer.autoInstallKanata { result in
            DispatchQueue.main.async {
                self.isInstalling = false
                switch result {
                case .success:
                    self.installationSuccess = true
                case .failure(let error):
                    self.installationError = error.localizedDescription
                }
            }
        }
    }
}

struct ConfigurationStep: View {
    let hasAccess: Bool
    @State private var showConfigSteps = false
    @State private var isSettingUp = false
    @State private var setupSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: hasAccess || setupSuccess ? "checkmark.circle.fill" :
                  isSettingUp ? "gear" : "folder.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(hasAccess || setupSuccess ? .green :
                               isSettingUp ? .blue : .orange)

            Text(hasAccess || setupSuccess ? "Configuration Ready" :
                 isSettingUp ? "Setting Up Configuration" : "Auto-Setup Configuration")
                .font(.title)
                .fontWeight(.semibold)

            if hasAccess {
                Text("Your Kanata configuration is ready for KeyPath.")
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 16) {
                    if isSettingUp {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Setting up Kanata configuration...")
                                .foregroundColor(.secondary)
                        }
                    } else if setupSuccess {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("Configuration ready!")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("KeyPath will automatically set up your configuration:")
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)

                            HStack {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(.green)
                                Text("~/.config/kanata/ directory")
                            }

                            HStack {
                                Image(systemName: "doc.badge.plus")
                                    .foregroundColor(.green)
                                Text("kanata.kbd configuration file")
                            }

                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                Text("Default settings for remapping")
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 40)
        .onAppear {
            if !hasAccess && !isSettingUp && !setupSuccess {
                setupConfiguration()
            }
        }
    }

    private func setupConfiguration() {
        isSettingUp = true

        DispatchQueue.global(qos: .userInitiated).async {
            let installer = KanataInstaller()
            let result = installer.checkKanataSetup()

            DispatchQueue.main.async {
                self.isSettingUp = false
                switch result {
                case .success:
                    self.setupSuccess = true
                case .failure(let error):
                    print("Setup failed: \(error)")
                    // Could show error here, but for now just leave setupSuccess as false
                }
            }
        }
    }
}

struct CodeBlock: View {
    let code: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ?
                          Color.white.opacity(0.05) :
                          Color.black.opacity(0.05))
            )
            .textSelection(.enabled)
    }
}
