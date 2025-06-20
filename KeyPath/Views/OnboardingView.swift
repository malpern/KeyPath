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

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to KeyPath")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            Text("KeyPath helps you create custom keyboard remappings using natural language and AI.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
                .lineSpacing(2)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "message.fill",
                    title: "Natural Language",
                    description: "Describe your remapping in plain English"
                )

                FeatureRow(
                    icon: "cpu",
                    title: "AI-Powered",
                    description: "Claude Sonnet 4 understands your intent"
                )

                FeatureRow(
                    icon: "checkmark.shield.fill",
                    title: "Safe & Validated",
                    description: "All rules are validated before installation"
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.vertical, 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct APIKeyStep: View {
    @Binding var tempAPIKey: String
    @Binding var showAPIKey: Bool
    @State private var isValidating = false
    @State private var savedAPIKey = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var saveSuccess = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Connect to Claude AI")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 16) {
                Text("KeyPath uses Claude AI to translate your natural language into keyboard remapping rules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Anthropic API Key:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("🔐 Your API key will be securely stored in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.bottom, 4)

                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 400)

                    HStack(spacing: 4) {
                        Text("Don't have an API key?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("Get one at console.anthropic.com",
                             destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 40)

                if !tempAPIKey.isEmpty && !saveSuccess {
                    Button(action: {
                        isSaving = true
                        saveError = nil

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            do {
                                try KeychainManager.shared.setAPIKey(tempAPIKey)
                                savedAPIKey = tempAPIKey
                                saveSuccess = true
                                SoundManager.shared.playSound(.success)
                            } catch {
                                saveError = "Failed to save API key: \(error.localizedDescription)"
                            }
                            isSaving = false
                        }
                    }) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            } else {
                                Text("Save to Keychain")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .disabled(isSaving)

                    if !saveSuccess {
                        Text("macOS will ask for permission to access Keychain")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 4)
                    }
                }

                if saveSuccess {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key Saved Successfully!")
                                .fontWeight(.medium)
                        }
                        .font(.callout)
                        .foregroundColor(.green)

                        Text("Your API key is now securely stored in macOS Keychain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }

                if let error = saveError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 40)
                }

                Text("You can skip this step and add your API key later in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            // Check for existing API key from Keychain
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                tempAPIKey = keychainKey
                savedAPIKey = keychainKey
            }
        }
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

struct KarabinerConflictStep: View {
    @State private var isKarabinerRunning = false
    @State private var hasChecked = false
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: isKarabinerRunning ? "exclamationmark.triangle.fill" :
                  hasChecked ? "checkmark.circle.fill" : "magnifyingglass")
                .font(.system(size: 80))
                .foregroundColor(isKarabinerRunning ? .orange :
                               hasChecked ? .green : .blue)
                .symbolEffect(.pulse, isActive: isChecking)

            Text(isKarabinerRunning ? "Karabiner-Elements Detected" :
                 hasChecked ? "No Conflicts Found" : "Checking for Conflicts")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            if isChecking {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Scanning for keyboard software conflicts...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if isKarabinerRunning {
                VStack(spacing: 16) {
                    Text("Karabiner-Elements is currently running and will conflict with Kanata.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("To use KeyPath, please:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(alignment: .top, spacing: 12) {
                            Text("1.")
                                .fontWeight(.medium)
                            Text("Quit Karabiner-Elements from the menu bar")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("2.")
                                .fontWeight(.medium)
                            Text("Click \"Check Again\" below")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Text("3.")
                                .fontWeight(.medium)
                            Text("You can re-enable Karabiner after using KeyPath")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)

                    Button("Check Again") {
                        checkForKarabiner()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else if hasChecked {
                VStack(spacing: 12) {
                    Text("Great! No conflicting keyboard software detected.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("KeyPath can safely manage your keyboard remappings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            if !hasChecked {
                checkForKarabiner()
            }
        }
    }

    private func checkForKarabiner() {
        isChecking = true

        DispatchQueue.global(qos: .userInitiated).async {
            let installer = KanataInstaller()
            let karabinerDetected = installer.isKarabinerRunning()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isChecking = false
                self.isKarabinerRunning = karabinerDetected
                self.hasChecked = true
            }
        }
    }
}
